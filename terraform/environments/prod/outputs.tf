output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.db_endpoint
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.elasticache.primary_endpoint_address
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (existing)"
  value       = data.aws_cloudfront_distribution.existing_frontend.id
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name (existing)"
  value       = data.aws_cloudfront_distribution.existing_frontend.domain_name
}

output "ecr_repository_urls" {
  description = "ECR repository URLs"
  value       = module.ecr.repository_urls
}

# Lambda 모듈 비활성화로 주석 처리
# output "lambda_function_names" {
#   description = "Lambda function names"
#   value       = module.lambda.lambda_function_names
# }

output "s3_frontend_bucket" {
  description = "Frontend S3 bucket name (existing)"
  value       = data.aws_s3_bucket.existing_frontend.id
}

output "dynamodb_table_names" {
  description = "DynamoDB table names"
  value       = module.dynamodb.table_names
}

output "sqs_queue_urls" {
  description = "SQS queue URLs"
  value       = module.sqs.queue_urls
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = module.eks.alb_controller_role_arn
}

output "kvs_stream_arns" {
  description = "KVS stream ARNs"
  value       = module.kvs.stream_arns
}

output "kvs_producer_role_arn" {
  description = "KVS producer IAM role ARN"
  value       = module.kvs.producer_role_arn
}

output "kvs_consumer_role_arn" {
  description = "KVS consumer IAM role ARN"
  value       = module.kvs.consumer_role_arn
}

output "github_actions_app_role_arn" {
  description = "IAM role ARN for gympt-app GitHub Actions prod deployments"
  value       = module.github_oidc.github_actions_app_role_arn
}

