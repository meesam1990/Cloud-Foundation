output "region" {
  value = local.app.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  value = module.eks.cluster_ca_certificate
}

output "lbc_namespace" {
  value = var.lbc_namespace
}

output "lbc_service_account" {
  value = var.lbc_service_account
}

output "public_access_cidrs" {
  value = local.public_access_cidrs
}

output "detected_ip" {
  description = "This machine's public IP allowed on the API endpoint (null on TFE runs or when detect_my_ip = false)."
  value       = local.detected_ip
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${local.app.region} --name ${module.eks.cluster_name}${var.apps_account.profile == null ? "" : " --profile ${var.apps_account.profile}"}"
}

output "lattice_caller_role_arns" {
  description = "Pod Identity roles of the Lattice callers; name them in the service auth policies (workloads-lattice)."
  value       = { for k, r in module.caller_roles : k => r.arn }
}

output "lattice_callers" {
  value = var.lattice_callers
}
