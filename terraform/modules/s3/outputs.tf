output "frontend_bucket_id" {
  description = "Frontend S3 bucket ID (manually managed)"
  value       = null
}

output "frontend_bucket_arn" {
  description = "Frontend S3 bucket ARN (manually managed)"
  value       = null
}

output "frontend_bucket_domain_name" {
  description = "Frontend S3 bucket domain name (manually managed)"
  value       = null
}

output "media_bucket_id" {
  description = "Media S3 bucket ID"
  value       = aws_s3_bucket.media.id
}

output "media_bucket_arn" {
  description = "Media S3 bucket ARN"
  value       = aws_s3_bucket.media.arn
}

output "logs_bucket_id" {
  description = "Logs S3 bucket ID"
  value       = aws_s3_bucket.logs.id
}

output "logs_bucket_arn" {
  description = "Logs S3 bucket ARN"
  value       = aws_s3_bucket.logs.arn
}

output "logs_bucket_policy_id" {
  description = "Logs S3 bucket policy ID"
  value       = aws_s3_bucket_policy.logs.id
}

output "lambda_artifacts_bucket_id" {
  description = "Lambda artifacts S3 bucket ID"
  value       = aws_s3_bucket.lambda_artifacts.id
}

output "lambda_artifacts_bucket_arn" {
  description = "Lambda artifacts S3 bucket ARN"
  value       = aws_s3_bucket.lambda_artifacts.arn
}

output "athena_results_bucket_id" {
  description = "Athena results S3 bucket ID"
  value       = aws_s3_bucket.athena_results.id
}

output "athena_results_bucket_arn" {
  description = "Athena results S3 bucket ARN"
  value       = aws_s3_bucket.athena_results.arn
}

output "bucket_arns" {
  description = "Map of all S3 bucket ARNs"
  value = {
    media            = aws_s3_bucket.media.arn
    logs             = aws_s3_bucket.logs.arn
    lambda_artifacts = aws_s3_bucket.lambda_artifacts.arn
    athena_results   = aws_s3_bucket.athena_results.arn
  }
}
