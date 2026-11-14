# L500: a second cluster in DR_REGION, built from the same modules.
# Used for (1) cross-region restore with Velero and (2) blue/green cluster upgrades.
#   make dr-up / make dr-down

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "eks-lab", Level = "L500", Cluster = var.cluster_name, ManagedBy = "terraform" }
  }
}

variable "region" {
  type = string
}

variable "cluster_name" {
  type    = string
  default = "eks-lab-dr"
}

variable "kubernetes_version" {
  type        = string
  default     = "1.35"
  description = "For a blue/green upgrade, set this one minor ABOVE the primary cluster."
}

variable "primary_region" {
  type        = string
  default     = "ap-southeast-1"
  description = "Region of the Velero bucket created by bootstrap."
}

data "aws_caller_identity" "current" {}

module "vpc" {
  source       = "../../modules/vpc"
  name         = var.cluster_name
  cluster_name = var.cluster_name
  cidr         = "10.1.0.0/16" # non-overlapping with the primary, so you could peer them
}

module "eks" {
  source = "../../modules/eks"

  cluster_name             = var.cluster_name
  kubernetes_version       = var.kubernetes_version
  vpc_id                   = module.vpc.vpc_id
  private_subnet_ids       = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  enable_prefix_delegation = true
  enable_ebs_csi           = true
  enable_metrics_server    = true
}

module "platform_iam" {
  source = "../../modules/platform-iam"

  cluster_name         = module.eks.cluster_name
  velero_bucket        = "eks-lab-velero-${data.aws_caller_identity.current.account_id}-${var.primary_region}"
  enable_lb_controller = true
  enable_velero        = true
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
