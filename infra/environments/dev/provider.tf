terraform {
  required_version = ">= 1.6"

  # Remote state — run infra/bootstrap first to create this bucket and table
  backend "s3" {
    bucket         = "digital-library-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
    profile        = "Digital-Library"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # Local development: uses the Digital-Library profile from ~/.aws/credentials
  # CI/CD: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY env vars override this
  profile = "Digital-Library"

  default_tags {
    tags = {
      Project     = "digital-library"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}
