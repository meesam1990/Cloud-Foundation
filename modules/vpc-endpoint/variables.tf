variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "service_name" {
  description = "Endpoint service name, e.g. com.amazonaws.vpce.us-west-2.vpce-svc-0123 or com.amazonaws.us-west-2.s3. Not used for ServiceNetwork and Resource endpoints."
  type        = string
  default     = null
}

variable "service_network_arn" {
  description = "VPC Lattice service network (ServiceNetwork endpoints)."
  type        = string
  default     = null
}

variable "resource_configuration_arn" {
  description = "VPC Lattice resource configuration (Resource endpoints)."
  type        = string
  default     = null
}

variable "vpc_endpoint_type" {
  type = string

  validation {
    condition     = contains(["Interface", "Gateway", "GatewayLoadBalancer", "ServiceNetwork", "Resource"], var.vpc_endpoint_type)
    error_message = "vpc_endpoint_type must be Interface, Gateway, GatewayLoadBalancer, ServiceNetwork or Resource."
  }
}

variable "subnet_ids" {
  description = "Interface, ServiceNetwork, Resource: one subnet per AZ. GatewayLoadBalancer: exactly one subnet."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Interface, ServiceNetwork and Resource endpoints."
  type        = list(string)
  default     = []
}

variable "route_table_ids" {
  description = "Gateway endpoints only."
  type        = list(string)
  default     = []
}

variable "private_dns_enabled" {
  description = "Interface, ServiceNetwork and Resource endpoints."
  type        = bool
  default     = true
}

variable "policy" {
  description = "Endpoint policy JSON (Interface and Gateway). Null for full access."
  type        = string
  default     = null
}
