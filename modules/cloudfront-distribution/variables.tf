variable "comment" {
  description = "Distribution comment (also the Name tag)."
  type        = string
}

variable "aliases" {
  description = "Alternate domain names served by the distribution."
  type        = list(string)
}

variable "acm_certificate_arn" {
  description = "ACM certificate in us-east-1 covering every alias."
  type        = string
}

variable "origin_domain_name" {
  description = "Origin hostname. Its certificate must be publicly trusted and match this name."
  type        = string
}

variable "origin_read_timeout" {
  type    = number
  default = 30
}

variable "origin_verify_header_name" {
  description = "Header CloudFront adds to every origin request (the origin's web ACL checks it). Null for none."
  type        = string
  default     = null
}

variable "origin_verify_header_value" {
  type      = string
  default   = null
  sensitive = true
}

variable "web_acl_arn" {
  description = "WAF web ACL (CLOUDFRONT scope) ARN."
  type        = string
  default     = null
}

variable "price_class" {
  type    = string
  default = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "price_class must be PriceClass_All, PriceClass_200 or PriceClass_100."
  }
}

variable "geo_allow_list" {
  description = "ISO country codes allowed; empty allows all."
  type        = list(string)
  default     = []
}

variable "access_log_bucket" {
  description = "S3 bucket domain name for standard logs (bucket must allow ACLs). Null to disable."
  type        = string
  default     = null
}

variable "access_log_prefix" {
  type    = string
  default = null
}
