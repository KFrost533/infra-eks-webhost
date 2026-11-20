variable "aws_region" {
  description = "AWS region for the infrastructure."
  type        = string
  default     = "ap-southeast-2"
}

variable "project_name" {
  description = "Short project name used in resource names and tags."
  type        = string
  default     = "infra-eks-webhost"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "infra-eks-webhost"
}

variable "enable_fargate_control" {
  description = "Prepare the shared log group and enable Fargate control in the EKS stack."
  type        = bool
  default     = false
}

variable "website_repository_url" {
  description = "GitHub HTTPS repository URL trusted by the Fargate control GitHub Actions role."
  type        = string
  default     = "https://github.com/KFrost533/infra-eks-webhost"

  validation {
    condition     = can(regex("^https://github\\.com/[^/]+/[^/]+/?$", var.website_repository_url))
    error_message = "website_repository_url must be a GitHub HTTPS repository URL."
  }
}
