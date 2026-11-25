output "ipam_id" {
  description = "IPAM ID."
  value       = aws_vpc_ipam.this.id
}

output "ipam_arn" {
  description = "IPAM ARN."
  value       = aws_vpc_ipam.this.arn
}

output "private_default_scope_id" {
  description = "Default private scope (all routable space)."
  value       = aws_vpc_ipam.this.private_default_scope_id
}

output "sandbox_scope_id" {
  description = "Sandbox private scope. Null without a sandbox."
  value       = one(aws_vpc_ipam_scope.sandbox[*].id)
}

output "global_pool_id" {
  description = "Global pool (every active block, no locale)."
  value       = aws_vpc_ipam_pool.global.id
}

output "regional_pool_ids" {
  description = "Regional pool IDs by region."
  value       = { for r, p in aws_vpc_ipam_pool.regional : r => p.id }
}

output "ou_pool_ids" {
  description = "OU pool IDs keyed by \"<ou>/<region>\". Account stacks pass these as the VPC's ipv4_ipam_pool_id."
  value       = { for k, p in aws_vpc_ipam_pool.ou : k => p.id }

  # Pools are usable only once their CIDRs are provisioned.
  depends_on = [aws_vpc_ipam_pool_cidr.ou]
}

output "ou_pool_arns" {
  description = "OU pool ARNs keyed by \"<ou>/<region>\"."
  value       = { for k, p in aws_vpc_ipam_pool.ou : k => p.arn }
}

output "sandbox_pool_id" {
  description = "Sandbox pool ID. Null without a sandbox."
  value       = one(aws_vpc_ipam_pool.sandbox[*].id)

  depends_on = [aws_vpc_ipam_pool_cidr.sandbox]
}

output "ram_share_arns" {
  description = "RAM share ARNs keyed by \"<ou>/<region>\" (OU pools with an ou_arn) plus \"sandbox\" when the sandbox is shared."
  value = merge(
    { for k, s in aws_ram_resource_share.ou : k => s.arn },
    local.sandbox_shared ? { sandbox = aws_ram_resource_share.sandbox[0].arn } : {},
  )
}
