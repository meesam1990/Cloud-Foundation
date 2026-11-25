# VPC with subnets grouped in tiers (one subnet per AZ per tier) and one route table per subnet,
# so every tier and AZ can route differently (GWLB endpoints and NAT gateways are per AZ).
#
# Addressing (ADR-32): with ipam_pool_id the VPC takes cidr_block from the OU's IPAM pool (the
# planned range is pinned, so the account gets exactly its range); the pool's allocation tag
# (client:ou) must be in tags. Without a pool the CIDR is used as is (test accounts without IPAM).
#
# Names (ADR-44): the VPC is var.name (the account name, or {account}-{descriptor} when the account
# has more than one VPC); subnets and route tables are {vpc}-{tier}-{az id}, NAT gateways
# {vpc}-nat-{az id}, with the AZ ID without its region prefix (usw2-az1 -> az1). The AZ ID is the
# same physical zone in every account; the AZ name is not.
#
# Optional: internet gateway (+ 0.0.0.0/0 route for the tiers in internet_route_tiers), NAT
# gateways (one per AZ, or one shared), VPC flow logs to CloudWatch Logs. The default security
# group is emptied so nothing uses it by accident.
#
# Routes that depend on resources outside the VPC (GWLB endpoints, Cloud WAN, NAT in another tier)
# are added by the caller on the route tables this module outputs.

data "aws_availability_zone" "this" {
  for_each = toset(var.azs)

  name = each.value
}

locals {
  # usw2-az1 -> az1 (ADR-44 section 6).
  az_id = { for az in var.azs : az => regex("-(az[0-9]+)$", data.aws_availability_zone.this[az].zone_id)[0] }

  subnets = merge([
    for tier, t in var.subnet_tiers : {
      for i, az in var.azs : "${tier}/${az}" => {
        tier = tier
        az   = az
        cidr = t.cidrs[i]
        tags = t.tags
      }
    }
  ]...)

  internet_routes = toset(flatten([
    for tier in var.internet_route_tiers : [for az in var.azs : "${tier}/${az}"]
  ]))

  nat_azs = var.nat_gateway == null ? [] : (var.nat_gateway.single ? [var.azs[0]] : var.azs)
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  ipv4_ipam_pool_id    = var.ipam_pool_id
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge({ Name = var.name }, var.tags)
}

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-default-unused" }
}

# ---------------------------------------------------------------- subnets and route tables

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value.az
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = false

  tags = merge({ Name = "${var.name}-${each.value.tier}-${local.az_id[each.value.az]}", subnet_tier = each.value.tier }, each.value.tags)
}

resource "aws_route_table" "this" {
  for_each = local.subnets

  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-${each.value.tier}-${local.az_id[each.value.az]}", subnet_tier = each.value.tier }
}

resource "aws_route_table_association" "this" {
  for_each = local.subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.this[each.key].id
}

# ---------------------------------------------------------------- internet gateway

resource "aws_internet_gateway" "this" {
  count = var.create_internet_gateway ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = { Name = var.name }
}

resource "aws_route" "internet" {
  for_each = local.internet_routes

  route_table_id         = aws_route_table.this[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

# ---------------------------------------------------------------- NAT gateways

resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)

  domain = "vpc"

  tags = { Name = "${var.name}-nat-${local.az_id[each.key]}" }
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this["${var.nat_gateway.subnet_tier}/${each.key}"].id

  tags = { Name = "${var.name}-nat-${local.az_id[each.key]}" }

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------- flow logs

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.flow_logs.enabled ? 1 : 0

  name              = coalesce(var.flow_logs.log_group_name, "/aws/vpc/flow-logs/${var.name}")
  retention_in_days = var.flow_logs.retention_in_days
  kms_key_id        = var.flow_logs.kms_key_arn
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flow_logs" {
  count = var.flow_logs.enabled ? 1 : 0

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs[0].arn}:*"]
  }
}

resource "aws_iam_role" "flow_logs" {
  count = var.flow_logs.enabled ? 1 : 0

  name               = "${var.name}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.flow_logs.enabled ? 1 : 0

  name   = "flow-logs"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs[0].json
}

resource "aws_flow_log" "this" {
  count = var.flow_logs.enabled ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = var.flow_logs.traffic_type
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn             = aws_iam_role.flow_logs[0].arn
  max_aggregation_interval = 60

  tags = { Name = var.name }
}
