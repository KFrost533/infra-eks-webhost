output "function_name" {
  value = aws_lambda_function.control.function_name
}

output "stop_alias_arn" {
  value = aws_lambda_alias.stop.arn
}

output "restore_alias_arn" {
  value = aws_lambda_alias.restore.arn
}
