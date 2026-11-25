variable "oidc_hostname" {
  description = "Terraform Enterprise hostname, without scheme or path. Issuer of the run tokens; AWS reads https://<host>/.well-known/openid-configuration and /.well-known/jwks."
  type        = string
  default     = "tfe.client.com"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.oidc_hostname))
    error_message = "oidc_hostname must be a bare lowercase hostname, e.g. tfe.client.com (no https:// and no path)."
  }
}

variable "audience" {
  description = "Audience (aud) of the TFE run token. Must match TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE in the workspace; aws.workload.identity is the TFE default."
  type        = string
  default     = "aws.workload.identity"

  validation {
    condition     = length(var.audience) > 0 && length(var.audience) <= 255
    error_message = "audience must be 1-255 characters."
  }
}

variable "create_oidc_provider" {
  description = "Create the IAM OIDC identity provider for TFE in this account. An account holds one provider per URL: set false and pass oidc_provider_arn when another module call (or another stack) already created it in the same account."
  type        = bool
  default     = true
}

variable "oidc_provider_arn" {
  description = "ARN of an existing IAM OIDC provider for TFE in this account. Required when create_oidc_provider is false; ignored otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.oidc_provider_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:oidc-provider/.+$", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be an IAM OIDC provider ARN (arn:<partition>:iam::<account>:oidc-provider/<host>)."
  }
}

variable "thumbprint_list" {
  description = "Server certificate thumbprints for the OIDC provider. Leave empty: IAM fetches and trusts the certificate chain itself. Set only if TFE uses a certificate IAM cannot validate (e.g. a private CA)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for t in var.thumbprint_list : can(regex("^[0-9a-fA-F]{40}$", t))])
    error_message = "Each thumbprint is a 40-character hex SHA-1 fingerprint."
  }
}

variable "organization" {
  description = "TFE organization whose runs may assume the roles (organization:<org> in the token subject)."
  type        = string
  default     = "client"

  validation {
    condition     = length(var.organization) > 0 && !can(regex("[:*?]", var.organization))
    error_message = "organization must be non-empty and must not contain ':', '*' or '?'."
  }
}

variable "workspaces" {
  description = <<-EOT
    TFE workspaces that get a plan role and an apply role in this account, keyed by a stable stack key.
      project             TFE project of the workspace (project:<project> in the subject)
      workspace           TFE workspace name (ADR-42: {environment}-{stack})
      role_name_prefix    role names are <prefix>-plan and <prefix>-apply, e.g. dev-workloads-tfe-eks
      iam_name_prefixes   name prefixes of the IAM roles, policies, instance profiles and SAML providers
                          the stack manages (e.g. ["dev-workloads-"]); the apply role may change only these
      oidc_provider_hosts IAM OIDC providers the stack manages, as the ARN suffix (host/path, wildcards
                          allowed, e.g. "oidc.eks.us-west-2.amazonaws.com/id/*"); default none
      plan_policy_arns    managed policies of the plan role (default ReadOnlyAccess)
      apply_policy_arns   managed policies of the apply role (default PowerUserAccess)
      apply_inline_policy extra inline policy JSON for the apply role (optional)
  EOT
  type = map(object({
    project             = string
    workspace           = string
    role_name_prefix    = string
    iam_name_prefixes   = list(string)
    oidc_provider_hosts = optional(list(string), [])
    plan_policy_arns    = optional(list(string), ["arn:aws:iam::aws:policy/ReadOnlyAccess"])
    apply_policy_arns   = optional(list(string), ["arn:aws:iam::aws:policy/PowerUserAccess"])
    apply_inline_policy = optional(string)
  }))

  validation {
    condition = alltrue([
      for w in values(var.workspaces) : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", w.role_name_prefix)) && length(w.role_name_prefix) + length("-apply") <= 64
    ])
    error_message = "role_name_prefix must be lowercase letters, digits and single hyphens, and <prefix>-apply must be 64 characters or fewer (ADR-44): ${join(", ", [for k, w in var.workspaces : "${k} (${w.role_name_prefix}-apply, ${length(w.role_name_prefix) + 6})" if length(w.role_name_prefix) + 6 > 64 || !can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", w.role_name_prefix))])}."
  }

  validation {
    condition = alltrue([
      for w in values(var.workspaces) : length(w.project) > 0 && length(w.workspace) > 0 && !can(regex("[:*?]", "${w.project}${w.workspace}"))
    ])
    error_message = "project and workspace must be non-empty and must not contain ':', '*' or '?' (the trust policy matches them exactly)."
  }

  validation {
    condition = alltrue(flatten([
      for w in values(var.workspaces) : concat([length(w.iam_name_prefixes) > 0], [
        for p in w.iam_name_prefixes : can(regex("^[a-z0-9]+(-[a-z0-9]+)*-$", p))
      ])
    ]))
    error_message = "iam_name_prefixes needs at least one entry, and each must be a lowercase name prefix ending in a hyphen, e.g. dev-network- (no wildcards; an empty prefix would allow every IAM name)."
  }

  validation {
    condition = alltrue(flatten([
      for w in values(var.workspaces) : [
        for h in w.oidc_provider_hosts : length(h) > 0 && !startswith(h, "https://") && !startswith(h, "*")
      ]
    ]))
    error_message = "oidc_provider_hosts entries are the host/path part of the provider ARN, without https:// and not starting with a wildcard."
  }

  validation {
    condition     = alltrue([for w in values(var.workspaces) : w.apply_inline_policy == null || can(jsondecode(w.apply_inline_policy))])
    error_message = "apply_inline_policy must be valid JSON."
  }
}

variable "role_path" {
  description = "IAM path of the plan and apply roles. Must not be \"/\": the apply roles may change IAM resources under \"/\" only, so a separate path keeps them from editing their own roles."
  type        = string
  default     = "/tfe/"

  validation {
    condition     = var.role_path != "/" && can(regex("^/([a-z0-9-]+/)+$", var.role_path))
    error_message = "role_path must be a path other than \"/\", e.g. /tfe/."
  }
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary for the plan and apply roles (optional)."
  type        = string
  default     = null
}

variable "max_session_duration" {
  description = "Maximum session length of the roles, in seconds (3600-43200). TFE requests one session per run phase."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be 3600-43200 seconds."
  }
}
