variable "name" {
  description = "Name of the IPAM and prefix for its scopes, pools and RAM shares, e.g. prod-network-ipam (ADR-44)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name))
    error_message = "name must be lowercase letters, digits and single hyphens (ADR-44)."
  }
}

variable "description" {
  description = "IPAM description."
  type        = string
  default     = null
}

variable "operating_regions" {
  description = "Regions the IPAM manages. Must include the provider region (the IPAM home region) and every region used by blocks, ou_pools and sandbox."
  type        = list(string)

  validation {
    condition     = length(var.operating_regions) > 0 && length(var.operating_regions) == length(distinct(var.operating_regions))
    error_message = "operating_regions must be a non-empty list without duplicates."
  }
}

variable "tier" {
  description = "IPAM tier: advanced (pools, RAM sharing, allocation rules) or free."
  type        = string
  default     = "advanced"

  validation {
    condition     = contains(["advanced", "free"], var.tier)
    error_message = "tier must be advanced or free."
  }
}

variable "blocks" {
  description = "Active address blocks, keyed by a stable name (e.g. a, b, c). Each is provisioned to the global pool and then to the regional pool of its region. Reserved blocks stay out of this map until they are needed."
  type = map(object({
    cidr   = string
    region = string
  }))

  validation {
    condition     = alltrue([for b in values(var.blocks) : can(cidrnetmask(b.cidr)) && cidrsubnet(b.cidr, 0, 0) == b.cidr])
    error_message = "Every block cidr must be a valid IPv4 network address (e.g. 10.192.0.0/13)."
  }
}

variable "ou_pools" {
  description = "OU pools keyed by \"<ou>/<region>\" (e.g. client-apps/us-west-2). Each is a child of its region's pool, auto-imports existing VPCs, only allocates to resources tagged <allocation_tag_key> = <ou>, and is shared through RAM with ou_arn when set (null: created, not shared)."
  type = map(object({
    region                 = string
    cidrs                  = list(string)
    default_netmask_length = number
    min_netmask_length     = optional(number, 16)
    max_netmask_length     = optional(number, 28)
    ou_arn                 = optional(string)
    description            = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, p in var.ou_pools : can(regex("^[a-z0-9]+(-[a-z0-9]+)*/[a-z0-9-]+$", k)) && split("/", k)[1] == p.region])
    error_message = "ou_pools keys must be \"<ou>/<region>\" with lowercase OU keys, and the region part must equal the pool's region."
  }

  validation {
    condition     = alltrue(flatten([for p in values(var.ou_pools) : [for c in p.cidrs : can(cidrnetmask(c)) && cidrsubnet(c, 0, 0) == c]]))
    error_message = "Every OU pool cidr must be a valid IPv4 network address."
  }

  validation {
    condition = alltrue([
      for p in values(var.ou_pools) :
      p.min_netmask_length <= p.default_netmask_length && p.default_netmask_length <= p.max_netmask_length && p.max_netmask_length <= 28 && p.min_netmask_length >= 16
    ])
    error_message = "Netmask lengths must satisfy 16 <= min <= default <= max <= 28 (VPC sizes, ADR-32)."
  }

  validation {
    condition     = alltrue([for p in values(var.ou_pools) : p.ou_arn == null || can(regex("^arn:aws:organizations::[0-9]{12}:ou/o-[a-z0-9]+/ou-[a-z0-9]+-[a-z0-9]+$", p.ou_arn))])
    error_message = "ou_arn must be an Organizations OU ARN (arn:aws:organizations::<management account>:ou/o-xxx/ou-xxx-xxx)."
  }
}

variable "allocation_tag_key" {
  description = "Tag key a VPC must carry, with the OU key as value, to allocate from an OU pool (ADR-32)."
  type        = string
  default     = "client:ou"
}

variable "sandbox" {
  description = "Sandbox pool in its own private scope (may overlap routable space, never routed). Every allocation is netmask_length. Shared through RAM with ou_arn when set. ou is the allocation tag value. Null: no sandbox scope or pool."
  type = object({
    cidr           = string
    region         = string
    netmask_length = number
    ou             = optional(string, "sandbox")
    ou_arn         = optional(string)
    description    = optional(string)
  })
  default = null

  validation {
    condition     = var.sandbox == null ? true : (can(cidrnetmask(var.sandbox.cidr)) && var.sandbox.netmask_length >= 16 && var.sandbox.netmask_length <= 28)
    error_message = "sandbox.cidr must be a valid IPv4 CIDR and netmask_length between 16 and 28."
  }
}
