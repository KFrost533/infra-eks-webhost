variable "shared" {
  description = "The eks_shared output from the applied shared Terraform root."
  type = object({
    account_id                     = string
    aws_region                     = string
    project_name                   = string
    environment                    = string
    cluster_name                   = string
    website_repository_url         = string
    enable_fargate_control         = bool
    eks_cluster_role_arn           = string
    fargate_pod_execution_role_arn = string
    codebuild_role_arn             = string
    codebuild_role_name            = string
    github_oidc_provider_arn       = string
    codebuild_log_group_arn        = string
    codebuild_log_group_name       = string
    fargate_log_group_name         = string
    fargate_control_log_group_name = string
    github_connection_arn          = string
    ecr_repository_arn             = string
    ecr_repository_url             = string
    build_tools_repository_arn     = string
    build_tools_repository_url     = string
    fargate_control_role_arn       = string
    fargate_scheduler_role_arn     = string
    fargate_restore_role_arn       = string
    lambda_alerts_topic_arn        = string
  })

  validation {
    condition = !var.shared.enable_fargate_control || alltrue([
      var.shared.fargate_control_log_group_name != null,
      var.shared.fargate_control_role_arn != null,
      var.shared.fargate_scheduler_role_arn != null,
      var.shared.fargate_restore_role_arn != null,
      var.shared.lambda_alerts_topic_arn != null,
    ])
    error_message = "Apply the shared root with Fargate control enabled and refresh its outputs."
  }
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