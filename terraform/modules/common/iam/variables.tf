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
