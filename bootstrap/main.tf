# One-time, long-lived resources for the lab. Uses LOCAL state on purpose
# (it creates the bucket that every other stack keeps its state in).
# Run with an admin identity:  make bootstrap

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "eks-lab"
      Level     = "bootstrap"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  repos      = ["shop-web", "shop-api", "shop-worker"]
}

# ---------------------------------------------------------------- state bucket
resource "aws_s3_bucket" "tfstate" {
  bucket        = "eks-lab-tfstate-${local.account_id}-${var.region}"
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------- cost guardrails
resource "aws_budgets_budget" "lab" {
  name         = "eks-lab-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.alert_email]
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}

# Most accounts already have AWS's default "Services" anomaly monitor, and only one
# SERVICE-dimension monitor is allowed. Enable this only if yours has none.
resource "aws_ce_anomaly_monitor" "services" {
  count             = var.create_anomaly_monitor ? 1 : 0
  name              = "eks-lab-services"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "services" {
  count            = var.create_anomaly_monitor ? 1 : 0
  name             = "eks-lab-anomalies"
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.services[0].arn]

  subscriber {
    type    = "EMAIL"
    address = var.alert_email
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = ["5"]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }
}

# ---------------------------------------------------------------- lab admin role
# You assume this role for every lab session instead of using long-lived admin keys.
data "aws_iam_policy_document" "lab_admin_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"]
    }
    # IAM-user path: require an MFA'd session.
    dynamic "condition" {
      for_each = var.require_mfa && length(var.trusted_sso_permission_sets) == 0 ? [1] : []
      content {
        test     = "Bool"
        variable = "aws:MultiFactorAuthPresent"
        values   = ["true"]
      }
    }
    # Identity Center path: only sessions of the named permission sets may assume the role.
    # (SSO sessions don't carry aws:MultiFactorAuthPresent; Identity Center enforced MFA at sign-in.)
    dynamic "condition" {
      for_each = length(var.trusted_sso_permission_sets) > 0 ? [1] : []
      content {
        test     = "ArnLike"
        variable = "aws:PrincipalArn"
        values = [for ps in var.trusted_sso_permission_sets :
          # path is .../sso.amazonaws.com/ for us-east-1 Identity Center, .../sso.amazonaws.com/<region>/ elsewhere
        "arn:${data.aws_partition.current.partition}:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_${ps}_*"]
      }
    }
  }
}

resource "aws_iam_role" "lab_admin" {
  name                 = "eks-lab-admin"
  assume_role_policy   = data.aws_iam_policy_document.lab_admin_trust.json
  max_session_duration = 43200
  description          = "Role used to run the EKS lab (Terraform, kubectl)."
}

# A lab needs broad rights (IAM, VPC, EKS, KMS, GuardDuty...). In a real org this would be
# a scoped permission set in IAM Identity Center plus a permissions boundary.
resource "aws_iam_role_policy_attachment" "lab_admin" {
  role       = aws_iam_role.lab_admin.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"
}

# ---------------------------------------------------------------- ECR
resource "aws_ecr_repository" "app" {
  for_each             = toset(local.repos)
  name                 = "eks-lab/${each.key}"
  image_tag_mutability = "MUTABLE" # L400 asks you to switch this to IMMUTABLE
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection    = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 1 }
        action       = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the last 15 images"
        selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 15 }
        action       = { type = "expire" }
      }
    ]
  })
}

# Pull-through cache: public.ecr.aws/<x> becomes <acct>.dkr.ecr.<region>.amazonaws.com/ecr-public/<x>
resource "aws_ecr_pull_through_cache_rule" "ecr_public" {
  ecr_repository_prefix = "ecr-public"
  upstream_registry_url = "public.ecr.aws"
}

# ---------------------------------------------------------------- DNS (optional)
resource "aws_route53_zone" "lab" {
  count         = var.domain == "" ? 0 : 1
  name          = var.domain
  force_destroy = true
}

# ---------------------------------------------------------------- Velero bucket (L500)
resource "aws_s3_bucket" "velero" {
  bucket        = "eks-lab-velero-${local.account_id}-${var.region}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket                  = aws_s3_bucket.velero.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "velero" {
  bucket = aws_s3_bucket.velero.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id
  rule {
    id     = "expire-old"
    status = "Enabled"
    filter {}
    expiration {
      days = 30
    }
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# ---------------------------------------------------------------- GitHub Actions OIDC (L300)
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.github_repo != "" && var.create_github_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_trust" {
  count = var.github_repo == "" ? 0 : 1
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_ci" {
  count              = var.github_repo == "" ? 0 : 1
  name               = "eks-lab-github-ci"
  assume_role_policy = data.aws_iam_policy_document.github_trust[0].json
  depends_on         = [aws_iam_openid_connect_provider.github]
}

data "aws_iam_policy_document" "github_ci" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload", "ecr:PutImage",
      "ecr:UploadLayerPart", "ecr:DescribeImages", "ecr:DescribeImageScanFindings",
    ]
    resources = [for r in aws_ecr_repository.app : r.arn]
  }
}

resource "aws_iam_role_policy" "github_ci" {
  count  = var.github_repo == "" ? 0 : 1
  name   = "ecr-push"
  role   = aws_iam_role.github_ci[0].id
  policy = data.aws_iam_policy_document.github_ci.json
}
