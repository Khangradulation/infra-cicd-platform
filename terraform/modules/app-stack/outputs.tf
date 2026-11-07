output "name" {
  description = "Resource name prefix for this environment."
  value       = local.name
}

output "app_url" {
  description = "Application base URL."
  value       = module.alb.base_url
}

output "alb_name" {
  description = "ALB name."
  value       = module.alb.alb_name
}

output "cluster_name" {
  description = "ECS cluster."
  value       = module.ecs.cluster_name
}

output "service_name" {
  description = "ECS service."
  value       = module.ecs.service_name
}

output "task_definition_family" {
  description = "Task definition family CI deploys into."
  value       = module.ecs.task_definition_family
}

output "container_name" {
  description = "Container name in the task definition."
  value       = module.ecs.container_name
}

output "log_group_name" {
  description = "Application log group."
  value       = module.monitoring.log_group_name
}

output "alarm_topic_arn" {
  description = "Alarm SNS topic."
  value       = module.monitoring.alarm_topic_arn
}

output "dashboard_name" {
  description = "CloudWatch dashboard."
  value       = module.monitoring.dashboard_name
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.networking.vpc_id
}

output "nat_gateway_count" {
  description = "NAT gateways (cost driver)."
  value       = module.networking.nat_gateway_count
}
