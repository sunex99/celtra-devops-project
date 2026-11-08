terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
  }

  # Remote state in S3. The bucket, key and region are not written here (no account-specific names in the repository); the pipeline passes them
  # at init time with -backend-config. use_lockfile makes Terraform lock the state with a lock file in the same bucket, so no DynamoDB table is needed
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  # Tags applied to every resource this module creates.
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
