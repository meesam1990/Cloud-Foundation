# Outputs of dev/network, read from its TFE workspace. That workspace must share its state with
# this one (workspace setting "Remote state sharing", set in terraform_enterprise).

data "tfe_outputs" "network" {
  organization = var.tfe_organization
  workspace    = "${var.environment}-network"
}

locals {
  network = data.tfe_outputs.network.nonsensitive_values
}
