# AWS VPC IPAM (ADR-32) with a three-level pool hierarchy in the default private scope:
#
#   global pool (no locale)      every active block
#     regional pool (locale)     the blocks of that region
#       OU pool (locale)         the OU's ranges; auto-imports existing VPCs; allocates only to
#                                resources tagged <allocation_tag_key> = <ou>; shared through RAM
#                                with that OU only
#
# Optional sandbox: a separate private scope (its space may overlap routable space and is never
# routed) with one pool shared with the Sandbox OU.
#
# The IPAM is created in the provider region (its home region). Pools with another locale are
# still managed from here: every pool is a resource of the home region whatever its locale, so the
# RAM shares are created here too. RAM shares with an OU need RAM sharing with AWS
# Organizations enabled in the management account.
#
# VPC allocations are not made here: account stacks create their VPCs with ipv4_ipam_pool_id
# (and a pinned cidr_block where the ADR fixes one) from the ou_pool_ids output.

data "aws_region" "current" {}

locals {
  regions = toset([for b in values(var.blocks) : b.region])

  ou_pool_cidrs = merge([
    for k, p in var.ou_pools : {
      for c in p.cidrs : "${k}/${c}" => {
        pool = k
        cidr = c
      }
    }
  ]...)

  shared_ou_pools = { for k, p in var.ou_pools : k => p if p.ou_arn != null }

  sandbox_shared = var.sandbox == null ? false : var.sandbox.ou_arn != null
}

resource "aws_vpc_ipam" "this" {
  description = var.description
  tier        = var.tier

  dynamic "operating_regions" {
    for_each = var.operating_regions

    content {
      region_name = operating_regions.value
    }
  }

  tags = {
    Name = var.name
  }

  lifecycle {
    precondition {
      condition     = contains(var.operating_regions, data.aws_region.current.region)
      error_message = "operating_regions must include the provider region (the IPAM home region)."
    }

    precondition {
      condition = alltrue(concat(
        [for r in local.regions : contains(var.operating_regions, r)],
        [for p in values(var.ou_pools) : contains(var.operating_regions, p.region)],
        var.sandbox == null ? [] : [contains(var.operating_regions, var.sandbox.region)],
      ))
      error_message = "Every block, OU pool and sandbox region must be in operating_regions."
    }

    precondition {
      condition     = alltrue([for p in values(var.ou_pools) : contains(local.regions, p.region)])
      error_message = "Every OU pool region needs at least one active block in that region (its parent regional pool)."
    }
  }
}

# ---------------------------------------------------------------- global pool

resource "aws_vpc_ipam_pool" "global" {
  address_family = "ipv4"
  ipam_scope_id  = aws_vpc_ipam.this.private_default_scope_id
  description    = "All routable space (ADR-32)."

  tags = {
    Name = "${var.name}-global"
  }
}

resource "aws_vpc_ipam_pool_cidr" "global" {
  for_each = var.blocks

  ipam_pool_id = aws_vpc_ipam_pool.global.id
  cidr         = each.value.cidr
}

# ---------------------------------------------------------------- regional pools

resource "aws_vpc_ipam_pool" "regional" {
  for_each = local.regions

  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.this.private_default_scope_id
  source_ipam_pool_id = aws_vpc_ipam_pool.global.id
  locale              = each.key
  description         = "Routable space of ${each.key} (ADR-32). Unallocated space here is the regional spare."

  tags = {
    Name = "${var.name}-${each.key}"
  }
}

resource "aws_vpc_ipam_pool_cidr" "regional" {
  for_each = var.blocks

  ipam_pool_id = aws_vpc_ipam_pool.regional[each.value.region].id
  cidr         = each.value.cidr

  # A child pool CIDR can only be provisioned once the parent holds it.
  depends_on = [aws_vpc_ipam_pool_cidr.global]
}

# ---------------------------------------------------------------- OU pools

