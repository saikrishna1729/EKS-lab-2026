# AWS resources the shop app uses, and the Pod Identity roles that let it use them
# WITHOUT any access keys in the cluster (L200 identity lab, L300 KEDA lab).

resource "aws_s3_bucket" "demo" {
  count         = var.enable_app_aws_resources ? 1 : 0
  bucket        = "${var.cluster_name}-demo-${local.account_id}-${var.region}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "demo" {
  count                   = var.enable_app_aws_resources ? 1 : 0
  bucket                  = aws_s3_bucket.demo[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "hello" {
  count   = var.enable_app_aws_resources ? 1 : 0
  bucket  = aws_s3_bucket.demo[0].id
  key     = "hello.txt"
  content = "If you can read this from a pod, Pod Identity works.\n"
}

resource "aws_sqs_queue" "orders_dlq" {
  count                     = var.enable_app_aws_resources ? 1 : 0
  name                      = "${var.cluster_name}-orders-dlq"
  message_retention_seconds = 86400
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "orders" {
  count                      = var.enable_app_aws_resources ? 1 : 0
  name                       = "${var.cluster_name}-orders"
  visibility_timeout_seconds = 30
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.orders_dlq[0].arn
    maxReceiveCount     = 5
  })
}

# shop-api: read the demo bucket + send to the queue
module "shop_api_pod_identity" {
  count   = var.enable_app_aws_resources ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                 = "${var.cluster_name}-shop-api"
  attach_custom_policy = true
  policy_statements = [
    {
      sid       = "ReadDemoBucket"
      actions   = ["s3:ListBucket", "s3:GetObject"]
      resources = [aws_s3_bucket.demo[0].arn, "${aws_s3_bucket.demo[0].arn}/*"]
    },
    {
      sid       = "SendOrders"
      actions   = ["sqs:SendMessage", "sqs:GetQueueAttributes"]
      resources = [aws_sqs_queue.orders[0].arn]
    }
  ]

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "shop"
      service_account = "shop-api"
    }
  }
}

# shop-worker: consume the queue
module "shop_worker_pod_identity" {
  count   = var.enable_app_aws_resources ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                 = "${var.cluster_name}-shop-worker"
  attach_custom_policy = true
  policy_statements = [
    {
      sid       = "ConsumeOrders"
      actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
      resources = [aws_sqs_queue.orders[0].arn]
    }
  ]

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "shop"
      service_account = "shop-worker"
    }
  }
}

# A Secrets Manager secret for the External Secrets lab (L300)
resource "aws_secretsmanager_secret" "shop" {
  count                   = var.enable_external_secrets ? 1 : 0
  name                    = "eks-lab/${var.cluster_name}/shop"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "shop" {
  count     = var.enable_external_secrets ? 1 : 0
  secret_id = aws_secretsmanager_secret.shop[0].id
  secret_string = jsonencode({
    API_TOKEN = "change-me-in-secrets-manager"
  })
}
