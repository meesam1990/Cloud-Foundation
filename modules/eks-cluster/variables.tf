variable "name" {
  description = "Cluster name; also the prefix for its IAM roles."
  type        = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}

variable "subnet_ids" {
  description = "Pod subnets (control plane ENIs and nodes)."
  type        = list(string)
}

variable "node_security_group_id" {
  description = "Security group for nodes and pods."
  type        = string
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to the public API endpoint (Terraform/Helm/kubectl). Empty makes the endpoint private only."
  type        = list(string)
  default     = []
}

variable "admin_principal_arns" {
  description = "IAM roles/users given cluster admin through access entries (the creator is added automatically)."
  type        = list(string)
  default     = []
}

variable "pod_identity_associations" {
  description = "IAM roles bound to service accounts through EKS Pod Identity, keyed by a stable name."
  type = map(object({
    namespace       = string
    service_account = string
    role_arn        = string
  }))
  default = {}
}

variable "secrets_kms_key_arn" {
  description = "KMS key for envelope encryption of Kubernetes secrets. Null to use the AWS-owned key."
  type        = string
  default     = null
}

variable "cluster_log_types" {
  type    = list(string)
  default = ["api", "audit", "authenticator"]
}

variable "ami_type" {
  type    = string
  default = "AL2023_x86_64_STANDARD"
}

variable "instance_types" {
  type    = list(string)
  default = ["t3.large"]
}

variable "capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "node_min" {
  type    = number
  default = 2
}

variable "node_max" {
  type    = number
  default = 3
}

variable "node_desired" {
  type    = number
  default = 2
}

variable "node_disk_size" {
  type    = number
  default = 40
}

variable "tags" {
  description = "ADR-46 tags (the context module's tags) for what the node launch template creates - instances, root EBS volumes and ENIs - which provider default_tags do not reach."
  type        = map(string)
  default     = {}
}
