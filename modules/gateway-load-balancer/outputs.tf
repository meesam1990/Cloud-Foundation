output "arn" {
  value = aws_lb.this.arn
}

output "arn_suffix" {
  description = "gwy/<name>/<id>; the GWLB ENIs are described as \"ELB <arn_suffix>\"."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn" {
  value = aws_lb_target_group.this.arn
}

output "endpoint_service_name" {
  description = "Pass to modules/vpc-endpoint (vpc_endpoint_type = GatewayLoadBalancer)."
  value       = aws_vpc_endpoint_service.this.service_name
}

output "endpoint_service_id" {
  value = aws_vpc_endpoint_service.this.id
}
