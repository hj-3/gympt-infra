terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    # Configure via:
    # terraform init \
    #   -backend-config="bucket=gympt-terraform-state" \
    #   -backend-config="key=shared/terraform.tfstate" \
    #   -backend-config="region=ap-northeast-2" \
    #   -backend-config="dynamodb_table=gympt-terraform-locks"
  }
}

provider "aws" {
  region = local.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  project_name = "gympt"
  env          = "shared"
  aws_region   = "ap-northeast-2"

  common_tags = {
    Project     = local.project_name
    Environment = local.env
    ManagedBy   = "terraform"
    Repository  = "gympt-infra"
  }
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  project_name         = local.project_name
  env                  = local.env
  aws_region           = local.aws_region
  github_repository    = "hj-3/gympt-app"
  allowed_branches     = []
  create_oidc_provider = true
  create_app_role      = false
  common_tags          = local.common_tags
}
