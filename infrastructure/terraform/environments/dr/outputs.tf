output "primary_alb_dns" {
  description = "DNS do balanceador na regiao primaria"
  value       = module.primary.alb_dns_name
}

output "standby_alb_dns" {
  description = "DNS do balanceador na regiao standby"
  value       = module.standby.alb_dns_name
}

output "app_domain" {
  description = "Nome DNS publico com failover automatico"
  value       = var.domain_name
}

output "primary_db_endpoint" {
  value = aws_db_instance.primary.endpoint
}

output "replica_db_endpoint" {
  value = aws_db_instance.replica.endpoint
}

output "health_check_id" {
  value = aws_route53_health_check.primary.id
}

output "failover_lambda" {
  value = module.failover_controller.lambda_name
}
