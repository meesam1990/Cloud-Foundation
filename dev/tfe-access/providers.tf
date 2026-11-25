# Bootstrap credentials (admin): a named profile locally, or an assumed role from the AFT
# account baseline. Never TFE dynamic credentials: this stack creates them.

# Network account: Cloud WAN, egress/inbound VPCs, VPC Lattice service network.
provider "aws" {
  region              = var.region
  profile             = var.network_account.profile
  allowed_account_ids = [var.network_account.id]

  dynamic "assume_role" {
    for_each = var.network_account.role_arn == null ? [] : [var.network_account.role_arn]

    content {
      role_arn = assume_role.value
    }
  }

  default_tags {
    tags = module.context_network.tags
  }
}

# Workloads account: application VPC, edge, EKS, Lattice associations, platform. In dev it is
# the same account as the network account.
provider "aws" {
  alias               = "workloads"
  region              = var.region
  profile             = var.workloads_account.profile
  allowed_account_ids = [var.workloads_account.id]

  dynamic "assume_role" {
    for_each = var.workloads_account.role_arn == null ? [] : [var.workloads_account.role_arn]

    content {
      role_arn = assume_role.value
    }
  }

  default_tags {
    tags = module.context_workloads.tags
  }
}
