variable "environment" {
  type    = string
  default = "dev"
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

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}

variable "instance_types" {
  type    = list(string)
  default = ["t3.large"]
}

variable "node_count" {
  description = "Nodes in the managed node group (min = desired; max = this + 1)."
  type        = number
  default     = 2
}

variable "detect_my_ip" {
  description = "Allow this machine's public IP (checkip.amazonaws.com, detected on every plan) on the public API endpoint. Null (default) = automatic: on for local runs, off for TFE runs (detected from the TFE plan/apply role), which would otherwise allow whichever runner IP the plan happened to use. true/false forces it."
  type        = bool
  default     = null
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to the public API endpoint: the TFE runners' egress CIDRs (workloads-platform runs Helm from them) and admin networks. Empty makes the endpoint private only; TFE runners then need a network path into the VPC."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.public_access_cidrs : can(cidrnetmask(c))])
    error_message = "Every entry must be a valid CIDR."
  }
}

variable "admin_principal_arns" {
  description = "IAM roles/users given cluster admin (the creator is added automatically)."
  type        = list(string)
  default     = []
}

variable "lbc_namespace" {
  type    = string
  default = "kube-system"
}

variable "lbc_service_account" {
  type    = string
  default = "aws-load-balancer-controller"
}

variable "lattice_callers" {
  description = "Service accounts that call VPC Lattice services, keyed by the role descriptor (role name {environment}-{function}-{key}). Each gets its own Pod Identity role."
  type = map(object({
    namespace       = string
    service_account = string
  }))
  default = {
    frontend = { namespace = "sample-app", service_account = "frontend" }
  }
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
