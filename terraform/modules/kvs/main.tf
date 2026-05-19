resource "aws_kinesisvideo_stream" "main" {
  for_each = var.streams

  name                    = "${var.environment}-${each.key}"
  data_retention_in_hours = each.value.retention_hours

  tags = merge(var.tags, {
    Name        = "${var.environment}-${each.key}"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "kvs"
  })
}

resource "aws_kinesisvideo_signaling_channel" "webrtc" {
  for_each = var.webrtc_channels

  name = "${var.environment}-${each.key}-signaling"

  tags = merge(var.tags, {
    Name        = "${var.environment}-${each.key}-signaling"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "kvs-webrtc"
  })
}

# IAM role for KVS access from EKS pods (IRSA)
resource "aws_iam_role" "kvs_producer" {
  name = "${var.environment}-kvs-producer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.eks_oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(var.eks_oidc_provider_arn, "/^(.*provider/)/", "")}:sub" = "system:serviceaccount:${var.kvs_namespace}:kvs-producer-sa"
        }
      }
    }]
  })

  tags = merge(var.tags, {
    Name        = "${var.environment}-kvs-producer-role"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

resource "aws_iam_role_policy" "kvs_producer" {
  name = "kvs-producer-policy"
  role = aws_iam_role.kvs_producer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesisvideo:PutMedia",
          "kinesisvideo:DescribeStream",
          "kinesisvideo:GetDataEndpoint"
        ]
        Resource = [for s in aws_kinesisvideo_stream.main : s.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "kinesisvideo:DescribeSignalingChannel",
          "kinesisvideo:GetSignalingChannelEndpoint",
          "kinesisvideo:GetIceServerConfig",
          "kinesisvideo:SendAlexaOfferToMaster"
        ]
        Resource = [for c in aws_kinesisvideo_signaling_channel.webrtc : c.arn]
      }
    ]
  })
}

# Consumer role for viewing streams
resource "aws_iam_role" "kvs_consumer" {
  name = "${var.environment}-kvs-consumer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.eks_oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(var.eks_oidc_provider_arn, "/^(.*provider/)/", "")}:sub" = "system:serviceaccount:${var.kvs_namespace}:kvs-consumer-sa"
        }
      }
    }]
  })

  tags = merge(var.tags, {
    Name        = "${var.environment}-kvs-consumer-role"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

resource "aws_iam_role_policy" "kvs_consumer" {
  name = "kvs-consumer-policy"
  role = aws_iam_role.kvs_consumer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesisvideo:GetMedia",
          "kinesisvideo:GetMediaForFragmentList",
          "kinesisvideo:ListFragments",
          "kinesisvideo:DescribeStream",
          "kinesisvideo:GetDataEndpoint"
        ]
        Resource = [for s in aws_kinesisvideo_stream.main : s.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "kinesisvideo:DescribeSignalingChannel",
          "kinesisvideo:GetSignalingChannelEndpoint",
          "kinesisvideo:GetIceServerConfig",
          "kinesisvideo:ConnectAsMaster",
          "kinesisvideo:ConnectAsViewer"
        ]
        Resource = [for c in aws_kinesisvideo_signaling_channel.webrtc : c.arn]
      }
    ]
  })
}

# CloudWatch alarms for stream monitoring
resource "aws_cloudwatch_metric_alarm" "put_media_errors" {
  for_each = var.streams

  alarm_name          = "${var.environment}-kvs-${each.key}-put-media-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "PutMedia.Errors"
  namespace           = "AWS/KinesisVideo"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "KVS PutMedia errors for ${each.key}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = aws_kinesisvideo_stream.main[each.key].name
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-kvs-${each.key}-put-media-errors"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

resource "aws_cloudwatch_metric_alarm" "incoming_bytes_low" {
  for_each = var.streams

  alarm_name          = "${var.environment}-kvs-${each.key}-incoming-bytes-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "PutMedia.IncomingBytes"
  namespace           = "AWS/KinesisVideo"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1000"
  alarm_description   = "KVS incoming bytes too low for ${each.key}"
  treat_missing_data  = "breaching"

  dimensions = {
    StreamName = aws_kinesisvideo_stream.main[each.key].name
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-kvs-${each.key}-incoming-bytes-low"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}
