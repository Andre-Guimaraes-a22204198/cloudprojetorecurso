# =============================================================
# Ambiente DR :: junta tudo
#   primary region-stack  (a servir)   +  RDS primaria
#   standby region-stack  (pilot-light) + RDS read replica cross-region
#   Route 53 health check + registos de failover
#   failover-controller (Lambda) em us-east-1
# =============================================================

# ---------- Segredos (SSM Parameter Store, nunca hardcoded) ----------
resource "aws_ssm_parameter" "db_password_primary" {
  name  = "/${var.project}/dr/db_password"
  type  = "SecureString"
  value = var.db_password
}

resource "aws_ssm_parameter" "db_password_standby" {
  provider = aws.standby
  name     = "/${var.project}/dr/db_password"
  type     = "SecureString"
  value    = var.db_password
}

# ---------- Compute + rede das duas regioes (mesmo modulo) ----------
module "primary" {
  source               = "../../modules/region-stack"
  project              = var.project
  role                 = "primary"
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  availability_zones   = ["${var.primary_region}a", "${var.primary_region}b"]
  desired_capacity     = 2 # esta a servir trafego
}

module "standby" {
  source               = "../../modules/region-stack"
  providers            = { aws = aws.standby }
  project              = var.project
  role                 = "standby"
  vpc_cidr             = "10.1.0.0/16"
  public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]
  availability_zones   = ["${var.standby_region}a", "${var.standby_region}b"]
  desired_capacity     = 0 # pilot-light: arranca so no failover
}

# ---------- Base de dados: primaria + read replica cross-region ----------
resource "aws_db_instance" "primary" {
  identifier              = "${var.project}-primary-db"
  engine                  = "postgres"
  engine_version          = "15"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  db_name                 = "appdb"
  username                = "appuser"
  password                = var.db_password
  db_subnet_group_name    = module.primary.db_subnet_group_name
  vpc_security_group_ids  = [module.primary.db_security_group_id]
  backup_retention_period = 1 # obrigatorio (>0) para permitir read replicas
  multi_az                = true # resiliencia a falha de UMA AZ na primaria
  skip_final_snapshot     = true
  publicly_accessible     = false
  tags                    = { Name = "${var.project}-primary-db" }
}

resource "aws_db_instance" "replica" {
  provider               = aws.standby
  identifier             = "${var.project}-standby-replica"
  instance_class         = "db.t3.micro"
  replicate_source_db    = aws_db_instance.primary.arn
  db_subnet_group_name   = module.standby.db_subnet_group_name
  vpc_security_group_ids = [module.standby.db_security_group_id]
  skip_final_snapshot    = true
  publicly_accessible    = false
  tags                   = { Name = "${var.project}-standby-replica" }
}

# ---------- Route 53: health check + failover DNS ----------
resource "aws_route53_health_check" "primary" {
  fqdn              = module.primary.alb_dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/actuator/health"
  request_interval  = 30
  failure_threshold = 3
  tags              = { Name = "${var.project}-primary-hc" }
}

resource "aws_route53_record" "primary" {
  zone_id        = var.hosted_zone_id
  name           = var.domain_name
  type           = "A"
  set_identifier = "primary"

  failover_routing_policy {
    type = "PRIMARY"
  }
  health_check_id = aws_route53_health_check.primary.id

  alias {
    name                   = module.primary.alb_dns_name
    zone_id                = module.primary.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  zone_id        = var.hosted_zone_id
  name           = var.domain_name
  type           = "A"
  set_identifier = "secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = module.standby.alb_dns_name
    zone_id                = module.standby.alb_zone_id
    evaluate_target_health = true
  }
}

# ---------- Controlador de failover (Lambda em us-east-1) ----------
module "failover_controller" {
  source                   = "../../modules/failover-controller"
  providers                = { aws = aws.useast1 }
  project                  = var.project
  standby_region           = var.standby_region
  standby_asg_name         = module.standby.asg_name
  standby_desired_capacity = 2
  replica_identifier       = aws_db_instance.replica.identifier
  health_check_id          = aws_route53_health_check.primary.id
}
