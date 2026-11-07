# PROD — stronger availability and security:
#   * NAT gateway per AZ (no cross-AZ egress SPOF)
#   * >= 2 tasks spread across AZs, larger task size, higher autoscaling ceiling
#   * Container Insights (+ RunningTaskCount alarm), VPC flow logs, ALB access logs
#   * ALB deletion protection, no ECS Exec, 90-day log retention
module "stack" {
  source = "../../modules/app-stack"

  permissions_boundary_name = var.permissions_boundary_name == "" ? null : var.permissions_boundary_name
  cpu_architecture          = var.cpu_architecture

  environment = "prod"

  vpc_cidr         = "10.30.0.0/16"
  az_count         = 2 # raise to 3 for AZ-loss tolerance with headroom (+1 NAT, ~USD 37/month)
  nat_gateway_mode = "per_az"
  enable_flow_logs = true

  allowed_ingress_cidrs      = var.allowed_ingress_cidrs
  certificate_arn            = var.certificate_arn
  enable_deletion_protection = true
  enable_alb_access_logs     = true
  force_destroy_log_buckets  = false

  container_image           = var.container_image
  cpu                       = 512
  memory                    = 1024
  desired_count             = 2
  min_capacity              = 2
  max_capacity              = 6
  fargate_spot_weight       = 0
  enable_container_insights = true
  enable_execute_command    = false

  log_retention_days    = 90
  alarm_email_addresses = var.alarm_email_addresses
}

check "prod_should_use_https" {
  assert {
    condition     = var.certificate_arn != null
    error_message = "Production is serving plain HTTP. Set certificate_arn (ACM) before sending real traffic."
  }
}
