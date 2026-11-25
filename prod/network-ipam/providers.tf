# network-prod (IPAM delegated administrator), IPAM home region. The RAM shares for us-east-1
# pools use the resource-level region argument (AWS provider 6.x), so no second provider.

provider "aws" {
  region              = var.region
  profile             = var.account.profile
  allowed_account_ids = [var.account.id]

  dynamic "assume_role" {
    for_each = var.account.role_arn == null ? [] : [var.account.role_arn]

    content {
      role_arn = assume_role.value
    }
  }

  default_tags {
    tags = module.context.tags
  }
}
