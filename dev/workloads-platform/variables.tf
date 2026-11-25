variable "environment" {
  description = "Environment of this stack folder (ADR-42)."
  type        = string
  default     = "dev"
}

variable "jira_ticket" {
  description = "jira_ticket tag (ADR-46), lowercase."
  type        = string
  default     = "awsm-28"
}

variable "apps_account" {
  type = object({
    id       = string
    profile  = optional(string)
    role_arn = optional(string)
  })
}

variable "lbc_chart_version" {
  description = "aws-load-balancer-controller chart (eks-charts). Keep policies/aws-load-balancer-controller.json in workloads-eks at the matching controller version."
  type        = string
  default     = "3.6.2"
}

variable "cert_manager_chart_version" {
  description = "cert-manager chart (charts.jetstack.io)."
  type        = string
  default     = "v1.16.2"
}

variable "deploy_sample_app" {
  type    = bool
  default = true
}

variable "sample_app_network_policy" {
  description = "Restrict the sample app pods to traffic from the ALB subnets (NetworkPolicy)."
  type        = bool
  default     = false
}

variable "tfe_hostname" {
  description = "Terraform Enterprise host that holds the other stacks' state (tfe_outputs)."
  type        = string
  default     = "tfe.client.com"
}

variable "tfe_organization" {
  description = "TFE organization of the workspaces read in remote-state.tf."
  type        = string
  default     = "client"
}
