# DEV — cheapest viable footprint: 2 AZs, one NAT, one small task.
module "stack" {
  source = "../../modules/app-stack"

  permissions_boundary_name = var.permissions_boundary_name == "" ? null : var.permissions_boundary_name
  cpu_architecture          = var.cpu_architecture

  environment = "dev"

  vpc_cidr         = "10.10.0.0/16"
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
  max_capacity              = 2
  fargate_spot_weight       = 0 # set e.g. 3 to run mostly on Spot (~70% cheaper, can be interrupted)
  enable_container_insights = false
  enable_execute_command    = true

  log_retention_days    = 14
  alarm_email_addresses = var.alarm_email_addresses
}
