# Network account (network-dev; network-prod in production): the core network, central
# inspection, the Inbound VPC and the environment's VPC Lattice service network.
#
# ADR-34 core network
#   segments   <env>workloads      workload VPCs; send-to the egress group for internet traffic
#              <env>sdwan          Silver Peak SD-WAN / MPLS (Connect attachments, not built here)
#              <env>directconnect  Direct Connect gateway for Las Vegas (optional attachment)
#              <env>inbound        the Inbound VPC only; shared with sdwan and directconnect, so
#                                  on-premises reaches the Inbound VPC and never a workload segment
#   group      <env>egress         network function group: the egress VPC (appliance mode)
#   Names are ADR-44 priority 3 (lowercase letters and digits, environment first).
#
# ADR-32 egress VPC (<account>-egress), tiers per AZ:
#   attachment  Cloud WAN attachment            0.0.0.0/0 -> GWLB endpoint (same AZ)
#   inspection  GWLB, firewalls, GWLB endpoints 0.0.0.0/0 -> NAT; internal ranges -> Cloud WAN
#   public      NAT gateways                    0.0.0.0/0 -> IGW; internal ranges -> GWLB endpoint
#   mgmt        firewall management             0.0.0.0/0 -> NAT (Strata Cloud Manager)
#   Outbound: workload -> Cloud WAN -> attachment -> GWLB endpoint -> GWLB -> firewall -> GWLB
#   endpoint -> NAT -> IGW. Replies: NAT -> GWLB endpoint -> firewall -> Cloud WAN. Both
#   directions use the same AZ (appliance mode), so the same stateful firewall.
#
# ADR-34 Inbound VPC (<account>-inbound), tiers per AZ:
#   attachment  Cloud WAN attachment (<env>inbound)    endpoints subnets -> GWLB endpoint of their AZ
#   gwlbe       GWLB endpoints                         on-premises ranges -> Cloud WAN
#   endpoints   Route 53 Resolver inbound endpoint,    on-premises ranges -> GWLB endpoint
#               Lattice service network endpoint
#   Every SD-WAN and Direct Connect call is inspected before it reaches an endpoint.
#
# ADR-36 service network <account>-services: auth AWS_IAM (organization only), access logs, shared
# through RAM with the environment's workload accounts.
#
# The GWLB endpoint service also serves the workload accounts' internet ingress endpoints.

module "context" {
  source = "../../modules/context"

  environment = var.environment
  function    = "network"

  tags = {
    owner       = "netops"
    jira_ticket = var.jira_ticket
  }

  names = {
    egress_vpc   = { type = "vpc", descriptor = "egress" }
    inbound_vpc  = { type = "vpc", descriptor = "inbound" }
    gwlb         = { type = "gwlb", descriptor = "firewall" }
    firewall     = { type = "security-group", descriptor = "firewall" }
    resolver     = { type = "route53-resolver-endpoint", descriptor = "inbound-dns" }
    services_sg  = { type = "security-group", descriptor = "inbound-services" }
    services     = { type = "lattice-service-network", descriptor = "services" }
    core_network = { type = "ram-resource-share", descriptor = "core-network" }
  }

  paths = {
    egress_flow_logs   = "egress-flow-logs"
    inbound_flow_logs  = "inbound-flow-logs"
    lattice_access_log = "lattice-access-logs"
  }
}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  names = module.context.names
  paths = module.context.paths

  az_name_by_id = zipmap(data.aws_availability_zones.available.zone_ids, data.aws_availability_zones.available.names)
  az_ids        = var.az_ids != null ? var.az_ids : slice(data.aws_availability_zones.available.zone_ids, 0, var.az_count)
  azs           = [for id in local.az_ids : local.az_name_by_id[id]]

  egress_tiers  = ["attachment", "inspection", "public", "mgmt"]
  inbound_tiers = ["attachment", "gwlbe", "endpoints"]

  # Cloud WAN names (ADR-44 priority 3).
  segment = {
    workloads     = "${var.environment}workloads"
    sdwan         = "${var.environment}sdwan"
    directconnect = "${var.environment}directconnect"
    inbound       = "${var.environment}inbound"
  }
  egress_group = "${var.environment}egress"

  internal_routes = { for p in setproduct(local.azs, var.internal_cidrs) : "${p[0]}|${p[1]}" => { az = p[0], cidr = p[1] } }
  onprem_routes   = { for p in setproduct(local.azs, var.onprem_cidrs) : "${p[0]}|${p[1]}" => { az = p[0], cidr = p[1] } }

  cross_account = var.apps_account_id != var.network_account.id
}

