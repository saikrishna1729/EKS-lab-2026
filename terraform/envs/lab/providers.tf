terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial config: bucket/region come from .lab/backend.hcl (written by `make bootstrap`),
  # key is passed by the Makefile. use_lockfile = S3-native state locking.
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "eks-lab"
      Level     = "L${var.level}"
      Cluster   = var.cluster_name
      ManagedBy = "terraform"
    }
  }
}
