variable "name" {
  description = "Zone name, e.g. dev.example.com."
  type        = string
}

variable "comment" {
  type    = string
  default = "Managed by Terraform"
}

variable "vpc_ids" {
  description = "VPCs to associate; makes the zone private. Empty for a public zone."
  type        = list(string)
  default     = []
}

variable "force_destroy" {
  description = "Delete all records when the zone is destroyed."
  type        = bool
  default     = false
}
