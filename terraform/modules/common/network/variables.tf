variable "project_name" {
  description = "Short project name used in resource names."
  type        = string
}

variable "environment" {
  description = "Environment name used in resource names."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
  nullable    = false
}

variable "cluster_name" {
  description = "EKS cluster name used for subnet discovery tags."
  type        = string
}
