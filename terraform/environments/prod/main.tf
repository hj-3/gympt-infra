terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Configure via:
    # terraform init \
    #   -backend-config="bucket=gympt-terraform-state" \
    #   -backend-config="key=prod/terraform.tfstate" \
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

data "aws_caller_identity" "current" {}

locals {
  project_name = "gympt"
  env          = "prod"
  aws_region   = "ap-northeast-2"
  account_id   = data.aws_caller_identity.current.account_id

  name_prefix = "${local.project_name}-${local.env}"
  s3_suffix   = local.account_id

  common_tags = {
    Project     = local.project_name
    Environment = local.env
    ManagedBy   = "terraform"
    Repository  = "gympt-infra"
  }
}

module "vpc" {
  source = "../../modules/vpc"

  project_name = local.project_name
  env          = local.env
  aws_region   = local.aws_region
  vpc_cidr     = "10.1.0.0/16"
  common_tags  = local.common_tags
}

module "ecr" {
  source = "../../modules/ecr"

  project_name         = local.project_name
  env                  = local.env
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  common_tags          = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  project_name          = local.project_name
  env                   = local.env
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_app_subnet_ids
  cluster_version       = "1.35"
  node_instance_types   = ["t3.xlarge"]
  node_desired_size     = 3
  node_min_size         = 3
  node_max_size         = 20
  enable_gpu_node_group = true
  gpu_node_instance_types = ["g4dn.xlarge"]
  gpu_node_desired_size = 1
  gpu_node_min_size     = 0
  gpu_node_max_size     = 5
  common_tags           = local.common_tags
}

module "rds" {
  source = "../../modules/rds"

  project_name              = local.project_name
  env                       = local.env
  vpc_id                    = module.vpc.vpc_id
  db_subnet_ids             = module.vpc.private_db_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]
  instance_class            = "db.t3.large"
  allocated_storage         = 100
  engine_version            = "17.2"
  database_name             = "gympt"
  master_username           = "gymptadmin"
  master_password           = var.rds_master_password
  multi_az                  = true
  backup_retention_period   = 30
  deletion_protection       = true
  common_tags               = local.common_tags
}

module "dynamodb" {
  source = "../../modules/dynamodb"

  project_name = local.project_name
  env          = local.env
  common_tags  = local.common_tags
}

module "elasticache" {
  source = "../../modules/elasticache"

  project_name              = local.project_name
  env                       = local.env
  vpc_id                    = module.vpc.vpc_id
  cache_subnet_ids          = module.vpc.private_app_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]
  node_type                 = "cache.t3.medium"
  num_cache_nodes           = 2
  engine_version            = "7.0"
  auth_token_enabled        = true
  auth_token                = var.redis_auth_token
  automatic_failover_enabled = true
  multi_az_enabled          = true
  snapshot_retention_limit  = 7
  common_tags               = local.common_tags
}

module "s3" {
  source = "../../modules/s3"

  project_name = local.project_name
  env          = local.env
  account_id   = local.account_id
  common_tags  = local.common_tags
}

module "cloudfront" {
  source = "../../modules/cloudfront"

  project_name                      = local.project_name
  env                               = local.env
  frontend_bucket_id                = module.s3.frontend_bucket_id
  frontend_bucket_arn               = module.s3.frontend_bucket_arn
  frontend_bucket_domain_name       = module.s3.frontend_bucket_domain_name
  price_class                       = "PriceClass_200"
  web_acl_id                        = module.waf.web_acl_id
  enable_spa_routing                = true
  common_tags                       = local.common_tags
}

module "sqs" {
  source = "../../modules/sqs"

  project_name = local.project_name
  env          = local.env
  common_tags  = local.common_tags
}

module "eventbridge" {
  source = "../../modules/eventbridge"

  project_name                 = local.project_name
  env                          = local.env
  report_queue_arn             = module.sqs.queue_arns["report-generation"]
  recommendation_queue_arn     = module.sqs.queue_arns["recommendation-update"]
  notification_queue_arn       = module.sqs.queue_arns["notification"]
  wearable_sync_queue_arn      = module.sqs.queue_arns["wearable-sync"]
  report_generator_lambda_arn  = module.lambda.lambda_function_arns["report-generator"]
  report_generator_lambda_name = module.lambda.lambda_function_names["report-generator"]
  recommendation_lambda_arn    = module.lambda.lambda_function_arns["recommendation-update"]
  recommendation_lambda_name   = module.lambda.lambda_function_names["recommendation-update"]
  archive_retention_days       = 90
  common_tags                  = local.common_tags
}

