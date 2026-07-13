# =============================================================
# Modulo reutilizavel: region-stack
# -------------------------------------------------------------
# Provisiona a rede + balanceador (ALB) + grupo de auto-scaling
# de UMA regiao. E instanciado duas vezes no ambiente DR:
#   - primary  (desired_capacity > 0  -> esta a servir trafego)
#   - standby  (desired_capacity = 0  -> pilot-light, arranca so no failover)
# =============================================================

variable "project" {
  description = "Nome do projeto"
  type        = string
}

variable "role" {
  description = "Papel desta stack: primary ou standby"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR da VPC desta regiao (tem de ser diferente entre regioes)"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets publicas"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas"
  type        = list(string)
}

variable "availability_zones" {
  description = "AZs desta regiao (ex: [eu-west-1a, eu-west-1b])"
  type        = list(string)
}

variable "desired_capacity" {
  description = "Numero de instancias a correr. Primary=2, Standby=0 (pilot-light)"
  type        = number
}

variable "instance_type" {
  description = "Tipo de instancia EC2"
  type        = string
  default     = "t3.micro"
}

variable "app_image" {
  description = "Imagem Docker do api-gateway a correr nas instancias"
  type        = string
  default     = "andreguimaraes2/api-gateway:latest"
}
