output "trust_anchor_arn" {
  value = aws_rolesanywhere_trust_anchor.this.arn
}

output "profile_arn" {
  value = aws_rolesanywhere_profile.this.arn
}

output "role_arns" {
  description = "Name these in the Lattice service auth policies."
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}
