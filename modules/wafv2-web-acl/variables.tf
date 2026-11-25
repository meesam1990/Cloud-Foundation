variable "name" {
  type = string
}

variable "description" {
  type    = string
  default = "Managed by Terraform"
}

variable "scope" {
  description = "REGIONAL (ALB, API Gateway, ...) or CLOUDFRONT (create in us-east-1)."
  type        = string

  validation {
    condition     = contains(["REGIONAL", "CLOUDFRONT"], var.scope)
    error_message = "scope must be REGIONAL or CLOUDFRONT."
  }
}

variable "default_action" {
  description = "Action for requests no rule matched: allow or block."
  type        = string
  default     = "allow"

  validation {
    condition     = contains(["allow", "block"], var.default_action)
    error_message = "default_action must be allow or block."
  }
}

variable "managed_rule_groups" {
  description = "AWS managed rule groups. count_only runs the whole group in count mode; count_rules counts single rules."
  type = list(object({
    name        = string
    vendor_name = optional(string, "AWS")
    priority    = number
    count_only  = optional(bool, false)
    count_rules = optional(list(string), [])
  }))
  default = []
}

variable "rate_limit" {
  description = "Rate-based rule. aggregate_key_type FORWARDED_IP keys on X-Forwarded-For (behind CloudFront). Null to disable."
  type = object({
    limit                 = number
    priority              = number
    evaluation_window_sec = optional(number, 300)
    aggregate_key_type    = optional(string, "IP")
  })
  default = null

  validation {
    condition     = var.rate_limit == null || contains(["IP", "FORWARDED_IP"], try(var.rate_limit.aggregate_key_type, "IP"))
    error_message = "aggregate_key_type must be IP or FORWARDED_IP."
  }
}

variable "allow_header" {
  description = "Allow requests whose header <name> equals one of allow_header_values. Null to disable."
  type = object({
    name     = string
    priority = number
  })
  default = null
}

variable "allow_header_values" {
  description = "Accepted values for allow_header (one, or two while rotating)."
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "associations" {
  description = "Regional resources to protect, keyed by a stable name (REGIONAL scope only)."
  type        = map(string)
  default     = {}
}

variable "logging" {
  type = object({
    enabled           = optional(bool, true)
    retention_in_days = optional(number, 30)
    kms_key_arn       = optional(string)
    redacted_headers  = optional(list(string), ["authorization", "cookie"])
  })
  default = {}
}
