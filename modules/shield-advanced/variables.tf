variable "enabled" {
  description = "Create the protections. Requires an active Shield Advanced subscription in the account."
  type        = bool
  default     = false
}

variable "name" {
  type = string
}

variable "resources" {
  description = "Resources to protect, keyed by a stable name."
  type        = map(string)
  default     = {}
}
