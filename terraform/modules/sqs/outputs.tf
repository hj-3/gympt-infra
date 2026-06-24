output "queue_urls" {
  description = "SQS queue URLs"
  value = {
    for k, v in aws_sqs_queue.main : k => v.url
  }
}

output "queue_arns" {
  description = "SQS queue ARNs"
  value = {
    for k, v in aws_sqs_queue.main : k => v.arn
  }
}

output "queue_names" {
  description = "SQS queue names"
  value = {
    for k, v in aws_sqs_queue.main : k => v.name
  }
}

output "dlq_arns" {
  description = "DLQ ARNs"
  value = {
    for k, v in aws_sqs_queue.dlq : k => v.arn
  }
}

output "dlq_names" {
  description = "DLQ names"
  value = {
    for k, v in aws_sqs_queue.dlq : k => v.name
  }
}
