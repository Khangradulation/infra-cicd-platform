# Composition of the reusable modules into one environment's application stack.
# Environment roots call this with environment-specific settings only.

locals {
  name = "${var.name_prefix}-${var.environment}"
}

data "aws_ecr_repository" "app" {
  name = var.ecr_repository_name
}

data "aws_iam_policy" "boundary" {
  count = var.permissions_boundary_name == null ? 0 : 1
  name  = var.permissions_boundary_name
}

locals {
  boundary_arn = var.permissions_boundary_name == null ? null : data.aws_iam_policy.boundary[0].arn
}

module "networking" {
  source = "../networking"

  name                     = local.name
  vpc_cidr                 = var.vpc_cidr
  az_count                 = var.az_count
  nat_gateway_mode         = var.nat_gateway_mode
  enable_flow_logs         = var.enable_flow_logs
  flow_logs_kms_key_arn    = module.monitoring.kms_key_arn
  flow_logs_retention_days = var.log_retention_days
  permissions_boundary_arn = local.boundary_arn
  tags                     = var.tags
}

module "alb" {
  source = "../alb"

  name                       = local.name
  vpc_id                     = module.networking.vpc_id
  vpc_cidr                   = module.networking.vpc_cidr
  public_subnet_ids          = module.networking.public_subnet_ids
  target_port                = var.container_port
  allowed_ingress_cidrs      = var.allowed_ingress_cidrs
  certificate_arn            = var.certificate_arn
  enable_deletion_protection = var.enable_deletion_protection
  enable_access_logs         = var.enable_alb_access_logs
  access_logs_force_destroy  = var.force_destroy_log_buckets
  tags                       = var.tags
}

module "monitoring" {
  source = "../monitoring"

  name                       = local.name
  log_retention_days         = var.log_retention_days
  cluster_name               = local.name # ecs module names the cluster and service <name>
  service_name               = local.name
  alb_arn_suffix             = module.alb.alb_arn_suffix
  target_group_arn_suffix    = module.alb.target_group_arn_suffix
  container_insights_enabled = var.enable_container_insights
  min_running_tasks          = var.min_capacity
  alarm_email_addresses      = var.alarm_email_addresses
  tags                       = var.tags
}

module "iam" {
  source = "../iam"

  name                     = local.name
  ecr_repository_arns      = [data.aws_ecr_repository.app.arn]
  log_group_arn            = module.monitoring.log_group_arn
  enable_execute_command   = var.enable_execute_command
  permissions_boundary_arn = local.boundary_arn
  tags                     = var.tags
}

module "ecs" {
  source = "../ecs"

  name                      = local.name
  vpc_id                    = module.networking.vpc_id
  private_subnet_ids        = module.networking.private_subnet_ids
  alb_security_group_id     = module.alb.security_group_id
  target_group_arn          = module.alb.target_group_arn
  container_image           = var.container_image
  container_port            = var.container_port
  cpu                       = var.cpu
  memory                    = var.memory
  cpu_architecture          = var.cpu_architecture
  desired_count             = var.desired_count
  min_capacity              = var.min_capacity
  max_capacity              = var.max_capacity
  fargate_spot_weight       = var.fargate_spot_weight
  enable_container_insights = var.enable_container_insights
  enable_execute_command    = var.enable_execute_command
  log_group_name            = module.monitoring.log_group_name
  execution_role_arn        = module.iam.execution_role_arn
  task_role_arn             = module.iam.task_role_arn
  environment_variables = merge(var.environment_variables, {
    APP_ENV   = var.environment
    LOG_LEVEL = var.environment == "prod" ? "INFO" : "DEBUG"
  })
  tags = var.tags
}
