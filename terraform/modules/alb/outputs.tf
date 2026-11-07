output "alb_arn" {
  description = "ARN of the load balancer."
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ARN suffix used as the LoadBalancer CloudWatch dimension."
  value       = aws_lb.this.arn_suffix
}

output "alb_name" {
  description = "Load balancer name (deploy workflow looks the DNS name up by this)."
  value       = aws_lb.this.name
}

output "alb_dns_name" {
  description = "Public DNS name of the ALB."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Route 53 hosted zone ID of the ALB (for alias records)."
  value       = aws_lb.this.zone_id
}

output "security_group_id" {
  description = "ALB security group ID; the app SG allows ingress only from this."
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "Target group ARN the ECS service registers into."
  value       = aws_lb_target_group.app.arn
}

output "target_group_arn_suffix" {
  description = "ARN suffix used as the TargetGroup CloudWatch dimension."
  value       = aws_lb_target_group.app.arn_suffix
}

output "listener_arn" {
  description = "ARN of the listener that forwards to the app (HTTPS if enabled, else HTTP)."
  value       = local.https_enabled ? aws_lb_listener.https[0].arn : aws_lb_listener.http_forward[0].arn
}

output "base_url" {
  description = "URL clients should use."
  value       = local.https_enabled ? "https://${aws_lb.this.dns_name}" : "http://${aws_lb.this.dns_name}"
}
