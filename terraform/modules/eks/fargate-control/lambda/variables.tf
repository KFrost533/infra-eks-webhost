variable "project_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "function_role_arn" {
  type = string
}

variable "security_group_id" {
  type        = string
}

