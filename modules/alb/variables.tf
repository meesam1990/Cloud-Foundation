variable "name" {
  description = "Load balancer name (32 characters max)."
  type        = string

  validation {
    condition     = length(var.name) <= 32
    error_message = "ELB names are limited to 32 characters."
  }
}

variable "internal" {
  type    = bool
  default = true
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "One subnet per AZ."
  type        = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "certificate_arn" {
  description = "Default certificate of the HTTPS listener (ACM, same region)."
  type        = string
}

variable "additional_certificate_arns" {
  description = "Extra certificates on the listener (SNI)."
  type        = list(string)
  default     = []
}

variable "ssl_policy" {
  type    = string
  default = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "target_group_name" {
  description = "Target group name (32 characters max)."
  type        = string

  validation {
    condition     = length(var.target_group_name) <= 32
    error_message = "Target group names are limited to 32 characters."
  }
}

variable "target_type" {
  type    = string
  default = "ip"

  validation {
    condition     = contains(["ip", "instance"], var.target_type)
    error_message = "target_type must be ip or instance."
  }
}

variable "target_port" {
  type = number
}

variable "target_protocol" {
  type    = string
  default = "HTTPS"

  validation {
    condition     = contains(["HTTP", "HTTPS"], var.target_protocol)
    error_message = "target_protocol must be HTTP or HTTPS."
  }
}

variable "health_check" {
  type = object({
    path     = optional(string, "/healthz")
    matcher  = optional(string, "200")
    interval = optional(number, 15)
  })
  default = {}
}

variable "idle_timeout" {
  type    = number
  default = 60
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "access_logs" {
  description = "S3 access logs (the bucket policy must allow ELB log delivery). Null to disable."
  type = object({
    bucket = string
    prefix = optional(string)
  })
  default = null
}
