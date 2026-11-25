# Route 53 hosted zone: public, or private when vpc_ids is set.
#
# A new public zone answers only once its parent delegates to it: add the name_servers output as
# NS records for the zone name in the parent zone.

resource "aws_route53_zone" "this" {
  name          = var.name
  comment       = var.comment
  force_destroy = var.force_destroy

  dynamic "vpc" {
    for_each = toset(var.vpc_ids)

    content {
      vpc_id = vpc.value
    }
  }

  tags = { Name = var.name }
}
