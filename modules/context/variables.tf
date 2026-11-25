variable "environment" {
  description = "Environment (Landing Zone ADR): prod, dev, test or uat. Sandbox accounts are dev; Client - Management, security and security-audit are prod."
  type        = string

  validation {
    condition     = contains(["prod", "dev", "test", "uat"], var.environment)
    error_message = "environment must be prod, dev, test or uat (ADR-44)."
  }
}

variable "function" {
  description = "Function of the account, e.g. network, workloads, oracle-apps (ADR-44 section 3). Recommended maximum 12 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.function)) && length(var.function) <= 12
    error_message = "function must be lowercase letters, digits and single hyphens, start with a letter, and have 12 characters or fewer."
  }
}

variable "dr" {
  description = "Stack builds the DR copy (us-east-1). Adds the -dr marker to names and paths."
  type        = bool
  default     = false
}

variable "names" {
  description = "Names to build, keyed by a stable name. type must have a row in resource-types.json; suffix holds parts the pattern adds after the base and the DR marker (host number, tier, AZ ID, account ID, date)."
  type = map(object({
    type       = string
    descriptor = optional(string)
    suffix     = optional(list(string), [])
  }))
  default = {}

  validation {
    condition = alltrue(flatten([
      for n in values(var.names) : [
        for p in concat([coalesce(n.descriptor, "x")], n.suffix) : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", p))
      ]
    ]))
    error_message = "descriptor and suffix parts must be lowercase letters and digits separated by single hyphens."
  }
}

variable "paths" {
  description = "Path names (SSM parameters, secrets, log groups) keyed by a stable name; the value is the descriptor. Built as /{environment}/{function}[-dr]/{descriptor}."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for d in values(var.paths) : can(regex("^[a-z0-9]+([-/][a-z0-9]+)*$", d))])
    error_message = "Path descriptors must be lowercase letters and digits separated by single hyphens or slashes."
  }
}

variable "tags" {
  description = "Values of the ADR-46 tags. Keys and values are lowercase."
  type = object({
    owner           = string
    jira_ticket     = string
    compliance      = optional(string, "none")
    backup_required = optional(bool, false)
    dr_required     = optional(bool, false)
    application     = optional(string)
    tier            = optional(string)
  })

  validation {
    condition     = contains(["infra", "devops", "sysops", "netops", "secops", "dba"], var.tags.owner)
    error_message = "owner must be infra, devops, sysops, netops, secops or dba (ADR-46)."
  }

  validation {
    condition     = contains(["none", "pci", "sox"], var.tags.compliance)
    error_message = "compliance must be none, pci or sox (ADR-46)."
  }

  validation {
    condition     = var.tags.tier == null || contains(["web", "database", "application"], coalesce(var.tags.tier, "web"))
    error_message = "tier must be web, database or application (ADR-46)."
  }

  validation {
    condition = alltrue([
      for v in compact([var.tags.jira_ticket, var.tags.application]) : v == lower(v) && length(v) <= 256
    ])
    error_message = "Tag values are lowercase (ADR-46) and 256 characters or fewer."
  }
}

variable "map_tags" {
  description = "AWS migration program tags (ADR-46 section 2). Every new resource carries both; the map-migrated value is the one uppercase exception. Confirm both with the AWS partner contact (ADR-46 open item)."
  type = object({
    map_migrated     = string
    apn_id_tag_key   = string
    apn_id_tag_value = string
  })
  default = {
    map_migrated     = "mig7MZ9CR0FKE"
    apn_id_tag_key   = "aws-apn-id-656441707956"
    apn_id_tag_value = "pc:dr0w726iea60dam948rtax9zm"
  }
}
