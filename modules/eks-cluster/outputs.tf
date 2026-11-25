output "cluster_name" {
  value = aws_eks_cluster.this.name

  # Ready for workloads only once nodes and CoreDNS are up.
  depends_on = [aws_eks_addon.coredns]
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  value = local.cluster_security_group_id
}

output "oidc_issuer_url" {
  value = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "node_role_arn" {
  value = aws_iam_role.node.arn
}
