# L300 part B: Amazon Managed Service for Prometheus (AMP).
# - AMP workspace (long-term, HA metric storage you don't operate)
# - Optional AMP *managed collector* (agentless scraper that runs in AWS, not in your cluster)
# - Pod Identity role so the in-cluster Grafana can query AMP with SigV4

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

resource "aws_prometheus_workspace" "this" {
  alias = var.cluster_name
  tags  = var.tags
}

resource "aws_cloudwatch_log_group" "amp" {
  name              = "/aws/prometheus/${var.cluster_name}"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_prometheus_scraper" "this" {
  count = var.enable_managed_scraper ? 1 : 0
  alias = "${var.cluster_name}-scraper"

  source {
    eks {
      cluster_arn        = var.cluster_arn
      subnet_ids         = var.subnet_ids
      security_group_ids = [var.node_security_group_id]
    }
  }

  destination {
    amp {
      workspace_arn = aws_prometheus_workspace.this.arn
    }
  }

  scrape_configuration = file("${path.module}/scraper-config.yaml")
  tags                 = var.tags
}

# Grafana (kube-prometheus-stack release "kps" => ServiceAccount "kps-grafana") queries AMP.
module "grafana_amp" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.0"

  name                                             = "${var.cluster_name}-grafana-amp"
  attach_amazon_managed_service_prometheus_policy  = true
  amazon_managed_service_prometheus_workspace_arns = [aws_prometheus_workspace.this.arn]

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = "monitoring"
      service_account = "kps-grafana"
    }
  }
  tags = var.tags
}
