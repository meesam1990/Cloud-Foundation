output "app_url" {
  value = "https://${local.app_fqdn}/"
}

output "app_fqdn" {
  value = local.app_fqdn
}

output "origin_fqdn" {
  value = local.origin_fqdn
}

output "name_servers" {
  description = "Delegate domain_name to these from the parent zone (NS record), or nothing validates."
  value       = module.zone.name_servers
}

output "cloudfront_domain_name" {
  value = module.cloudfront.domain_name
}

output "alb_dns_name" {
  description = "Public ALB (origin). Only CloudFront can connect to it."
  value       = module.alb.dns_name
}

output "alb_target_group_arn" {
  description = "Pods are registered here by the TargetGroupBinding in workloads-platform."
  value       = module.alb.target_group_arn
}

output "origin_certificate_arn" {
  description = "Exportable certificate on the ALB (aws acm export-certificate for the firewall)."
  value       = module.origin_certificate.arn
}

output "origin_verify_header_name" {
  value = var.origin_verify_header_name
}

output "origin_secret_arn" {
  description = "Secrets Manager secret holding the origin header value."
  value       = aws_secretsmanager_secret.origin_secret.arn
}

output "waf_alb_arn" {
  value = module.waf_alb.arn
}

output "waf_cloudfront_arn" {
  value = module.waf_cloudfront.arn
}
