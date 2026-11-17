resource "aws_cloudwatch_event_bus" "control" {
  name = "${var.project_name}-fargate-control"
}

resource "aws_cloudwatch_event_rule" "control" {
  for_each       = var.alias_arns
  name           = "${var.project_name}-fargate-${each.key}"
  event_bus_name = aws_cloudwatch_event_bus.control.name
  event_pattern = jsonencode({
    source      = ["fargate-control.github"]
    detail-type = ["fargate-control.request"]
    detail = {
      action    = [each.key]
      requestId = [{ exists = true }]
    }
  })
}

resource "aws_cloudwatch_event_target" "control" {
  for_each       = var.alias_arns
  event_bus_name = aws_cloudwatch_event_bus.control.name
  rule           = aws_cloudwatch_event_rule.control[each.key].name
  arn            = each.value
  retry_policy {
    maximum_event_age_in_seconds = 60
    maximum_retry_attempts       = 0
  }
  depends_on = [aws_lambda_permission.control]
}

resource "aws_lambda_permission" "control" {
  for_each      = var.alias_arns
  statement_id  = "AllowEventBridge${title(each.key)}"
  action        = "lambda:InvokeFunction"
  function_name = var.function_name
  qualifier     = each.key
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.control[each.key].arn
}
