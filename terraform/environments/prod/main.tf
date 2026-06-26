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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
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

provider "aws" {
  alias  = "use1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", module.eks.cluster_name,
      "--region", local.aws_region
    ]
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

module "s3" {
  source = "../../modules/s3"

  project_name = local.project_name
  env          = local.env
  account_id   = local.account_id
  common_tags  = local.common_tags
}

module "vpc" {
  source = "../../modules/vpc"

  project_name             = local.project_name
  env                      = local.env
  aws_region               = local.aws_region
  vpc_cidr                 = "10.1.0.0/16"
  flow_logs_bucket_arn     = module.s3.logs_bucket_arn
  nat_gateway_count        = 0     # ← down: 0 / up: 1
  enable_cluster_endpoints = false # ← down: false / up: true
  common_tags              = local.common_tags
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

  project_name            = local.project_name
  env                     = local.env
  aws_region              = local.aws_region
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_app_subnet_ids
  cluster_version         = "1.35"
  enable_public_access    = true
  public_access_cidrs     = var.eks_public_access_cidrs
  node_instance_types     = ["t3.medium"] # 시스템 노드용 (Karpenter/CoreDNS/ArgoCD)
  node_desired_size       = 1             # ← down: 0으로 스크립트 조정 / up: 1
  node_min_size           = 0
  node_max_size           = 3 # 시스템 노드는 최대 3으로 충분
  enable_gpu_node_group   = true
  gpu_node_instance_types = ["g4dn.xlarge"]
  gpu_node_desired_size   = 0 # Karpenter handles GPU nodes via gpu NodePool
  gpu_node_min_size       = 0
  gpu_node_max_size       = 3
  # Karpenter NodePool 한도 (값 변경 시 여기 한 줄만 PR). 기본값 = 현재값 → no-op
  karpenter_general_cpu_limit    = "150"
  karpenter_general_memory_limit = "200Gi"
  karpenter_gpu_cpu_limit        = "32"
  karpenter_gpu_memory_limit     = "128Gi"
  karpenter_gpu_count_limit      = "4"
  bootstrap_self_managed_addons  = false # 추가
  enabled_cluster_log_types      = []    # 비용 절감: control plane 로그 OFF
  common_tags                    = local.common_tags

}

# Data source for EKS additional security groups
data "aws_security_groups" "eks_additional" {
  filter {
    name   = "group-name"
    values = ["eks-cluster-sg-${module.eks.cluster_name}-*"]
  }
  filter {
    name   = "vpc-id"
    values = [module.vpc.vpc_id]
  }
}

# Boundary Controller SG (수동 생성). RDS/Redis가 boundary 접근을 허용하도록 data source로 조회.
# 이 참조가 없으면 apply 때마다 콘솔로 넣은 boundary 인바운드 규칙이 사라짐(drift).
data "aws_security_group" "boundary" {
  name   = "gympt-prod-boundary-controller-sg"
  vpc_id = module.vpc.vpc_id
}

module "rds" {
  source = "../../modules/rds"

  project_name  = local.project_name
  env           = local.env
  vpc_id        = module.vpc.vpc_id
  db_subnet_ids = module.vpc.private_db_subnet_ids
  allowed_security_group_ids = concat(
    [
      module.eks.node_security_group_id,
      module.eks.cluster_security_group_id,
      data.aws_security_group.boundary.id
    ],
    data.aws_security_groups.eks_additional.ids
  )
  instance_class          = "db.t3.large"
  allocated_storage       = 100
  engine_version          = "17.9"
  database_name           = "gympt"
  master_username         = "gymptadmin"
  master_password         = var.rds_master_password
  multi_az                = true
  backup_retention_period = 30
  deletion_protection     = true
  alarm_actions           = [module.cloudwatch.sns_topic_arn]
  common_tags             = local.common_tags
}

module "dynamodb" {
  source = "../../modules/dynamodb"

  project_name = local.project_name
  env          = local.env
  common_tags  = local.common_tags
}

module "elasticache" {
  source = "../../modules/elasticache"

