variable "environment" {
  description = "Environment of this stack folder (ADR-42)."
  type        = string
  default     = "dev"
}

variable "jira_ticket" {
  description = "jira_ticket tag (ADR-46), lowercase."
  type        = string
  default     = "awsm-28"
}

variable "apps_account" {
  description = "Workload account (workloads-dev; workloads-prod in production)."
  type = object({
    id       = string
    profile  = optional(string)
    role_arn = optional(string)
  })
}

variable "ipam_pool_id" {
  description = "Client Apps OU IPAM pool (shared from network-prod, ADR-32). Null in accounts without IPAM; vpc_cidr is then used directly."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "Workload VPC (ADR-32 workloads-dev: 10.192.0.0/16). Tier layout assumes a /16."
  type        = string
  default     = "10.192.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr must be a /16."
  }
}

variable "app_port" {
  description = "Pod port the ALBs forward to over TLS."
  type        = number
  default     = 8443
}

variable "lattice_resource_ports" {
  description = "TCP ports of Lattice resource configurations (databases) that pods may open, e.g. [5432, 1521]."
  type        = list(number)
  default     = []

  validation {
    condition     = length(var.lattice_resource_ports) <= 10
    error_message = "Keep the list short (NACL rule numbers 150-159)."
  }
}

variable "lattice_link_local_cidr" {
  description = "Link-local range VPC Lattice uses in associated VPCs (content of the vpc-lattice managed prefix list)."
  type        = string
  default     = "169.254.171.0/24"
}

variable "accept_ram_shares" {
  description = "Accept the core network and service network shares. Only needed cross-account when RAM sharing with AWS Organizations is off."
  type        = bool
  default     = false
}

variable "egress_allowlist" {
  description = "Outbound traffic allowed from the private subnets to outside the VPC (security group and NACL)."
  type = list(object({
    name      = string
    cidr      = string
    protocol  = string
    from_port = optional(number)
    to_port   = optional(number)
  }))
  default = [
    { name = "https-internet", cidr = "0.0.0.0/0", protocol = "tcp", from_port = 443, to_port = 443 },
  ]

  validation {
    condition     = alltrue([for r in var.egress_allowlist : contains(["tcp", "udp", "icmp", "all"], r.protocol)])
    error_message = "protocol must be tcp, udp, icmp or all."
  }

  validation {
    condition     = length(var.egress_allowlist) <= 15
    error_message = "Keep the list short: the NACL allows 20 rules per direction."
  }
}

variable "flow_log_retention_days" {
  type    = number
  default = 30
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
