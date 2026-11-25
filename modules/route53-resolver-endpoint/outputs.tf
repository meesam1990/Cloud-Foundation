output "id" {
  value = aws_route53_resolver_endpoint.this.id
}

output "ip_addresses" {
  description = "Forward targets for on-premises DNS (INBOUND)."
  value       = [for ip in aws_route53_resolver_endpoint.this.ip_address : ip.ip]
}

output "security_group_id" {
  value = aws_security_group.this.id
}
