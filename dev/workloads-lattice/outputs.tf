output "service_urls" {
  description = "Custom domain URL of each service (resolvable from the workload VPC)."
  value       = { for k, s in module.service : k => "https://${local.fqdn[k]}" }
}

output "service_dns_names" {
  description = "Generated Lattice DNS names."
  value       = { for k, s in module.service : k => s.dns_name }
}

output "service_arns" {
  value = { for k, s in module.service : k => s.arn }
}

output "alb_target_group_arns" {
  description = "Internal ALB target groups; the backend pods are registered by a TargetGroupBinding (workloads-platform)."
  value       = { for k, a in module.alb : k => a.target_group_arn }
}

output "private_domain" {
  value = local.private_domain
}

output "ca_bundle_pem" {
  description = "CA that signed the service certificates (dev stand-in). Pods mount it to verify the custom domains. Null when certificate_arn is given."
  value       = try(tls_self_signed_cert.ca[0].cert_pem, null)
}

output "resource_configuration_arns" {
  value = try(module.resource_gateway[0].resource_configuration_arns, {})
}

output "roles_anywhere" {
  description = "Trust anchor and profile for on-premises callers (aws_signing_helper), and their role ARNs."
  value = var.onprem_ca_certificate_pem == null ? null : {
    trust_anchor_arn = module.roles_anywhere[0].trust_anchor_arn
    profile_arn      = module.roles_anywhere[0].profile_arn
    role_arns        = module.roles_anywhere[0].role_arns
  }
}
