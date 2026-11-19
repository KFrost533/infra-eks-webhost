output "eks_log_group_arn" {
  description = "EKS control plane log group ARN."
  value       = aws_cloudwatch_log_group.eks_cluster.arn
}

output "fargate_log_group_arn" {
  description = "Fargate container log group ARN."
  value       = aws_cloudwatch_log_group.fargate.arn
}

output "fargate_log_group_name" {
  description = "Fargate container log group name."
  value       = aws_cloudwatch_log_group.fargate.name
}

output "fargate_control_log_group_name" {
  value = try(aws_cloudwatch_log_group.fargate_destroy_function[0].name, null)
}