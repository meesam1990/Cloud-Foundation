variable "name" {
  description = "Name of the VPC and prefix for its resources."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 CIDR."
  }
}

variable "ipam_pool_id" {
  description = "IPAM pool (the OU pool shared through RAM, ADR-32) the VPC allocates cidr_block from. Null uses cidr_block without IPAM."
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra VPC tags, e.g. the IPAM allocation tag { \"client:ou\" = \"client-apps\" }."
  type        = map(string)
  default     = {}
}

variable "azs" {
  description = "Availability Zone names, in the same order as each tier's cidrs."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "Use at least two AZs."
  }
}

variable "subnet_tiers" {
  description = "Subnet tiers. cidrs holds one CIDR per AZ, in the order of azs."
  type = map(object({
    cidrs = list(string)
    tags  = optional(map(string), {})
  }))

  validation {
    condition     = alltrue([for t in values(var.subnet_tiers) : alltrue([for c in t.cidrs : can(cidrnetmask(c))])])
    error_message = "Every subnet CIDR must be a valid IPv4 CIDR."
  }
}

variable "create_internet_gateway" {
  description = "Create an internet gateway."
  type        = bool
  default     = false
}

variable "internet_route_tiers" {
  description = "Tiers whose route tables get 0.0.0.0/0 to the internet gateway."
  type        = list(string)
  default     = []
}

variable "nat_gateway" {
  description = "NAT gateways in subnet_tier: one per AZ, or one shared (single = true, cheaper, not AZ-resilient). Null for none."
  type = object({
    subnet_tier = string
    single      = optional(bool, false)
  })
  default = null
}

variable "flow_logs" {
  description = "VPC flow logs to CloudWatch Logs. log_group_name follows ADR-44 paths, e.g. /dev/network/egress-flow-logs."
  type = object({
    enabled           = optional(bool, true)
    retention_in_days = optional(number, 30)
    traffic_type      = optional(string, "ALL")
    kms_key_arn       = optional(string)
    log_group_name    = optional(string)
  })
  default = {}

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_logs.traffic_type)
    error_message = "traffic_type must be ACCEPT, REJECT or ALL."
  }
}
