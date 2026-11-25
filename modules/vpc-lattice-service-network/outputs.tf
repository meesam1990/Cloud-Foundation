output "id" {
  value = aws_vpclattice_service_network.this.id
}

output "arn" {
  description = "Use as service_network_identifier from other accounts (after the RAM share is accepted)."
  value       = aws_vpclattice_service_network.this.arn

  depends_on = [aws_vpclattice_auth_policy.this]
}

output "name" {
  value = aws_vpclattice_service_network.this.name
}

output "ram_share_arn" {
  description = "Null when not shared."
  value       = try(aws_ram_resource_share.this[0].arn, null)
}

output "access_log_group_name" {
  value = try(aws_cloudwatch_log_group.access_logs[0].name, null)
}