# ================================================================ Cloud WAN (ADR-34)

module "cloudwan" {
  source = "../../modules/cloudwan-core-network"

  providers = {
    aws = aws.cloudwan
  }

  name           = module.context.base
  edge_locations = var.edge_locations

  segments = {
    (local.segment.workloads) = {
      description = "${var.environment} workload VPCs"
      # Production: attachments isolated from each other and accepted by the network team.
      isolate_attachments           = var.environment == "prod"
      require_attachment_acceptance = var.environment == "prod"
    }
    (local.segment.sdwan)         = { description = "${var.environment} SD-WAN and MPLS (offices, branches)" }
    (local.segment.directconnect) = { description = "${var.environment} Direct Connect from the data center" }
    (local.segment.inbound)       = { description = "Inbound VPC: the only destination on-premises routes reach" }
  }

  network_function_groups = {
    (local.egress_group) = { description = "Central internet egress inspection" }
  }

  send_to = {
    (local.segment.workloads) = local.egress_group
  }

  segment_shares = {
    (local.segment.inbound) = [local.segment.sdwan, local.segment.directconnect]
  }
}

# Direct Connect gateway (Las Vegas, Megaport) into the directconnect segment, when it exists.
resource "aws_networkmanager_dx_gateway_attachment" "this" {
  count = var.direct_connect_gateway_arn == null ? 0 : 1

  provider = aws.cloudwan

  core_network_id            = module.cloudwan.core_network_id
  direct_connect_gateway_arn = var.direct_connect_gateway_arn
  edge_locations             = var.edge_locations

  tags = {
    Name    = "${module.context.base}-directconnect"
    segment = local.segment.directconnect
  }
}

# Cross-account: share the core network with the workload account (accepted in workloads-network).
# Inside the organization only.
resource "aws_ram_resource_share" "core_network" {
  count = local.cross_account ? 1 : 0

  region                    = var.ram_share_region
  name                      = local.names.core_network
  allow_external_principals = false
}

resource "aws_ram_resource_association" "core_network" {
  count = local.cross_account ? 1 : 0

  region             = var.ram_share_region
  resource_share_arn = aws_ram_resource_share.core_network[0].arn
  resource_arn       = module.cloudwan.core_network_arn
}

resource "aws_ram_principal_association" "apps" {
  count = local.cross_account ? 1 : 0

  region             = var.ram_share_region
  resource_share_arn = aws_ram_resource_share.core_network[0].arn
  principal          = var.apps_account_id
}

# ================================================================ egress VPC (ADR-32 / ADR-34)

module "egress_vpc" {
  source = "../../modules/vpc"

  name         = local.names.egress_vpc
  cidr_block   = var.egress_vpc_cidr
  ipam_pool_id = var.ipam_pool_id
  tags         = { "client:ou" = "network" }
  azs          = local.azs

  subnet_tiers = {
    for t, tier in local.egress_tiers : tier => {
      cidrs = [for i, az in local.azs : cidrsubnet(var.egress_vpc_cidr, var.subnet_newbits, t * length(local.azs) + i)]
    }
  }

  create_internet_gateway = true
  internet_route_tiers    = ["public"]

  # One NAT gateway per AZ: a shared one would send replies through another AZ's firewall.
  nat_gateway = {
    subnet_tier = "public"
  }

  flow_logs = {
    retention_in_days = var.flow_log_retention_days
    log_group_name    = local.paths.egress_flow_logs
  }
}

module "gwlb" {
  source = "../../modules/gateway-load-balancer"

  name       = local.names.gwlb
  vpc_id     = module.egress_vpc.vpc_id
  subnet_ids = values(module.egress_vpc.subnet_ids["inspection"])

  allowed_principals = distinct([
    "arn:aws:iam::${var.network_account.id}:root",
    "arn:aws:iam::${var.apps_account_id}:root",
  ])
}

module "egress_endpoints" {
  source   = "../../modules/vpc-endpoint"
  for_each = toset(local.azs)

  name              = "${local.names.egress_vpc}-gwlbe-${module.egress_vpc.az_ids[each.key]}"
  vpc_id            = module.egress_vpc.vpc_id
  service_name      = module.gwlb.endpoint_service_name
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [module.egress_vpc.subnet_ids["inspection"][each.key]]
}

