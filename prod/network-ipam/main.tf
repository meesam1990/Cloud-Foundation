# IP address management for the organization (ADR-32): AWS VPC IPAM, Advanced tier, in
# network-prod, home region us-west-2, operating regions us-west-2 (primary) and us-east-1 (DR).
# Configured through Terraform only.
#
# Prerequisite (out of scope): the management account makes network-prod the IPAM delegated
# administrator (aws ec2 enable-ipam-organization-admin-account) and enables RAM sharing with
# AWS Organizations.
#
# This stack builds the scopes, the pool hierarchy and the RAM shares. It does not allocate VPC
# ranges: the baseline VPC ranges are pinned in the account stacks (VPC created with
# ipv4_ipam_pool_id + cidr_block from the ou_pool_ids output). An allocation here for the same
# range would conflict with them.

module "context" {
  source = "../../modules/context"

  environment = var.environment
  function    = "network"

  tags = {
    owner       = "netops"
    jira_ticket = var.jira_ticket
  }
}

locals {
  # ADR-32 address blocks. Only "active" blocks are provisioned.
  address_blocks = {
    a = { cidr = "10.192.0.0/13", region = "us-west-2", status = "active" }
    b = { cidr = "10.200.0.0/14", region = "us-west-2", status = "active" }
    c = { cidr = "10.224.0.0/16", region = "us-east-1", status = "active" }

    # Reserved, not provisioned. When a region runs low, set status = "active" and the region
    # that needs it: the block is provisioned to the global pool and that region's pool, and OU
    # pools can then take ranges from it (add them to ou_pools below).
    d = { cidr = "10.232.0.0/16", region = "us-east-1", status = "reserved" }

    # Never provisioned: do not use (ADR-32).
    e = { cidr = "10.222.0.0/16", region = null, status = "never" }
  }

  active_blocks = {
    for k, b in local.address_blocks : k => { cidr = b.cidr, region = b.region } if b.status == "active"
  }

  # ADR-32 OU pools: ranges and default allocation size (netmask) per OU per region. The rest of
  # each block stays in the regional pool as regional spare.
  ou_pools = {
    us-west-2 = {
      client-apps    = { cidrs = ["10.192.0.0/13"], default_netmask_length = 20 } # block A
      integrations   = { cidrs = ["10.200.0.0/19"], default_netmask_length = 23 } # block B
      oracle-apps    = { cidrs = ["10.200.32.0/20"], default_netmask_length = 23 }
      infrastructure = { cidrs = ["10.200.48.0/20"], default_netmask_length = 23 }
      analytics      = { cidrs = ["10.200.64.0/20"], default_netmask_length = 24 }
      devops         = { cidrs = ["10.200.80.0/20"], default_netmask_length = 24 }
      security       = { cidrs = ["10.200.96.0/21"], default_netmask_length = 23 }
      network        = { cidrs = ["10.200.104.0/21"], default_netmask_length = 25 }
    }
    us-east-1 = { # block C
      client-apps    = { cidrs = ["10.224.0.0/20"], default_netmask_length = 21 }
      security       = { cidrs = ["10.224.16.0/22"], default_netmask_length = 24 }
      integrations   = { cidrs = ["10.224.20.0/22"], default_netmask_length = 23 }
      infrastructure = { cidrs = ["10.224.24.0/22"], default_netmask_length = 23 }
      devops         = { cidrs = ["10.224.28.0/22"], default_netmask_length = 23 }
      network        = { cidrs = ["10.224.32.0/23"], default_netmask_length = 24 }
      oracle-apps    = { cidrs = ["10.224.34.0/23"], default_netmask_length = 24 }
      analytics      = { cidrs = ["10.224.36.0/23"], default_netmask_length = 24 }
    }
  }

  # ADR-32 sandbox: separate scope (may overlap, never routed), us-west-2 only, up to four
  # accounts of one /21 each.
  sandbox = {
    cidr           = "100.64.0.0/16"
    region         = "us-west-2"
    netmask_length = 21
  }
}

module "ipam" {
  source = "../../modules/ipam"

  name              = "${module.context.base}-ipam"
  description       = "Client organization IPAM (ADR-32)."
  operating_regions = ["us-west-2", "us-east-1"]
  tier              = "advanced"

  blocks = local.active_blocks

  ou_pools = merge([
    for region, ous in local.ou_pools : {
      for ou, p in ous : "${ou}/${region}" => {
        region                 = region
        cidrs                  = p.cidrs
        default_netmask_length = p.default_netmask_length
        min_netmask_length     = 16 # VPC sizes /16 to /28 (ADR-32)
        max_netmask_length     = 28
        ou_arn                 = lookup(var.ou_arns, ou, null)
      }
    }
  ]...)

  sandbox = merge(local.sandbox, {
    ou     = "sandbox"
    ou_arn = lookup(var.ou_arns, "sandbox", null)
  })
}
