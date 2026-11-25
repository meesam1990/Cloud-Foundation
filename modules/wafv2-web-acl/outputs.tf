output "arn" {
  value = aws_wafv2_web_acl.this.arn
}

output "id" {
  value = aws_wafv2_web_acl.this.id
}

output "log_group_name" {
  value = try(aws_cloudwatch_log_group.this[0].name, null)
}
