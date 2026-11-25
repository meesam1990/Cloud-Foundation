variable "name" {
  description = "Resource gateway name (ADR-44), e.g. dev-workloads-data. 3-40 lowercase letters, digits and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "Resource gateway names are 3-40 lowercase letters, digits and hyphens."
  }
}

variable "vpc_id" {
  description = "VPC of the resources."
  type        = string
}

variable "subnet_ids" {
  description = "One subnet per AZ (the data tier)."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups of the gateway ENIs; the resources' security groups allow these as the source."
  type        = list(string)
}

variable "resource_configurations" {
  description = "Resources keyed by a stable name. Exactly one of dns_name, ip_address or arn. name follows ADR-44 (3-40 characters)."
  type = map(object({
    name               = string
    dns_name           = optional(string)
    ip_address         = optional(string)
    arn                = optional(string)
    port_ranges        = optional(list(string), [])
    custom_domain_name = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for r in values(var.resource_configurations) : length(compact([r.dns_name, r.ip_address, r.arn])) == 1])
    error_message = "Each resource configuration needs exactly one of dns_name, ip_address or arn."
  }

  validation {
    condition     = alltrue([for r in values(var.resource_configurations) : r.arn != null || length(r.port_ranges) > 0])
    error_message = "port_ranges (e.g. [\"5432\"] or [\"1521-1522\"]) are required for DNS and IP resources."
  }

  validation {
    condition     = alltrue([for r in values(var.resource_configurations) : length(r.name) >= 3 && length(r.name) <= 40])
    error_message = "Resource configuration names are 3-40 characters."
  }
}

variable "service_network_arn" {
  description = "Service network to associate every resource configuration with. Null: not associated."
  type        = string
  default     = null
}

variable "ram_principals" {
  description = "OU ARNs or account IDs to share the resource configurations with directly (inside the organization). Empty: not shared."
  type        = list(string)
  default     = []
}
