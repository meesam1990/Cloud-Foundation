variable "name" {
  description = "Load balancer and target group name (32 characters max)."
  type        = string

  validation {
    condition     = length(var.name) <= 32
    error_message = "ELB names are limited to 32 characters."
  }
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Firewall subnets, one per AZ."
  type        = list(string)
}

variable "allowed_principals" {
  description = "IAM principal ARNs allowed to create endpoints to the GWLB, e.g. arn:aws:iam::<account>:root."
  type        = list(string)
}

variable "cross_zone" {
  type    = bool
  default = false
}

variable "health_check_port" {
  description = "Port the firewall answers health checks on."
  type        = number
  default     = 80
}

variable "health_check_path" {
  type    = string
  default = "/"
}
