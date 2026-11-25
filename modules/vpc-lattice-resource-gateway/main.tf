# VPC Lattice resource gateway and resource configurations (ADR-36 section 3).
#
# Databases and other TCP resources (RDS Proxy in front of Aurora, Oracle databases) are reached
# from other VPCs and accounts through a resource configuration on a resource gateway in the
# resource's VPC. Lattice passes the TCP connection through, so TLS runs end to end to the resource.
#
#   resource gateway         ENIs in the resource's VPC (one subnet per AZ); its security group
#                            is the source the resource's own security group must allow
#   resource configurations  one per resource: DNS name, IP or ARN, TCP port ranges; associated
#                            with the environment's service network (callers in associated VPCs
#                            reach it by its custom domain) and optionally shared through RAM
#
# Callers need vpc-lattice-svcs:Connect, which the service network policy grants inside the
# organization.

resource "aws_vpclattice_resource_gateway" "this" {
  name               = var.name
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids
  ip_address_type    = "IPV4"

  tags = { Name = var.name }
}

resource "aws_vpclattice_resource_configuration" "this" {
  for_each = var.resource_configurations

  name                        = each.value.name
  resource_gateway_identifier = aws_vpclattice_resource_gateway.this.id
  type                        = each.value.arn == null ? "SINGLE" : "ARN"
  protocol                    = each.value.arn == null ? "TCP" : null
  port_ranges                 = each.value.arn == null ? each.value.port_ranges : null
  custom_domain_name          = each.value.custom_domain_name

  allow_association_to_shareable_service_network = true

  resource_configuration_definition {
    dynamic "dns_resource" {
      for_each = each.value.dns_name == null ? [] : [each.value.dns_name]

      content {
        domain_name     = dns_resource.value
        ip_address_type = "IPV4"
      }
    }

    dynamic "ip_resource" {
      for_each = each.value.ip_address == null ? [] : [each.value.ip_address]

      content {
        ip_address = ip_resource.value
      }
    }

    dynamic "arn_resource" {
      for_each = each.value.arn == null ? [] : [each.value.arn]

      content {
        arn = arn_resource.value
      }
    }
  }

  tags = { Name = each.value.name }
}

resource "aws_vpclattice_service_network_resource_association" "this" {
  for_each = var.service_network_arn == null ? {} : var.resource_configurations

  resource_configuration_identifier = aws_vpclattice_resource_configuration.this[each.key].id
  service_network_identifier        = var.service_network_arn

  tags = { Name = each.value.name }
}

# ---------------------------------------------------------------- RAM (optional)

resource "aws_ram_resource_share" "this" {
  count = length(var.ram_principals) > 0 ? 1 : 0

  name                      = var.name
  allow_external_principals = false

  tags = { Name = var.name }
}

resource "aws_ram_resource_association" "this" {
  for_each = length(var.ram_principals) > 0 ? var.resource_configurations : {}

  resource_share_arn = aws_ram_resource_share.this[0].arn
  resource_arn       = aws_vpclattice_resource_configuration.this[each.key].arn
}

resource "aws_ram_principal_association" "this" {
  for_each = toset(var.ram_principals)

  resource_share_arn = aws_ram_resource_share.this[0].arn
  principal          = each.value
}
