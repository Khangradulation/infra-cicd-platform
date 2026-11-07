output "app_url" {
  description = "Application base URL."
  value       = module.stack.app_url
}

output "alb_name" {
  description = "ALB name (deploy workflow discovers the URL from it)."
  value       = module.stack.alb_name
}

output "cluster_name" {
  description = "ECS cluster."
  value       = module.stack.cluster_name
}

output "service_name" {
  description = "ECS service."
  value       = module.stack.service_name
}

output "task_definition_family" {
  description = "Task definition family."
  value       = module.stack.task_definition_family
}

output "container_name" {
  description = "Container name."
  value       = module.stack.container_name
}

output "log_group_name" {
  description = "Application log group."
  value       = module.stack.log_group_name
}

output "dashboard_name" {
  description = "CloudWatch dashboard."
  value       = module.stack.dashboard_name
}

output "nat_gateway_count" {
  description = "NAT gateways running (each ~USD 33/month + data)."
  value       = module.stack.nat_gateway_count
}
