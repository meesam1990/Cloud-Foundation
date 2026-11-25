# One VPC Lattice service (ADR-36), owned by the application account that runs it.
#
# A service is approved by ADR-36 when it is published in its environment's service network with
# auth type AWS_IAM, an auth policy naming its callers, and access logging on. This module always
# sets AWS_IAM, always logs, and with no allowed_callers creates no auth policy - which Lattice
# treats as deny all (deny by default).
#
#   custom domain  e.g. backend.dev.client.internal, with an ACM certificate for that name; the
#                  caller's private hosted zone gets a CNAME to dns_name (route53-record module)
#   listeners      HTTPS (ADR-36: HTTPS on every listener); rules route by path prefix / method
#   target groups  ALB (the service's internal ALB, the EKS default), IP (pod IPs registered by the
#                  AWS Gateway API Controller), INSTANCE or LAMBDA. Lattice does not validate
#                  target certificates, so the targets' security groups must allow only the
#                  Lattice prefix list (com.amazonaws.<region>.vpc-lattice).
#   auth policy    one statement per caller group: role ARNs, optional methods and path patterns
#
# The service network is shared from the network account through RAM; association needs only its
# ARN.

resource "aws_vpclattice_service" "this" {
  name               = var.name
  auth_type          = "AWS_IAM"
  custom_domain_name = var.custom_domain_name
  certificate_arn    = var.certificate_arn

  tags = { Name = var.name }

  lifecycle {
    precondition {
      condition     = var.custom_domain_name == null || var.certificate_arn != null || !anytrue([for l in values(var.listeners) : l.protocol == "HTTPS"])
      error_message = "An HTTPS listener on a custom domain needs certificate_arn for that name."
    }
  }
}

# ---------------------------------------------------------------- target groups

resource "aws_vpclattice_target_group" "this" {
  for_each = var.target_groups

  name = "${var.name}-${each.key}"
  type = each.value.type

  dynamic "config" {
    for_each = each.value.type == "LAMBDA" ? [] : [each.value]

    content {
      port             = config.value.port
      protocol         = config.value.protocol
      protocol_version = config.value.type == "ALB" ? null : config.value.protocol_version
      vpc_identifier   = config.value.vpc_id
      ip_address_type  = config.value.type == "IP" ? "IPV4" : null

      dynamic "health_check" {
        for_each = config.value.type == "ALB" || config.value.health_check == null ? [] : [config.value.health_check]

        content {
          enabled                       = true
          path                          = health_check.value.path
          protocol                      = coalesce(health_check.value.protocol, config.value.protocol)
          port                          = health_check.value.port
          health_check_interval_seconds = health_check.value.interval
          healthy_threshold_count       = 2
          unhealthy_threshold_count     = 3

          matcher {
            value = health_check.value.matcher
          }
        }
      }
    }
  }

  tags = { Name = "${var.name}-${each.key}" }
}

locals {
  targets = merge([
    for tg, t in var.target_groups : {
      for i, target in t.targets : "${tg}/${i}" => { target_group = tg, id = target.id, port = target.port }
    }
  ]...)
}

resource "aws_vpclattice_target_group_attachment" "this" {
  for_each = local.targets

  target_group_identifier = aws_vpclattice_target_group.this[each.value.target_group].id

  target {
    id   = each.value.id
    port = each.value.port
  }
}

# ---------------------------------------------------------------- listeners and rules

resource "aws_vpclattice_listener" "this" {
  for_each = var.listeners

  name               = each.key
  service_identifier = aws_vpclattice_service.this.id
  protocol           = each.value.protocol
  port               = each.value.port

  default_action {
    dynamic "forward" {
      for_each = each.value.default_target_group == null ? [] : [each.value.default_target_group]

      content {
        target_groups {
          target_group_identifier = aws_vpclattice_target_group.this[forward.value].id
          weight                  = 100
        }
      }
    }

    dynamic "fixed_response" {
      for_each = each.value.default_target_group == null ? [404] : []

      content {
        status_code = fixed_response.value
      }
    }
  }

  tags = { Name = "${var.name}-${each.key}" }
}

locals {
  rules = merge([
    for l, listener in var.listeners : {
      for r, rule in listener.rules : "${l}/${r}" => merge(rule, { listener = l, name = r })
    }
  ]...)
}

resource "aws_vpclattice_listener_rule" "this" {
  for_each = local.rules

  name                = each.value.name
  service_identifier  = aws_vpclattice_service.this.id
  listener_identifier = aws_vpclattice_listener.this[each.value.listener].listener_id
  priority            = each.value.priority

  match {
    http_match {
      method = each.value.method

      dynamic "path_match" {
        for_each = each.value.path_prefix == null ? [] : [each.value.path_prefix]

        content {
          case_sensitive = false

          match {
            prefix = path_match.value
          }
        }
      }
    }
  }

  action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.this[each.value.target_group].id
        weight                  = 100
      }
    }
  }

  tags = { Name = "${var.name}-${each.value.name}" }
}

# ---------------------------------------------------------------- auth policy (deny by default)

data "aws_iam_policy_document" "auth" {
  count = length(var.allowed_callers) > 0 ? 1 : 0

  dynamic "statement" {
    for_each = var.allowed_callers

    content {
      sid       = replace(title(replace(statement.key, "-", " ")), " ", "")
      effect    = "Allow"
      actions   = ["vpc-lattice-svcs:Invoke"]
      resources = [for p in statement.value.paths : "${aws_vpclattice_service.this.arn}${p}"]

      principals {
        type        = "AWS"
        identifiers = statement.value.principal_arns
      }

      dynamic "condition" {
        for_each = length(statement.value.methods) > 0 ? [statement.value.methods] : []

        content {
          test     = "StringEquals"
          variable = "vpc-lattice-svcs:RequestMethod"
          values   = condition.value
        }
      }
    }
  }
}

resource "aws_vpclattice_auth_policy" "this" {
  count = length(var.allowed_callers) > 0 ? 1 : 0

  resource_identifier = aws_vpclattice_service.this.arn
  policy              = data.aws_iam_policy_document.auth[0].json
}

# ---------------------------------------------------------------- access logs

resource "aws_cloudwatch_log_group" "access_logs" {
  count = length(var.access_logs.destination_arns) == 0 ? 1 : 0

  name              = var.access_logs.log_group_name
  retention_in_days = var.access_logs.retention_in_days
  kms_key_id        = var.access_logs.kms_key_arn

  lifecycle {
    precondition {
      condition     = var.access_logs.log_group_name != null
      error_message = "access_logs.log_group_name is required when no destination_arns are given (ADR-36: access logging on)."
    }
  }
}

resource "aws_vpclattice_access_log_subscription" "this" {
  for_each = length(var.access_logs.destination_arns) == 0 ? { local = aws_cloudwatch_log_group.access_logs[0].arn } : { for i, a in var.access_logs.destination_arns : tostring(i) => a }

  resource_identifier = aws_vpclattice_service.this.arn
  destination_arn     = each.value

  tags = { Name = "${var.name}-access-logs" }
}

# ---------------------------------------------------------------- service network association

resource "aws_vpclattice_service_network_service_association" "this" {
  count = var.service_network_arn == null ? 0 : 1

  service_identifier         = aws_vpclattice_service.this.id
  service_network_identifier = var.service_network_arn

  tags = { Name = var.name }

  # Publish only once the policy is in place.
  depends_on = [aws_vpclattice_auth_policy.this, aws_vpclattice_listener.this]
}