module "lambda" {
  source = "../../modules/lambda"

  project_name            = local.project_name
  env                     = local.env
  aws_region              = local.aws_region
  lambda_artifact_bucket  = module.s3.lambda_artifacts_bucket_id
  dynamodb_table_arns     = values(module.dynamodb.table_arns)
  s3_bucket_arns          = values(module.s3.bucket_arns)
  sqs_queue_arns          = values(module.sqs.queue_arns)
  secrets_manager_arns    = []
  vpc_config_enabled      = true
  vpc_subnet_ids          = module.vpc.private_app_subnet_ids
  vpc_security_group_ids  = [module.eks.node_security_group_id]
  xray_tracing_enabled    = true
  log_retention_days      = 30
  alarm_actions           = [module.cloudwatch.sns_topic_arn]
  common_tags             = local.common_tags

  sqs_event_sources = {
    report-generator        = { queue_arn = module.sqs.queue_arns["report-generation"], batch_size = 1, max_concurrency = 10 }
    posture-event-processor = { queue_arn = module.sqs.queue_arns["posture-event"], batch_size = 10, max_concurrency = 20 }
    thumbnail-generator     = { queue_arn = module.sqs.queue_arns["thumbnail-generation"], batch_size = 1, max_concurrency = 5 }
    wearable-sync           = { queue_arn = module.sqs.queue_arns["wearable-sync"], batch_size = 10, max_concurrency = 10 }
    recommendation-update   = { queue_arn = module.sqs.queue_arns["recommendation-update"], batch_size = 1, max_concurrency = 5 }
    notification            = { queue_arn = module.sqs.queue_arns["notification"], batch_size = 10, max_concurrency = 20 }
    export                  = { queue_arn = module.sqs.queue_arns["export"], batch_size = 1, max_concurrency = 3 }
  }
}

module "waf" {
  source = "../../modules/waf"

  project_name = local.project_name
  env          = local.env
  scope        = "REGIONAL"
  rate_limit   = 5000
  common_tags  = local.common_tags
}

module "bedrock" {
  source = "../../modules/bedrock"

  project_name   = local.project_name
  env            = local.env
  aws_region     = local.aws_region
  s3_bucket_arns = [module.s3.media_bucket_arn]
  common_tags    = local.common_tags
}

module "iam" {
  source = "../../modules/iam"

  project_name        = local.project_name
  env                 = local.env
  oidc_provider_arn   = module.eks.oidc_provider_arn
  oidc_provider_url   = module.eks.oidc_provider_url
  s3_bucket_arns      = values(module.s3.bucket_arns)
  dynamodb_table_arns = values(module.dynamodb.table_arns)
  common_tags         = local.common_tags
}

module "karpenter" {
  source = "../../modules/karpenter"

  project_name       = local.project_name
  env                = local.env
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url
  eks_node_role_name = module.eks.node_role_arn
  common_tags        = local.common_tags
}

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  project_name       = local.project_name
  env                = local.env
  aws_region         = local.aws_region
  alarm_email        = var.alarm_email
  log_retention_days = 30
  common_tags        = local.common_tags
}

module "cloudtrail" {
  source = "../../modules/cloudtrail"

  project_name   = local.project_name
  env            = local.env
  s3_bucket_name = module.s3.logs_bucket_id
  common_tags    = local.common_tags
}

module "athena" {
  source = "../../modules/athena"

  project_name   = local.project_name
  env            = local.env
  results_bucket = module.s3.athena_results_bucket_id
  common_tags    = local.common_tags
}

module "glue" {
  source = "../../modules/glue"

  project_name = local.project_name
  env          = local.env
  logs_bucket  = module.s3.logs_bucket_id
  common_tags  = local.common_tags
}

module "monitoring" {
  source = "../../modules/monitoring"

  project_name     = local.project_name
  env              = local.env
  aws_region       = local.aws_region
  eks_cluster_name = module.eks.cluster_name
  sqs_queue_names  = module.sqs.queue_names
  sns_topic_arn    = module.cloudwatch.sns_topic_arn
  cpu_threshold    = 80
  memory_threshold = 85
  sqs_age_threshold = 300
  common_tags      = local.common_tags
}
