output "region" {
  value = local.network.region
}

output "environment" {
  value = var.environment
}

output "base" {
  description = "{environment}-{function} (ADR-44), e.g. dev-workloads."
  value       = local.base
}

output "cluster_name" {
  description = "Name the EKS cluster must use (the node security group is tagged for it)."
  value       = local.cluster_name
}

output "azs" {
  value = local.azs
}

output "internal_cidrs" {
  value = local.internal_cidrs
}

output "app_port" {
  value = var.app_port
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr" {
  value = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  value = values(module.vpc.subnet_ids["public"])
}

output "public_subnet_cidrs" {
  description = "Source of the public ALB's traffic and health checks to the pods."
  value       = values(module.vpc.subnet_cidrs["public"])
}

output "private_subnet_ids" {
  description = "EKS nodes and pods, internal ALBs."
  value       = values(module.vpc.subnet_ids["private"])
}

output "private_subnet_cidrs" {
  value = values(module.vpc.subnet_cidrs["private"])
}

output "data_subnet_ids" {
  description = "Databases and the Lattice resource gateway."
  value       = values(module.vpc.subnet_ids["data"])
}

output "data_subnet_cidrs" {
  value = values(module.vpc.subnet_cidrs["data"])
}

output "public_alb_security_group_id" {
  value = module.alb_sg.id
}

output "backend_alb_security_group_id" {
  value = module.backend_alb_sg.id
}

output "nodes_security_group_id" {
  value = module.nodes_sg.id
}

output "service_network_arn" {
  value = local.network.service_network_arn
}

output "lattice_vpc_association_id" {
  value = module.lattice_association.id
}
