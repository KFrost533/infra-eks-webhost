variable "project_name" {
  description = "Project name used in the IAM policy name."
  type        = string
}

variable "codebuild_role_name" {
  description = "Name of the CodeBuild service role."
  type        = string
}

variable "cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN for the build."
  type        = string
}

variable "github_connection_arn" {
  description = "GitHub CodeConnections connection ARN."
  type        = string
}

variable "ecr_repository_arn" {
  description = "ECR website repository ARN."
  type        = string
}

variable "build_tools_repository_arn" {
  description = "ECR build tools repository ARN."
  type        = string
}

variable "eks_cluster_arn" {
  description = "EKS cluster ARN."
  type        = string
}