resource "aws_vpc_ipam_pool" "ou" {
  for_each = var.ou_pools

  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.this.private_default_scope_id
  source_ipam_pool_id = aws_vpc_ipam_pool.regional[each.value.region].id
  locale              = each.value.region
  description         = coalesce(each.value.description, "${split("/", each.key)[0]} OU in ${each.value.region} (ADR-32).")
  auto_import         = true

  allocation_default_netmask_length = each.value.default_netmask_length
  allocation_min_netmask_length     = each.value.min_netmask_length
  allocation_max_netmask_length     = each.value.max_netmask_length

  allocation_resource_tags = {
    (var.allocation_tag_key) = split("/", each.key)[0]
  }

  tags = {
    Name = "${var.name}-${split("/", each.key)[0]}-${each.value.region}"
  }
}

resource "aws_vpc_ipam_pool_cidr" "ou" {
  for_each = local.ou_pool_cidrs

  ipam_pool_id = aws_vpc_ipam_pool.ou[each.value.pool].id
  cidr         = each.value.cidr

  depends_on = [aws_vpc_ipam_pool_cidr.regional]
}

resource "aws_ram_resource_share" "ou" {
  for_each = local.shared_ou_pools

  name                      = "${var.name}-${split("/", each.key)[0]}-${each.value.region}"
  allow_external_principals = false

  tags = {
    Name = "${var.name}-${split("/", each.key)[0]}-${each.value.region}"
  }
}

resource "aws_ram_resource_association" "ou" {
  for_each = local.shared_ou_pools

  resource_share_arn = aws_ram_resource_share.ou[each.key].arn
  resource_arn       = aws_vpc_ipam_pool.ou[each.key].arn
}

resource "aws_ram_principal_association" "ou" {
  for_each = local.shared_ou_pools

  resource_share_arn = aws_ram_resource_share.ou[each.key].arn
  principal          = each.value.ou_arn
}

# ---------------------------------------------------------------- sandbox

resource "aws_vpc_ipam_scope" "sandbox" {
  count = var.sandbox == null ? 0 : 1

  ipam_id     = aws_vpc_ipam.this.id
  description = "Sandbox space: may overlap routable space, never routed (ADR-32)."

  tags = {
    Name = "${var.name}-sandbox"
  }
}

resource "aws_vpc_ipam_pool" "sandbox" {
  count = var.sandbox == null ? 0 : 1

  address_family = "ipv4"
  ipam_scope_id  = aws_vpc_ipam_scope.sandbox[0].id
  locale         = var.sandbox.region
  description    = coalesce(var.sandbox.description, "Sandbox accounts, one /${var.sandbox.netmask_length} each (ADR-32).")
  auto_import    = true

  allocation_default_netmask_length = var.sandbox.netmask_length
  allocation_min_netmask_length     = var.sandbox.netmask_length
  allocation_max_netmask_length     = var.sandbox.netmask_length

  allocation_resource_tags = {
    (var.allocation_tag_key) = var.sandbox.ou
  }

  tags = {
    Name = "${var.name}-${var.sandbox.ou}-${var.sandbox.region}"
  }
}

resource "aws_vpc_ipam_pool_cidr" "sandbox" {
  count = var.sandbox == null ? 0 : 1

  ipam_pool_id = aws_vpc_ipam_pool.sandbox[0].id
  cidr         = var.sandbox.cidr
}

resource "aws_ram_resource_share" "sandbox" {
  count = local.sandbox_shared ? 1 : 0

  name                      = "${var.name}-${var.sandbox.ou}"
  allow_external_principals = false

  tags = {
    Name = "${var.name}-${var.sandbox.ou}"
  }
}

resource "aws_ram_resource_association" "sandbox" {
  count = local.sandbox_shared ? 1 : 0

  resource_share_arn = aws_ram_resource_share.sandbox[0].arn
  resource_arn       = aws_vpc_ipam_pool.sandbox[0].arn
}

resource "aws_ram_principal_association" "sandbox" {
  count = local.sandbox_shared ? 1 : 0

  resource_share_arn = aws_ram_resource_share.sandbox[0].arn
  principal          = var.sandbox.ou_arn
}
