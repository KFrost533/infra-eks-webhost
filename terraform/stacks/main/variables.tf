variable "aws_region" {
  description = "AWS region for the infrastructure."
  type        = string
  default     = "ap-southeast-1"
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

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.36"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_admin_cidrs" {
  description = "Additional IPv4 CIDR blocks allowed to reach the public EKS API endpoint."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.cluster_admin_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every cluster_admin_cidrs entry must be a valid IPv4 CIDR block."
  }
}

variable "website_repository_url" {
  description = "GitHub HTTPS URL for the website source for CodeBuild."
  type        = string
  default     = "https://github.com/KFrost533/infra-eks-webhost"

  validation {
    condition     = can(regex("^https://github\\.com/[^/]+/[^/]+/?$", var.website_repository_url))
    error_message = "website_repository_url must be a GitHub HTTPS repository URL."
  }
}

variable "website_repository_branch" {
  description = "Git branch CodeBuild uses as its source."
  type        = string
  default     = "main"

  validation {
    condition     = var.website_repository_branch == "main"
    error_message = "The deployment webhook is restricted to the main branch."
  }
}

variable "buildspec_path" {
  description = "Buildspec path relative to the repository root."
  type        = string
  default     = "buildspec.yml"
}

variable "enable_github_webhook" {
  description = "Enable GitHub push-triggered CodeBuild after authorizing the connection."
  type        = bool
  default     = false
}

variable "enable_weekly_report" {
  description = "Enable the weekly SES report CronJob after its secrets and SES identity are configured."
  type        = bool
  default     = false
}

variable "build_tools_image_tag" {
  description = "Immutable tag for the private CodeBuild tools image."
  type        = string
  default     = "tools-v1"
}

variable "enable_fargate_stop_schedule" {
  description = "Enable daily 17:00 JST Fargate shutdown after RBAC and recovery have been tested."
  type        = bool
  default     = false
}