resource "aws_scheduler_schedule" "stop" {
  name                         = "${var.project_name}-fargate-stop"
  state                        = var.schedule_enabled ? "ENABLED" : "DISABLED"
  schedule_expression          = "cron(0 17 * * ? *)"
  schedule_expression_timezone = "Asia/Tokyo"
  flexible_time_window {
    mode = "OFF"
  }
  target {
    arn      = var.stop_alias_arn
    role_arn = var.scheduler_role_arn
    input    = jsonencode({ action = "stop" })
    retry_policy {
      maximum_retry_attempts       = 0
      maximum_event_age_in_seconds = 60
    }
  }
}