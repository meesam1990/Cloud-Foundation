output "id" {
  value = aws_vpclattice_resource_gateway.this.id
}

output "arn" {
  value = aws_vpclattice_resource_gateway.this.arn
}

output "resource_configuration_arns" {
  value = { for k, r in aws_vpclattice_resource_configuration.this : k => r.arn }
}

output "resource_configuration_ids" {
  value = { for k, r in aws_vpclattice_resource_configuration.this : k => r.id }
}
