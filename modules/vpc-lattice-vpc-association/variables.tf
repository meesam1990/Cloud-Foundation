variable "name" {
  description = "Name tag of the association, e.g. the VPC name."
  type        = string
}

variable "vpc_id" {
  description = "Workload VPC that calls services."
  type        = string
}

variable "service_network_arn" {
  description = "Service network of the VPC's environment (shared from the network account through RAM)."
  type        = string
}

variable "security_group_ids" {
  description = "Security groups on the association (up to 5); they control which sources in the VPC can reach Lattice."
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) >= 1 && length(var.security_group_ids) <= 5
    error_message = "Give 1 to 5 security groups."
  }
}
