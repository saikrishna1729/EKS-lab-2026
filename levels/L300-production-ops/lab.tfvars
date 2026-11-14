# L300 — production operations (everything from L200, plus:)
level                    = 300
enable_vpc_endpoints     = true
enable_prefix_delegation = true
enable_ebs_csi           = true
enable_efs               = false # not needed after L200; saves a few cents
enable_metrics_server    = true
enable_lb_controller     = true
enable_external_dns      = true
enable_cert_manager      = true
enable_app_aws_resources = true

enable_karpenter           = true
enable_keda                = true
enable_external_secrets    = true
enable_container_insights  = true  # CloudWatch Observability add-on (Container Insights + Fluent Bit logs)
enable_amp                 = true  # Amazon Managed Prometheus workspace
enable_amp_managed_scraper = false # set true for part B of the observability lab (~$0.04/h + samples)
