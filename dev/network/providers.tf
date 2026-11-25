# Everything in this stack belongs to the network account (network-dev; network-prod in production).
# Credentials: a named profile locally, an assumed role, or neither on TFE (dynamic credentials,
# ADR-38: TFC_AWS_PROVIDER_AUTH with the plan/apply roles from dev/tfe-access).

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
    tags = module.context.tags
  }
}

# Cloud WAN global resources (global network, core network, policy) live in its home region.
provider "aws" {
  alias               = "cloudwan"
  region              = var.cloudwan_home_region
  profile             = var.network_account.profile
  allowed_account_ids = [var.network_account.id]

  dynamic "assume_role" {
    for_each = var.network_account.role_arn == null ? [] : [var.network_account.role_arn]

    content {
      role_arn = assume_role.value
    }
  }

  default_tags {
    tags = module.context.tags
  }
}
