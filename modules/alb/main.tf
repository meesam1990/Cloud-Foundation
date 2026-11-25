# Application Load Balancer with one HTTPS listener and one target group.
#
# Targets are registered from outside Terraform (the AWS Load Balancer Controller's
# TargetGroupBinding adds the pod IPs), so the target group has no attachments here.
# TLS is re-encrypted to the targets (target_protocol HTTPS); the ALB does not validate target
# certificates.

resource "aws_lb" "this" {
  name                       = var.name
  load_balancer_type         = "application"
  internal                   = var.internal
  subnets                    = var.subnet_ids
  security_groups            = var.security_group_ids
  idle_timeout               = var.idle_timeout
  drop_invalid_header_fields = true
  desync_mitigation_mode     = "defensive"
  enable_deletion_protection = var.deletion_protection

  dynamic "access_logs" {
    for_each = var.access_logs == null ? [] : [var.access_logs]

    content {
      enabled = true
      bucket  = access_logs.value.bucket
      prefix  = access_logs.value.prefix
    }
  }

  tags = { Name = var.name }
}

resource "aws_lb_target_group" "this" {
  name                 = var.target_group_name
  vpc_id               = var.vpc_id
  port                 = var.target_port
  protocol             = var.target_protocol
  protocol_version     = "HTTP1"
  target_type          = var.target_type
  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = var.target_protocol
    port                = "traffic-port"
    path                = var.health_check.path
    matcher             = var.health_check.matcher
    interval            = var.health_check.interval
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = var.target_group_name }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

resource "aws_lb_listener_certificate" "additional" {
  for_each = toset(var.additional_certificate_arns)

  listener_arn    = aws_lb_listener.https.arn
  certificate_arn = each.value
}
