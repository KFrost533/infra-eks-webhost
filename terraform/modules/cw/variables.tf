variable "project_name" {
  description = "Short project name used in the CodeBuild log group name."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name used in the control plane log group name."
  type        = string
}

variable "retention_in_days" {
  description = "CloudWatch Logs retention period."
  type        = number
  default     = 30
}