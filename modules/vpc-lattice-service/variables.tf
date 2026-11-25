variable "name" {
  description = "Service name (ADR-44), e.g. dev-workloads-backend. 3-40 lowercase letters, digits and hyphens. Target groups are named <name>-<key>."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "Lattice service names are 3-40 lowercase letters, digits and hyphens, without a leading, trailing or double hyphen."
  }
}

variable "custom_domain_name" {
  description = "Custom domain, e.g. backend.dev.client.internal (ADR-36: a Route 53 private hosted zone name). Null uses only the generated Lattice name."
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "ACM certificate for custom_domain_name (HTTPS listeners)."
  type        = string
  default     = null
}

variable "service_network_arn" {
  description = "Service network of the environment (shared from the network account). Null leaves the service unpublished."
  type        = string
  default     = null
}

variable "target_groups" {
  description = "Target groups keyed by a short name. ALB: port/protocol of the ALB listener, no health check (the ALB checks its targets). IP/INSTANCE: health_check recommended."
  type = map(object({
    type             = string
    port             = optional(number, 443)
    protocol         = optional(string, "HTTPS")
    protocol_version = optional(string, "HTTP1")
    vpc_id           = optional(string)
    health_check = optional(object({
      path     = optional(string, "/healthz")
      protocol = optional(string)
      port     = optional(number)
      interval = optional(number, 30)
      matcher  = optional(string, "200")
    }))
    targets = optional(list(object({
      id   = string
      port = optional(number)
    })), [])
  }))

  validation {
    condition     = alltrue([for t in values(var.target_groups) : contains(["ALB", "IP", "INSTANCE", "LAMBDA"], t.type)])
    error_message = "type must be ALB, IP, INSTANCE or LAMBDA."
  }

  validation {
    condition     = alltrue([for t in values(var.target_groups) : t.type == "LAMBDA" || t.vpc_id != null])
    error_message = "vpc_id is required for ALB, IP and INSTANCE target groups."
  }
}

variable "listeners" {
  description = "Listeners keyed by name. default_target_group null answers 404. rules: path_prefix and/or method -> target_group."
  type = map(object({
    protocol             = optional(string, "HTTPS")
    port                 = optional(number, 443)
    default_target_group = optional(string)
    rules = optional(map(object({
      priority     = number
      target_group = string
      path_prefix  = optional(string)
      method       = optional(string)
    })), {})
  }))

  validation {
    condition     = alltrue([for l in values(var.listeners) : l.protocol == "HTTPS" || l.protocol == "TLS_PASSTHROUGH"])
    error_message = "ADR-36: every listener is HTTPS (or TLS_PASSTHROUGH for end-to-end TLS)."
  }
}

variable "allowed_callers" {
  description = "Auth policy statements keyed by a short name: the caller roles (EKS Pod Identity roles, EC2 instance roles, IAM Roles Anywhere roles), optional HTTP methods and path patterns (starting with /). Empty denies everything."
  type = map(object({
    principal_arns = list(string)
    methods        = optional(list(string), [])
    paths          = optional(list(string), ["/*"])
  }))
  default = {}

  validation {
    condition     = alltrue(flatten([for c in values(var.allowed_callers) : [for p in c.paths : startswith(p, "/")]]))
    error_message = "paths start with /, e.g. /* or /api/*."
  }

  validation {
    condition     = alltrue(flatten([for c in values(var.allowed_callers) : [for a in c.principal_arns : a != "*"]]))
    error_message = "Name the calling roles; \"*\" is not allowed in a service policy (ADR-36)."
  }
}

variable "access_logs" {
  description = "Access log destinations (S3, CloudWatch Logs or Firehose ARNs). Empty creates a log group named log_group_name."
  type = object({
    destination_arns  = optional(list(string), [])
    log_group_name    = optional(string)
    retention_in_days = optional(number, 90)
    kms_key_arn       = optional(string)
  })
  default = {}
}
