# VPC for EKS: 3 AZs, public + private subnets (+ optional intra subnets for the control-plane ENIs),
# subnet tags the AWS Load Balancer Controller and Karpenter discover, and optional
# VPC endpoints so image pulls and AWS API calls don't pay NAT data charges.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.name
  cidr = var.cidr
  azs  = local.azs

  # /19 private subnets = 8k IPs each: pods get VPC IPs, so size private subnets generously.
  private_subnets = [for k, v in local.azs : cidrsubnet(var.cidr, 3, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.cidr, 8, k + 192)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(var.cidr, 8, k + 200)]

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway # true = lab ($), false = one per AZ (prod, AZ-resilient)
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = var.cluster_name
  }

  tags = var.tags
}

# ---------------------------------------------------------------- VPC endpoints (L200+)
resource "aws_security_group" "endpoints" {
  count       = var.enable_vpc_endpoints ? 1 : 0
  name_prefix = "${var.name}-vpce-"
  description = "HTTPS from inside the VPC to interface endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.cidr]
  }
  tags = var.tags
}

module "endpoints" {
  count   = var.enable_vpc_endpoints ? 1 : 0
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.0"

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [aws_security_group.endpoints[0].id]

  endpoints = merge(
    {
      # Gateway endpoint: free, and ECR image layers come from S3.
      s3 = {
        service         = "s3"
        service_type    = "Gateway"
        route_table_ids = module.vpc.private_route_table_ids
        tags            = { Name = "${var.name}-s3" }
      }
    },
    # Interface endpoints cost ~$0.01/h per AZ each — keep the list short in a lab.
    { for svc in var.interface_endpoints : replace(svc, ".", "_") => {
      service             = svc
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      tags                = { Name = "${var.name}-${svc}" }
    } }
  )

  tags = var.tags
}
