# Customer managed KMS key with rotation and an alias.
#
# Without a policy, the default key policy applies: the account's IAM policies decide who may use
# the key (the account root has full access).

resource "aws_kms_key" "this" {
  description             = var.description
  enable_key_rotation     = true
  rotation_period_in_days = var.rotation_period_in_days
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = var.policy

  tags = { Name = var.alias }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias}"
  target_key_id = aws_kms_key.this.key_id
}
