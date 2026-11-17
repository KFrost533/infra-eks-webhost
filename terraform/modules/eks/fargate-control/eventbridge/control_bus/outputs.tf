output "bus_name" {
  value = aws_cloudwatch_event_bus.control.name
}

output "bus_arn" {
  value = aws_cloudwatch_event_bus.control.arn
}

output "rule_names" {
  value = { for action, rule in aws_cloudwatch_event_rule.control : action => rule.name }
}
