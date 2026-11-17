output "topic_arn" {
  value      = aws_sns_topic.lambda_alerts.arn
  depends_on = [aws_sns_topic_policy.lambda_alerts]
}
