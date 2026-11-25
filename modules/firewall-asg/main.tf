# Firewall fleet behind the GWLB: one Auto Scaling group per AZ (cross-zone is off, so each AZ
# needs its own target).
#
# Until the vendor image is ready (AWSM-27; Palo Alto VM-Series managed in Strata Cloud Manager,
# ADR-34) the instances run a stand-in built on the AWS GWLB tunnel handler (gwlbtun.sh.tftpl).
# By default it returns every flow to the GWLB (single-arm, as VM-Series behind a GWLB does); the
# GWLB endpoint's route table then forwards it (e.g. to the NAT gateway for egress). Endpoints
# listed in nat_endpoint_ids are instead NATed out of the instance's own interface (two-arm mode).
# To switch to the real firewall, set ami_id / user_data_override and keep the rest.

data "aws_partition" "current" {}

data "aws_ssm_parameter" "ami" {
  count = var.ami_id == null ? 1 : 0
  name  = var.ami_ssm_parameter
}

# ---------------------------------------------------------------- IAM (Session Manager access)

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = var.name
  role = aws_iam_role.this.name
}

# ---------------------------------------------------------------- security group

resource "aws_security_group" "this" {
  name        = var.name
  description = "GWLB GENEVE traffic and health checks"
  vpc_id      = var.vpc_id

  tags = { Name = var.name }
}

resource "aws_vpc_security_group_ingress_rule" "geneve" {
  for_each = var.gwlb_subnet_cidrs

  security_group_id = aws_security_group.this.id
  description       = "GENEVE from the GWLB in ${each.key}"
  cidr_ipv4         = each.value
  ip_protocol       = "udp"
  from_port         = 6081
  to_port           = 6081
}

resource "aws_vpc_security_group_ingress_rule" "health" {
  for_each = var.gwlb_subnet_cidrs

  security_group_id = aws_security_group.this.id
  description       = "GWLB health checks from ${each.key}"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.health_check_port
  to_port           = var.health_check_port
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "GENEVE back to the GWLB, egress via NAT (inspected traffic, packages, SSM)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------------------------------------------------------- per-AZ fleet

resource "aws_launch_template" "this" {
  for_each = var.subnet_ids

  name_prefix   = "${var.name}-${var.az_ids[each.key]}-"
  image_id      = coalesce(var.ami_id, try(data.aws_ssm_parameter.ami[0].insecure_value, null))
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.this.arn
  }

  vpc_security_group_ids = [aws_security_group.this.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }

  user_data = base64encode(coalesce(var.user_data_override, templatefile("${path.module}/gwlbtun.sh.tftpl", {
    gwlbtun_version   = var.gwlbtun_version
    health_check_port = var.health_check_port
    nat_endpoint_ids  = join(" ", [for id in var.nat_endpoint_ids : trimprefix(id, "vpce-")])
  })))

  # default_tags do not reach what a launch template creates (ADR-46).
  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-${var.az_ids[each.key]}" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "${var.name}-${var.az_ids[each.key]}" })
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = merge(var.tags, { Name = "${var.name}-${var.az_ids[each.key]}" })
  }
}

resource "aws_autoscaling_group" "this" {
  for_each = var.subnet_ids

  name                      = "${var.name}-${var.az_ids[each.key]}"
  vpc_zone_identifier       = [each.value]
  min_size                  = var.instances_per_az
  max_size                  = var.instances_per_az
  desired_capacity          = var.instances_per_az
  target_group_arns         = [var.target_group_arn]
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period

  launch_template {
    id      = aws_launch_template.this[each.key].id
    version = aws_launch_template.this[each.key].latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-${var.az_ids[each.key]}"
    propagate_at_launch = false
  }
}
