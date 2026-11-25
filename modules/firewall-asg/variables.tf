variable "name" {
  description = "Name of the firewall fleet (ADR-44), e.g. dev-network-firewall. The IAM role, instance profile and security group use it; launch templates and ASGs add the AZ ID."
  type        = string
}

variable "az_ids" {
  description = "Short AZ ID by AZ name (modules/vpc output az_ids), used in per-AZ names."
  type        = map(string)
}

variable "tags" {
  description = "ADR-46 tags for instances, root EBS volumes and ENIs, which provider default_tags do not reach."
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Firewall subnet ID by AZ (one Auto Scaling group per AZ)."
  type        = map(string)
}

variable "gwlb_subnet_cidrs" {
  description = "CIDR of the subnet holding the GWLB ENI, by AZ (GENEVE and health checks come from there)."
  type        = map(string)
}

variable "target_group_arn" {
  type = string
}

variable "nat_endpoint_ids" {
  description = "GWLB endpoint IDs (vpce-...) whose traffic the stand-in sends out through its own interface and the NAT gateway (internet egress). Traffic from other endpoints goes back to the GWLB. Ignored with user_data_override."
  type        = list(string)
  default     = []
}

variable "gwlbtun_version" {
  description = "Git tag of aws-samples/aws-gateway-load-balancer-tunnel-handler the stand-in builds at boot."
  type        = string
  default     = "v3.3"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "instances_per_az" {
  type    = number
  default = 1
}

variable "health_check_port" {
  type    = number
  default = 80
}

variable "health_check_grace_period" {
  description = "Seconds before the ASG acts on GWLB health checks. The stand-in compiles gwlbtun at boot (several minutes)."
  type        = number
  default     = 900
}

variable "ami_id" {
  description = "Vendor firewall AMI. Null uses Amazon Linux 2023 with the gwlbtun stand-in."
  type        = string
  default     = null
}

variable "ami_ssm_parameter" {
  type    = string
  default = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

variable "user_data_override" {
  description = "Vendor bootstrap user data. Null uses the gwlbtun stand-in."
  type        = string
  default     = null
}
