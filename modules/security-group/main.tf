# Security group with explicit ingress and egress rules (one aws_vpc_security_group_*_rule per
# rule, keyed by a stable name, so adding or removing one rule never replaces the others).
# Each rule has exactly one source/destination: cidr_ipv4, prefix_list_id or
# referenced_security_group_id. No rules are created implicitly; with no egress rules the group
# allows no outbound traffic.

resource "aws_security_group" "this" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id

  tags = merge({ Name = var.name }, var.tags)
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = var.ingress_rules

  security_group_id            = aws_security_group.this.id
  description                  = each.value.description
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.ip_protocol == "-1" ? null : each.value.from_port
  to_port                      = each.value.ip_protocol == "-1" ? null : coalesce(each.value.to_port, each.value.from_port)
  cidr_ipv4                    = each.value.cidr_ipv4
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.self ? aws_security_group.this.id : each.value.referenced_security_group_id

  tags = { Name = "${var.name}-${each.key}" }
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = var.egress_rules

  security_group_id            = aws_security_group.this.id
  description                  = each.value.description
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.ip_protocol == "-1" ? null : each.value.from_port
  to_port                      = each.value.ip_protocol == "-1" ? null : coalesce(each.value.to_port, each.value.from_port)
  cidr_ipv4                    = each.value.cidr_ipv4
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.self ? aws_security_group.this.id : each.value.referenced_security_group_id

  tags = { Name = "${var.name}-${each.key}" }
}
