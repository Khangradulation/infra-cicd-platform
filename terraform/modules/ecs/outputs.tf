output "cluster_name" {
  description = "ECS cluster name."
  value       = local.cluster_name
}

output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = local.cluster_arn
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.this.name
}

output "service_arn" {
  description = "ECS service ARN (scope deploy-role permissions to this)."
  value       = aws_ecs_service.this.id
}

output "task_definition_family" {
  description = "Task definition family; CI registers new revisions in it."
  value       = aws_ecs_task_definition.this.family
}

output "task_definition_arn" {
  description = "Terraform-managed task definition revision (CI may have deployed a newer one)."
  value       = aws_ecs_task_definition.this.arn
}

output "service_security_group_id" {
  description = "Security group attached to tasks."
  value       = aws_security_group.service.id
}

output "container_name" {
  description = "Application container name."
  value       = var.container_name
}

output "task_definition_container_definitions" {
  description = "Rendered container definitions JSON of the Terraform-managed revision."
  value       = aws_ecs_task_definition.this.container_definitions
}
