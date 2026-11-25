# Attaches a VPC to the core network. Placement is driven by routing_tags, which the core network
# policy matches (segment=<name> or network-function-group=<name>).
#
# Inspection VPCs need appliance_mode = true so both directions of a flow use the same AZ and
# therefore the same (stateful) firewall.

resource "aws_networkmanager_vpc_attachment" "this" {
  core_network_id = var.core_network_id
  vpc_arn         = var.vpc_arn
  subnet_arns     = var.subnet_arns

  options {
    appliance_mode_support = var.appliance_mode
  }

  tags = merge({ Name = "${var.name}-cwan-attachment" }, var.routing_tags)
}
