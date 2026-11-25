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

# ---------------------------------------------------------------- DNS and certificates

variable "domain_name" {
  description = "Public DNS zone for the environment, e.g. dev.example.com. The zone is created here; certificates only validate once the parent delegates it (see the name_servers output)."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.domain_name))
    error_message = "domain_name must be a lowercase DNS name such as dev.example.com."
  }
}

variable "app_hostname" {
  description = "Label of the customer-facing name (served by CloudFront)."
  type        = string
  default     = "app"
}

variable "origin_hostname" {
  description = "Label of the origin name CloudFront connects to (the public ALB)."
  type        = string
  default     = "origin"
}

variable "origin_certificate_exportable" {
  description = "Issue the origin (ALB) certificate as exportable (billed), so the firewall can load its key for TLS inspection."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------- CloudFront origin protection

variable "origin_verify_header_name" {
  description = "Header CloudFront adds to origin requests; the ALB web ACL only allows requests carrying it."
  type        = string
  default     = "X-Origin-Verify"
}

variable "origin_secret_version" {
  description = "Change to generate a new origin secret (rotation)."
  type        = string
  default     = "1"
}

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window when the secret is deleted (0 deletes immediately)."
  type        = number
  default     = 7
}

# ---------------------------------------------------------------- WAF and CloudFront

variable "cloudfront_price_class" {
  type    = string
  default = "PriceClass_100"
}

variable "waf_rate_limit" {
  description = "Requests per client IP per 5 minutes before CloudFront's web ACL blocks it."
  type        = number
  default     = 2000
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "enable_shield_advanced" {
  description = "Protect CloudFront and the public ALB with Shield Advanced. Needs an active subscription (about USD 3,000/month, 1-year commitment), which this code does not create."
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
