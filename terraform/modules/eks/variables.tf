variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "support_type" {
  type        = string
  default     = "STANDARD"
  description = "STANDARD = cluster is auto-upgraded at end of standard support instead of paying for EXTENDED."
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "control_plane_subnet_ids" {
  type = list(string)
}

variable "endpoint_public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "access_entries" {
  type    = any
  default = {}
}

variable "control_plane_log_types" {
  type    = list(string)
  default = ["api", "audit", "authenticator"]
}

variable "enable_prefix_delegation" {
  type    = bool
  default = false
}

variable "vpc_cni_extra_env" {
  type    = map(string)
  default = {}
}

variable "enable_network_policy" {
  type    = bool
  default = false
}

variable "enable_ebs_csi" {
  type    = bool
  default = false
}

variable "enable_efs_csi" {
  type    = bool
  default = false
}

variable "enable_metrics_server" {
  type    = bool
  default = false
}

variable "enable_container_insights" {
  type    = bool
  default = false
}

variable "enable_secrets_kms" {
  type    = bool
  default = false
}

variable "enable_zonal_shift" {
  type    = bool
  default = false
}

variable "core_ami_type" {
  type    = string
  default = "AL2023_ARM_64_STANDARD"
}

variable "core_instance_types" {
  type    = list(string)
  default = ["t4g.large", "m7g.large", "m6g.large"]
}

variable "core_capacity_type" {
  type    = string
  default = "SPOT"
}

variable "core_min_size" {
  type    = number
  default = 2
}

variable "core_max_size" {
  type    = number
  default = 4
}

variable "core_desired_size" {
  type    = number
  default = 2
}

variable "tags" {
  type    = map(string)
  default = {}
}
