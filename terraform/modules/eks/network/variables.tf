variable "project_name" {
  description = "Short project name used in resource names."
  type        = string
}

variable "environment" {
  description = "Environment name used in resource names."
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID for the NAT gateway."
  type        = string
}

variable "private_route_table_id" {
  description = "Private route table receiving the internet route."
  type        = string
}
