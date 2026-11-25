output "id" {
  value = aws_vpc_endpoint.this.id
}

output "arn" {
  value = aws_vpc_endpoint.this.arn
}

output "network_interface_ids" {
  value = aws_vpc_endpoint.this.network_interface_ids
}

output "dns_entries" {
  description = "DNS names of the endpoint (for ServiceNetwork endpoints, one per service/resource)."
  value       = aws_vpc_endpoint.this.dns_entry
}
