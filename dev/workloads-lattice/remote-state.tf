# Outputs of dev/workloads-network and dev/workloads-eks, read from their TFE workspaces. Both
# must share their state with this one (workspace setting "Remote state sharing", set in
# terraform_enterprise).

data "tfe_outputs" "app_network" {
  organization = var.tfe_organization
  workspace    = "${var.environment}-workloads-network"
}

data "tfe_outputs" "eks" {
  organization = var.tfe_organization
  workspace    = "${var.environment}-workloads-eks"
}

locals {
  app = data.tfe_outputs.app_network.nonsensitive_values
  eks = data.tfe_outputs.eks.nonsensitive_values
}
