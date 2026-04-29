# Prod environment — same module structure as dev, hardened for production.
#
# Differences vs dev:
#   - ON_DEMAND instances (no spot interruptions in production)
#   - Multi-AZ RDS (automatic failover)
#   - Two NAT gateways (one per AZ, HA egress)
#   - Larger instance types
#   - deletion_protection and skip_final_snapshot set in RDS module

locals {
  environment    = "prod"
  cluster_name   = "digital-library-prod"
  region         = "eu-central-1"
  domain         = "444noresponse.com"
  hosted_zone_id = "Z0414591K81BU1BVJ424"
}

# ─── ACM certificate ─────────────────────────────────────────────────────────

module "acm" {
  source = "../../modules/acm"

  domain_name    = local.domain
  hosted_zone_id = local.hosted_zone_id
  environment    = local.environment
}

data "aws_caller_identity" "current" {}

module "s3" {
  source      = "../../modules/s3"
  environment = local.environment
  account_id  = data.aws_caller_identity.current.account_id
}

module "iam" {
  source = "../../modules/iam"

  environment       = local.environment
  cluster_name      = local.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  sqs_queue_arn     = module.sqs.queue_arn
  sqs_dlq_arn       = module.sqs.dlq_arn
  db_secret_arn     = module.rds.db_secret_arn
  hosted_zone_id    = local.hosted_zone_id
  s3_bucket_arn     = module.s3.bucket_arn
}

module "vpc" {
  source = "../../modules/vpc"

  environment          = local.environment
  cluster_name         = local.cluster_name
  vpc_cidr             = "10.1.0.0/16"
  public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]
  azs                  = ["${local.region}a", "${local.region}b"]

  # Prod: one NAT gateway per AZ for HA (if one AZ goes down, egress still works)
  single_nat_gateway = false
}

module "ecr" {
  source      = "../../modules/ecr"
  environment = local.environment
  image_names = ["frontend", "compressor", "worker"]
}

module "sqs" {
  source      = "../../modules/sqs"
  environment = local.environment
  queue_name  = "books-compressed"

  # Prod: longer visibility timeout — allow more time for processing
  visibility_timeout_seconds = 60
}

module "eks" {
  source = "../../modules/eks"

  environment        = local.environment
  cluster_name       = local.cluster_name
  cluster_version    = "1.31"
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  node_role_arn      = module.iam.node_role_arn

  # Prod: on-demand instances — no interruptions
  frontend_capacity_type = "ON_DEMAND"
  backend_capacity_type  = "ON_DEMAND"

  frontend_instance_type = "t3.small"
  backend_instance_type  = "t3.medium"
}

module "rds" {
  source = "../../modules/rds"

  environment               = local.environment
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = module.vpc.private_subnet_ids
  allowed_security_group_id = module.eks.cluster_security_group_id

  db_name        = "library"
  db_username    = "library"
  instance_class = "db.t3.small"

  # Prod: Multi-AZ for automatic failover, more storage
  multi_az          = true
  allocated_storage = 50
}
