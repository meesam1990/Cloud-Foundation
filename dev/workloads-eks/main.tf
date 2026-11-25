# Workload account: EKS cluster in the private subnets.
#
#   - Kubernetes secrets encrypted with a customer managed KMS key
#   - nodes use only the node security group from workloads-network (egress allowlist applies)
#   - nodes reach the internet only through Cloud WAN and the egress VPC (image pulls included)
#   - nodes, their root EBS volumes and ENIs get the ADR-46 tags directly (default_tags do not
#     reach what a launch template creates)
#   - public API endpoint limited to public_access_cidrs (TFE runners, admins; + this machine's IP
#     when detect_my_ip is on); private endpoint on
#   - Pod Identity roles (ADR-36: pods sign Lattice requests with their own role):
#       aws-load-balancer-controller  TargetGroupBinding only (policies/aws-load-balancer-controller.json)
#       lattice callers               one role per calling service account; the service's auth
#                                     policy (workloads-lattice) names the role

module "context" {
  source = "../../modules/context"

  environment = var.environment
  function    = "workloads"

  tags = {
    owner       = "devops"
    jira_ticket = var.jira_ticket
  }

  names = merge(
    {
      kms_secrets = { type = "kms-alias", descriptor = "eks-secrets" }
      lbc_role    = { type = "iam-role", descriptor = "lb-controller" }
    },
    { for k in keys(var.lattice_callers) : "caller_${k}" => { type = "iam-role", descriptor = k } },
  )
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  # A TFE run uses the plan/apply role from dev/tfe-access (<base>-tfe-<stack>-plan|apply).
  is_tfe_run   = can(regex(":assumed-role/[a-z0-9-]+-tfe-[a-z0-9-]+-(plan|apply)/", data.aws_caller_identity.current.arn))
  detect_my_ip = coalesce(var.detect_my_ip, !local.is_tfe_run)
}

# This machine's public IP, read again on every plan: when it changes, the next apply swaps the
# old /32 for the new one (output detected_ip shows which address is allowed).
data "http" "my_ip" {
  count = local.detect_my_ip ? 1 : 0

  url                = "https://checkip.amazonaws.com"
  request_timeout_ms = 5000

  retry {
    attempts     = 3
    min_delay_ms = 1000
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && can(cidrhost("${chomp(self.response_body)}/32", 0))
      error_message = "Could not detect this machine's public IP from checkip.amazonaws.com (3 attempts). Check internet access, or set detect_my_ip = false and list CIDRs in public_access_cidrs."
    }
  }
}

locals {
  name  = local.app.cluster_name
  names = module.context.names

  detected_ip = local.detect_my_ip ? "${chomp(data.http.my_ip[0].response_body)}/32" : null

  public_access_cidrs = distinct(concat(
    local.detected_ip == null ? [] : [local.detected_ip],
    var.public_access_cidrs,
  ))
}

module "kms" {
  source = "../../modules/kms-key"

  alias       = local.names.kms_secrets
  description = "EKS ${local.name} Kubernetes secrets encryption"
}

module "lbc_role" {
  source = "../../modules/iam-role"

  name                = local.names.lbc_role
  description         = "AWS Load Balancer Controller (EKS Pod Identity)"
  trusted_services    = ["pods.eks.amazonaws.com"]
  assume_role_actions = ["sts:AssumeRole", "sts:TagSession"]

  inline_policies = {
    aws-load-balancer-controller = file("${path.module}/policies/aws-load-balancer-controller.json")
  }
}

# Lattice callers: identity policy allowing Invoke on services in this region (the service auth
# policies decide which paths and methods; both are evaluated, and cross-account calls need both).
module "caller_roles" {
  source   = "../../modules/iam-role"
  for_each = var.lattice_callers

  name                = local.names["caller_${each.key}"]
  description         = "VPC Lattice caller ${each.value.namespace}/${each.value.service_account} (EKS Pod Identity)"
  trusted_services    = ["pods.eks.amazonaws.com"]
  assume_role_actions = ["sts:AssumeRole", "sts:TagSession"]

  inline_policies = {
    lattice-invoke = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "InvokeLatticeServices"
        Effect   = "Allow"
        Action   = ["vpc-lattice-svcs:Invoke", "vpc-lattice-svcs:Connect"]
        Resource = ["arn:aws:vpc-lattice:${data.aws_region.current.region}:*:service/*", "arn:aws:vpc-lattice:${data.aws_region.current.region}:*:resourceconfiguration/*"]
      }]
    })
  }
}

module "eks" {
  source = "../../modules/eks-cluster"

  name                   = local.name
  tags                   = module.context.tags
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = local.app.private_subnet_ids
  node_security_group_id = local.app.nodes_security_group_id
  public_access_cidrs    = local.public_access_cidrs
  admin_principal_arns   = var.admin_principal_arns
  secrets_kms_key_arn    = module.kms.arn

  instance_types = var.instance_types
  node_min       = var.node_count
  node_desired   = var.node_count
  node_max       = var.node_count + 1

  pod_identity_associations = merge(
    {
      aws-load-balancer-controller = {
        namespace       = var.lbc_namespace
        service_account = var.lbc_service_account
        role_arn        = module.lbc_role.arn
      }
    },
    {
      for k, c in var.lattice_callers : "lattice-${k}" => {
        namespace       = c.namespace
        service_account = c.service_account
        role_arn        = module.caller_roles[k].arn
      }
    },
  )
}
