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

variable "queue_arns" {
  type        = list(string)
  description = "SQS queue ARNs the app instances need to send/receive/delete messages on"
}