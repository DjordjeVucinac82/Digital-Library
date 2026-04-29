terraform {
  required_version = ">= 1.6"

  backend "s3" {
    bucket         = "digital-library-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
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
  # Local: Digital-Library profile; CI/CD: env vars override
  profile = "Digital-Library"

  default_tags {
    tags = {
      Project     = "digital-library"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}
