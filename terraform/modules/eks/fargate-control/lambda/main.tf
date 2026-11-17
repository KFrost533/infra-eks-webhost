data "archive_file" "function" {
  type        = "zip"
  source_file = "${path.module}/dist/fargate_off.js"
  output_path = "${path.module}/dist/fargate_off.zip"
}

resource "aws_lambda_function" "control" {
  function_name                  = "${var.project_name}-fargate-control"
  role                           = var.function_role_arn
  runtime                        = "nodejs22.x"
  handler                        = "fargate_off.handler"
  publish                        = true
  filename                       = data.archive_file.function.output_path
  source_code_hash               = data.archive_file.function.output_base64sha256
  timeout                        = 600
  memory_size                    = 256
  reserved_concurrent_executions = 1
  environment {
    variables = { CLUSTER_NAME = var.cluster_name }
  }
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.security_group_id]
  }
}

resource "aws_lambda_alias" "stop" {
  name             = "stop"
  function_name    = aws_lambda_function.control.function_name
  function_version = aws_lambda_function.control.version
}

resource "aws_lambda_alias" "restore" {
  name             = "restore"
  function_name    = aws_lambda_function.control.function_name
  function_version = aws_lambda_function.control.version
}

resource "aws_lambda_function_event_invoke_config" "control" {
  function_name                = aws_lambda_function.control.function_name
  qualifier                    = aws_lambda_alias.stop.name
  maximum_retry_attempts       = 0
  maximum_event_age_in_seconds = 60
}

resource "aws_lambda_function_event_invoke_config" "restore" {
  function_name                = aws_lambda_function.control.function_name
  qualifier                    = aws_lambda_alias.restore.name
  maximum_retry_attempts       = 0
  maximum_event_age_in_seconds = 60
}