  enabled          = false # ← down: false / up: true
  project_name     = local.project_name
  env              = local.env
  vpc_id           = module.vpc.vpc_id
  cache_subnet_ids = module.vpc.private_app_subnet_ids
  allowed_security_group_ids = concat(
    [
      module.eks.node_security_group_id,
      module.eks.cluster_security_group_id,
      data.aws_security_group.boundary.id
    ],
    data.aws_security_groups.eks_additional.ids
  )
  node_type                  = "cache.t3.medium"
  num_cache_nodes            = 2
  engine_version             = "7.0"
  auth_token_enabled         = false
  auth_token                 = var.redis_auth_token
  automatic_failover_enabled = false
  multi_az_enabled           = false
  snapshot_retention_limit   = 7
  alarm_actions              = [module.cloudwatch.sns_topic_arn]
  common_tags                = local.common_tags
}

# ============================================
# Frontend 리소스 (기존 수동 생성 리소스 참조)
# ============================================
data "aws_s3_bucket" "existing_frontend" {
  bucket = "gympt-fe-deploy-${local.account_id}"
}

resource "aws_s3_bucket_metric" "frontend_requests" {
  bucket = data.aws_s3_bucket.existing_frontend.id
  name   = "EntireBucket"
}

data "aws_cloudfront_distribution" "existing_frontend" {
  id = var.cloudfront_distribution_id
}

module "cloudfront_monitoring" {
  source = "../../modules/cloudfront-monitoring"

  providers = {
    aws = aws.use1
  }

  project_name    = local.project_name
  env             = local.env
  distribution_id = data.aws_cloudfront_distribution.existing_frontend.id
  slack_workspace_id = "T0B30UFQ45S"
  slack_channel_id   = "C0B6C0F1JB0"
  common_tags     = local.common_tags
}

data "aws_lbs" "gympt_prod" {
  tags = {
    "ingress.k8s.aws/stack" = "gympt-prod"
    "elbv2.k8s.aws/cluster" = module.eks.cluster_name
  }
}

data "aws_lb" "gympt_prod" {
  count = length(data.aws_lbs.gympt_prod.arns) == 1 ? 1 : 0
  arn   = one(data.aws_lbs.gympt_prod.arns)
}

data "aws_resourcegroupstaggingapi_resources" "gympt_prod_target_groups" {
  resource_type_filters = ["elasticloadbalancing:targetgroup"]

  tag_filter {
    key    = "ingress.k8s.aws/stack"
    values = ["gympt-prod"]
  }

  tag_filter {
    key    = "elbv2.k8s.aws/cluster"
    values = [module.eks.cluster_name]
  }
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  project_name                 = local.project_name
  env                          = local.env
  aws_region                   = local.aws_region
  github_repository            = "hj-3/gympt-app"
  allowed_branches             = ["main"]
  create_oidc_provider         = true
  create_app_role              = true
  ecr_repository_arns          = values(module.ecr.repository_arns)
  frontend_bucket_arn          = data.aws_s3_bucket.existing_frontend.arn
  lambda_artifacts_bucket_arn  = module.s3.lambda_artifacts_bucket_arn
  cloudfront_distribution_arns = [data.aws_cloudfront_distribution.existing_frontend.arn]
  common_tags                  = local.common_tags
}

module "sqs" {
  source = "../../modules/sqs"

  project_name = local.project_name
  env          = local.env
  common_tags  = local.common_tags
}

# Lambda (must be before EventBridge as EventBridge references Lambda ARNs)
module "lambda" {
  source = "../../modules/lambda"

