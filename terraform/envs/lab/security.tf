# L400: personas mapped with EKS access entries + GuardDuty EKS protection.

data "aws_iam_policy_document" "persona_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "dev" {
  count              = var.enable_rbac_personas ? 1 : 0
  name               = "${var.cluster_name}-dev"
  assume_role_policy = data.aws_iam_policy_document.persona_trust.json
}

resource "aws_iam_role" "viewer" {
  count              = var.enable_rbac_personas ? 1 : 0
  name               = "${var.cluster_name}-viewer"
  assume_role_policy = data.aws_iam_policy_document.persona_trust.json
}

# Both personas need eks:DescribeCluster to run `aws eks update-kubeconfig`.
resource "aws_iam_role_policy" "persona_describe" {
  for_each = var.enable_rbac_personas ? { dev = aws_iam_role.dev[0].name, viewer = aws_iam_role.viewer[0].name } : {}
  name     = "eks-describe"
  role     = each.value
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["eks:DescribeCluster", "eks:ListClusters"], Resource = "*" }]
  })
}

locals {
  access_entries = { for k, v in {
    # dev: edit rights only inside the "shop" namespace (EKS-managed access policy)
    dev = {
      principal_arn = try(aws_iam_role.dev[0].arn, null)
      policy_associations = {
        edit = {
          policy_arn   = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
          access_scope = { type = "namespace", namespaces = ["shop"] }
        }
      }
    }
    # viewer: no access policy — mapped to a Kubernetes group bound by our own RBAC
    # (k8s/L400/rbac/viewer.yaml) to show the "bring your own RBAC" pattern.
    viewer = {
      principal_arn     = try(aws_iam_role.viewer[0].arn, null)
      kubernetes_groups = ["lab-viewers"]
    }
  } : k => v if var.enable_rbac_personas }
}

# ------------------------------------------------------------------ GuardDuty
resource "aws_guardduty_detector" "this" {
  count  = var.enable_guardduty ? 1 : 0
  enable = true
}

resource "aws_guardduty_detector_feature" "eks_audit" {
  count       = var.enable_guardduty ? 1 : 0
  detector_id = aws_guardduty_detector.this[0].id
  name        = "EKS_AUDIT_LOGS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "runtime" {
  count       = var.enable_guardduty ? 1 : 0
  detector_id = aws_guardduty_detector.this[0].id
  name        = "RUNTIME_MONITORING"
  status      = "ENABLED"

  additional_configuration {
    name   = "EKS_ADDON_MANAGEMENT"
    status = "ENABLED"
  }
}
