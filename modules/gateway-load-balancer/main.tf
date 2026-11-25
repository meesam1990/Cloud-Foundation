# Gateway Load Balancer in the firewall VPC's firewall subnets, with:
#
#   - a GENEVE target group the firewall Auto Scaling groups register into
#   - a PrivateLink endpoint service, so GWLB endpoints in other VPCs (and, in prod, other
#     accounts) can send traffic to it; only allowed_principals may connect
#
# Cross-zone is off: each AZ's endpoint only sends to that AZ's firewall, which keeps flows
# symmetric with Cloud WAN appliance mode. The endpoints themselves are modules/vpc-endpoint,
# because they live in the consumer VPCs.

resource "aws_lb" "this" {
  name                             = var.name
  load_balancer_type               = "gateway"
  subnets                          = var.subnet_ids
  enable_cross_zone_load_balancing = var.cross_zone

  tags = { Name = var.name }
}

resource "aws_lb_target_group" "this" {
  name                 = var.name
  port                 = 6081
  protocol             = "GENEVE"
  target_type          = "instance"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    protocol            = "HTTP"
    port                = var.health_check_port
    path                = var.health_check_path
    interval            = 10
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  target_failover {
    on_deregistration = "rebalance"
    on_unhealthy      = "rebalance"
  }

  tags = { Name = var.name }
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_vpc_endpoint_service" "this" {
  acceptance_required        = false
  gateway_load_balancer_arns = [aws_lb.this.arn]
  allowed_principals         = var.allowed_principals

  tags = { Name = var.name }
}
