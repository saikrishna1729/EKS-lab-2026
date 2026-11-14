# AWS side of Karpenter: controller IAM role (Pod Identity), node IAM role + access entry,
# and the SQS queue + EventBridge rules for Spot interruption / rebalance / health events.
# The Helm chart and NodePools are installed by scripts/addons.sh (L300) / Argo CD.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = var.cluster_name
  namespace    = "kube-system"

  # Fixed name so the EC2NodeClass can reference it: spec.role = "<cluster>-karpenter-node"
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${var.cluster_name}-karpenter-node"

  create_pod_identity_association = true

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = var.tags
}
