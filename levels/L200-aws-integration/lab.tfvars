# L200 — AWS integration
level                    = 200
enable_vpc_endpoints     = true # S3 gateway (free) + ECR api/dkr + STS interface endpoints
enable_prefix_delegation = true
enable_ebs_csi           = true
enable_efs               = true
enable_metrics_server    = true
enable_lb_controller     = true
enable_external_dns      = true # only takes effect when DOMAIN is set
enable_cert_manager      = true # only takes effect when DOMAIN is set
enable_app_aws_resources = true
