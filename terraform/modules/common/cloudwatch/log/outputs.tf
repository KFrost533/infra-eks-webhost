output "codebuild_log_group_arn" {
  description = "CodeBuild log group ARN."
  value       = aws_cloudwatch_log_group.codebuild.arn
}

output "codebuild_log_group_name" {
  description = "CodeBuild log group name."
  value       = aws_cloudwatch_log_group.codebuild.name
}