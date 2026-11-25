output "asg_names" {
  description = "Auto Scaling group by AZ (the tests use these to find the instances)."
  value       = { for az, g in aws_autoscaling_group.this : az => g.name }
}

output "security_group_id" {
  value = aws_security_group.this.id
}
