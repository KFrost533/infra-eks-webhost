output "repository_name" {
  description = "ECR repository name."
  value       = aws_ecr_repository.website.name
}

output "repository_arn" {
  description = "ECR repository ARN."
  value       = aws_ecr_repository.website.arn
}

output "repository_url" {
  description = "ECR repository URL."
  value       = aws_ecr_repository.website.repository_url
}

output "build_tools_repository_arn" {
  description = "ECR repository ARN for the private CodeBuild image."
  value       = aws_ecr_repository.build_tools.arn
}

output "build_tools_repository_url" {
  description = "ECR repository URL for the private CodeBuild image."
  value       = aws_ecr_repository.build_tools.repository_url
}