  project_name           = local.project_name
  env                    = local.env
  aws_region             = local.aws_region
  lambda_artifact_bucket = module.s3.lambda_artifacts_bucket_id
  dynamodb_table_arns    = values(module.dynamodb.table_arns)
  s3_bucket_arns         = values(module.s3.bucket_arns)
  sqs_queue_arns         = values(module.sqs.queue_arns)
  secrets_manager_arns   = []
  vpc_config_enabled     = true
  vpc_subnet_ids         = module.vpc.private_app_subnet_ids
  vpc_security_group_ids = [module.eks.node_security_group_id]
  xray_tracing_enabled   = true
  log_retention_days     = 30
  alarm_actions          = [module.cloudwatch.sns_topic_arn]
  common_tags            = local.common_tags

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

# WAF 모듈 제거: CloudFront에서 직접 WAF 붙일 예정


module "iam" {
  source = "../../modules/iam"

  project_name              = local.project_name
  env                       = local.env
  aws_region                = local.aws_region
  bedrock_region            = "us-west-2"
  bedrock_agent_id          = "WPQ0RESSZS"
  kvs_signaling_channel_arn = "arn:aws:kinesisvideo:ap-northeast-2:337112169365:channel/prod-live-sessions-signaling/1779644737658"
  oidc_provider_arn         = module.eks.oidc_provider_arn
  oidc_provider_url         = module.eks.oidc_provider_url
  s3_bucket_arns            = values(module.s3.bucket_arns)
  dynamodb_table_arns       = values(module.dynamodb.table_arns)
  common_tags               = local.common_tags

  pod_service_accounts = {
    backend-api = {
      namespace       = "gympt-prod"
      service_account = "backend-api-prod"
    }
    agent-service = {
      namespace       = "gympt-prod"
      service_account = "agent-service-prod"
    }
    posture-analysis-service = {
      namespace       = "gympt-prod"
      service_account = "posture-analysis-service-prod"
    }
    report-service = {
      namespace       = "gympt-prod"
      service_account = "report-service-prod"
    }
    kvs-consumer-service = {
      namespace       = "gympt-prod"
      service_account = "kvs-consumer-service-prod"
    }
    generic-worker = {
      namespace       = "gympt-prod"
      service_account = "generic-worker-prod"
    }
  }
}

module "karpenter" {
  source = "../../modules/karpenter"

  project_name       = local.project_name
  env                = local.env
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url
  eks_node_role_name = module.eks.node_role_name
  common_tags        = local.common_tags
}

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  project_name            = local.project_name
  env                     = local.env
  aws_region              = local.aws_region
  alarm_email             = var.alarm_email
  log_retention_days        = 30
  slack_workspace_id        = "T0B30UFQ45S"
  slack_channel_id          = "C0B6C0F1JB0"
  security_slack_channel_id = "C0B8L829W92"
  inspector_sns_topic_arn   = module.inspector.sns_topic_arn
  common_tags               = local.common_tags
}

module "cloudtrail" {
  source = "../../modules/cloudtrail"

  project_name        = local.project_name
  env                 = local.env
  s3_bucket_name      = module.s3.logs_bucket_id
  s3_bucket_policy_id = module.s3.logs_bucket_policy_id
  common_tags         = local.common_tags
  kms_key_id          = "arn:aws:kms:ap-northeast-2:337112169365:key/63574ed7-d86f-434f-86f5-295cf5788fe2"
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

data "aws_iam_policy_document" "grafana_athena_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:monitoring:kube-prometheus-stack-grafana"]
    }
  }
}

resource "aws_iam_role" "grafana_athena" {
  name               = "${local.name_prefix}-grafana-athena"
  assume_role_policy = data.aws_iam_policy_document.grafana_athena_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "grafana_athena" {
  name = "${local.name_prefix}-grafana-athena"
  role = aws_iam_role.grafana_athena.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:StopQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:GetQueryResultsStream",
          "athena:GetWorkGroup",
          "athena:ListWorkGroups",
          "athena:GetDataCatalog",
          "athena:ListDataCatalogs",
          "athena:GetDatabase",
          "athena:ListDatabases",
          "athena:GetTableMetadata",
          "athena:ListTableMetadata"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchGetPartition"
        ]
        Resource = [
          "arn:aws:glue:${local.aws_region}:${local.account_id}:catalog",
          "arn:aws:glue:${local.aws_region}:${local.account_id}:database/${module.glue.catalog_database_name}",
          "arn:aws:glue:${local.aws_region}:${local.account_id}:table/${module.glue.catalog_database_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads",
          "s3:ListBucket"
        ]
        Resource = [
          module.s3.logs_bucket_arn,
          module.s3.athena_results_bucket_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${module.s3.logs_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = [
          "${module.s3.athena_results_bucket_arn}/athena-results/*"
        ]
      }
    ]
  })
}

