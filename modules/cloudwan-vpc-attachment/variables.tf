variable "name" {
  type = string
}

variable "core_network_id" {
  type = string
}

variable "vpc_arn" {
  type = string
}

variable "subnet_arns" {
  description = "One attachment subnet per AZ."
  type        = list(string)
}

variable "appliance_mode" {
  description = "Keep flows symmetric across AZs. Turn on for the inspection VPC."
  type        = bool
  default     = false
}

variable "routing_tags" {
  description = "Tags the core network policy matches, e.g. { segment = \"apps\" }."
  type        = map(string)
}
