terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# Provider credentials come from the standard AWS CLI credential chain:
#   1. Environment vars (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN)
#   2. Shared credentials file (~/.aws/credentials, profile via AWS_PROFILE or var.aws_profile)
#   3. Shared config file (~/.aws/config)
#   4. IAM role (EC2 instance / ECS task / SSO)
# Do NOT put access keys in .env or .tfvars — let `aws configure` manage them.
provider "aws" {
  region  = var.region
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = local.common_tags
  }
}
