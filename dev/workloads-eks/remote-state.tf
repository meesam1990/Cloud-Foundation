# Outputs of dev/workloads-network, read from its TFE workspace. That workspace must share its
# state with this one (workspace setting "Remote state sharing", set in terraform_enterprise).

data "tfe_outputs" "app_network" {
  organization = var.tfe_organization
  workspace    = "${var.environment}-workloads-network"
}

locals {
  app = data.tfe_outputs.app_network.nonsensitive_values
}
