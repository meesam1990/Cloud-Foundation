provider "aws" {
  region              = local.eks.region
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

# The cluster token comes from the AWS provider's own credentials (TFE dynamic credentials, a
# profile or the assumed role), so the runner needs no AWS CLI. The token is valid for 15
# minutes, enough for the Helm timeouts in main.tf.
data "aws_eks_cluster_auth" "this" {
  name = local.eks.cluster_name
}

provider "helm" {
  kubernetes = {
    host                   = local.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(local.eks.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# Reads the other stacks' outputs (remote-state.tf). In a TFE run it authenticates with the run's
# own token; locally it needs TFE_TOKEN or `terraform login tfe.client.com`.
provider "tfe" {
  hostname = var.tfe_hostname
}
