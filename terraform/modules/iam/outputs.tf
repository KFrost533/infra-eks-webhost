output "eks_cluster_role_arn" {
  description = "EKS cluster service role ARN."
  value       = aws_iam_role.eks_cluster.arn
}

output "fargate_pod_execution_role_arn" {
  description = "Fargate pod execution role ARN."
  value       = aws_iam_role.fargate_pod_execution.arn
}

output "codebuild_role_arn" {
  description = "CodeBuild service role ARN."
  value       = aws_iam_role.codebuild.arn
}

output "codebuild_role_name" {
  description = "CodeBuild service role name for inline policy attachment."
  value       = aws_iam_role.codebuild.name
}