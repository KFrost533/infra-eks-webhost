variable "function_name" {
  type = string
}

variable "log_group_name" {
  type = string
}

variable "failure_pattern" {
  description = "CloudWatch Logs filter pattern for explicit application failures."
  type        = string
  default     = "\"FARGATE_CONTROL_FAILURE\""
}

variable "sns_topic_arn" {
  type = string
}

variable "event_bus_name" {
  type    = string
  default = ""
}

variable "event_rule_names" {
  type    = map(string)
  default = {}
}
