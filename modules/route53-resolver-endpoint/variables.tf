variable "name" {
  description = "Endpoint and security group name (ADR-44), e.g. dev-network-inbound-dns."
  type        = string
}

variable "direction" {
  description = "INBOUND (on-premises -> AWS zones) or OUTBOUND."
  type        = string
  default     = "INBOUND"

  validation {
    condition     = contains(["INBOUND", "OUTBOUND"], var.direction)
    error_message = "direction must be INBOUND or OUTBOUND."
  }
}

variable "vpc_id" {
  description = "VPC of the endpoint (the Inbound VPC)."
  type        = string
}

variable "subnet_ids" {
  description = "One subnet per AZ; one IP address in each."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Resolver endpoints need at least two subnets (AZs)."
  }
}

variable "allowed_cidrs" {
  description = "INBOUND: DNS clients (on-premises DNS servers). OUTBOUND: target DNS servers."
  type        = list(string)
}

variable "protocols" {
  description = "Do53 and/or DoH."
  type        = list(string)
  default     = ["Do53"]
}
