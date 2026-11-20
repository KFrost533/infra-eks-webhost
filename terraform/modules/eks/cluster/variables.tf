variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.36"
  nullable    = false
}

variable "cluster_role_arn" {
  description = "IAM role ARN assumed by the EKS control plane."
  type        = string
}

variable "fargate_pod_execution_role_arn" {
  description = "IAM role ARN used by EKS Fargate pods to pull images and write logs."
  type        = string
}

variable "codebuild_role_arn" {
  description = "CodeBuild IAM role ARN granted access to the website namespace."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the EKS control plane and Fargate profiles."
  type        = list(string)
}

variable "cluster_public_access_cidrs" {
  description = "IPv4 CIDR blocks allowed to reach the public Kubernetes API endpoint."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "codebuild_security_group_id" {
  description = "Security group ID for CodeBuild access to the private EKS API endpoint."
  type        = string
}