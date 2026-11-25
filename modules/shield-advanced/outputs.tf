output "protection_ids" {
  value = { for k, p in aws_shield_protection.this : k => p.id }
}
