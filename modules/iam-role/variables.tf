variable "name" {
  type = string
}

variable "description" {
  type    = string
  default = null
}

variable "path" {
  type    = string
  default = "/"
}

variable "trusted_services" {
  description = "Service principals allowed to assume the role, e.g. [\"pods.eks.amazonaws.com\"]."
  type        = list(string)
}

variable "assume_role_actions" {
  description = "Pod Identity needs sts:TagSession as well as sts:AssumeRole."
  type        = list(string)
  default     = ["sts:AssumeRole"]
}

variable "inline_policies" {
  description = "Inline policy JSON keyed by policy name."
  type        = map(string)
  default     = {}
}

variable "managed_policy_arns" {
  type    = list(string)
  default = []
}

variable "max_session_duration" {
  type    = number
  default = 3600
}

variable "permissions_boundary_arn" {
  type    = string
  default = null
}
