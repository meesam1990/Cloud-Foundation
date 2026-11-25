# Public ACM certificate, DNS-validated in a Route 53 public hosted zone.
#
# exportable = true issues it as an exportable public certificate (billed): its private key can be
# exported (aws acm export-certificate) and loaded on the firewall for TLS inspection.
#
# Validation only completes once the zone is publicly resolvable (delegated from its parent).
# For CloudFront, call this module with a us-east-1 provider.

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  key_algorithm             = var.key_algorithm
  validation_method         = "DNS"

  options {
    certificate_transparency_logging_preference = "ENABLED"
    export                                      = var.exportable ? "ENABLED" : "DISABLED"
  }

  tags = { Name = var.domain_name }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = {
    for o in aws_acm_certificate.this.domain_validation_options : o.domain_name => {
      name   = o.resource_record_name
      type   = o.resource_record_type
      record = o.resource_record_value
    }
  }

  zone_id         = var.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  count = var.wait_for_validation ? 1 : 0

  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]

  timeouts {
    create = var.validation_timeout
  }
}
