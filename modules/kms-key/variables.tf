variable "alias" {
  description = "Alias without the alias/ prefix."
  type        = string
}

variable "description" {
  type = string
}

variable "policy" {
  description = "Key policy JSON. Null for the default policy."
  type        = string
  default     = null
}

variable "rotation_period_in_days" {
  type    = number
  default = 365
}

variable "deletion_window_in_days" {
  type    = number
  default = 7

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be 7 to 30."
  }
}
