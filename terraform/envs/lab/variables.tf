# ------------------------------------------------------------------ basics (from lab.env via TF_VAR_*)
variable "region" {
  type = string
}

variable "cluster_name" {
  type    = string
  default = "eks-lab"
}

variable "domain" {
  type        = string
  default     = ""
  description = "Route 53 hosted zone created by bootstrap (empty = no DNS/TLS labs)."
}

variable "kubernetes_version" {
  type = string
}

variable "level" {
  type        = number
  default     = 100
  description = "Current lab level; only used for tagging. Feature flags below decide what exists."
}

# ------------------------------------------------------------------ network
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  type    = bool
  default = true
}

variable "enable_vpc_endpoints" {
  type    = bool
  default = false
}

variable "enable_prefix_delegation" {
  type    = bool
  default = false
}

variable "enable_network_policy" {
  type    = bool
  default = false
}

# ------------------------------------------------------------------ cluster
variable "endpoint_public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "core_instance_types" {
  type    = list(string)
  default = ["t4g.large", "m7g.large", "m6g.large"]
}

variable "core_capacity_type" {
  type    = string
  default = "SPOT"
}

variable "core_ami_type" {
  type    = string
  default = "AL2023_ARM_64_STANDARD"
}

variable "core_desired_size" {
  type    = number
  default = 2
}

variable "enable_secrets_kms" {
  type    = bool
  default = false
}

variable "enable_zonal_shift" {
  type    = bool
  default = false
}

# ------------------------------------------------------------------ add-ons / platform
variable "enable_ebs_csi" {
  type    = bool
  default = false
}

variable "enable_efs" {
  type    = bool
  default = false
}

variable "enable_metrics_server" {
  type    = bool
  default = false
}

variable "enable_lb_controller" {
  type    = bool
  default = false
}

variable "enable_external_dns" {
  type    = bool
  default = false
}

variable "enable_cert_manager" {
  type    = bool
  default = false
}

variable "enable_app_aws_resources" {
  type        = bool
  default     = false
  description = "S3 demo bucket + SQS queue + Pod Identity roles for the shop app."
}

variable "enable_karpenter" {
  type    = bool
  default = false
}

variable "enable_keda" {
  type    = bool
  default = false
}

variable "enable_external_secrets" {
  type    = bool
  default = false
}

variable "enable_container_insights" {
  type    = bool
  default = false
}

variable "enable_amp" {
  type    = bool
  default = false
}

variable "enable_amp_managed_scraper" {
  type    = bool
  default = false
}

# ------------------------------------------------------------------ security (L400)
variable "enable_rbac_personas" {
  type        = bool
  default     = false
  description = "Create eks-lab-dev / eks-lab-viewer IAM roles mapped with access entries."
}

variable "enable_guardduty" {
  type        = bool
  default     = false
  description = "GuardDuty detector + EKS audit/runtime monitoring. Only one detector per region: set false if you already have one and enable the EKS features in the console."
}

# ------------------------------------------------------------------ expert (L500)
variable "enable_velero" {
  type    = bool
  default = false
}

variable "enable_kyverno" {
  type        = bool
  default     = false
  description = "Pod Identity (ECR read) for Kyverno image-signature verification."
}
