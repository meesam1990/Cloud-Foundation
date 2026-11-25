terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.71.0"
    }
  }

  # State: local for now (terraform.tfstate in this folder). For Terraform Enterprise add
  #
  #   cloud {
  #     hostname     = "tfe.client.com"
  #     organization = "client"
  #     workspaces { name = "prod-network-ipam" }
  #   }
}
