# L500 — expert (everything from L400, plus:)
level                     = 500
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
enable_network_policy     = true
enable_secrets_kms        = true
enable_rbac_personas      = true
enable_kyverno            = true
enable_guardduty          = false

enable_velero      = true
enable_zonal_shift = true # ARC zonal shift for the AZ-failure game day
