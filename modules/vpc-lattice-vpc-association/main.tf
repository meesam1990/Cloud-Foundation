# Associates a workload VPC with its environment's VPC Lattice service network (ADR-36).
#
# The association gives the VPC reachability and DNS for every service and resource in the
# network; it is not permission (the auth policies decide). Its security groups decide which
# sources in the VPC may send to Lattice: allow egress to the Lattice managed prefix list
# (com.amazonaws.<region>.vpc-lattice) only from the calling workloads.
#
# Each workload VPC associates with exactly one service network, so prod and non-prod never meet.

resource "aws_vpclattice_service_network_vpc_association" "this" {
  vpc_identifier             = var.vpc_id
  service_network_identifier = var.service_network_arn
  security_group_ids         = var.security_group_ids

  tags = { Name = var.name }
}
