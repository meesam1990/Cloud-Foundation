terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.71.0"
    }
  }

  # State: local for now (terraform.tfstate in this folder).
  #
  # Bootstrap stack: run it with admin credentials, locally or from the AFT account baseline,
  # NOT on Terraform Enterprise. It creates the OIDC provider and the roles TFE itself uses to
  # reach AWS, so a TFE workspace cannot run it before it exists, and a TFE apply role must never
  # be able to change it (the roles live under the /tfe/ path, outside every apply role's grant).
}
