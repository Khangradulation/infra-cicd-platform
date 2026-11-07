# STAGING — production-like topology at small scale; integration tests run here.
module "stack" {
  source = "../../modules/app-stack"

  environment = "staging"

  vpc_cidr         = "10.20.0.0/16"
  az_count         = 2
  nat_gateway_mode = "single"
  enable_flow_logs = false

  allowed_ingress_cidrs      = var.allowed_ingress_cidrs
  certificate_arn            = var.certificate_arn
  enable_deletion_protection = false
  enable_alb_access_logs     = false
  force_destroy_log_buckets  = true

  container_image           = var.container_image
  cpu                       = 256
  memory                    = 512
  desired_count             = 1
  min_capacity              = 1
  max_capacity              = 3
  enable_container_insights = false
  enable_execute_command    = false

  log_retention_days    = 30
  alarm_email_addresses = var.alarm_email_addresses
}
