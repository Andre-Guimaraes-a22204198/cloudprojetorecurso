variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "app_security_group_id" {
  type = string
}

variable "key_name" {
  type = string
}