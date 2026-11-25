variable "environment" {
  description = "Environment (ADR-44): prod, dev, test or uat."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "Region of the provider API calls. IAM is global; the roles work in every region."
  type        = string
  default     = "us-west-2"
}

variable "jira_ticket" {
  description = "Jira ticket for the jira_ticket tag (ADR-46), lowercase."
  type        = string
  default     = "awsm-28"
}

variable "network_account" {
  description = "Network account (Cloud WAN, egress/inbound VPCs, Lattice service network). Bootstrap credentials: admin profile or role."
  type = object({
    id       = string
    profile  = optional(string)
    role_arn = optional(string)
  })
}

variable "workloads_account" {
  description = "Workloads account (application stacks). May be the same account as network_account (dev); the TFE OIDC provider is then created once."
  type = object({
    id       = string
    profile  = optional(string)
    role_arn = optional(string)
  })
}

variable "tfe_hostname" {
  description = "Terraform Enterprise hostname (token issuer)."
  type        = string
  default     = "tfe.client.com"
}

variable "tfe_audience" {
  description = "Audience of the TFE run tokens. Change only together with TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE on the workspaces."
  type        = string
  default     = "aws.workload.identity"
}

variable "tfe_organization" {
  description = "TFE organization."
  type        = string
  default     = "client"
}

variable "tfe_project" {
  description = "TFE project holding the landing-zone workspaces."
  type        = string
  default     = "aws-landing-zone"
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary for all TFE plan and apply roles (optional)."
  type        = string
  default     = null
}
