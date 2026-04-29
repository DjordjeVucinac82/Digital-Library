# Test environment — mirrors dev settings (spot, single NAT GW, minimal RDS).
#
# Use this environment to validate infrastructure changes before promoting to prod.
# Cost is approximately the same as dev (~$72/month for EKS control plane alone).
#
# Key differences vs dev:
#   - Separate VPC CIDR (10.2.0.0/16) — no overlap with dev (10.0.x) or prod (10.1.x)
#   - Separate EKS cluster: digital-library-test
#   - Domain: test.444noresponse.com
#   - S3 state key: test/terraform.tfstate

locals {
  environment    = "test"
  cluster_name   = "digital-library-test"
  region         = "eu-central-1"
  domain         = "test.444noresponse.com"
  hosted_zone_id = "Z0414591K81BU1BVJ424"
}

# ─── ACM certificate ─────────────────────────────────────────────────────────

module "acm" {
  source = "../../modules/acm"

  domain_name    = local.domain
  hosted_zone_id = local.hosted_zone_id
  environment    = local.environment
}

# ─── IAM (node role — needed by EKS node groups) ─────────────────────────────

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
}

# ─── VPC ──────────────────────────────────────────────────────────────────────

module "vpc" {
  source = "../../modules/vpc"

  environment          = local.environment
  cluster_name         = local.cluster_name
  vpc_cidr             = "10.2.0.0/16"
  public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
  private_subnet_cidrs = ["10.2.10.0/24", "10.2.11.0/24"]
  azs                  = ["${local.region}a", "${local.region}b"]

  # Test: one shared NAT gateway — same cost trade-off as dev
  single_nat_gateway = true
}

# ─── ECR ──────────────────────────────────────────────────────────────────────

module "ecr" {
  source      = "../../modules/ecr"
  environment = local.environment
  image_names = ["frontend", "compressor", "worker"]
}

# ─── SQS ──────────────────────────────────────────────────────────────────────

module "sqs" {
  source      = "../../modules/sqs"
  environment = local.environment
  queue_name  = "books-compressed"

  # Test: short visibility timeout — faster feedback during testing
  visibility_timeout_seconds = 30
}

# ─── EKS ──────────────────────────────────────────────────────────────────────

module "eks" {
  source = "../../modules/eks"

  environment        = local.environment
  cluster_name       = local.cluster_name
  cluster_version    = "1.31"
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  node_role_arn      = module.iam.node_role_arn

  # Test: spot instances — acceptable interruptions in a non-prod environment
  frontend_capacity_type = "SPOT"
  backend_capacity_type  = "SPOT"

  frontend_instance_type = "t3.small"
  backend_instance_type  = "t3.medium"
}

# ─── RDS MySQL ────────────────────────────────────────────────────────────────

module "rds" {
  source = "../../modules/rds"

  environment               = local.environment
  vpc_id                    = module.vpc.vpc_id
  private_subnet_ids        = module.vpc.private_subnet_ids
  allowed_security_group_id = module.eks.cluster_security_group_id

  db_name        = "library"
  db_username    = "library"
  instance_class = "db.t3.micro"

  # Test: single-AZ, minimal storage — mirrors dev, not production
  multi_az          = false
  allocated_storage = 20
}
