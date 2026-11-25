variable "name" {
  description = "Service network name (ADR-44), e.g. dev-network-services. 3-63 lowercase letters, digits and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "Lattice names are 3-63 lowercase letters, digits and hyphens, without a leading, trailing or double hyphen."
  }
}

variable "organization_id" {
  description = "Client organization ID (o-...). The network auth policy allows only principals of this organization. Null in accounts outside an organization; then allowed_account_ids is used."
  type        = string
  default     = null
}

variable "allowed_account_ids" {
  description = "Accounts whose principals may call through the network when organization_id is null."
  type        = list(string)
  default     = []
}

variable "auth_policy_override" {
  description = "Full auth policy JSON instead of the generated one."
  type        = string
  default     = null
}

variable "access_logs" {
  description = "Access log destinations. destination_arns: S3 bucket, CloudWatch log group or Firehose stream ARNs (the Log Archive account in production). Empty creates a log group named log_group_name in this account."
  type = object({
    destination_arns  = optional(list(string), [])
    log_group_name    = optional(string)
    retention_in_days = optional(number, 90)
    kms_key_arn       = optional(string)
  })
  default = {}
}

variable "ram_principals" {
  description = "OU ARNs, account IDs or the organization ARN to share the service network with (inside the organization only). Empty: not shared (single-account setups)."
  type        = list(string)
  default     = []
}
