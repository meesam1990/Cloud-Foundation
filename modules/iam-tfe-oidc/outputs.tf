output "oidc_provider_arn" {
  description = "ARN of the TFE IAM OIDC provider in this account (created here or passed in). Pass it to another module call in the same account with create_oidc_provider = false."
  value       = local.oidc_provider_arn
}

output "account_id" {
  description = "Account the roles were created in."
  value       = local.account_id
}

output "roles" {
  description = "Per stack key: TFE workspace name, plan role ARN and apply role ARN."
  value = {
    for k, w in local.workspaces : k => {
      workspace      = w.workspace
      plan_role_arn  = aws_iam_role.this["${k}/plan"].arn
      apply_role_arn = aws_iam_role.this["${k}/apply"].arn
    }
  }
}

output "plan_role_arns" {
  description = "Plan role ARN per stack key."
  value       = { for k in keys(local.workspaces) : k => aws_iam_role.this["${k}/plan"].arn }
}

output "apply_role_arns" {
  description = "Apply role ARN per stack key."
  value       = { for k in keys(local.workspaces) : k => aws_iam_role.this["${k}/apply"].arn }
}

output "tfe_workspace_variables" {
  description = "Per TFE workspace name: the environment variables (category env, not terraform) the terraform_enterprise repo sets on the workspace. TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE appears only when the audience is not the TFE default."
  value = {
    for k, w in local.workspaces : w.workspace => merge(
      {
        TFC_AWS_PROVIDER_AUTH  = "true"
        TFC_AWS_PLAN_ROLE_ARN  = aws_iam_role.this["${k}/plan"].arn
        TFC_AWS_APPLY_ROLE_ARN = aws_iam_role.this["${k}/apply"].arn
      },
      var.audience == "aws.workload.identity" ? {} : { TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE = var.audience },
    )
  }
}
