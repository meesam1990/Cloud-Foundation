output "id" {
  value = aws_vpclattice_service.this.id
}

output "arn" {
  value = aws_vpclattice_service.this.arn
}

output "dns_name" {
  description = "Generated Lattice DNS name. Point the custom domain's CNAME here."
  value       = aws_vpclattice_service.this.dns_entry[0].domain_name
}

output "dns_hosted_zone_id" {
  value = aws_vpclattice_service.this.dns_entry[0].hosted_zone_id
}

output "url" {
  value = "https://${coalesce(var.custom_domain_name, aws_vpclattice_service.this.dns_entry[0].domain_name)}"
}

output "target_group_ids" {
  value = { for k, tg in aws_vpclattice_target_group.this : k => tg.id }
}

output "service_network_association_id" {
  value = try(aws_vpclattice_service_network_service_association.this[0].id, null)
}
