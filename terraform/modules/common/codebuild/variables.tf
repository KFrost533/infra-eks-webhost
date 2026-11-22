variable "project_name" {
  description = "Name used for the CodeBuild project and related resources."
  type        = string
}

variable "aws_region" {
  description = "AWS region containing the build project and EKS cluster."
  type        = string
}

variable "github_connection_arn" {
  description = "GitHub CodeConnections connection ARN."
  type        = string
}

variable "repository_branch" {
  description = "Git branch CodeBuild uses as its source."
  type        = string
  default     = "main"
  nullable    = false

  validation {
    condition     = var.repository_branch == "main"
    error_message = "The deployment webhook is restricted to the main branch."
  }
}

variable "buildspec_path" {
  description = "Buildspec path relative to the repository root."
  type        = string
  default     = "buildspec.yml"
  nullable    = false
}

variable "enable_github_webhook" {
  description = "Enable push-triggered builds after the GitHub connection is authorized."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_weekly_report" {
  description = "Whether CodeBuild deploys the weekly report CronJob."
  type        = bool
  default     = false
  nullable    = false
}

variable "codebuild_role_arn" {
  description = "IAM role ARN assumed by CodeBuild."
  type        = string
}

variable "vpc_id" {
  description = "Optional VPC ID for the CodeBuild network interface."
  type        = string
  default     = null
}

variable "private_subnet_ids" {
  description = "Private subnet IDs used when CodeBuild runs in a VPC."
  type        = list(string)
  default     = null

  validation {
    condition     = var.vpc_id == null ? var.private_subnet_ids == null : length(var.private_subnet_ids) > 0
    error_message = "private_subnet_ids must be set with vpc_id and omitted without it."
  }
}

variable "codebuild_security_group_id" {
  description = "Security group assigned when CodeBuild runs in a VPC."
  type        = string
  default     = null

  validation {
    condition     = var.vpc_id == null ? var.codebuild_security_group_id == null : var.codebuild_security_group_id != null
    error_message = "codebuild_security_group_id must be set with vpc_id and omitted without it."
  }
}

variable "ecr_repository_url" {
  description = "ECR repository URL passed to build commands."
  type        = string
}

variable "eks_cluster_name" {
  description = "Name shared by the EKS cluster and its supporting resources."
  type        = string
}

variable "cloudwatch_log_group_name" {
  description = "CloudWatch Logs group name for the CodeBuild project."
  type        = string
}