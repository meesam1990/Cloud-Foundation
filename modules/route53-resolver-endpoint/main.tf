# Route 53 Resolver endpoint (ADR-34 section 4).
#
# INBOUND: on-premises AD DNS forwards the AWS zones (e.g. dev.client.internal) to these
# addresses in the Inbound VPC. OUTBOUND (with forwarding rules) is for AWS resolving on-premises
# names; not used yet.
#
# One IP per subnet (one subnet per AZ, at least two). The security group allows DNS (53 TCP/UDP)
# only from allowed_cidrs.

resource "aws_security_group" "this" {
  name        = var.name
  description = "Route 53 Resolver ${lower(var.direction)} endpoint: DNS"
  vpc_id      = var.vpc_id

  tags = { Name = var.name }
}

resource "aws_vpc_security_group_ingress_rule" "dns" {
  for_each = var.direction == "INBOUND" ? {
    for p in setproduct(var.allowed_cidrs, ["tcp", "udp"]) : "${p[0]}/${p[1]}" => { cidr = p[0], protocol = p[1] }
  } : {}

  security_group_id = aws_security_group.this.id
  description       = "DNS from ${each.value.cidr}"
  cidr_ipv4         = each.value.cidr
  ip_protocol       = each.value.protocol
  from_port         = 53
  to_port           = 53

  tags = { Name = "${var.name}-dns" }
}

resource "aws_vpc_security_group_egress_rule" "dns" {
  for_each = var.direction == "OUTBOUND" ? {
    for p in setproduct(var.allowed_cidrs, ["tcp", "udp"]) : "${p[0]}/${p[1]}" => { cidr = p[0], protocol = p[1] }
  } : {}

  security_group_id = aws_security_group.this.id
  description       = "DNS to ${each.value.cidr}"
  cidr_ipv4         = each.value.cidr
  ip_protocol       = each.value.protocol
  from_port         = 53
  to_port           = 53

  tags = { Name = "${var.name}-dns" }
}

resource "aws_route53_resolver_endpoint" "this" {
  name                   = var.name
  direction              = var.direction
  resolver_endpoint_type = "IPV4"
  security_group_ids     = [aws_security_group.this.id]
  protocols              = var.protocols

  dynamic "ip_address" {
    for_each = var.subnet_ids

    content {
      subnet_id = ip_address.value
    }
  }

  tags = { Name = var.name }
}