module "monitoring" {
  source = "../../modules/monitoring"

  project_name                  = local.project_name
  env                           = local.env
  aws_region                    = local.aws_region
  eks_cluster_name              = module.eks.cluster_name
  sqs_queue_names               = module.sqs.queue_names
  sqs_dlq_names                 = module.sqs.dlq_names
  sns_topic_arn                 = module.cloudwatch.sns_topic_arn
  rds_instance_id               = module.rds.db_instance_id
  lambda_function_names         = module.lambda.lambda_function_names
  dynamodb_table_names          = module.dynamodb.table_names
  alb_load_balancer_arn_suffix  = try(data.aws_lb.gympt_prod[0].arn_suffix, null)
  alb_target_group_arn_suffixes = {
    for resource in data.aws_resourcegroupstaggingapi_resources.gympt_prod_target_groups.resource_tag_mapping_list :
    replace(resource.resource_arn, "/^.*:targetgroup\\//", "") => "targetgroup/${replace(resource.resource_arn, "/^.*:targetgroup\\//", "")}"
  }
  s3_request_metric_buckets = {
    frontend = data.aws_s3_bucket.existing_frontend.id
    media    = module.s3.media_bucket_id
  }
  waf_web_acl_metrics = {
    alb = {
      web_acl = "gympt-alb-waf"
      region  = local.aws_region
      rule    = "ALL"
    }
  }
  kvs_stream_names             = module.kvs.stream_names
  eventbridge_rule_names       = module.eventbridge.rule_names
  athena_workgroup_names       = { logs = module.athena.workgroup_name }
  cpu_threshold                = 80
  memory_threshold             = 85
  sqs_age_threshold            = 300
  common_tags                  = local.common_tags
}

module "kvs" {
  source = "../../modules/kvs"

  environment           = local.env
  eks_oidc_provider_arn = module.eks.oidc_provider_arn
  kvs_namespace         = "prod"

  streams = {
    workout-sessions = {
      retention_hours = 24
    }
  }

  webrtc_channels = {
    live-sessions = {
      enabled = true
    }
  }

  tags = local.common_tags
}

resource "kubernetes_labels" "gympt_prod_psa" {
  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = "gympt-prod"
  }
  labels = {
    "pod-security.kubernetes.io/warn"  = "baseline"
    "pod-security.kubernetes.io/audit" = "baseline"
  }
}

module "inspector" {
  source = "../../modules/inspector"

  project_name    = local.project_name
  env             = local.env
  logs_bucket_arn = module.s3.logs_bucket_arn
  common_tags     = local.common_tags
}

module "security_monitor" {
  source = "../../modules/security-monitor"

  project_name              = local.project_name
  env                       = local.env
  aws_region                = local.aws_region
  account_id                = local.account_id
  glue_database_name        = module.glue.catalog_database_name
  athena_results_bucket_id  = module.s3.athena_results_bucket_id
  athena_results_bucket_arn = module.s3.athena_results_bucket_arn
  logs_bucket_arn           = module.s3.logs_bucket_arn
  logs_bucket_id            = module.s3.logs_bucket_id
  slack_webhook_secret_name = "gympt/prod/slack/security-webhook-url"
  slack_webhook_secret_arn  = "arn:aws:secretsmanager:ap-northeast-2:${local.account_id}:secret:gympt/prod/slack/security-webhook-url-bln6XW"
  security_sns_topic_arn    = module.cloudwatch.security_sns_topic_arn
  bedrock_region            = "us-west-2"
  bedrock_model_id          = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
  log_retention_days        = 30
  common_tags               = local.common_tags
}
