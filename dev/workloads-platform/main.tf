# Helm releases on the cluster:
#
#   aws-load-balancer-controller  only registers pod IPs into the Terraform-managed ALB target
#                                 groups (TargetGroupBinding); it creates no load balancers. Its
#                                 defaultTags carry the ADR-46 tags onto anything it does create.
#   cert-manager                  issues the pod certificates
#   cert-manager-issuers          internal CA + ClusterIssuer "client-internal" (charts/)
#   sample-app                    frontend: CloudFront -> public ALB -> pods (hops 0-3); its service
#                                 account "frontend" is the Lattice caller (Pod Identity role)
#   backend                       backend: VPC Lattice -> internal ALB -> pods (hops 5-6b)

module "context" {
  source = "../../modules/context"

  environment = var.environment
  function    = "workloads"

  tags = {
    owner       = "devops"
    jira_ticket = var.jira_ticket
  }
}

locals {
  charts = "${path.module}/../../charts"

  frontend_caller = try(local.eks.lattice_callers["frontend"], null)
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lbc_chart_version
  namespace  = local.eks.lbc_namespace
  wait       = true
  timeout    = 600

  values = [yamlencode({
    clusterName  = local.eks.cluster_name
    region       = local.eks.region
    vpcId        = local.app.vpc_id
    replicaCount = 2

    # Credentials come from the Pod Identity association on this service account (workloads-eks).
    serviceAccount = {
      create = true
      name   = local.eks.lbc_service_account
    }

    # Kubernetes-created AWS resources are tagged directly (ADR-46).
    defaultTags = module.context.tags

    # Load balancers, WAF and Shield are Terraform's (workloads-edge, workloads-lattice).
    createIngressClassResource  = false
    enableServiceMutatorWebhook = false
    enableWafv2                 = false
    enableWaf                   = false
    enableShield                = false
  })]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version
  namespace        = "cert-manager"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    crds = { enabled = true }
  })]
}

resource "helm_release" "cert_manager_issuers" {
  name      = "cert-manager-issuers"
  chart     = "${local.charts}/cert-manager-issuers"
  namespace = "cert-manager"

  depends_on = [helm_release.cert_manager]
}

resource "helm_release" "sample_app" {
  count = var.deploy_sample_app ? 1 : 0

  name             = "sample-app"
  chart            = "${local.charts}/sample-app"
  namespace        = "sample-app"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    containerPort = local.app.app_port

    targetGroupBinding = {
      targetGroupArn = local.edge.alb_target_group_arn
    }

    # The Lattice caller identity (Pod Identity association in workloads-eks).
    serviceAccount = local.frontend_caller == null ? { create = false, name = "" } : {
      create = local.frontend_caller.namespace == "sample-app"
      name   = local.frontend_caller.service_account
    }

    latticeCaBundle = local.lattice.ca_bundle_pem == null ? "" : local.lattice.ca_bundle_pem

    networkPolicy = {
      enabled        = var.sample_app_network_policy
      albSubnetCidrs = local.app.public_subnet_cidrs
    }
  })]

  depends_on = [
    helm_release.aws_load_balancer_controller,
    helm_release.cert_manager_issuers,
  ]
}

# Backend behind VPC Lattice: same test image, registered into the internal ALB's target group.
resource "helm_release" "backend" {
  count = var.deploy_sample_app && contains(keys(local.lattice.alb_target_group_arns), "backend") ? 1 : 0

  name             = "backend"
  chart            = "${local.charts}/sample-app"
  namespace        = "sample-app"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    containerPort = local.app.app_port

    targetGroupBinding = {
      targetGroupArn = local.lattice.alb_target_group_arns["backend"]
    }

    # The internal ALB is in the private subnets.
    networkPolicy = {
      enabled        = var.sample_app_network_policy
      albSubnetCidrs = local.app.private_subnet_cidrs
    }
  })]

  depends_on = [
    helm_release.aws_load_balancer_controller,
    helm_release.cert_manager_issuers,
  ]
}
