output "frontend_bucket_id" {
  description = "Frontend S3 bucket ID"
  value       = aws_s3_bucket.frontend.id
}

output "frontend_bucket_arn" {
  description = "Frontend S3 bucket ARN"
  value       = aws_s3_bucket.frontend.arn
}

output "frontend_bucket_domain_name" {
  description = "Frontend S3 bucket regional domain name"
  value       = aws_s3_bucket.frontend.bucket_regional_domain_name
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
    frontend         = aws_s3_bucket.frontend.arn
    media            = aws_s3_bucket.media.arn
    logs             = aws_s3_bucket.logs.arn
    lambda_artifacts = aws_s3_bucket.lambda_artifacts.arn
    athena_results   = aws_s3_bucket.athena_results.arn
  }
}
