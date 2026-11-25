output "app_url" {
  value = local.edge.app_url
}

output "sample_app_namespace" {
  value = var.deploy_sample_app ? "sample-app" : null
}

output "backend_url" {
  description = "Lattice custom domain of the backend (from the workload VPC, signed requests only)."
  value       = try(local.lattice.service_urls["backend"], null)
}
