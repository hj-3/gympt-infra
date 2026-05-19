output "stream_arns" {
  description = "Map of KVS stream ARNs by stream name"
  value       = { for k, v in aws_kinesisvideo_stream.main : k => v.arn }
}

output "stream_names" {
  description = "Map of KVS stream names by stream key"
  value       = { for k, v in aws_kinesisvideo_stream.main : k => v.name }
}

output "stream_ids" {
  description = "Map of KVS stream IDs by stream name"
  value       = { for k, v in aws_kinesisvideo_stream.main : k => v.id }
}

output "signaling_channel_arns" {
  description = "Map of WebRTC signaling channel ARNs by channel name"
  value       = { for k, v in aws_kinesisvideo_signaling_channel.webrtc : k => v.arn }
}

output "signaling_channel_names" {
  description = "Map of WebRTC signaling channel names by channel key"
  value       = { for k, v in aws_kinesisvideo_signaling_channel.webrtc : k => v.name }
}

output "producer_role_arn" {
  description = "IAM role ARN for KVS stream producers (camera/encoder pods)"
  value       = aws_iam_role.kvs_producer.arn
}

output "producer_role_name" {
  description = "IAM role name for KVS stream producers"
  value       = aws_iam_role.kvs_producer.name
}

output "consumer_role_arn" {
  description = "IAM role ARN for KVS stream consumers (viewer pods)"
  value       = aws_iam_role.kvs_consumer.arn
}

output "consumer_role_name" {
  description = "IAM role name for KVS stream consumers"
  value       = aws_iam_role.kvs_consumer.name
}

output "cloudwatch_alarm_arns" {
  description = "Map of CloudWatch alarm ARNs for stream monitoring"
  value = merge(
    { for k, v in aws_cloudwatch_metric_alarm.put_media_errors : "${k}-errors" => v.arn },
    { for k, v in aws_cloudwatch_metric_alarm.incoming_bytes_low : "${k}-bytes" => v.arn }
  )
}
