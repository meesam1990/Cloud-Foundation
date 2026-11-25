# Cloud WAN global network, core network and its policy (ADR-34).
#
#   segments                 attachment segments, ADR-44 priority 3 names (lowercase letters and
#                            digits, environment first: devworkloads, devsdwan, devdirectconnect,
#                            devinbound). isolate_attachments / require_attachment_acceptance per
#                            segment (Production workload attachments: both on).
#   network_function_groups  inspection groups (e.g. devegress); their VPC attachments need
#                            appliance mode
#   send_to                  segment => group: traffic leaving the segment for the internet is sent
#                            to the group, and the group learns the segment's routes for the return
#   segment_shares           segment => segments it shares routes with (both ways). ADR-34 allows
#                            only SD-WAN <-> Inbound and Direct Connect <-> Inbound, so on-premises
#                            reaches the Inbound VPC and never a workload segment.
#
# Attachments are placed by tag (segment=<name> or network-function-group=<name>) and acceptance
# is off, so a correctly tagged attachment lands in the right place without a manual step.
#
# Call this module with a provider configured for us-west-2 (the Cloud WAN home region).

locals {
  # Attachment policies: groups first (rule 100+), then segments (rule 1000+).
  attachment_rules = concat(
    [for i, g in sort(keys(var.network_function_groups)) : {
      rule_number = 100 + i
      tag_key     = "network-function-group"
      value       = g
      group       = g
      segment     = null
    }],
    [for i, s in sort(keys(var.segments)) : {
      rule_number = 1000 + i
      tag_key     = "segment"
      value       = s
      group       = null
      segment     = s
    }],
  )
}

resource "aws_networkmanager_global_network" "this" {
  description = "${var.name} global network"

  tags = { Name = "${var.name}-global-network" }
}

resource "aws_networkmanager_core_network" "this" {
  global_network_id   = aws_networkmanager_global_network.this.id
  description         = "${var.name} core network"
  create_base_policy  = true
  base_policy_regions = var.edge_locations

  tags = { Name = "${var.name}-core-network" }
}

data "aws_networkmanager_core_network_policy_document" "this" {
  core_network_configuration {
    vpn_ecmp_support = false
    asn_ranges       = [var.asn_range]

    dynamic "edge_locations" {
      for_each = var.edge_locations

      content {
        location = edge_locations.value
      }
    }
  }

  dynamic "segments" {
    for_each = var.segments

    content {
      name                          = segments.key
      description                   = segments.value.description
      edge_locations                = segments.value.edge_locations
      require_attachment_acceptance = segments.value.require_attachment_acceptance
      isolate_attachments           = segments.value.isolate_attachments
    }
  }

  dynamic "network_function_groups" {
    for_each = var.network_function_groups

    content {
      name                          = network_function_groups.key
      description                   = network_function_groups.value.description
      require_attachment_acceptance = network_function_groups.value.require_attachment_acceptance
    }
  }

  dynamic "segment_actions" {
    for_each = var.segment_shares

    content {
      action     = "share"
      mode       = "attachment-route"
      segment    = segment_actions.key
      share_with = segment_actions.value
    }
  }

  dynamic "segment_actions" {
    for_each = var.send_to

    content {
      action  = "send-to"
      segment = segment_actions.key

      via {
        network_function_groups = [segment_actions.value]
      }
    }
  }

  dynamic "attachment_policies" {
    for_each = local.attachment_rules

    content {
      rule_number     = attachment_policies.value.rule_number
      condition_logic = "or"

      conditions {
        type     = "tag-value"
        operator = "equals"
        key      = attachment_policies.value.tag_key
        value    = attachment_policies.value.value
      }

      action {
        add_to_network_function_group = attachment_policies.value.group
        association_method            = attachment_policies.value.segment == null ? null : "constant"
        segment                       = attachment_policies.value.segment
      }
    }
  }
}

resource "aws_networkmanager_core_network_policy_attachment" "this" {
  core_network_id = aws_networkmanager_core_network.this.id
  policy_document = data.aws_networkmanager_core_network_policy_document.this.json
}
