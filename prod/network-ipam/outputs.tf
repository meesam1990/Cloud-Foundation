output "ipam_id" {
  description = "IPAM ID."
  value       = module.ipam.ipam_id
}

output "ou_pool_ids" {
  description = "OU pool IDs by OU and region, e.g. ou_pool_ids[\"client-apps\"][\"us-west-2\"]. Account stacks pass them as the VPC's ipv4_ipam_pool_id and tag the VPC client:ou = <ou>."
  value = {
    for ou in distinct([for k in keys(module.ipam.ou_pool_ids) : split("/", k)[0]]) : ou => {
      for k, id in module.ipam.ou_pool_ids : split("/", k)[1] => id if split("/", k)[0] == ou
    }
  }
}

output "sandbox_pool_id" {
  description = "Sandbox pool ID (us-west-2, separate scope). Sandbox VPCs are tagged client:ou = sandbox."
  value       = module.ipam.sandbox_pool_id
}

output "ram_share_arns" {
  description = "RAM share ARNs keyed by \"<ou>/<region>\" and \"sandbox\" (only OUs with an ARN in ou_arns)."
  value       = module.ipam.ram_share_arns
}
