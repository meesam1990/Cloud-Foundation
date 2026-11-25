# IAM Roles Anywhere for on-premises callers (ADR-34/36): data center systems that call AWS
# services through Lattice sign their requests (SigV4) with short-lived credentials obtained with
# an X.509 certificate from the Client CA, instead of long-lived keys.
#
#   trust anchor  the issuing CA (PEM bundle, or an ACM Private CA ARN)
#   roles         one per calling system; trusted only for certificates from this anchor whose
#                 subject CN matches the system
#   profile       which roles the anchor's certificates may assume, with a session duration
#
# The caller runs the aws_signing_helper with its certificate and key; the role ARN is then named
# in the Lattice service auth policy like any other caller.

resource "aws_rolesanywhere_trust_anchor" "this" {
  name    = var.name
  enabled = true

  source {
    source_type = var.acm_pca_arn == null ? "CERTIFICATE_BUNDLE" : "AWS_ACM_PCA"

    source_data {
      x509_certificate_data = var.acm_pca_arn == null ? var.ca_certificate_pem : null
      acm_pca_arn           = var.acm_pca_arn
    }
  }

  tags = { Name = var.name }

  lifecycle {
    precondition {
      condition     = (var.acm_pca_arn == null) != (var.ca_certificate_pem == null)
      error_message = "Give exactly one of ca_certificate_pem or acm_pca_arn."
    }
  }
}

data "aws_iam_policy_document" "assume" {
  for_each = var.roles

  statement {
    actions = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]

    principals {
      type        = "Service"
      identifiers = ["rolesanywhere.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_rolesanywhere_trust_anchor.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/x509Subject/CN"
      values   = [each.value.certificate_cn]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = var.roles

  name                 = each.value.role_name
  description          = "IAM Roles Anywhere: ${each.value.certificate_cn}"
  assume_role_policy   = data.aws_iam_policy_document.assume[each.key].json
  max_session_duration = 3600
  permissions_boundary = var.permissions_boundary_arn

  tags = { Name = each.value.role_name }
}

resource "aws_iam_role_policy" "this" {
  for_each = { for k, r in var.roles : k => r if r.inline_policy != null }

  name   = "access"
  role   = aws_iam_role.this[each.key].id
  policy = each.value.inline_policy
}

resource "aws_rolesanywhere_profile" "this" {
  name             = var.name
  enabled          = true
  role_arns        = [for r in aws_iam_role.this : r.arn]
  duration_seconds = var.session_duration_seconds

  tags = { Name = var.name }
}
