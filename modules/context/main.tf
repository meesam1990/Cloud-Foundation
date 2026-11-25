# Naming (ADR-44) and tagging (ADR-46) for every stack. Each stack calls this once.
#
# Names
#   base       {environment}-{function}               e.g. dev-workloads
#   names      {environment}-{function}[-{descriptor}][-dr][-{suffix...}] in the highest-priority
#              form the resource type accepts (resource-types.json, the copy of the ADR-43 epic
#              table). The DR marker follows the base name and comes before anything added after it
#              (host number, AZ ID, account ID, date). The plan fails when a type has no row, a
#              required descriptor is missing or a name is longer than the type's limit. Names are
#              never cut.
#   paths      /{environment}/{function}[-dr]/{descriptor} for SSM parameters, secrets, log groups
#
# Forms (ADR-44 priority matrix)
#   1  prod-oracle-apps-artifacts   lowercase, digits, hyphens
#   2  prod_oracle_apps_artifacts   snake case
#   3  prodoracleappsartifacts      lowercase letters and digits only
#   4  prodOracleAppsArtifacts      camel case (only where a service needs uppercase)
#
# Tags: the seven required tags, the optional application and tier tags and both AWS migration
# program (MAP) tags. Stacks put the output in the provider default_tags; root EBS volumes and
# Kubernetes-created resources get the same map directly.

locals {
  resource_types = jsondecode(file("${path.module}/resource-types.json")).resource_types

  dr_marker = var.dr ? "dr" : null
  base      = "${var.environment}-${var.function}"

  # Hyphenated (priority 1) name first; the form is applied below.
  raw_names = {
    for k, n in var.names : k => join("-", compact(concat(
      [var.environment, var.function, n.descriptor, local.dr_marker],
      n.suffix,
    )))
  }

  formatted_names = {
    for k, n in var.names : k => (
      try(local.resource_types[n.type].form, 1) == 2 ? replace(local.raw_names[k], "-", "_") :
      try(local.resource_types[n.type].form, 1) == 3 ? replace(local.raw_names[k], "-", "") :
      try(local.resource_types[n.type].form, 1) == 4 ? join("", [
        for i, part in split("-", local.raw_names[k]) : i == 0 ? part : title(part)
      ]) :
      local.raw_names[k]
    )
  }

  path_prefix = "/${var.environment}/${var.function}${var.dr ? "-dr" : ""}"

  paths = { for k, d in var.paths : k => "${local.path_prefix}/${d}" }

  tags = merge(
    {
      environment     = var.environment
      owner           = var.tags.owner
      jira_ticket     = var.tags.jira_ticket
      terraform       = "true"
      compliance      = var.tags.compliance
      backup_required = tostring(var.tags.backup_required)
      dr_required     = tostring(var.tags.dr_required)
    },
    var.tags.application == null ? {} : { application = var.tags.application },
    var.tags.tier == null ? {} : { tier = var.tags.tier },
    var.map_tags == null ? {} : {
      "map-migrated"                = var.map_tags.map_migrated
      (var.map_tags.apn_id_tag_key) = var.map_tags.apn_id_tag_value
    },
  )
}
