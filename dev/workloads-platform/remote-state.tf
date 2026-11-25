# Outputs of the dev/workloads-* stacks, read from their TFE workspaces. Each must share its
# state with this one (workspace setting "Remote state sharing", set in terraform_enterprise).

data "tfe_outputs" "app_network" {
  organization = var.tfe_organization
  workspace    = "${var.environment}-workloads-network"
}

data "tfe_outputs" "edge" {
  organization = var.tfe_organization
  workspace    = "${var.environment}-workloads-edge"
}

data "tfe_outputs" "eks" {
  organization = var.tfe_organization
  workspace    = "${var.environment}-workloads-eks"
}

data "tfe_outputs" "lattice" {
  organization = var.tfe_organization
  workspace    = "${var.environment}-workloads-lattice"
}

locals {
  app     = data.tfe_outputs.app_network.nonsensitive_values
  edge    = data.tfe_outputs.edge.nonsensitive_values
  eks     = data.tfe_outputs.eks.nonsensitive_values
  lattice = data.tfe_outputs.lattice.nonsensitive_values
}
