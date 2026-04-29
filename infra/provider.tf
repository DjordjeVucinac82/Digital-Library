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
  region  = var.aws_region
  # Uses the Digital-Library profile from ~/.aws/credentials for local runs.
  # In CI/CD (GitHub Actions), credentials are injected via environment variables
  # (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY) and override this profile.
  profile = "Digital-Library"
}
