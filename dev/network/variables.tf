variable "environment" {
  description = "Environment of this stack folder (ADR-42): names start with it and the environment tag has its value."
  type        = string
  default     = "dev"
}

variable "jira_ticket" {
  description = "jira_ticket tag (ADR-46), lowercase."
  type        = string
  default     = "awsm-28"
}

variable "region" {
  description = "Primary region (ADR-5): us-west-2. The DR copy (us-east-1) is a separate stack with dr = true in the context module."
  type        = string
  default     = "us-west-2"
}

variable "cloudwan_home_region" {
  description = "Cloud WAN home region (global network and core network API)."
  type        = string
  default     = "us-west-2"
}

variable "edge_locations" {
  description = "Core network edges. Production: [\"us-west-2\", \"us-east-1\"] (ADR-34, both with inspection, Inbound and SD-WAN capacity)."
  type        = list(string)
  default     = ["us-west-2"]
}

variable "network_account" {
  description = "Account that owns the core network, inspection, the Inbound VPC and the service network (network-dev here, network-prod in production)."
  type = object({
    id       = string
    profile  = optional(string)
    role_arn = optional(string)
  })
}

variable "apps_account_id" {
  description = "Workload account (workloads-dev). May create GWLB endpoints; the core network and service network are shared with it through RAM when it differs from the network account."
  type        = string
}

variable "organization_id" {
  description = "Client organization ID (o-...). The service network policy allows only its principals. Null in test accounts outside an organization (the network and apps accounts are allowed instead)."
  type        = string
  default     = null
}

variable "az_count" {
  description = "AZs to use. ADR-32 sizes non-prod for 1 AZ; dev uses 2 because GWLB/ALB/EKS/Resolver need two (README deviation)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "Use two or three AZs."
  }
}

variable "az_ids" {
  description = "AZ IDs to use (e.g. [\"usw2-az1\", \"usw2-az2\"]). Null picks the first az_count. IDs, not names, because names differ between accounts."
  type        = list(string)
  default     = null
}

# ---------------------------------------------------------------- addressing (ADR-32)

variable "ipam_pool_id" {
  description = "Network OU IPAM pool (shared from network-prod). Null in accounts without IPAM; the pinned CIDRs below are then used directly."
  type        = string
  default     = null
}

variable "egress_vpc_cidr" {
  description = "Egress VPC: ADR-32 network-dev 10.200.106.0/25 (network-prod 10.200.104.0/23)."
  type        = string
  default     = "10.200.106.0/25"

  validation {
    condition     = can(cidrnetmask(var.egress_vpc_cidr))
    error_message = "egress_vpc_cidr must be a valid CIDR."
  }
}

variable "inbound_vpc_cidr" {
  description = "Inbound VPC. ADR-32 has no range for it; this takes the next free /25 of the Network OU pool (10.200.104.0/21)."
  type        = string
  default     = "10.200.107.128/25"

  validation {
    condition     = can(cidrnetmask(var.inbound_vpc_cidr))
    error_message = "inbound_vpc_cidr must be a valid CIDR."
  }
}

variable "subnet_newbits" {
  description = "Subnet size relative to the VPC: 3 gives /28 subnets in a /25 (8 subnets: 4 tiers x 2 AZs). network-prod (/23, 3 AZs, /27) uses 4."
  type        = number
  default     = 3
}

variable "internal_cidrs" {
  description = "Routable Client AWS space reached over Cloud WAN (ADR-32 Blocks A, B and C). Inspected replies return to these."
  type        = list(string)
  default     = ["10.192.0.0/13", "10.200.0.0/14", "10.224.0.0/16"]
}

variable "onprem_cidrs" {
  description = "On-premises ranges that reach the Inbound VPC over SD-WAN / Direct Connect (Las Vegas from ADR-32; add Salt Lake, Singapore, DRaaS Atlanta, Azure US West, branches)."
  type        = list(string)
  default     = ["10.34.0.0/15", "10.37.0.0/16"]
}

variable "onprem_service_ports" {
  description = "TCP ports on-premises callers may open to the Lattice service network endpoint (HTTPS services and database resource configurations)."
  type        = list(number)
  default     = [443]
}

variable "direct_connect_gateway_arn" {
  description = "Direct Connect gateway (Las Vegas) to attach to the directconnect segment. Null until the circuits are ready."
  type        = string
  default     = null
}

variable "ram_share_region" {
  description = "Region the core network is shared from with AWS RAM (cross-account only)."
  type        = string
  default     = "us-west-2"
}

# ---------------------------------------------------------------- egress and firewall

variable "firewall_instance_type" {
  type    = string
  default = "t3.small"
}

variable "firewall_instances_per_az" {
  type    = number
  default = 1
}

# ---------------------------------------------------------------- Lattice and logs

variable "lattice_access_log_destination_arns" {
  description = "Service network access log destinations in the Log Archive account (security-audit), e.g. an S3 bucket ARN. Empty: a log group in this account."
  type        = list(string)
  default     = []
}

variable "service_network_share_principals" {
  description = "Extra RAM principals for the service network (the environment's workload OU ARNs in production)."
  type        = list(string)
  default     = []
}

variable "flow_log_retention_days" {
  type    = number
  default = 30
}

variable "log_retention_days" {
  description = "Lattice access log retention (local log group only)."
  type        = number
  default     = 90
}
