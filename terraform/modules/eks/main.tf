# EKS cluster wrapper around terraform-aws-modules/eks (v21).
# - Access entries (API auth mode) instead of the aws-auth ConfigMap
# - EKS managed add-ons, with Pod Identity for the ones that call AWS APIs
# - One small "core" managed node group (Graviton Spot by default). From L300 Karpenter
#   provisions all other capacity; the core group only runs critical controllers.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  vpc_cni_config = {
    env = merge(
      {
        # Prefix delegation: each ENI slot gets a /28 (16 IPs) => far more pods per node.
        ENABLE_PREFIX_DELEGATION = tostring(var.enable_prefix_delegation)
        WARM_PREFIX_TARGET       = "1"
      },
      var.vpc_cni_extra_env
    )
    # VPC CNI's built-in Kubernetes NetworkPolicy enforcement (eBPF), L400
    enableNetworkPolicy = tostring(var.enable_network_policy)
  }

  base_addons = {
    vpc-cni = {
      most_recent          = true
      before_compute       = true
      configuration_values = jsonencode(local.vpc_cni_config)
    }
    eks-pod-identity-agent = {
      most_recent    = true
      before_compute = true
    }
    kube-proxy = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
  }

  ebs_addon = { for k, v in {
    aws-ebs-csi-driver = {
      most_recent = true
      pod_identity_association = [{
        role_arn        = try(module.ebs_csi_pod_identity[0].iam_role_arn, null)
        service_account = "ebs-csi-controller-sa"
      }]
    }
    snapshot-controller = {
      most_recent = true
    }
  } : k => v if var.enable_ebs_csi }

  efs_addon = { for k, v in {
    aws-efs-csi-driver = {
      most_recent = true
      pod_identity_association = [{
        role_arn        = try(module.efs_csi_pod_identity[0].iam_role_arn, null)
        service_account = "efs-csi-controller-sa"
      }]
    }
  } : k => v if var.enable_efs_csi }

  metrics_server_addon = { for k, v in {
    metrics-server = {
      most_recent = true
    }
  } : k => v if var.enable_metrics_server }

  cw_addon = { for k, v in {
    amazon-cloudwatch-observability = {
      most_recent = true
      pod_identity_association = [{
        role_arn        = try(module.cloudwatch_pod_identity[0].iam_role_arn, null)
        service_account = "cloudwatch-agent"
      }]
    }
  } : k => v if var.enable_container_insights }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # Avoid surprise Extended Support charges ($0.60/h) if you forget to upgrade.
  upgrade_policy = {
    support_type = var.support_type
  }

  # L100-L300: public endpoint (optionally restricted to your IP). L400 tightens this.
  endpoint_public_access       = true
  endpoint_private_access      = true
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true
  access_entries                           = var.access_entries

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.control_plane_subnet_ids

  enabled_log_types                      = var.control_plane_log_types
  cloudwatch_log_group_retention_in_days = 7

  # Secrets envelope encryption with a customer-managed KMS key (L400). EKS already
  # encrypts with an AWS-owned key by default; this adds a key *you* control and audit.
  create_kms_key    = var.enable_secrets_kms
  encryption_config = var.enable_secrets_kms ? { resources = ["secrets"] } : null

  zonal_shift_config = {
    enabled = var.enable_zonal_shift
  }

  addons = merge(local.base_addons, local.ebs_addon, local.efs_addon, local.metrics_server_addon, local.cw_addon)

  eks_managed_node_groups = {
    core = {
      ami_type       = var.core_ami_type
      instance_types = var.core_instance_types
      capacity_type  = var.core_capacity_type

      min_size     = var.core_min_size
      max_size     = var.core_max_size
      desired_size = var.core_desired_size

      labels = {
        "node-role" = "core"
      }

      # IMDSv2 only, hop limit 1: pods can't reach the node's instance-role credentials.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }

      block_device_mappings = {
        root = {
          device_name = var.core_ami_type == "BOTTLEROCKET_ARM_64" || var.core_ami_type == "BOTTLEROCKET_x86_64" ? "/dev/xvdb" : "/dev/xvda"
          ebs = {
            volume_size = 30
            volume_type = "gp3"
            encrypted   = true
          }
        }
      }
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = var.tags
}

# ---------------------------------------------------------------- Pod Identity roles for managed add-ons
module "ebs_csi_pod_identity" {
  count   = var.enable_ebs_csi ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                      = "${var.cluster_name}-ebs-csi"
  attach_aws_ebs_csi_policy = true
  tags                      = var.tags
}

module "efs_csi_pod_identity" {
  count   = var.enable_efs_csi ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                      = "${var.cluster_name}-efs-csi"
  attach_aws_efs_csi_policy = true
  tags                      = var.tags
}

module "cloudwatch_pod_identity" {
  count   = var.enable_container_insights ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                                       = "${var.cluster_name}-cloudwatch"
  attach_aws_cloudwatch_observability_policy = true
  tags                                       = var.tags
}
