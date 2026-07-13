output "vpc_id" {
  value = module.vpc.vpc_id
}

output "instance_public_ips" {
  value = module.compute.instance_public_ips
}

output "db_endpoint" {
  value = module.database.db_endpoint
}

output "sqs_queue_url" {
  value = module.queue.order_created_queue_url
}