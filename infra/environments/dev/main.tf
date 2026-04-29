# Dev environment — wires all modules together with dev-specific values.
#
# Module dependency order (each module is documented with what it needs):
#   1. iam    — needs nothing (standalone)
#   2. vpc    — needs nothing (standalone)
#   3. ecr    — needs nothing (standalone)
#   4. sqs    — needs nothing (standalone)
#   5. eks    — needs vpc (subnets) + iam (node_role_arn)
#   6. rds    — needs vpc (subnets) + eks (cluster_security_group_id for SG rule)
#
# Note: IAM IRSA roles need OIDC outputs from EKS, so IAM is split:
#   - Node role created early (used by EKS node groups)
#   - IRSA roles created after EKS (needs oidc_provider_arn)
# We solve this by passing eks outputs back into the iam module via a second
# pass — Terraform handles the dependency graph automatically.

locals {
  environment    = "dev"
  cluster_name   = "digital-library-dev"
  region         = "eu-central-1"
  domain         = "dev.444noresponse.com"
  hosted_zone_id = "Z0414591K81BU1BVJ424"
}

# ─── ACM certificate ─────────────────────────────────────────────────────────

# Creates a TLS certificate for dev.444noresponse.com and validates it via
# Route 53 DNS (automatically adds the CNAME validation records).
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
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  azs                  = ["${local.region}a", "${local.region}b"]

  # Dev: one shared NAT gateway (costs ~$32/mo vs $64/mo for two)
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

  # Dev: short visibility timeout — faster local testing
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

  # Dev: spot instances cut EC2 cost by ~70%
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
  # Allow MySQL access from the EKS cluster security group (covers all nodes)
  allowed_security_group_id = module.eks.cluster_security_group_id

  db_name        = "library"
  db_username    = "library"
  instance_class = "db.t3.micro"

  # Dev: single-AZ, minimal storage
  multi_az          = false
  allocated_storage = 20
}
