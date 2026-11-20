variable "project_name" {
  type = string
}

variable "schedule_enabled" {
  type     = bool
  default  = false
  nullable = false
}

variable "stop_alias_arn" {
  type = string
}

variable "scheduler_role_arn" {
  type = string
}
