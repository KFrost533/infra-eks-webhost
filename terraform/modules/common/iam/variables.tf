variable "project_name" {
  description = "Short project name used in the CodeBuild role name."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name used in the cluster and Fargate role names."
  type        = string
}

variable "fargate_log_group_arn" {
  description = "CloudWatch Logs group ARN for Fargate container logs."
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
