terraform {
  required_version = ">= 1.11"

  # Exact provider versions (ADR-42: versions.tf pins Terraform and provider versions).
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "0.84.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "6.71.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }
  }

  # State: local for now. Terraform Enterprise (ADR-42, ADR-38): workspace dev-workloads-platform, AWS access
  # through dynamic credentials (roles from dev/tfe-access).
  # remote-state.tf reads the other stacks' outputs with tfe_outputs.
  #
  #   cloud {
  #     hostname     = "tfe.client.com"
  #     organization = "client"
  #     workspaces { name = "dev-workloads-platform" }
  #   }
  # The TFE agents need network access to the EKS API endpoint (public_access_cidrs in workloads-eks).
}
