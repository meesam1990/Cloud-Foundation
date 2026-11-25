variable "name" {
  description = "Name prefix for the global and core networks."
  type        = string
}

variable "edge_locations" {
  description = "Regions that get a core network edge."
  type        = list(string)
}

variable "asn_range" {
  description = "Private ASN range for the core network edges. Do not shrink it once edges have ASNs."
  type        = string
  default     = "64512-65534"
}

variable "segments" {
  description = "Segments keyed by name. VPC attachments tagged segment=<name> join them. edge_locations null means every edge location."
  type = map(object({
    description                   = string
    edge_locations                = optional(list(string))
    isolate_attachments           = optional(bool, false)
    require_attachment_acceptance = optional(bool, false)
  }))

  validation {
    condition     = alltrue([for k in keys(var.segments) : can(regex("^[a-z][a-z0-9]{0,63}$", k))])
    error_message = "Segment names use ADR-44 priority 3: lowercase letters and digits only, environment first (e.g. devworkloads). Cloud WAN rejects hyphens."
  }
}

variable "network_function_groups" {
  description = "Network function (inspection) groups keyed by name. VPC attachments tagged network-function-group=<name> join them."
  type = map(object({
    description                   = string
    require_attachment_acceptance = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.network_function_groups) : can(regex("^[a-z][a-z0-9]{0,63}$", k))])
    error_message = "Network function group names use ADR-44 priority 3: lowercase letters and digits only (e.g. devegress)."
  }
}

variable "send_to" {
  description = "Segment => network function group that inspects the segment's internet-bound traffic (send-to)."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for s, g in var.send_to : contains(keys(var.segments), s) && contains(keys(var.network_function_groups), g)])
    error_message = "send_to must map existing segments to existing network function groups."
  }
}

variable "segment_shares" {
  description = "Segment => segments it shares attachment routes with (both directions). ADR-34: only SD-WAN <-> Inbound and Direct Connect <-> Inbound."
  type        = map(list(string))
  default     = {}

  validation {
    condition = alltrue(flatten([
      for s, targets in var.segment_shares : [for t in concat([s], targets) : contains(keys(var.segments), t)]
    ]))
    error_message = "segment_shares must reference existing segments."
  }
}