module "firewall" {
  source = "../../modules/firewall-asg"

  name              = local.names.firewall
  az_ids            = module.egress_vpc.az_ids
  tags              = module.context.tags
  vpc_id            = module.egress_vpc.vpc_id
  subnet_ids        = module.egress_vpc.subnet_ids["inspection"]
  gwlb_subnet_cidrs = module.egress_vpc.subnet_cidrs["inspection"]
  target_group_arn  = module.gwlb.target_group_arn
  instance_type     = var.firewall_instance_type
  instances_per_az  = var.firewall_instances_per_az

  # Single-arm: every flow goes back to the GWLB; the endpoint's route table forwards it.
  nat_endpoint_ids = []

  # The instances build the stand-in and register with SSM at boot, through NAT.
  depends_on = [aws_route.inspection_to_nat]
}

# attachment: everything from Cloud WAN goes to this AZ's GWLB endpoint.
resource "aws_route" "egress_attachment_to_gwlbe" {
  for_each = toset(local.azs)

  route_table_id         = module.egress_vpc.route_table_ids["attachment"][each.key]
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = module.egress_endpoints[each.key].id
}

# inspection: inspected egress (from the endpoint) and the firewalls' own traffic leave through NAT.
resource "aws_route" "inspection_to_nat" {
  for_each = toset(local.azs)

  route_table_id         = module.egress_vpc.route_table_ids["inspection"][each.key]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = module.egress_vpc.nat_gateway_ids[each.key]
}

# inspection: inspected replies go back to the workloads over Cloud WAN.
resource "aws_route" "inspection_to_cloudwan" {
  for_each = local.internal_routes

  route_table_id         = module.egress_vpc.route_table_ids["inspection"][each.value.az]
  destination_cidr_block = each.value.cidr
  core_network_arn       = module.cloudwan.core_network_arn

  depends_on = [module.egress_attachment]
}

# public: replies from the internet (after NAT) go back through the firewall of the same AZ.
resource "aws_route" "public_to_gwlbe" {
  for_each = local.internal_routes

  route_table_id         = module.egress_vpc.route_table_ids["public"][each.value.az]
  destination_cidr_block = each.value.cidr
  vpc_endpoint_id        = module.egress_endpoints[each.value.az].id
}

# mgmt: firewall management (Strata Cloud Manager, updates) through NAT.
resource "aws_route" "mgmt_to_nat" {
  for_each = toset(local.azs)

  route_table_id         = module.egress_vpc.route_table_ids["mgmt"][each.key]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = module.egress_vpc.nat_gateway_ids[each.key]
}

module "egress_attachment" {
  source = "../../modules/cloudwan-vpc-attachment"

  name            = local.names.egress_vpc
  core_network_id = module.cloudwan.core_network_id
  vpc_arn         = module.egress_vpc.vpc_arn
  subnet_arns     = values(module.egress_vpc.subnet_arns["attachment"])
  appliance_mode  = true

  routing_tags = {
    network-function-group = local.egress_group
  }
}

# ================================================================ Inbound VPC (ADR-34)

module "inbound_vpc" {
  source = "../../modules/vpc"

  name         = local.names.inbound_vpc
  cidr_block   = var.inbound_vpc_cidr
  ipam_pool_id = var.ipam_pool_id
  tags         = { "client:ou" = "network" }
  azs          = local.azs

  subnet_tiers = {
    for t, tier in local.inbound_tiers : tier => {
      cidrs = [for i, az in local.azs : cidrsubnet(var.inbound_vpc_cidr, var.subnet_newbits, t * length(local.azs) + i)]
    }
  }

  flow_logs = {
    retention_in_days = var.flow_log_retention_days
    log_group_name    = local.paths.inbound_flow_logs
  }
}

module "inbound_endpoints" {
  source   = "../../modules/vpc-endpoint"
  for_each = toset(local.azs)

  name              = "${local.names.inbound_vpc}-gwlbe-${module.inbound_vpc.az_ids[each.key]}"
  vpc_id            = module.inbound_vpc.vpc_id
  service_name      = module.gwlb.endpoint_service_name
  vpc_endpoint_type = "GatewayLoadBalancer"
  subnet_ids        = [module.inbound_vpc.subnet_ids["gwlbe"][each.key]]
}

