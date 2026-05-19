output "trail_arn" {
  value = aws_cloudtrail.main.arn
}

output "trail_name" {
  value = aws_cloudtrail.main.name
}
