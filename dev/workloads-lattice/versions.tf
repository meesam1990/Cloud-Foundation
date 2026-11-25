terraform {
  required_version = ">= 1.11"

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "0.84.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "6.71.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.1.0"
    }
  }

  # State: local for now. Terraform Enterprise (ADR-42): workspace dev-workloads-lattice,
  #
  #   cloud {
  #     hostname     = "tfe.client.com"
  #     organization = "client"
  #     workspaces { name = "dev-workloads-lattice" }
  #   }
  #
  # The state holds the dev CA and certificate keys when certificate_arn is not set: keep it in TFE.
}
