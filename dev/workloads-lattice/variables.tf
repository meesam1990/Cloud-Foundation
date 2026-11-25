variable "environment" {
  description = "Environment of this stack folder (ADR-42)."
  type        = string
  default     = "dev"
}

variable "jira_ticket" {
  description = "jira_ticket tag (ADR-46), lowercase."
  type        = string
  default     = "awsm-28"
}

variable "apps_account" {
  type = object({
    id       = string
    profile  = optional(string)
    role_arn = optional(string)
  })
}

variable "private_domain" {
  description = "Private hosted zone of the custom domains (ADR-36: e.g. prod.client.internal). Null: <environment>.client.internal."
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "ACM certificate for *.<private_domain> issued by the Client CA (imported). Null generates a dev CA stand-in and imports its certificate."
  type        = string
  default     = null
}

variable "services" {
  description = <<-EOT
    Services to publish, keyed by the descriptor (names {environment}-{function}-{key}, custom domain
    <hostname or key>.<private_domain>). callers: keys of workloads-eks lattice_callers;
    onprem_callers: keys of onprem_callers; extra_caller_arns: any other role ARNs. An empty caller
    list leaves the service denying everything.
  EOT
  type = map(object({
    hostname          = optional(string)
    health_check_path = optional(string, "/healthz")
    callers           = optional(list(string), [])
    onprem_callers    = optional(list(string), [])
    extra_caller_arns = optional(list(string), [])
    methods           = optional(list(string), [])
    paths             = optional(list(string), ["/*"])
  }))
  default = {
    backend = {
      callers = ["frontend"]
      methods = ["GET", "HEAD"]
    }
  }
}

variable "lattice_resources" {
  description = "Databases and other TCP resources published as resource configurations (callers in other VPCs). Exactly one of dns_name, ip_address, arn per entry. Empty: no resource gateway."
  type = map(object({
    dns_name           = optional(string)
    ip_address         = optional(string)
    arn                = optional(string)
    ports              = list(number)
    custom_domain_name = optional(string)
  }))
  default = {}
}

variable "onprem_ca_certificate_pem" {
  description = "PEM of the CA that issues on-premises callers' certificates (IAM Roles Anywhere). Null: no on-premises callers."
  type        = string
  default     = null
}

variable "onprem_callers" {
  description = "On-premises callers keyed by name, with the certificate subject CN of each (needs onprem_ca_certificate_pem)."
  type = map(object({
    certificate_cn = string
  }))
  default = {}
}

variable "access_log_destination_arns" {
  description = "Service access log destinations in the Log Archive account. Empty: a log group per service in this account."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "tfe_hostname" {
  description = "Terraform Enterprise host that holds the other stacks' state (tfe_outputs)."
  type        = string
  default     = "tfe.client.com"
}

variable "tfe_organization" {
  description = "TFE organization of the workspaces read in remote-state.tf."
  type        = string
  default     = "client"
}
