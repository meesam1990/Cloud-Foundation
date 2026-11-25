variable "name" {
  type = string
}

variable "description" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "ingress_rules" {
  description = "Ingress rules keyed by a short stable name. ip_protocol is tcp, udp, icmp or -1 (all)."
  type = map(object({
    description                  = string
    ip_protocol                  = string
    from_port                    = optional(number)
    to_port                      = optional(number)
    cidr_ipv4                    = optional(string)
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
    self                         = optional(bool, false)
  }))
  default = {}

  validation {
    condition = alltrue([for r in values(var.ingress_rules) :
      length(compact([r.cidr_ipv4, r.prefix_list_id, r.referenced_security_group_id, r.self ? "self" : null])) == 1
    ])
    error_message = "Each rule needs exactly one of cidr_ipv4, prefix_list_id, referenced_security_group_id or self."
  }

  validation {
    condition     = alltrue([for r in values(var.ingress_rules) : r.ip_protocol == "-1" || r.from_port != null])
    error_message = "from_port is required unless ip_protocol is -1."
  }
}

variable "egress_rules" {
  description = "Egress rules keyed by a short stable name. Same shape as ingress_rules."
  type = map(object({
    description                  = string
    ip_protocol                  = string
    from_port                    = optional(number)
    to_port                      = optional(number)
    cidr_ipv4                    = optional(string)
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
    self                         = optional(bool, false)
  }))
  default = {}

  validation {
    condition = alltrue([for r in values(var.egress_rules) :
      length(compact([r.cidr_ipv4, r.prefix_list_id, r.referenced_security_group_id, r.self ? "self" : null])) == 1
    ])
    error_message = "Each rule needs exactly one of cidr_ipv4, prefix_list_id, referenced_security_group_id or self."
  }

  validation {
    condition     = alltrue([for r in values(var.egress_rules) : r.ip_protocol == "-1" || r.from_port != null])
    error_message = "from_port is required unless ip_protocol is -1."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
