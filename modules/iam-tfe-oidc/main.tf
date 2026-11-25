# Terraform Enterprise dynamic credentials for one AWS account (ADR-38).
#
# Each TFE run gets a signed OIDC token whose subject names the organization, project, workspace
# and run phase:
#
#   organization:<org>:project:<project>:workspace:<workspace>:run_phase:<plan|apply>
#
# AWS validates it against the TFE keys (https://<host>/.well-known/openid-configuration and
# /.well-known/jwks) through an IAM OIDC identity provider in this account. The module builds:
#
# - the IAM OIDC provider for TFE (optional: an account holds one provider per URL, so a second
#   module call in the same account passes create_oidc_provider = false and the existing ARN);
# - per workspace a PLAN role, trusted for run_phase:plan only, with read-only permissions
#   (ReadOnlyAccess by default);
# - per workspace an APPLY role, trusted for run_phase:apply only, scoped to the stack instead of
#   account-wide admin: PowerUserAccess by default (everything except IAM, Organizations and
#   Account management) plus an inline policy that allows IAM changes only on roles, policies,
#   instance profiles and SAML providers whose names start with the workspace's iam_name_prefixes,
#   under path "/". iam:* on those roles includes iam:PassRole.
#
# Both roles live under role_path ("/tfe/" by default). Their ARNs are role/tfe/<name>, which the
# apply role's "/"-path IAM grants never match, so an apply role cannot edit, re-trust or attach
# policies to its own role or to any other TFE role; an explicit deny repeats this, and also
# protects the TFE OIDC provider.
#
# Known limit: an apply role may create a prefixed role and attach any policy to it. Set
# permissions_boundary_arn and a boundary condition in apply_inline_policy if that has to be closed.
#
# A role trusts only the OIDC provider in its own account, so every target account gets its own
# module call. No workload workspace gets a role in the Client - Management account.

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  iam_arn    = "arn:${local.partition}:iam::${local.account_id}"

  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.tfe[0].arn : var.oidc_provider_arn

  # Default policy ARNs in variables.tf use the aws partition; rewrite them for other partitions.
  workspaces = {
    for k, w in var.workspaces : k => merge(w, {
      subject_prefix    = "organization:${var.organization}:project:${w.project}:workspace:${w.workspace}:run_phase"
      plan_policy_arns  = [for a in w.plan_policy_arns : replace(a, "/^arn:aws:/", "arn:${local.partition}:")]
      apply_policy_arns = [for a in w.apply_policy_arns : replace(a, "/^arn:aws:/", "arn:${local.partition}:")]
    })
  }

  phases = {
    for pair in setproduct(keys(local.workspaces), ["plan", "apply"]) : "${pair[0]}/${pair[1]}" => {
      key   = pair[0]
      phase = pair[1]
      name  = "${local.workspaces[pair[0]].role_name_prefix}-${pair[1]}"
    }
  }

  plan_attachments = merge([
    for k, w in local.workspaces : { for a in w.plan_policy_arns : "${k}/${a}" => { key = k, arn = a } }
  ]...)

  apply_attachments = merge([
    for k, w in local.workspaces : { for a in w.apply_policy_arns : "${k}/${a}" => { key = k, arn = a } }
  ]...)
}

# ---------------------------------------------------------------- OIDC provider

resource "aws_iam_openid_connect_provider" "tfe" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://${var.oidc_hostname}"
  client_id_list  = [var.audience]
  thumbprint_list = length(var.thumbprint_list) == 0 ? null : var.thumbprint_list

  tags = { Name = var.oidc_hostname }
}

# ---------------------------------------------------------------- roles

data "aws_iam_policy_document" "trust" {
  for_each = local.phases

  statement {
    sid     = "TfeRun${title(each.value.phase)}"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_hostname}:aud"
      values   = [var.audience]
    }

    # Exact match on organization, project, workspace and run phase. No wildcards: a plan token
    # cannot assume the apply role, and no other workspace's token matches.
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_hostname}:sub"
      values   = ["${local.workspaces[each.value.key].subject_prefix}:${each.value.phase}"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = local.phases

  name                 = each.value.name
  path                 = var.role_path
  description          = "TFE ${each.value.phase} role for workspace ${local.workspaces[each.value.key].workspace} (ADR-38)."
  assume_role_policy   = data.aws_iam_policy_document.trust[each.key].json
  max_session_duration = var.max_session_duration
  permissions_boundary = var.permissions_boundary_arn

  tags = { Name = each.value.name }

  lifecycle {
    precondition {
      condition     = length(each.value.name) <= 64
      error_message = "Role name ${each.value.name} is longer than 64 characters (ADR-44); shorten role_name_prefix."
    }

    precondition {
      condition     = local.oidc_provider_arn != null
      error_message = "oidc_provider_arn is required when create_oidc_provider is false."
    }

    precondition {
      condition     = var.create_oidc_provider || split(":", coalesce(var.oidc_provider_arn, "::::"))[4] == local.account_id
      error_message = "oidc_provider_arn must be a provider in this account (${local.account_id}); a role can only trust an identity provider in its own account."
    }
  }
}

resource "aws_iam_role_policy_attachment" "plan" {
  for_each = local.plan_attachments

  role       = aws_iam_role.this["${each.value.key}/plan"].name
  policy_arn = each.value.arn
}

resource "aws_iam_role_policy_attachment" "apply" {
  for_each = local.apply_attachments

  role       = aws_iam_role.this["${each.value.key}/apply"].name
  policy_arn = each.value.arn
}

# ---------------------------------------------------------------- apply role: scoped IAM

data "aws_iam_policy_document" "apply_iam" {
  for_each = local.workspaces

  statement {
    sid    = "IamOnStackResources"
    effect = "Allow"
    # iam:* includes iam:PassRole on the stack's own roles.
    actions = ["iam:*"]
    resources = concat(
      flatten([
        for p in each.value.iam_name_prefixes : [
          "${local.iam_arn}:role/${p}*",
          "${local.iam_arn}:policy/${p}*",
          "${local.iam_arn}:instance-profile/${p}*",
          "${local.iam_arn}:saml-provider/${p}*",
        ]
      ]),
      [for h in each.value.oidc_provider_hosts : "${local.iam_arn}:oidc-provider/${h}"],
    )
  }

  statement {
    sid    = "IamRead"
    effect = "Allow"
    actions = [
      "iam:Get*",
      "iam:List*",
      "iam:CreateServiceLinkedRole",
    ]
    resources = ["*"]
  }

  # Belt and braces: the path already keeps the TFE roles out of the grant above.
  statement {
    sid         = "DenyTfeAccessChanges"
    effect      = "Deny"
    not_actions = ["iam:Get*", "iam:List*"]
    resources = [
      "${local.iam_arn}:role${var.role_path}*",
      "${local.iam_arn}:oidc-provider/${var.oidc_hostname}",
    ]
  }
}

resource "aws_iam_role_policy" "apply_iam" {
  for_each = local.workspaces

  name   = "stack-iam"
  role   = aws_iam_role.this["${each.key}/apply"].id
  policy = data.aws_iam_policy_document.apply_iam[each.key].json
}

resource "aws_iam_role_policy" "apply_extra" {
  for_each = { for k, w in local.workspaces : k => w if w.apply_inline_policy != null }

  name   = "stack-extra"
  role   = aws_iam_role.this["${each.key}/apply"].id
  policy = each.value.apply_inline_policy
}
