# Workload account: services published in the environment's VPC Lattice service network (ADR-36),
# HTML hops 4-7.
#
#   frontend pod --(SigV4, Pod Identity role)--> backend.<env>.client.internal       (hop 4)
#     -> VPC Lattice service (auth AWS_IAM; network policy + service policy)       (hop 5)
#     -> internal ALB (HTTPS, security group: Lattice prefix list only)            (hop 6a)
#     -> backend pods (HTTPS app_port, TargetGroupBinding in workloads-platform)   (hop 6b)
#   databases (RDS Proxy / Aurora, Oracle): resource gateway + resource configurations for callers
#   in other VPCs (hops 7a-7b); callers in this VPC keep the direct hop (ADR-36 open item, resolved:
#   calls inside one VPC stay on the VPC).
#
# Per service (var.services):
#   internal ALB + target group     the EKS target type (ADR-36 open item, resolved: internal ALB by
#                                   default; Terraform owns the ALB, the Load Balancer Controller
#                                   only registers pod IPs)
#   Lattice service                 custom domain <name>.<env>.client.internal, HTTPS listener,
#                                   target group type ALB, auth policy naming the caller roles,
#                                   access logs, association with the service network
#   private hosted zone record      CNAME custom domain -> Lattice DNS name (ADR-36 section 4)
#
# Certificates (ADR-36 open item, resolved): custom domains with Client certificates in ACM. Pass
# certificate_arn (issued by the Client CA and imported into ACM). Without it, a dev CA is generated
# here as a stand-in and its certificate imported; pods trust it through the CA bundle output (the
# private key is in the state: keep the state in TFE). Lattice does not validate target
# certificates, so the internal ALB uses the same certificate.

module "context" {
  source = "../../modules/context"

  environment = var.environment
  function    = "workloads"

  tags = {
    owner       = "devops"
    jira_ticket = var.jira_ticket
    tier        = "application"
  }

  names = merge(
    { for k in keys(var.services) : "alb_${k}" => { type = "alb", descriptor = k } },
    { for k in keys(var.services) : "tg_${k}" => { type = "target-group", descriptor = k } },
    { for k in keys(var.services) : "svc_${k}" => { type = "lattice-service", descriptor = k } },
    {
      resource_gateway    = { type = "lattice-resource-gateway", descriptor = "data" }
      resource_gateway_sg = { type = "security-group", descriptor = "data-gateway" }
      onprem              = { type = "rolesanywhere-trust-anchor", descriptor = "onprem" }
    },
    { for k in keys(var.lattice_resources) : "res_${k}" => { type = "lattice-resource-configuration", descriptor = k } },
    { for k in keys(var.onprem_callers) : "onprem_${k}" => { type = "iam-role", descriptor = "onprem-${k}" } },
  )

  paths = { for k in keys(var.services) : k => "lattice-${k}-access-logs" }
}

locals {
  names          = module.context.names
  private_domain = coalesce(var.private_domain, "${var.environment}.client.internal")

  fqdn = { for k, s in var.services : k => "${coalesce(s.hostname, k)}.${local.private_domain}" }

  # Caller keys refer to the Pod Identity roles of workloads-eks; extra ARNs (EC2 instance roles,
  # Roles Anywhere roles, other accounts) are added as they are.
  caller_arns = {
    for k, s in var.services : k => distinct(concat(
      [for c in s.callers : local.eks.lattice_caller_role_arns[c]],
      [for c in s.onprem_callers : module.roles_anywhere[0].role_arns[c]],
      s.extra_caller_arns,
    ))
  }

  generate_certificate = var.certificate_arn == null
  certificate_arn      = local.generate_certificate ? aws_acm_certificate.dev[0].arn : var.certificate_arn
}

# ---------------------------------------------------------------- certificate (dev CA stand-in)

