variable "environment" {
  description = "Environment (ADR-44)."
  type        = string
  default     = "prod"
}

variable "region" {
  description = "IPAM home region. Pools for other operating regions are managed from here."
  type        = string
  default     = "us-west-2"
}

variable "account" {
  description = "network-prod, the IPAM delegated administrator. With TFE dynamic credentials profile and role_arn are null."
  type = object({
    id       = string
    profile  = optional(string)
    role_arn = optional(string)
  })

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account.id))
    error_message = "account.id must be a 12-digit AWS account ID."
  }
}

variable "jira_ticket" {
  description = "Jira ticket for the jira_ticket tag (lowercase, ADR-46)."
  type        = string
  default     = "awsm-28"
}

variable "ou_arns" {
  description = "OU ARNs keyed by OU key (client-apps, integrations, oracle-apps, infrastructure, analytics, devops, security, network, sandbox). Each OU's pools are shared through RAM with its ARN. A missing key: pools are created but not shared yet."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k in keys(var.ou_arns) : contains(["client-apps", "integrations", "oracle-apps", "infrastructure", "analytics", "devops", "security", "network", "sandbox"], k)
    ])
    error_message = "ou_arns keys must be OU keys: client-apps, integrations, oracle-apps, infrastructure, analytics, devops, security, network, sandbox."
  }
}
