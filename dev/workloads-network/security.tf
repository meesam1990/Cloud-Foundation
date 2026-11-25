# Security groups and the private-subnet egress allowlist.
#
#   public-alb   public ALB: 443 from CloudFront only (managed prefix list); to the pods on app_port
#   backend-alb  internal ALBs that are Lattice targets: 443 from the Lattice prefix list only
#                (Lattice does not validate target certificates, ADR-36); to the pods on app_port
#   nodes        EKS nodes and pods: app_port from the two ALB groups, everything between nodes,
#                anything inside the VPC, HTTPS to Lattice, plus the egress allowlist
#   lattice      on the service network VPC association: which sources in this VPC may send to
#                Lattice (the nodes only)
#
# The CloudFront origin-facing prefix list counts as ~55 rules against the 60-rule quota, so it is
# the only inbound rule on the public ALB group (no quota increase needed).

data "aws_region" "current" {}

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# 169.254.171.0/24: the link-local range Lattice uses in every associated VPC.
data "aws_ec2_managed_prefix_list" "lattice" {
  name = "com.amazonaws.${data.aws_region.current.region}.vpc-lattice"
}

check "cloudfront_prefix_list_fits" {
  assert {
    condition     = data.aws_ec2_managed_prefix_list.cloudfront.max_entries <= 60
    error_message = "The CloudFront prefix list no longer fits the default 60 inbound rules per security group; request a quota increase."
  }
}

module "alb_sg" {
  source = "../../modules/security-group"

  name        = local.names.public_alb
  description = "Public ALB: HTTPS from CloudFront only"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    cloudfront = {
      description    = "HTTPS from CloudFront origin-facing servers"
      ip_protocol    = "tcp"
      from_port      = 443
      prefix_list_id = data.aws_ec2_managed_prefix_list.cloudfront.id
    }
  }

  egress_rules = {
    pods = {
      description                  = "To the pods on the app port (traffic and health checks)"
      ip_protocol                  = "tcp"
      from_port                    = var.app_port
      referenced_security_group_id = module.nodes_sg.id
    }
  }
}

module "backend_alb_sg" {
  source = "../../modules/security-group"

  name        = local.names.backend_alb
  description = "Internal ALBs behind VPC Lattice: HTTPS from Lattice only"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    lattice = {
      description    = "HTTPS from VPC Lattice"
      ip_protocol    = "tcp"
      from_port      = 443
      prefix_list_id = data.aws_ec2_managed_prefix_list.lattice.id
    }
  }

  egress_rules = {
    pods = {
      description                  = "To the pods on the app port (traffic and health checks)"
      ip_protocol                  = "tcp"
      from_port                    = var.app_port
      referenced_security_group_id = module.nodes_sg.id
    }
  }
}

module "lattice_sg" {
  source = "../../modules/security-group"

  name        = local.names.lattice
  description = "Lattice service network association: callers allowed into Lattice"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = merge(
    {
      nodes-https = {
        description                  = "HTTPS services from nodes and pods"
        ip_protocol                  = "tcp"
        from_port                    = 443
        referenced_security_group_id = module.nodes_sg.id
      }
    },
    {
      for p in var.lattice_resource_ports : "nodes-${p}" => {
        description                  = "Resource configurations (databases) on ${p} from nodes and pods"
        ip_protocol                  = "tcp"
        from_port                    = p
        referenced_security_group_id = module.nodes_sg.id
      }
    },
  )
}

module "nodes_sg" {
  source = "../../modules/security-group"

  name        = local.names.nodes
  description = "EKS nodes and pods"
  vpc_id      = module.vpc.vpc_id

  tags = { "kubernetes.io/cluster/${local.cluster_name}" = "owned" }

  ingress_rules = {
    self = {
      description = "Node and pod traffic between nodes"
      ip_protocol = "-1"
      self        = true
    }
    public-alb = {
      description                  = "App port from the public ALB"
      ip_protocol                  = "tcp"
      from_port                    = var.app_port
      referenced_security_group_id = module.alb_sg.id
    }
    backend-alb = {
      description                  = "App port from the internal (Lattice target) ALBs"
      ip_protocol                  = "tcp"
      from_port                    = var.app_port
      referenced_security_group_id = module.backend_alb_sg.id
    }
  }

  egress_rules = merge(
    {
      vpc = {
        description = "Anything inside the VPC (DNS, API endpoint, ALBs, pods, data tier)"
        ip_protocol = "-1"
        cidr_ipv4   = var.vpc_cidr
      }
      lattice-https = {
        description    = "Services in the service network (VPC Lattice)"
        ip_protocol    = "tcp"
        from_port      = 443
        prefix_list_id = data.aws_ec2_managed_prefix_list.lattice.id
      }
    },
    {
      for p in var.lattice_resource_ports : "lattice-${p}" => {
        description    = "Resource configurations (databases) on ${p} through VPC Lattice"
        ip_protocol    = "tcp"
        from_port      = p
        prefix_list_id = data.aws_ec2_managed_prefix_list.lattice.id
      }
    },
    {
      for r in var.egress_allowlist : "allow-${r.name}" => {
        description = "Egress allowlist: ${r.name}"
        ip_protocol = r.protocol == "all" ? "-1" : r.protocol
        from_port   = r.protocol == "icmp" ? -1 : r.from_port
        to_port     = r.protocol == "icmp" ? -1 : r.to_port
        cidr_ipv4   = r.cidr
      }
    },
  )
}

# Stateless second layer on the private subnets: same allowlist, Lattice, plus return traffic.
module "pods_nacl" {
  source = "../../modules/network-acl"

  name       = local.names.pods_nacl
  vpc_id     = module.vpc.vpc_id
  subnet_ids = values(module.vpc.subnet_ids["private"])

  egress_rules = concat(
    [{ rule_number = 100, protocol = "all", cidr_block = var.vpc_cidr }],
    [for i, p in concat([443], var.lattice_resource_ports) : {
      rule_number = 150 + i
      protocol    = "tcp"
      cidr_block  = var.lattice_link_local_cidr
      from_port   = p
      to_port     = p
    }],
    [for i, r in var.egress_allowlist : {
      rule_number = 200 + i * 10
      protocol    = r.protocol
      cidr_block  = r.cidr
      from_port   = r.from_port
      to_port     = r.to_port
    }],
  )

  ingress_rules = [
    { rule_number = 100, protocol = "all", cidr_block = var.vpc_cidr },
    { rule_number = 200, protocol = "tcp", cidr_block = "0.0.0.0/0", from_port = 1024, to_port = 65535 },
    { rule_number = 210, protocol = "udp", cidr_block = "0.0.0.0/0", from_port = 1024, to_port = 65535 },
  ]
}
