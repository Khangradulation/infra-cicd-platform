data "aws_region" "current" {}

locals {
  cluster_name = var.create_cluster ? aws_ecs_cluster.this[0].name : var.cluster_name
  cluster_arn  = var.create_cluster ? aws_ecs_cluster.this[0].arn : data.aws_ecs_cluster.existing[0].arn

  capacity_providers = var.fargate_spot_weight > 0 ? ["FARGATE", "FARGATE_SPOT"] : ["FARGATE"]

  container_definitions = [
    {
      name                   = var.container_name
      image                  = var.container_image
      essential              = true
      readonlyRootFilesystem = true
      portMappings = [{
        containerPort = var.container_port
        protocol      = "tcp"
        name          = "http"
      }]
      environment = [for k in sort(keys(var.environment_variables)) : { name = k, value = var.environment_variables[k] }]
      secrets     = [for k in sort(keys(var.secrets)) : { name = k, valueFrom = var.secrets[k] }]
      mountPoints = [{ sourceVolume = "tmp", containerPath = "/tmp", readOnly = false }]
      linuxParameters = {
        initProcessEnabled = true
        capabilities       = { drop = ["ALL"] }
      }
      healthCheck = {
        command     = ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:${var.container_port}/health', timeout=3)"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = var.container_name
          mode                  = "non-blocking"
          max-buffer-size       = "4m"
        }
      }
    }
  ]
}

# ------------------------------------------------------------- Cluster

resource "aws_ecs_cluster" "this" {
  #checkov:skip=CKV_AWS_65:Exception SEC-09: Container Insights is a per-env toggle (cost); enabled in prod
  count = var.create_cluster ? 1 : 0

  name = var.name

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = var.tags
}

data "aws_ecs_cluster" "existing" {
  count        = var.create_cluster ? 0 : 1
  cluster_name = var.cluster_name
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  count = var.create_cluster ? 1 : 0

  cluster_name       = aws_ecs_cluster.this[0].name
  capacity_providers = local.capacity_providers

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# -------------------------------------------------------- Security group

resource "aws_security_group" "service" {
  name        = "${var.name}-service"
  description = "${var.name} tasks: ingress only from the ALB on the container port"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-service" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.service.id
  description                  = "App port from ALB only"
  referenced_security_group_id = var.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
}

# trivy:ignore:AWS-0104 Exception SEC-10: 443-only egress via NAT to ECR/CloudWatch/STS; narrow with var.egress_cidrs when using VPC endpoints
resource "aws_vpc_security_group_egress_rule" "https" {
  for_each = toset(var.egress_cidrs)

  security_group_id = aws_security_group.service.id
  description       = "HTTPS egress (ECR, CloudWatch Logs, STS)"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# ------------------------------------------------------ Task definition

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  # Writable scratch space; the root filesystem is read-only.
  volume {
    name = "tmp"
  }

  container_definitions = jsonencode(local.container_definitions)

  tags = var.tags
}

# -------------------------------------------------------------- Service

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = local.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  enable_execute_command             = var.enable_execute_command
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  wait_for_steady_state              = var.wait_for_steady_state
  availability_zone_rebalancing      = "ENABLED"

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = var.fargate_spot_weight > 0 ? 1 : 100
    base              = 1
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.fargate_spot_weight > 0 ? [1] : []
    content {
      capacity_provider = "FARGATE_SPOT"
      weight            = var.fargate_spot_weight
    }
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  # Failed deployments (tasks that never become healthy) roll back automatically.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  tags = var.tags

  lifecycle {
    # CI owns the running image (new task-definition revisions); autoscaling owns the count.
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_ecs_cluster_capacity_providers.this]
}

# ---------------------------------------------------------- Autoscaling

resource "aws_appautoscaling_target" "this" {
  count = var.enable_autoscaling ? 1 : 0

  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${local.cluster_name}/${aws_ecs_service.this.name}"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity

  tags = var.tags
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.enable_autoscaling ? 1 : 0

  name               = "${var.name}-cpu-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[0].resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.cpu_target_percent
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "memory" {
  count = var.enable_autoscaling ? 1 : 0

  name               = "${var.name}-memory-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[0].resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.memory_target_percent
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}
