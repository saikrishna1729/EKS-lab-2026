# L400 — security & hardening (everything from L300, plus:)
level                     = 400
enable_vpc_endpoints      = true
enable_prefix_delegation  = true
enable_ebs_csi            = true
enable_metrics_server     = true
enable_lb_controller      = true
enable_external_dns       = true
enable_cert_manager       = true
enable_app_aws_resources  = true
enable_karpenter          = true
enable_keda               = true
enable_external_secrets   = true
enable_container_insights = true
enable_amp                = true

enable_network_policy = true  # VPC CNI enforces Kubernetes NetworkPolicies
enable_secrets_kms    = true  # customer-managed KMS key for Secrets envelope encryption
enable_rbac_personas  = true  # eks-lab-dev / eks-lab-viewer roles + access entries
enable_kyverno        = true  # ECR read for image signature verification
enable_guardduty      = false # set true if this region has NO GuardDuty detector yet (30-day free trial)
# Lock the public API endpoint to your IP (run: curl -s https://checkip.amazonaws.com)
# endpoint_public_access_cidrs = ["203.0.113.10/32"]
