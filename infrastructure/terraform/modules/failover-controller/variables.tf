# =============================================================
# Modulo: failover-controller
# -------------------------------------------------------------
# Uma pequena Lambda que reage ao alarme do health check da
# regiao primaria e executa a promocao automatica do standby:
#   1) promove a read replica RDS a base de dados independente
#   2) faz scale-up do Auto Scaling Group standby (0 -> N)
# O switch de DNS e feito automaticamente pelos registos de
# failover do Route 53 (nao precisa da Lambda para isso).
# =============================================================

variable "project" {
  type = string
}

variable "standby_asg_name" {
  description = "Nome do ASG na regiao standby a fazer scale-up"
  type        = string
}

variable "standby_desired_capacity" {
  description = "Capacidade a definir no standby durante o failover"
  type        = number
  default     = 2
}

variable "replica_identifier" {
  description = "Identificador da read replica RDS a promover"
  type        = string
}

variable "health_check_id" {
  description = "ID do Route 53 health check da regiao primaria"
  type        = string
}

variable "standby_region" {
  description = "Regiao AWS onde estao o ASG standby e a replica RDS"
  type        = string
}
