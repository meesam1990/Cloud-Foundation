# AWS Shield Advanced protections for the given resources (CloudFront, ALB, EIPs, Route 53).
#
# Protections only work in an account with an active Shield Advanced subscription. The
# subscription is deliberately NOT created here: it costs about USD 3,000 per month with a
# one-year commitment (per organization), so it is an account-level decision made outside this
# code (console, or aws_shield_subscription in the account's baseline). Keep enabled = false
# until it exists.

resource "aws_shield_protection" "this" {
  for_each = var.enabled ? var.resources : {}

  name         = "${var.name}-${each.key}"
  resource_arn = each.value
}

resource "aws_shield_protection_group" "this" {
  count = var.enabled && length(var.resources) > 1 ? 1 : 0

  protection_group_id = var.name
  aggregation         = "MAX"
  pattern             = "ARBITRARY"
  members             = values(var.resources)

  depends_on = [aws_shield_protection.this]
}
