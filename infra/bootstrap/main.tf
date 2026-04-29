# Bootstrap — run once before any environment.
# Creates the S3 bucket and DynamoDB table used for Terraform remote state.
# Apply with local state: terraform init && terraform apply
# Do NOT add a backend "s3" block here — it would be circular.

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "eu-central-1"
  profile = "Digital-Library"
}

# ─── S3 bucket for TF state ───────────────────────────────────────────────────

resource "aws_s3_bucket" "terraform_state" {
  bucket = "digital-library-terraform-state"

  # Prevent accidental destruction of the state bucket
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name    = "digital-library-terraform-state"
    Purpose = "Terraform remote state storage"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access — state files can contain sensitive data
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── DynamoDB table for state locking ─────────────────────────────────────────

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST" # no capacity planning needed for lock table
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name    = "terraform-locks"
    Purpose = "Terraform state lock table"
  }
}

output "state_bucket_name" {
  value = aws_s3_bucket.terraform_state.bucket
}

output "lock_table_name" {
  value = aws_dynamodb_table.terraform_locks.name
}
