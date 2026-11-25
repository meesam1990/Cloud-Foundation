variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "ingress_rules" {
  description = "Ingress rules. protocol is tcp, udp, icmp or all; action is allow or deny."
  type = list(object({
    rule_number = number
    action      = optional(string, "allow")
    protocol    = string
    cidr_block  = string
    from_port   = optional(number)
    to_port     = optional(number)
  }))
  default = []

  validation {
    condition     = alltrue([for r in var.ingress_rules : contains(["tcp", "udp", "icmp", "all"], r.protocol) && contains(["allow", "deny"], r.action)])
    error_message = "protocol must be tcp, udp, icmp or all; action allow or deny."
  }
}

variable "egress_rules" {
  description = "Egress rules. Same shape as ingress_rules."
  type = list(object({
    rule_number = number
    action      = optional(string, "allow")
    protocol    = string
    cidr_block  = string
    from_port   = optional(number)
    to_port     = optional(number)
  }))
  default = []

  validation {
    condition     = alltrue([for r in var.egress_rules : contains(["tcp", "udp", "icmp", "all"], r.protocol) && contains(["allow", "deny"], r.action)])
    error_message = "protocol must be tcp, udp, icmp or all; action allow or deny."
  }

  validation {
    condition     = length(var.egress_rules) <= 20
    error_message = "NACLs allow 20 rules per direction by default."
  }
}
