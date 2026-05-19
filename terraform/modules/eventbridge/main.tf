locals {
  name_prefix = "${var.project_name}-${var.env}"
}

resource "aws_cloudwatch_event_bus" "main" {
  name = "${local.name_prefix}-event-bus"
  tags = merge(var.common_tags, { Name = "${local.name_prefix}-event-bus" })
}

resource "aws_cloudwatch_event_rule" "workout_completed" {
  name           = "${local.name_prefix}-workout-completed"
  description    = "Trigger when workout session is completed"
  event_bus_name = aws_cloudwatch_event_bus.main.name
  event_pattern = jsonencode({
    source      = ["gympt.workout"]
    detail-type = ["Workout Completed"]
  })
  tags = var.common_tags
}

resource "aws_cloudwatch_event_rule" "posture_analyzed" {
  name           = "${local.name_prefix}-posture-analyzed"
  description    = "Trigger when posture analysis is complete"
  event_bus_name = aws_cloudwatch_event_bus.main.name
  event_pattern = jsonencode({
    source      = ["gympt.posture"]
    detail-type = ["Posture Analyzed"]
  })
  tags = var.common_tags
}

resource "aws_cloudwatch_event_rule" "daily_report_schedule" {
  name                = "${local.name_prefix}-daily-report-schedule"
  description         = "Daily report generation schedule"
  schedule_expression = "cron(0 1 * * ? *)"
  tags                = var.common_tags
}

resource "aws_cloudwatch_event_target" "workout_to_report_queue" {
  rule           = aws_cloudwatch_event_rule.workout_completed.name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  arn            = var.report_queue_arn
  target_id      = "SendToReportQueue"
}

resource "aws_cloudwatch_event_target" "daily_report_to_lambda" {
  rule      = aws_cloudwatch_event_rule.daily_report_schedule.name
  arn       = var.report_generator_lambda_arn
  target_id = "InvokeDailyReport"
}

resource "aws_lambda_permission" "eventbridge_daily_report" {
  statement_id  = "AllowEventBridgeDailyReport"
  action        = "lambda:InvokeFunction"
  function_name = var.report_generator_lambda_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_report_schedule.arn
}

resource "aws_cloudwatch_event_archive" "main" {
  name             = "${local.name_prefix}-event-archive"
  event_source_arn = aws_cloudwatch_event_bus.main.arn
  retention_days   = var.archive_retention_days
  event_pattern = jsonencode({
    source = ["gympt.workout", "gympt.posture", "gympt.wearable"]
  })
}
