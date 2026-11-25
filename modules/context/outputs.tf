output "environment" {
  value = var.environment
}

output "function" {
  value = var.function
}

output "base" {
  description = "{environment}-{function}, e.g. dev-workloads. Same as the account name and the VPC name of a one-VPC account."
  value       = local.base
}

output "dr_marker" {
  description = "\"-dr\" for a DR stack, \"\" otherwise. Append after the base name and descriptor, before AZ IDs and numbers."
  value       = var.dr ? "-dr" : ""
}

output "names" {
  description = "Names requested in var.names, in the form their resource type accepts."
  value       = local.formatted_names

  precondition {
    condition     = alltrue([for n in values(var.names) : contains(keys(local.resource_types), n.type)])
    error_message = "A resource type has no row in resource-types.json (the ADR-43 table). Add the row before the module is merged (ADR-44 section 9): ${join(", ", [for n in values(var.names) : n.type if !contains(keys(local.resource_types), n.type)])}."
  }

  precondition {
    condition = alltrue([
      for n in values(var.names) : n.descriptor != null || try(local.resource_types[n.type].descriptor, "required") == "optional"
    ])
    error_message = "A descriptor is required for: ${join(", ", [for k, n in var.names : k if n.descriptor == null && try(local.resource_types[n.type].descriptor, "required") != "optional"])}."
  }

  precondition {
    condition = alltrue([
      for k, n in var.names : length(local.formatted_names[k]) + try(local.resource_types[n.type].reserved, 0) <= try(local.resource_types[n.type].max_length, 0)
    ])
    error_message = "Names longer than their resource type allows (shorten the descriptor with the approved abbreviations, ADR-44 section 4): ${join(", ", [for k, n in var.names : "${local.formatted_names[k]} (${length(local.formatted_names[k])} > ${try(local.resource_types[n.type].max_length, 0) - try(local.resource_types[n.type].reserved, 0)})" if length(local.formatted_names[k]) + try(local.resource_types[n.type].reserved, 0) > try(local.resource_types[n.type].max_length, 0)])}."
  }
}

output "path_prefix" {
  description = "/{environment}/{function}[-dr], for path names built inside modules."
  value       = local.path_prefix
}

output "paths" {
  description = "Path names requested in var.paths."
  value       = local.paths
}

output "tags" {
  description = "ADR-46 tags for the provider default_tags (and for root EBS volumes and Kubernetes-created resources, which do not get default_tags)."
  value       = local.tags
}

output "resource_types" {
  description = "The resource type table (form, length limit, descriptor rule)."
  value       = local.resource_types
}