module "inbound_attachment" {
  source = "../../modules/cloudwan-vpc-attachment"

  name            = local.names.inbound_vpc
  core_network_id = module.cloudwan.core_network_id
  vpc_arn         = module.inbound_vpc.vpc_arn
  subnet_arns     = values(module.inbound_vpc.subnet_arns["attachment"])
  appliance_mode  = true

  routing_tags = {
    segment = local.segment.inbound
  }
}

# attachment: calls from on-premises to an endpoints subnet go through the GWLB endpoint of that
# subnet's AZ first (more-specific routes for subnets inside the VPC).
resource "aws_route" "inbound_attachment_to_gwlbe" {
  for_each = { for p in setproduct(local.azs, local.azs) : "${p[0]}|${p[1]}" => { rt_az = p[0], dest_az = p[1] } }

  route_table_id         = module.inbound_vpc.route_table_ids["attachment"][each.value.rt_az]
  destination_cidr_block = module.inbound_vpc.subnet_cidrs["endpoints"][each.value.dest_az]
  vpc_endpoint_id        = module.inbound_endpoints[each.value.dest_az].id
}

# endpoints: replies to on-premises go back through the same AZ's GWLB endpoint.
resource "aws_route" "endpoints_to_gwlbe" {
  for_each = local.onprem_routes

  route_table_id         = module.inbound_vpc.route_table_ids["endpoints"][each.value.az]
  destination_cidr_block = each.value.cidr
  vpc_endpoint_id        = module.inbound_endpoints[each.value.az].id
}

# gwlbe: inspected replies to on-premises over Cloud WAN (the inbound segment shares routes with
# the sdwan and directconnect segments only).
resource "aws_route" "inbound_gwlbe_to_cloudwan" {
  for_each = local.onprem_routes

  route_table_id         = module.inbound_vpc.route_table_ids["gwlbe"][each.value.az]
  destination_cidr_block = each.value.cidr
  core_network_arn       = module.cloudwan.core_network_arn

  depends_on = [module.inbound_attachment]
}

# On-premises AD DNS forwards the AWS zones here (ADR-34 section 4).
module "resolver_inbound" {
  source = "../../modules/route53-resolver-endpoint"

  name          = local.names.resolver
  direction     = "INBOUND"
  vpc_id        = module.inbound_vpc.vpc_id
  subnet_ids    = values(module.inbound_vpc.subnet_ids["endpoints"])
  allowed_cidrs = var.onprem_cidrs
}

# ================================================================ VPC Lattice (ADR-36)

module "service_network" {
  source = "../../modules/vpc-lattice-service-network"

  name                = local.names.services
  organization_id     = var.organization_id
  allowed_account_ids = distinct([var.network_account.id, var.apps_account_id])

  access_logs = {
    destination_arns  = var.lattice_access_log_destination_arns
    log_group_name    = local.paths.lattice_access_log
    retention_in_days = var.log_retention_days
  }

  # Inside the organization only: the environment's workload accounts (OU ARNs in production).
  ram_principals = local.cross_account ? concat([var.apps_account_id], var.service_network_share_principals) : var.service_network_share_principals
}

# On-premises callers (IAM Roles Anywhere, signed requests) reach the services through this
# endpoint, after the firewall (ADR-36 section 2).
module "services_endpoint_sg" {
  source = "../../modules/security-group"

  name        = local.names.services_sg
  description = "Lattice service network endpoint: HTTPS and database ports from on-premises"
  vpc_id      = module.inbound_vpc.vpc_id

  ingress_rules = {
    for p in setproduct(var.onprem_cidrs, var.onprem_service_ports) : "${replace(p[0], "/", "-")}-${p[1]}" => {
      description = "Port ${p[1]} from ${p[0]}"
      ip_protocol = "tcp"
      from_port   = p[1]
      cidr_ipv4   = p[0]
    }
  }
}

module "services_endpoint" {
  source = "../../modules/vpc-endpoint"

  name                = "${local.names.inbound_vpc}-services"
  vpc_id              = module.inbound_vpc.vpc_id
  vpc_endpoint_type   = "ServiceNetwork"
  service_network_arn = module.service_network.arn
  subnet_ids          = values(module.inbound_vpc.subnet_ids["endpoints"])
  security_group_ids  = [module.services_endpoint_sg.id]
  private_dns_enabled = true
}
