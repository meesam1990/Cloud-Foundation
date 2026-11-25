# Workload account (workloads-dev; Client Apps OU): the workload VPC.
#
# Internet inbound (ADR-34 keeps internet ingress for its own ADR; built per the agreed design):
#   CloudFront -> IGW -> edge route table -> GWLB endpoint (this AZ) -> GWLB/firewall in the
#   network account -> GWLB endpoint -> public ALB. Replies from the public subnets go back through
#   the same endpoint (0.0.0.0/0 -> GWLB endpoint), then out through the IGW.
# Outbound (ADR-34): private -> 0.0.0.0/0 -> Cloud WAN (<env>workloads) -> egress group.
# Between VPCs (ADR-36): the VPC is associated with the environment's Lattice service network;
#   pods call services by their custom domain with signed requests. No IP route to other VPCs.
#
# Subnet tiers (ADR-32 tiers, one subnet per AZ; dev uses 2 AZs, see README):
#   private     /18  EKS nodes and pods, internal ALBs     0.0.0.0/0 -> Cloud WAN
#   data        /20  databases, Lattice resource gateway   local only
#   public      /24  public ALB (internet-facing)          0.0.0.0/0 -> GWLB endpoint
#   gwlbe       /24  GWLB endpoints (internet ingress)     0.0.0.0/0 -> IGW
#   attachment  /24  Cloud WAN attachment                  local only
#   mgmt        /24  management (bastions, SSM endpoints)  0.0.0.0/0 -> Cloud WAN
# Remaining space (10.192.176.0/20 and up) is spare.

module "context" {
  source = "../../modules/context"

  environment = var.environment
  function    = "workloads"

  tags = {
    owner       = "devops"
    jira_ticket = var.jira_ticket
  }

  names = {
    cluster     = { type = "eks-cluster" }
    public_alb  = { type = "security-group", descriptor = "public-alb" }
    backend_alb = { type = "security-group", descriptor = "backend-alb" }
    nodes       = { type = "security-group", descriptor = "nodes" }
    lattice     = { type = "security-group", descriptor = "lattice" }
    pods_nacl   = { type = "network-acl", descriptor = "private-egress" }
    edge        = { type = "route-table", descriptor = "edge" }
  }

  paths = {
    flow_logs = "flow-logs"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  base         = module.context.base
  names        = module.context.names
  cluster_name = local.names.cluster

  # Same AZs as the network account, by AZ ID (AZ names differ between accounts).
  az_name_by_id = zipmap(data.aws_availability_zones.available.zone_ids, data.aws_availability_zones.available.names)
  azs           = [for id in local.network.az_ids : local.az_name_by_id[id]]

  small_tiers = ["public", "gwlbe", "attachment", "mgmt"]

  internal_cidrs = local.network.internal_cidrs
}

# ---------------------------------------------------------------- VPC

module "vpc" {
  source = "../../modules/vpc"

  # One VPC in the account: the VPC name is the account name (ADR-44 section 8).
  name         = local.base
  cidr_block   = var.vpc_cidr
  ipam_pool_id = var.ipam_pool_id
  tags         = { "client:ou" = "client-apps" }
  azs          = local.azs

  subnet_tiers = merge(
    { private = { cidrs = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 2, i)] } },
    { data = { cidrs = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, 8 + i)] } },
    {
      for t, tier in local.small_tiers : tier => {
        cidrs = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, 160 + t * 4 + i)]
      }
    },
  )

  create_internet_gateway = true
  internet_route_tiers    = ["gwlbe"]

  flow_logs = {
    retention_in_days = var.flow_log_retention_days
    log_group_name    = module.context.paths.flow_logs
  }
}

# ---------------------------------------------------------------- RAM shares from the network account

# Only needed when the accounts differ and RAM sharing with AWS Organizations is off (otherwise
# shares inside the organization are accepted automatically).
resource "aws_ram_resource_share_accepter" "core_network" {
  count = var.accept_ram_shares && local.network.core_network_ram_share_arn != null ? 1 : 0

  region    = local.network.ram_share_region
  share_arn = local.network.core_network_ram_share_arn
}

resource "aws_ram_resource_share_accepter" "service_network" {
  count = var.accept_ram_shares && local.network.service_network_ram_share_arn != null ? 1 : 0

  share_arn = local.network.service_network_ram_share_arn
}

# ---------------------------------------------------------------- GWLB endpoints (internet ingress)

module "gwlb_endpoints" {
  source   = "../../modules/vpc-endpoint"
  for_each = toset(local.azs)

  name              = "${local.base}-gwlbe-${module.vpc.az_ids[each.key]}"
  vpc_id            = module.vpc.vpc_id
  service_name      = local.network.gwlb_endpoint_service_name
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [module.vpc.subnet_ids["gwlbe"][each.key]]
}

# ---------------------------------------------------------------- Cloud WAN

module "attachment" {
  source = "../../modules/cloudwan-vpc-attachment"

  name            = local.base
  core_network_id = local.network.core_network_id
  vpc_arn         = module.vpc.vpc_arn
  subnet_arns     = values(module.vpc.subnet_arns["attachment"])

  routing_tags = {
    segment = local.network.workloads_segment_name
  }

  depends_on = [aws_ram_resource_share_accepter.core_network]
}

# ---------------------------------------------------------------- VPC Lattice (ADR-36)

module "lattice_association" {
  source = "../../modules/vpc-lattice-vpc-association"

  name                = local.base
  vpc_id              = module.vpc.vpc_id
  service_network_arn = local.network.service_network_arn
  security_group_ids  = [module.lattice_sg.id]

  depends_on = [aws_ram_resource_share_accepter.service_network]
}

# ---------------------------------------------------------------- inbound routing (edge)

# Ingress routing: the IGW hands traffic for the public subnets to that AZ's GWLB endpoint.
resource "aws_route_table" "edge" {
  vpc_id = module.vpc.vpc_id

  tags = { Name = local.names.edge }
}

resource "aws_route_table_association" "edge" {
  gateway_id     = module.vpc.internet_gateway_id
  route_table_id = aws_route_table.edge.id
}

resource "aws_route" "edge_to_gwlbe" {
  for_each = toset(local.azs)

  route_table_id         = aws_route_table.edge.id
  destination_cidr_block = module.vpc.subnet_cidrs["public"][each.key]
  vpc_endpoint_id        = module.gwlb_endpoints[each.key].id
}

# Public subnets: replies to the internet go back through the same AZ's endpoint (symmetric).
resource "aws_route" "public_to_gwlbe" {
  for_each = toset(local.azs)

  route_table_id         = module.vpc.route_table_ids["public"][each.key]
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = module.gwlb_endpoints[each.key].id
}

# ---------------------------------------------------------------- outbound routing (Cloud WAN)

resource "aws_route" "to_cloudwan" {
  for_each = { for p in setproduct(["private", "mgmt"], local.azs) : "${p[0]}|${p[1]}" => { tier = p[0], az = p[1] } }

  route_table_id         = module.vpc.route_table_ids[each.value.tier][each.value.az]
  destination_cidr_block = "0.0.0.0/0"
  core_network_arn       = local.network.core_network_arn

  depends_on = [module.attachment]
}