resource "tls_private_key" "ca" {
  count = local.generate_certificate ? 1 : 0

  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "ca" {
  count = local.generate_certificate ? 1 : 0

  private_key_pem       = tls_private_key.ca[0].private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 24 * 365 * 2

  subject {
    common_name  = "${module.context.base} internal CA (dev stand-in for the Client CA)"
    organization = "Client"
  }

  allowed_uses = ["cert_signing", "crl_signing"]
}

resource "tls_private_key" "services" {
  count = local.generate_certificate ? 1 : 0

  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "services" {
  count = local.generate_certificate ? 1 : 0

  private_key_pem = tls_private_key.services[0].private_key_pem
  dns_names       = concat(["*.${local.private_domain}"], values(local.fqdn))

  subject {
    common_name  = "*.${local.private_domain}"
    organization = "Client"
  }
}

resource "tls_locally_signed_cert" "services" {
  count = local.generate_certificate ? 1 : 0

  cert_request_pem      = tls_cert_request.services[0].cert_request_pem
  ca_private_key_pem    = tls_private_key.ca[0].private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca[0].cert_pem
  validity_period_hours = 24 * 365
  early_renewal_hours   = 24 * 30

  allowed_uses = ["digital_signature", "key_encipherment", "server_auth"]
}

resource "aws_acm_certificate" "dev" {
  count = local.generate_certificate ? 1 : 0

  private_key       = tls_private_key.services[0].private_key_pem
  certificate_body  = tls_locally_signed_cert.services[0].cert_pem
  certificate_chain = tls_self_signed_cert.ca[0].cert_pem

  tags = { Name = "*.${local.private_domain}" }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------- private hosted zone

module "zone" {
  source = "../../modules/route53-zone"

  name    = local.private_domain
  comment = "${module.context.base}: VPC Lattice custom domains (ADR-36)"
  vpc_ids = [local.app.vpc_id]
}

# ---------------------------------------------------------------- internal ALBs (Lattice targets)

module "alb" {
  source   = "../../modules/alb"
  for_each = var.services

  name               = local.names["alb_${each.key}"]
  internal           = true
  vpc_id             = local.app.vpc_id
  subnet_ids         = local.app.private_subnet_ids
  security_group_ids = [local.app.backend_alb_security_group_id]
  certificate_arn    = local.certificate_arn

  target_group_name = local.names["tg_${each.key}"]
  target_type       = "ip"
  target_port       = local.app.app_port
  target_protocol   = "HTTPS"
  health_check      = { path = each.value.health_check_path }
}

# ---------------------------------------------------------------- Lattice services

module "service" {
  source   = "../../modules/vpc-lattice-service"
  for_each = var.services

  name                = local.names["svc_${each.key}"]
  custom_domain_name  = local.fqdn[each.key]
  certificate_arn     = local.certificate_arn
  service_network_arn = local.app.service_network_arn

  target_groups = {
    alb = {
      type     = "ALB"
      port     = 443
      protocol = "HTTPS"
      vpc_id   = local.app.vpc_id
      targets  = [{ id = module.alb[each.key].arn, port = 443 }]
    }
  }

  listeners = {
    https = {
      protocol             = "HTTPS"
      port                 = 443
      default_target_group = "alb"
    }
  }

  allowed_callers = length(local.caller_arns[each.key]) == 0 ? {} : {
    callers = {
      principal_arns = local.caller_arns[each.key]
      methods        = each.value.methods
      paths          = each.value.paths
    }
  }

  access_logs = {
    destination_arns  = var.access_log_destination_arns
    log_group_name    = module.context.paths[each.key]
    retention_in_days = var.log_retention_days
  }
}

module "records" {
  source = "../../modules/route53-record"

  zone_id = module.zone.zone_id

  records = {
    for k, s in var.services : k => {
      name   = local.fqdn[k]
      type   = "CNAME"
      ttl    = 300
      values = [module.service[k].dns_name]
    }
  }
}

# ---------------------------------------------------------------- databases (resource configurations)

module "resource_gateway_sg" {
  source = "../../modules/security-group"
  count  = length(var.lattice_resources) > 0 ? 1 : 0

  name        = local.names.resource_gateway_sg
  description = "Lattice resource gateway: to the databases in the data tier"
  vpc_id      = local.app.vpc_id

  egress_rules = merge([
    for k, r in var.lattice_resources : {
      for p in setproduct(local.app.data_subnet_cidrs, r.ports) : "${k}-${replace(p[0], "/", "-")}-${p[1]}" => {
        description = "${k} on ${p[1]}"
        ip_protocol = "tcp"
        from_port   = tonumber(p[1])
        cidr_ipv4   = p[0]
      }
    }
  ]...)
}

module "resource_gateway" {
  source = "../../modules/vpc-lattice-resource-gateway"
  count  = length(var.lattice_resources) > 0 ? 1 : 0

  name                = local.names.resource_gateway
  vpc_id              = local.app.vpc_id
  subnet_ids          = local.app.data_subnet_ids
  security_group_ids  = [module.resource_gateway_sg[0].id]
  service_network_arn = local.app.service_network_arn

  resource_configurations = {
    for k, r in var.lattice_resources : k => {
      name               = local.names["res_${k}"]
      dns_name           = r.dns_name
      ip_address         = r.ip_address
      arn                = r.arn
      port_ranges        = [for p in r.ports : tostring(p)]
      custom_domain_name = r.custom_domain_name
    }
  }
}

# ---------------------------------------------------------------- on-premises callers (optional)

module "roles_anywhere" {
  source = "../../modules/iam-roles-anywhere"
  count  = var.onprem_ca_certificate_pem == null ? 0 : 1

  name               = local.names.onprem
  ca_certificate_pem = var.onprem_ca_certificate_pem

  roles = {
    for k, c in var.onprem_callers : k => {
      role_name      = local.names["onprem_${k}"]
      certificate_cn = c.certificate_cn
      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect   = "Allow"
          Action   = ["vpc-lattice-svcs:Invoke"]
          Resource = ["arn:aws:vpc-lattice:${local.app.region}:*:service/*"]
        }]
      })
    }
  }
}
