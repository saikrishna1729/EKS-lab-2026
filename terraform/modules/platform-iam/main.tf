# EKS Pod Identity roles + associations for in-cluster controllers installed with Helm/Argo CD.
# Pattern: Terraform owns the IAM role and the (namespace, serviceaccount) association;
# the chart only has to use that ServiceAccount name. No annotations, no OIDC trust policies.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  zone_arns = var.route53_zone_arn == "" ? ["arn:aws:route53:::hostedzone/*"] : [var.route53_zone_arn]
}

module "aws_lb_controller" {
  count   = var.enable_lb_controller ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                            = "${var.cluster_name}-aws-lbc"
  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
  tags = var.tags
}

module "external_dns" {
  count   = var.enable_external_dns ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                          = "${var.cluster_name}-external-dns"
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = local.zone_arns

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "external-dns"
      service_account = "external-dns"
    }
  }
  tags = var.tags
}

module "cert_manager" {
  count   = var.enable_cert_manager ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                          = "${var.cluster_name}-cert-manager"
  attach_cert_manager_policy    = true
  cert_manager_hosted_zone_arns = local.zone_arns

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "cert-manager"
      service_account = "cert-manager"
    }
  }
  tags = var.tags
}

module "external_secrets" {
  count   = var.enable_external_secrets ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                                  = "${var.cluster_name}-external-secrets"
  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = ["arn:aws:secretsmanager:*:*:secret:eks-lab/*"]
  external_secrets_ssm_parameter_arns   = ["arn:aws:ssm:*:*:parameter/eks-lab/*"]
  external_secrets_create_permission    = false

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "external-secrets"
      service_account = "external-secrets"
    }
  }
  tags = var.tags
}

module "velero" {
  count   = var.enable_velero ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                       = "${var.cluster_name}-velero"
  attach_velero_policy       = true
  velero_s3_bucket_arns      = ["arn:aws:s3:::${var.velero_bucket}"]
  velero_s3_bucket_path_arns = ["arn:aws:s3:::${var.velero_bucket}/*"]

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "velero"
      service_account = "velero-server"
    }
  }
  tags = var.tags
}

# KEDA operator reads SQS queue depth to scale shop-worker (L300)
module "keda" {
  count   = var.enable_keda ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                 = "${var.cluster_name}-keda"
  attach_custom_policy = true
  policy_statements = [{
    sid       = "ReadQueueDepth"
    actions   = ["sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
    resources = var.sqs_queue_arns
  }]

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "keda"
      service_account = "keda-operator"
    }
  }
  tags = var.tags
}

# Kyverno pulls image signatures from ECR to verify them (L400 supply chain)
module "kyverno" {
  count   = var.enable_kyverno ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name = "${var.cluster_name}-kyverno"
  additional_policy_arns = {
    ECRReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  }

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "kyverno"
      service_account = "kyverno-admission-controller"
    }
  }
  tags = var.tags
}
