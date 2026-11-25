output "region" {
  value = var.region
}

output "environment" {
  value = var.environment
}

output "az_ids" {
  description = "AZ IDs in use; other accounts map them to their own AZ names."
  value       = local.az_ids
}

output "internal_cidrs" {
  value = var.internal_cidrs
}

output "core_network_id" {
  value = module.cloudwan.core_network_id
}

output "core_network_arn" {
  value = module.cloudwan.core_network_arn
}

output "workloads_segment_name" {
  value = local.segment.workloads
}

output "segment_names" {
  value = local.segment
}

output "egress_group_name" {
  value = local.egress_group
}

output "core_network_ram_share_arn" {
  description = "Accept in the workload account (workloads-network does it). Null in single-account setups."
  value       = try(aws_ram_resource_share.core_network[0].arn, null)
}

output "ram_share_region" {
  value = var.ram_share_region
}

output "gwlb_endpoint_service_name" {
  value = module.gwlb.endpoint_service_name
}

output "egress_vpc_id" {
  value = module.egress_vpc.vpc_id
}

output "inbound_vpc_id" {
  value = module.inbound_vpc.vpc_id
}

output "nat_public_ips" {
  description = "Egress IPs the internet sees (allowlist these at third parties)."
  value       = module.egress_vpc.nat_public_ips
}

output "firewall_asg_names" {
  value = module.firewall.asg_names
}

output "resolver_inbound_ips" {
  description = "Forward the AWS zones (e.g. dev.client.internal) to these from on-premises AD DNS."
  value       = module.resolver_inbound.ip_addresses
}

output "service_network_arn" {
  description = "Environment's Lattice service network (workloads associate VPCs, services and resources with it)."
  value       = module.service_network.arn
}

output "service_network_ram_share_arn" {
  description = "Accept in the workload account. Null when not shared."
  value       = module.service_network.ram_share_arn
}

output "service_network_endpoint_dns_entries" {
  description = "DNS names on the Inbound VPC's service network endpoint (on-premises callers)."
  value       = module.services_endpoint.dns_entries
}
