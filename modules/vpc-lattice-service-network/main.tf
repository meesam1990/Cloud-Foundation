# VPC Lattice service network for one environment (ADR-36), owned by the network account.
#
#   auth          AWS_IAM, always. The network policy allows only signed requests from principals
#                 in the Client organization (aws:PrincipalOrgID) or, where there is no organization
#                 (test accounts), from the listed accounts. Each service adds its own policy;
#                 both must allow a request (deny by default).
#   access logs   every request through the network, with the caller's identity. ADR-36 sends them
#                 to the Log Archive account (security-audit): pass the S3 bucket / Firehose ARN
#                 there in access_logs.destination_arns. Without one, a CloudWatch log group in
#                 this account is created.
#   sharing       AWS RAM, inside the organization only (allow_external_principals = false), to
#                 the OUs or accounts of this environment. Workload accounts then associate their
#                 VPCs and services themselves.
#
# A VPC association gives reachability and DNS only; it is not permission.

locals {
  principal_condition = var.organization_id != null ? {
    test     = "StringEquals"
    variable = "aws:PrincipalOrgID"
    values   = [var.organization_id]
    } : {
    test     = "StringEquals"
    variable = "aws:PrincipalAccount"
    values   = var.allowed_account_ids
  }

  create_log_group = length(var.access_logs.destination_arns) == 0
}

resource "aws_vpclattice_service_network" "this" {
  name      = var.name
  auth_type = "AWS_IAM"

  tags = { Name = var.name }
}

data "aws_iam_policy_document" "auth" {
  statement {
    sid       = "SignedRequestsFromInsideClient"
    effect    = "Allow"
    actions   = ["vpc-lattice-svcs:Invoke", "vpc-lattice-svcs:Connect"]
    resources = ["*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = local.principal_condition.test
      variable = local.principal_condition.variable
      values   = local.principal_condition.values
    }

    # Unsigned (anonymous) requests never match.
    condition {
      test     = "StringNotEqualsIgnoreCase"
      variable = "aws:PrincipalType"
      values   = ["anonymous"]
    }
  }
}

resource "aws_vpclattice_auth_policy" "this" {
  resource_identifier = aws_vpclattice_service_network.this.arn
  policy              = coalesce(var.auth_policy_override, data.aws_iam_policy_document.auth.json)

  lifecycle {
    precondition {
      condition     = var.organization_id != null || length(var.allowed_account_ids) > 0
      error_message = "Set organization_id, or allowed_account_ids where there is no organization."
    }
  }
}

# ---------------------------------------------------------------- access logs

resource "aws_cloudwatch_log_group" "access_logs" {
  count = local.create_log_group ? 1 : 0

  name              = var.access_logs.log_group_name
  retention_in_days = var.access_logs.retention_in_days
  kms_key_id        = var.access_logs.kms_key_arn

  lifecycle {
    precondition {
      condition     = var.access_logs.log_group_name != null
      error_message = "access_logs.log_group_name is required when no destination_arns are given."
    }
  }
}

resource "aws_vpclattice_access_log_subscription" "this" {
  for_each = local.create_log_group ? { local = aws_cloudwatch_log_group.access_logs[0].arn } : { for i, a in var.access_logs.destination_arns : tostring(i) => a }

  resource_identifier = aws_vpclattice_service_network.this.arn
  destination_arn     = each.value

  tags = { Name = "${var.name}-access-logs" }
}

# ---------------------------------------------------------------- sharing (AWS RAM)

resource "aws_ram_resource_share" "this" {
  count = length(var.ram_principals) > 0 ? 1 : 0

  name                      = var.name
  allow_external_principals = false

  tags = { Name = var.name }
}

resource "aws_ram_resource_association" "this" {
  count = length(var.ram_principals) > 0 ? 1 : 0

  resource_share_arn = aws_ram_resource_share.this[0].arn
  resource_arn       = aws_vpclattice_service_network.this.arn
}

resource "aws_ram_principal_association" "this" {
  for_each = toset(var.ram_principals)

  resource_share_arn = aws_ram_resource_share.this[0].arn
  principal          = each.value
}
