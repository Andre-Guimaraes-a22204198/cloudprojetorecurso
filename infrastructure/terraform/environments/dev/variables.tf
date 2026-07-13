variable "project" {
  type    = string
  default = "cloudprojetofinal"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "key_name" {
  type        = string
  description = "EC2 Key Pair name for SSH access"
}