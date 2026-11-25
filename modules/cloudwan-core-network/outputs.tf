output "global_network_id" {
  value = aws_networkmanager_global_network.this.id
}

output "core_network_id" {
  description = "Core network ID. Waits for the policy to be live, so attachments are routed by it."
  value       = aws_networkmanager_core_network.this.id

  depends_on = [aws_networkmanager_core_network_policy_attachment.this]
}

output "core_network_arn" {
  value = aws_networkmanager_core_network.this.arn

  depends_on = [aws_networkmanager_core_network_policy_attachment.this]
}

output "segment_names" {
  value = keys(var.segments)
}

output "network_function_group_names" {
  value = keys(var.network_function_groups)
}
