variable "project" {
  type    = string
  default = "cloudprojetofinal"
}

variable "primary_region" {
  type    = string
  default = "eu-west-1"
}

variable "standby_region" {
  type    = string
  default = "eu-central-1"
}

variable "db_password" {
  description = "Password inicial do RDS. Lido a partir do SSM/Secrets, nunca hardcoded no codigo."
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Nome DNS da aplicacao gerido pelo Route 53 (ex: app.exemplo.com)"
  type        = string
}

variable "hosted_zone_id" {
  description = "ID da hosted zone Route 53 ja existente para o dominio"
  type        = string
}
