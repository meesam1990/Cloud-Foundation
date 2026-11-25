# TFE dynamic credentials for the dev landing-zone workspaces (ADR-38). Bootstrap stack: run it
# with admin credentials, not on TFE (see versions.tf).
#
# Per target account: the IAM OIDC provider for tfe.client.com and, per TFE workspace, a
# read-only plan role (run_phase:plan) and a stack-scoped apply role (run_phase:apply), under the
# /tfe/ path. Role names: {environment}-{function}-tfe-{stack}-plan|apply.
#
#   account    stack folder              TFE workspace (ADR-42)    roles
#   network    dev/network               dev-network               dev-network-tfe-network-*
#   workloads  dev/workloads-network     dev-workloads-network     dev-workloads-tfe-network-*
#   workloads  dev/workloads-edge        dev-workloads-edge        dev-workloads-tfe-edge-*
#   workloads  dev/workloads-eks         dev-workloads-eks         dev-workloads-tfe-eks-*
#   workloads  dev/workloads-lattice     dev-workloads-lattice     dev-workloads-tfe-lattice-*
#   workloads  dev/workloads-platform    dev-workloads-platform    dev-workloads-tfe-platform-*
#
# In dev both accounts are the same test account. An account holds one OIDC provider per URL, so
# the network call creates it and the workloads call reuses its ARN.
#
# No workload workspace gets a role in the Client - Management account.

module "context_network" {
  source = "../../modules/context"

  environment = var.environment
  function    = "network"
  tags        = { owner = "devops", jira_ticket = var.jira_ticket }
}

module "context_workloads" {
  source = "../../modules/context"

  environment = var.environment
  function    = "workloads"
  tags        = { owner = "devops", jira_ticket = var.jira_ticket }
}

locals {
  same_account = var.network_account.id == var.workloads_account.id

  network_stacks   = ["network"]
  workloads_stacks = ["network", "edge", "eks", "lattice", "platform"]

  network_workspaces = {
    for s in local.network_stacks : s => {
      project           = var.tfe_project
      workspace         = module.context_network.base # dev-network: the stack is the account's base stack
      role_name_prefix  = "${module.context_network.base}-tfe-${s}"
      iam_name_prefixes = ["${module.context_network.base}-"]
    }
  }

  workloads_workspaces = {
    for s in local.workloads_stacks : s => {
      project           = var.tfe_project
      workspace         = "${module.context_workloads.base}-${s}"
      role_name_prefix  = "${module.context_workloads.base}-tfe-${s}"
      iam_name_prefixes = ["${module.context_workloads.base}-"]
    }
  }
}

module "tfe_network" {
  source = "../../modules/iam-tfe-oidc"

  oidc_hostname            = var.tfe_hostname
  audience                 = var.tfe_audience
  organization             = var.tfe_organization
  create_oidc_provider     = true
  workspaces               = local.network_workspaces
  permissions_boundary_arn = var.permissions_boundary_arn
}

module "tfe_workloads" {
  source = "../../modules/iam-tfe-oidc"

  providers = {
    aws = aws.workloads
  }

  oidc_hostname            = var.tfe_hostname
  audience                 = var.tfe_audience
  organization             = var.tfe_organization
  create_oidc_provider     = !local.same_account
  oidc_provider_arn        = local.same_account ? module.tfe_network.oidc_provider_arn : null
  workspaces               = local.workloads_workspaces
  permissions_boundary_arn = var.permissions_boundary_arn
}
