variable "domain_name" {
  type = string
}

variable "subject_alternative_names" {
  type    = list(string)
  default = []
}

variable "zone_id" {
  description = "Public hosted zone for the DNS validation records."
  type        = string
}

variable "exportable" {
  description = "Issue as an exportable public certificate (billed) so the private key can be exported."
  type        = bool
  default     = false
}

variable "key_algorithm" {
  type    = string
  default = "RSA_2048"

  validation {
    condition     = contains(["RSA_2048", "EC_prime256v1", "EC_secp384r1"], var.key_algorithm)
    error_message = "key_algorithm must be RSA_2048, EC_prime256v1 or EC_secp384r1."
  }
}

variable "wait_for_validation" {
  description = "Wait until the certificate is issued, so arn is usable by listeners and CloudFront."
  type        = bool
  default     = true
}

variable "validation_timeout" {
  description = "How long to wait for issuance (the zone must be delegated for it to finish)."
  type        = string
  default     = "45m"
}
