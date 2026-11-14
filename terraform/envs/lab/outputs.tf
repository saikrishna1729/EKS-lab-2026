# scripts/addons.sh and the verify scripts read these with `terraform output -json`.

output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_version" {
  value = module.eks.cluster_version
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "domain" {
  value = var.domain
}

output "account_id" {
  value = local.account_id
}

output "ecr_registry" {
  value = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

output "demo_bucket" {
  value = try(aws_s3_bucket.demo[0].bucket, "")
}

output "orders_queue_url" {
  value = try(aws_sqs_queue.orders[0].url, "")
}

output "orders_queue_name" {
  value = try(aws_sqs_queue.orders[0].name, "")
}

output "efs_id" {
  value = try(aws_efs_file_system.lab[0].id, "")
}

output "karpenter_queue_name" {
  value = try(module.karpenter[0].queue_name, "")
}

output "karpenter_node_role_name" {
  value = try(module.karpenter[0].node_iam_role_name, "")
}

output "amp_endpoint" {
  value = try(module.observability[0].amp_endpoint, "")
}

output "amp_scraper_role_arn" {
  value = try(module.observability[0].scraper_role_arn, "")
}

output "velero_bucket" {
  value = local.velero_bucket
}

output "platform_role_arns" {
  value = module.platform_iam.role_arns
}

output "persona_role_arns" {
  value = {
    dev    = try(aws_iam_role.dev[0].arn, "")
    viewer = try(aws_iam_role.viewer[0].arn, "")
  }
}

output "kms_key_arn" {
  value = module.eks.kms_key_arn
}

output "acm_certificate_arn" {
  value = try(aws_acm_certificate_validation.wildcard[0].certificate_arn, "")
}

output "route53_zone_id" {
  value = try(data.aws_route53_zone.lab[0].zone_id, "")
}
