output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_arn" {
  value = aws_vpc.this.arn
}

output "vpc_cidr_block" {
  value = aws_vpc.this.cidr_block
}

output "internet_gateway_id" {
  value = try(aws_internet_gateway.this[0].id, null)
}

output "subnet_ids" {
  description = "Subnet IDs as { tier = { az = id } }."
  value       = { for tier in keys(var.subnet_tiers) : tier => { for az in var.azs : az => aws_subnet.this["${tier}/${az}"].id } }
}

output "subnet_arns" {
  description = "Subnet ARNs as { tier = { az = arn } }."
  value       = { for tier in keys(var.subnet_tiers) : tier => { for az in var.azs : az => aws_subnet.this["${tier}/${az}"].arn } }
}

output "subnet_cidrs" {
  description = "Subnet CIDRs as { tier = { az = cidr } }."
  value       = { for tier in keys(var.subnet_tiers) : tier => { for az in var.azs : az => aws_subnet.this["${tier}/${az}"].cidr_block } }
}

output "route_table_ids" {
  description = "Route table IDs as { tier = { az = id } }."
  value       = { for tier in keys(var.subnet_tiers) : tier => { for az in var.azs : az => aws_route_table.this["${tier}/${az}"].id } }
}

output "nat_gateway_ids" {
  description = "NAT gateway to use from each AZ (the shared one when single = true)."
  value = var.nat_gateway == null ? {} : {
    for az in var.azs : az => aws_nat_gateway.this[var.nat_gateway.single ? var.azs[0] : az].id
  }
}

output "nat_public_ips" {
  value = [for e in aws_eip.nat : e.public_ip]
}

output "az_ids" {
  description = "Short AZ ID by AZ name, e.g. { us-west-2a = \"az1\" } (ADR-44 names)."
  value       = local.az_id
}
