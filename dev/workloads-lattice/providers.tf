provider "aws" {
  region              = local.app.region
  profile             = var.apps_account.profile
  allowed_account_ids = [var.apps_account.id]

  dynamic "assume_role" {
    for_each = var.apps_account.role_arn == null ? [] : [var.apps_account.role_arn]

    content {
      role_arn = assume_role.value
    }
  }

  default_tags {
    tags = module.context.tags
  }
}

# Reads the other stacks' outputs (remote-state.tf). In a TFE run it authenticates with the run's
# own token; locally it needs TFE_TOKEN or `terraform login tfe.client.com`.
provider "tfe" {
  hostname = var.tfe_hostname
}
