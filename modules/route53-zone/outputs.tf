output "zone_id" {
  value = aws_route53_zone.this.zone_id
}

output "name" {
  value = aws_route53_zone.this.name
}

output "name_servers" {
  description = "Delegate the zone to these from its parent (public zones)."
  value       = aws_route53_zone.this.name_servers
}
