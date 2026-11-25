# Workload account: the customer inbound path in front of the cluster (HTML hops 0-3).
#
#   Route 53   app.<domain>    -> CloudFront                                           (hop 0)
#              origin.<domain> -> public ALB
#   CloudFront ACM public certificate for app.<domain> (us-east-1), web ACL #1 (managed rules +
#              rate limit), HTTPS only to origin.<domain>, adds the secret X-Origin-Verify header
#   public ALB internet-facing, security group allows CloudFront only; ends the CloudFront session
#              with the exportable public certificate for origin.<domain> (the firewall can load
#              its key for inspection); web ACL #2 allows only requests with the secret header;
#              re-encrypts to the frontend pods (HTTPS app_port)                    (hops 2a-3)
#   pods       registered into the ALB target group by the Load Balancer Controller
#              (TargetGroupBinding, workloads-platform)
#
# The firewall sits between the IGW and the ALB (GWLB endpoints, workloads-network). It does not
# decrypt yet: that needs the vendor firewall acting as an inbound TLS proxy (AWSM-27).
# Hops 4-7 (VPC Lattice, internal ALB, backend pods) are in workloads-lattice.

module "context" {
  source = "../../modules/context"

  environment = var.environment
  function    = "workloads"

  tags = {
    owner       = "devops"
    jira_ticket = var.jira_ticket
    tier        = "web"
  }

  # ADR-44 names; no type tokens (the resource type tells them apart).
  names = {
    alb          = { type = "alb", descriptor = "public" }
    target_group = { type = "target-group", descriptor = "frontend" }
    waf_origin   = { type = "wafv2-web-acl", descriptor = "origin" }
    waf_edge     = { type = "wafv2-web-acl", descriptor = "edge" }
  }

  paths = {
    origin_secret = "cloudfront-origin-verify"
  }
}

locals {
  base        = module.context.base
  names       = module.context.names
  app_fqdn    = "${var.app_hostname}.${var.domain_name}"
  origin_fqdn = "${var.origin_hostname}.${var.domain_name}"
}

# ---------------------------------------------------------------- DNS zone and certificates

module "zone" {
  source = "../../modules/route53-zone"

  name    = var.domain_name
  comment = "${local.base} public zone"
}

module "cloudfront_certificate" {
  source = "../../modules/acm-certificate"

  providers = {
    aws = aws.us_east_1
  }

  domain_name = local.app_fqdn
  zone_id     = module.zone.zone_id
}

module "origin_certificate" {
  source = "../../modules/acm-certificate"

  domain_name = local.origin_fqdn
  zone_id     = module.zone.zone_id
  exportable  = var.origin_certificate_exportable
}

# ---------------------------------------------------------------- origin secret

resource "random_password" "origin_secret" {
  length  = 48
  special = false

  keepers = {
    version = var.origin_secret_version
  }
}

resource "aws_secretsmanager_secret" "origin_secret" {
  name                    = module.context.paths.origin_secret
  description             = "Value of the ${var.origin_verify_header_name} header CloudFront adds to origin requests"
  recovery_window_in_days = var.secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "origin_secret" {
  secret_id     = aws_secretsmanager_secret.origin_secret.id
  secret_string = random_password.origin_secret.result
}

# ---------------------------------------------------------------- public ALB

module "alb" {
  source = "../../modules/alb"

  name               = local.names.alb
  internal           = false
  vpc_id             = local.app.vpc_id
  subnet_ids         = local.app.public_subnet_ids
  security_group_ids = [local.app.public_alb_security_group_id]
  certificate_arn    = module.origin_certificate.arn

  target_group_name = local.names.target_group
  target_type       = "ip"
  target_port       = local.app.app_port
  target_protocol   = "HTTPS"
  health_check      = { path = "/healthz" }
}

# ---------------------------------------------------------------- web ACLs

# #2 on the ALB: only requests that came through CloudFront (secret header) are allowed.
module "waf_alb" {
  source = "../../modules/wafv2-web-acl"

  name           = local.names.waf_origin
  description    = "Allows only requests carrying the CloudFront origin header"
  scope          = "REGIONAL"
  default_action = "block"

  allow_header = {
    name     = var.origin_verify_header_name
    priority = 0
  }
  allow_header_values = [random_password.origin_secret.result]

  associations = {
    alb = module.alb.arn
  }

  logging = {
    retention_in_days = var.log_retention_days
  }
}

# #1 on CloudFront: AWS managed protections and a per-IP rate limit.
module "waf_cloudfront" {
  source = "../../modules/wafv2-web-acl"

  providers = {
    aws = aws.us_east_1
  }

  name           = local.names.waf_edge
  description    = "Edge protections for ${local.app_fqdn}"
  scope          = "CLOUDFRONT"
  default_action = "allow"

  rate_limit = {
    limit    = var.waf_rate_limit
    priority = 0
  }

  managed_rule_groups = [
    { name = "AWSManagedRulesAmazonIpReputationList", priority = 10 },
    { name = "AWSManagedRulesCommonRuleSet", priority = 20 },
    { name = "AWSManagedRulesKnownBadInputsRuleSet", priority = 30 },
    { name = "AWSManagedRulesSQLiRuleSet", priority = 40 },
  ]

  logging = {
    retention_in_days = var.log_retention_days
  }
}

# ---------------------------------------------------------------- CloudFront

module "cloudfront" {
  source = "../../modules/cloudfront-distribution"

  comment             = "${local.base} ${local.app_fqdn}"
  aliases             = [local.app_fqdn]
  acm_certificate_arn = module.cloudfront_certificate.arn
  web_acl_arn         = module.waf_cloudfront.arn
  price_class         = var.cloudfront_price_class

  origin_domain_name         = local.origin_fqdn
  origin_verify_header_name  = var.origin_verify_header_name
  origin_verify_header_value = random_password.origin_secret.result

  # CloudFront must not send traffic before the ALB enforces the header.
  depends_on = [module.waf_alb]
}

# ---------------------------------------------------------------- DNS records

module "records" {
  source = "../../modules/route53-record"

  zone_id = module.zone.zone_id

  records = {
    app-a = {
      name  = local.app_fqdn
      type  = "A"
      alias = { name = module.cloudfront.domain_name, zone_id = module.cloudfront.hosted_zone_id }
    }
    app-aaaa = {
      name  = local.app_fqdn
      type  = "AAAA"
      alias = { name = module.cloudfront.domain_name, zone_id = module.cloudfront.hosted_zone_id }
    }
    origin-a = {
      name  = local.origin_fqdn
      type  = "A"
      alias = { name = module.alb.dns_name, zone_id = module.alb.zone_id }
    }
  }
}

# ---------------------------------------------------------------- Shield Advanced (off)

module "shield" {
  source = "../../modules/shield-advanced"

  enabled = var.enable_shield_advanced
  name    = local.base

  resources = {
    cloudfront = module.cloudfront.arn
    alb        = module.alb.arn
  }
}
