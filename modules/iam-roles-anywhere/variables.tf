variable "name" {
  description = "Trust anchor and profile name (ADR-44), e.g. dev-workloads-onprem."
  type        = string
}

variable "ca_certificate_pem" {
  description = "PEM of the CA that issues the on-premises callers' certificates (the Client CA; open item in ADR-36)."
  type        = string
  default     = null
}

variable "acm_pca_arn" {
  description = "ACM Private CA that issues the callers' certificates, instead of ca_certificate_pem."
  type        = string
  default     = null
}

variable "roles" {
  description = "Roles keyed by caller, with the certificate subject CN allowed to assume each one and an optional inline policy."
  type = map(object({
    role_name      = string
    certificate_cn = string
    inline_policy  = optional(string)
  }))

  validation {
    condition     = alltrue([for r in values(var.roles) : length(r.role_name) <= 64])
    error_message = "IAM role names are 64 characters or fewer."
  }
}

variable "session_duration_seconds" {
  description = "Credential lifetime."
  type        = number
  default     = 3600
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary for the roles."
  type        = string
  default     = null
}
