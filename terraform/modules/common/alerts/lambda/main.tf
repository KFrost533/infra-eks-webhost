resource "aws_cloudwatch_log_metric_filter" "lambda_fargateControl_failure" {
  name           = "${var.function_name}-failure"
  pattern        = var.failure_pattern
  log_group_name = var.log_group_name

  metric_transformation {
    name      = "${var.function_name}-failure"
    namespace = "Lambda/FargateControl"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_fargateControl_log_failure" {
  alarm_name          = "${var.function_name}-failure-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.lambda_fargateControl_failure.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.lambda_fargateControl_failure.metric_transformation[0].namespace
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "lambda" {
  for_each            = toset(["Errors", "Throttles", "AsyncEventsDropped"])
  alarm_name          = "${var.function_name}-${each.key}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = each.key
  namespace           = "AWS/Lambda"
  dimensions          = { FunctionName = var.function_name }
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "eventbridge" {
  for_each            = var.event_rule_names
  alarm_name          = "${var.function_name}-delivery-${each.key}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedInvocations"
  namespace           = "AWS/Events"
  dimensions          = { EventBusName = var.event_bus_name, RuleName = each.value }
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_composite_alarm" "notification" {
  alarm_name    = "${var.function_name}-notification"
  alarm_actions = [var.sns_topic_arn]
  alarm_rule = join(" OR ", concat(
    ["ALARM(\"${aws_cloudwatch_metric_alarm.lambda_fargateControl_log_failure.alarm_name}\")"],
    [for alarm in aws_cloudwatch_metric_alarm.lambda : "ALARM(\"${alarm.alarm_name}\")"],
    [for alarm in aws_cloudwatch_metric_alarm.eventbridge : "ALARM(\"${alarm.alarm_name}\")"]
  ))
}
