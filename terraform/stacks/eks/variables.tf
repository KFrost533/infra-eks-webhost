variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = null
}

variable "cluster_admin_cidrs" {
  description = "Additional IPv4 CIDR blocks allowed to reach the public EKS API endpoint."
  type        = list(string)
  default     = null

  validation {
    condition     = var.cluster_admin_cidrs == null ? true : alltrue([for cidr in var.cluster_admin_cidrs : can(cidrnetmask(cidr))])
    error_message = "Every cluster_admin_cidrs entry must be a valid IPv4 CIDR block."
  }
}

variable "enable_fargate_stop_schedule" {
  description = "Enable daily 17:00 JST Fargate shutdown after RBAC and recovery have been tested."
  type        = bool
  default     = null
}