# One VPC endpoint: Interface, Gateway, GatewayLoadBalancer, or a VPC Lattice ServiceNetwork /
# Resource endpoint.
#
# A GatewayLoadBalancer endpoint lives in exactly one subnet (one AZ), so callers create one per
# AZ (module for_each) and route each AZ's traffic to its own endpoint.
#
# A ServiceNetwork endpoint (ADR-36) gives a VPC that is not associated with a Lattice service
# network - e.g. the Inbound VPC that on-premises callers reach over Cloud WAN - IP addresses for
# every service and resource in the service network. A Resource endpoint does the same for one
# resource configuration.

locals {
  interface_like = contains(["Interface", "ServiceNetwork", "Resource"], var.vpc_endpoint_type)
}

resource "aws_vpc_endpoint" "this" {
  vpc_id                     = var.vpc_id
  service_name               = contains(["ServiceNetwork", "Resource"], var.vpc_endpoint_type) ? null : var.service_name
  service_network_arn        = var.vpc_endpoint_type == "ServiceNetwork" ? var.service_network_arn : null
  resource_configuration_arn = var.vpc_endpoint_type == "Resource" ? var.resource_configuration_arn : null
  vpc_endpoint_type          = var.vpc_endpoint_type
  subnet_ids                 = var.vpc_endpoint_type == "Gateway" ? null : var.subnet_ids
  security_group_ids         = local.interface_like ? var.security_group_ids : null
  route_table_ids            = var.vpc_endpoint_type == "Gateway" ? var.route_table_ids : null
  private_dns_enabled        = local.interface_like ? var.private_dns_enabled : null
  policy                     = contains(["Interface", "Gateway"], var.vpc_endpoint_type) ? var.policy : null

  tags = { Name = var.name }

  lifecycle {
    precondition {
      condition     = var.vpc_endpoint_type != "GatewayLoadBalancer" || length(var.subnet_ids) == 1
      error_message = "A GatewayLoadBalancer endpoint takes exactly one subnet."
    }

    precondition {
      condition     = var.vpc_endpoint_type != "ServiceNetwork" || var.service_network_arn != null
      error_message = "A ServiceNetwork endpoint needs service_network_arn."
    }

    precondition {
      condition     = var.vpc_endpoint_type != "Resource" || var.resource_configuration_arn != null
      error_message = "A Resource endpoint needs resource_configuration_arn."
    }

    precondition {
      condition     = contains(["ServiceNetwork", "Resource"], var.vpc_endpoint_type) || var.service_name != null
      error_message = "service_name is required for Interface, Gateway and GatewayLoadBalancer endpoints."
    }
  }
}
