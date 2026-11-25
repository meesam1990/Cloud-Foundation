output "oidc_provider_arns" {
  description = "TFE IAM OIDC provider per account role (network, workloads); the same ARN when both are one account."
  value = {
    network   = module.tfe_network.oidc_provider_arn
    workloads = module.tfe_workloads.oidc_provider_arn
  }
}

output "plan_role_arns" {
  description = "Plan role ARN per TFE workspace."
  value = merge(
    { for k, r in module.tfe_network.roles : r.workspace => r.plan_role_arn },
    { for k, r in module.tfe_workloads.roles : r.workspace => r.plan_role_arn },
  )
}

output "apply_role_arns" {
  description = "Apply role ARN per TFE workspace."
  value = merge(
    { for k, r in module.tfe_network.roles : r.workspace => r.apply_role_arn },
    { for k, r in module.tfe_workloads.roles : r.workspace => r.apply_role_arn },
  )
}

output "tfe_workspace_variables" {
  description = "Per TFE workspace: environment variables (category env) for the terraform_enterprise repo to set. Copy as is."
  value       = merge(module.tfe_network.tfe_workspace_variables, module.tfe_workloads.tfe_workspace_variables)
}
