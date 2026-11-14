# The lab cluster. Every level applies this same stack with a different levels/LXXX/lab.tfvars,
# so features accumulate: L100 ⊂ L200 ⊂ L300 ⊂ L400 ⊂ L500.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_route53_zone" "lab" {
  count = var.domain == "" ? 0 : 1
  name  = var.domain
}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  partition     = data.aws_partition.current.partition
  velero_bucket = "eks-lab-velero-${local.account_id}-${var.region}"
  zone_arn      = try(data.aws_route53_zone.lab[0].arn, "")
  tags          = { Level = "L${var.level}" }
}

# ------------------------------------------------------------------ network
module "vpc" {
  source = "../../modules/vpc"

  name                 = var.cluster_name
  cluster_name         = var.cluster_name
  cidr                 = var.vpc_cidr
  single_nat_gateway   = var.single_nat_gateway
  enable_vpc_endpoints = var.enable_vpc_endpoints
  tags                 = local.tags
}

# ------------------------------------------------------------------ cluster
module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id                       = module.vpc.vpc_id
  private_subnet_ids           = module.vpc.private_subnets
  control_plane_subnet_ids     = module.vpc.intra_subnets
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  enable_prefix_delegation  = var.enable_prefix_delegation
  enable_network_policy     = var.enable_network_policy
  enable_ebs_csi            = var.enable_ebs_csi
  enable_efs_csi            = var.enable_efs
  enable_metrics_server     = var.enable_metrics_server
  enable_container_insights = var.enable_container_insights
  enable_secrets_kms        = var.enable_secrets_kms
  enable_zonal_shift        = var.enable_zonal_shift

  core_ami_type       = var.core_ami_type
  core_instance_types = var.core_instance_types
  core_capacity_type  = var.core_capacity_type
  core_desired_size   = var.core_desired_size

  access_entries = local.access_entries
  tags           = local.tags
}

# ------------------------------------------------------------------ Pod Identity for Helm-installed controllers
module "platform_iam" {
  source = "../../modules/platform-iam"

  cluster_name     = module.eks.cluster_name
  route53_zone_arn = local.zone_arn
  velero_bucket    = local.velero_bucket
  sqs_queue_arns   = var.enable_app_aws_resources ? [aws_sqs_queue.orders[0].arn] : []

  enable_lb_controller    = var.enable_lb_controller
  enable_external_dns     = var.enable_external_dns && var.domain != ""
  enable_cert_manager     = var.enable_cert_manager && var.domain != ""
  enable_external_secrets = var.enable_external_secrets
  enable_velero           = var.enable_velero
  enable_keda             = var.enable_keda && var.enable_app_aws_resources
  enable_kyverno          = var.enable_kyverno
  tags                    = local.tags
}

# ------------------------------------------------------------------ Karpenter (L300+)
module "karpenter" {
  count  = var.enable_karpenter ? 1 : 0
  source = "../../modules/karpenter"

  cluster_name = module.eks.cluster_name
  tags         = local.tags
}

# ------------------------------------------------------------------ Amazon Managed Prometheus (L300+)
module "observability" {
  count  = var.enable_amp ? 1 : 0
  source = "../../modules/observability"

  cluster_name           = module.eks.cluster_name
  cluster_arn            = "arn:${local.partition}:eks:${var.region}:${local.account_id}:cluster/${module.eks.cluster_name}"
  subnet_ids             = module.vpc.private_subnets
  node_security_group_id = module.eks.node_security_group_id
  enable_managed_scraper = var.enable_amp_managed_scraper
  tags                   = local.tags
}

# ------------------------------------------------------------------ EFS (L200 storage, RWX)
resource "aws_security_group" "efs" {
  count       = var.enable_efs ? 1 : 0
  name_prefix = "${var.cluster_name}-efs-"
  vpc_id      = module.vpc.vpc_id
  description = "NFS from cluster nodes"

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }
}

resource "aws_efs_file_system" "lab" {
  count          = var.enable_efs ? 1 : 0
  creation_token = "${var.cluster_name}-efs"
  encrypted      = true
  tags           = { Name = "${var.cluster_name}-efs" }
}

resource "aws_efs_mount_target" "lab" {
  count           = var.enable_efs ? length(module.vpc.private_subnets) : 0
  file_system_id  = aws_efs_file_system.lab[0].id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs[0].id]
}

# ------------------------------------------------------------------ ACM wildcard cert for ALB TLS (L200, needs DOMAIN)
# The AWS Load Balancer Controller auto-discovers this certificate from the Ingress host.
resource "aws_acm_certificate" "wildcard" {
  count                     = var.domain != "" && var.enable_lb_controller ? 1 : 0
  domain_name               = var.domain
  subject_alternative_names = ["*.${var.domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = var.domain != "" && var.enable_lb_controller ? {
    for dvo in aws_acm_certificate.wildcard[0].domain_validation_options : dvo.domain_name => dvo
  } : {}

  zone_id         = data.aws_route53_zone.lab[0].zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "wildcard" {
  count                   = var.domain != "" && var.enable_lb_controller ? 1 : 0
  certificate_arn         = aws_acm_certificate.wildcard[0].arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}
