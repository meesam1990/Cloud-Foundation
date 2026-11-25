# AWS WAF web ACL, with:
#
#   - AWS managed rule groups (managed_rule_groups)
#   - an optional rate-based rule (per client IP, or per X-Forwarded-For behind a proxy/CDN)
#   - an optional "allow if header" rule: allow only requests carrying a shared secret header,
#     e.g. the header CloudFront adds to origin requests (use default_action = "block" with it)
#   - logging to CloudWatch Logs (log group aws-waf-logs-<name>), with chosen headers redacted
#   - associations to regional resources (ALB, API Gateway, ...). CloudFront distributions
#     reference the ACL themselves (web_acl_id).
#
# scope = "CLOUDFRONT" must be created in us-east-1: call the module with a us-east-1 provider.

locals {
  header_value_count = var.allow_header == null ? 0 : nonsensitive(length(var.allow_header_values))
}

resource "aws_wafv2_web_acl" "this" {
  name        = var.name
  description = var.description
  scope       = var.scope

  default_action {
    dynamic "allow" {
      for_each = var.default_action == "allow" ? [1] : []
      content {}
    }

    dynamic "block" {
      for_each = var.default_action == "block" ? [1] : []
      content {}
    }
  }

  # ------------------------------------------------------------ allow if the secret header matches

  dynamic "rule" {
    for_each = var.allow_header == null ? [] : [var.allow_header]

    content {
      name     = "allow-${rule.value.name}"
      priority = rule.value.priority

      action {
        allow {}
      }

      statement {
        dynamic "byte_match_statement" {
          for_each = local.header_value_count == 1 ? [0] : []

          content {
            search_string         = var.allow_header_values[0]
            positional_constraint = "EXACTLY"

            field_to_match {
              single_header {
                name = lower(rule.value.name)
              }
            }

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }

        # Several accepted values (e.g. current and previous secret while rotating).
        dynamic "or_statement" {
          for_each = local.header_value_count > 1 ? [1] : []

          content {
            dynamic "statement" {
              for_each = range(local.header_value_count)

              content {
                byte_match_statement {
                  search_string         = var.allow_header_values[statement.value]
                  positional_constraint = "EXACTLY"

                  field_to_match {
                    single_header {
                      name = lower(rule.value.name)
                    }
                  }

                  text_transformation {
                    priority = 0
                    type     = "NONE"
                  }
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-allow-header"
        sampled_requests_enabled   = true
      }
    }
  }

  # ------------------------------------------------------------ rate limit

  dynamic "rule" {
    for_each = var.rate_limit == null ? [] : [var.rate_limit]

    content {
      name     = "rate-limit"
      priority = rule.value.priority

      action {
        block {}
      }

      statement {
        rate_based_statement {
          limit                 = rule.value.limit
          evaluation_window_sec = rule.value.evaluation_window_sec
          aggregate_key_type    = rule.value.aggregate_key_type

          dynamic "forwarded_ip_config" {
            for_each = rule.value.aggregate_key_type == "FORWARDED_IP" ? [1] : []

            content {
              header_name       = "X-Forwarded-For"
              fallback_behavior = "MATCH"
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-rate-limit"
        sampled_requests_enabled   = true
      }
    }
  }

  # ------------------------------------------------------------ AWS managed rule groups

  dynamic "rule" {
    for_each = var.managed_rule_groups

    content {
      name     = rule.value.name
      priority = rule.value.priority

      override_action {
        dynamic "none" {
          for_each = rule.value.count_only ? [] : [1]
          content {}
        }

        dynamic "count" {
          for_each = rule.value.count_only ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = rule.value.vendor_name

          dynamic "rule_action_override" {
            for_each = toset(rule.value.count_rules)

            content {
              name = rule_action_override.value

              action_to_use {
                count {}
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-${rule.value.name}"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = true
  }

  tags = { Name = var.name }
}

# ---------------------------------------------------------------- associations (regional only)

resource "aws_wafv2_web_acl_association" "this" {
  for_each = var.associations

  resource_arn = each.value
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}

# ---------------------------------------------------------------- logging

resource "aws_cloudwatch_log_group" "this" {
  count = var.logging.enabled ? 1 : 0

  # WAF only logs to groups whose name starts with aws-waf-logs-.
  name              = "aws-waf-logs-${var.name}"
  retention_in_days = var.logging.retention_in_days
  kms_key_id        = var.logging.kms_key_arn
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "logging" {
  count = var.logging.enabled ? 1 : 0

  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this[0].arn}:*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

data "aws_partition" "current" {}

resource "aws_cloudwatch_log_resource_policy" "this" {
  count = var.logging.enabled ? 1 : 0

  policy_name     = "aws-waf-logs-${var.name}"
  policy_document = data.aws_iam_policy_document.logging[0].json
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count = var.logging.enabled ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.this[0].arn]

  dynamic "redacted_fields" {
    for_each = toset(concat(var.logging.redacted_headers, var.allow_header == null ? [] : [var.allow_header.name]))

    content {
      single_header {
        name = lower(redacted_fields.value)
      }
    }
  }

  depends_on = [aws_cloudwatch_log_resource_policy.this]
}
