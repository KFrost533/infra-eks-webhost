variable "project_name" {
  description = "Name used for the CodeBuild project and related resources."
  type        = string
}

variable "aws_region" {
  description = "AWS region containing the build project and EKS cluster."
  type        = string
}

variable "repository_url" {
  description = "GitHub HTTPS URL for the website source."
  type        = string
}

variable "github_connection_arn" {
  description = "GitHub CodeConnections connection ARN."
  type        = string
}

variable "repository_branch" {
  description = "Git branch CodeBuild uses as its source."
  type        = string
}

variable "buildspec_path" {
  description = "Buildspec path relative to the repository root."
  type        = string
}

variable "enable_github_webhook" {
  description = "Enable push-triggered builds after the GitHub connection is authorized."
  type        = bool
  default     = false
}

variable "enable_weekly_report" {
  description = "Whether CodeBuild deploys the weekly report CronJob."
  type        = bool
  default     = false
}

variable "codebuild_role_arn" {
  description = "IAM role ARN assumed by CodeBuild."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the CodeBuild network interface."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the CodeBuild project."
  type        = list(string)
}

variable "codebuild_security_group_id" {
  description = "Security group ID assigned to the CodeBuild build environment."
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL passed to build commands."
  type        = string
}

variable "eks_cluster_name" {
  description = "EKS cluster name passed to build commands."
  type        = string
}

variable "cloudwatch_log_group_name" {
  description = "CloudWatch Logs group name for the CodeBuild project."
  type        = string
}