# Network ACL for a set of subnets. NACLs are stateless: allow the return traffic of every
# outbound rule explicitly (ephemeral ports on ingress). Anything not matched is denied by the
# implicit last rule.

resource "aws_network_acl" "this" {
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  tags = { Name = var.name }
}

resource "aws_network_acl_rule" "this" {
  for_each = { for r in concat(
    [for r in var.ingress_rules : merge(r, { egress = false })],
    [for r in var.egress_rules : merge(r, { egress = true })],
  ) : "${r.egress ? "egress" : "ingress"}-${r.rule_number}" => r }

  network_acl_id = aws_network_acl.this.id
  egress         = each.value.egress
  rule_number    = each.value.rule_number
  rule_action    = each.value.action
  protocol       = local.protocol_numbers[each.value.protocol]
  cidr_block     = each.value.cidr_block
  from_port      = contains(["all", "icmp"], each.value.protocol) ? null : each.value.from_port
  to_port        = contains(["all", "icmp"], each.value.protocol) ? null : coalesce(each.value.to_port, each.value.from_port)
  icmp_type      = each.value.protocol == "icmp" ? -1 : null
  icmp_code      = each.value.protocol == "icmp" ? -1 : null
}

locals {
  protocol_numbers = { tcp = "6", udp = "17", icmp = "1", all = "-1" }
}
