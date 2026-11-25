variable "zone_id" {
  type = string
}

variable "records" {
  description = "Records keyed by a stable name. Set alias for alias records, or ttl + values otherwise."
  type = map(object({
    name   = string
    type   = optional(string, "A")
    ttl    = optional(number, 300)
    values = optional(list(string))
    alias = optional(object({
      name                   = string
      zone_id                = string
      evaluate_target_health = optional(bool, false)
    }))
  }))

  validation {
    condition     = alltrue([for r in values(var.records) : (r.alias != null) != (r.values != null)])
    error_message = "Each record needs either alias or values, not both."
  }
}
