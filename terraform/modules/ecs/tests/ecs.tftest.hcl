mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
}

variables {
  name                  = "icp-test"
  vpc_id                = "vpc-0123456789abcdef0"
  private_subnet_ids    = ["subnet-aaaa", "subnet-bbbb"]
  alb_security_group_id = "sg-0123456789abcdef0"
  target_group_arn      = "arn:aws:elasticloadbalancing:us-east-1:111111111111:targetgroup/icp-test-tg/abc"
  container_image       = "111111111111.dkr.ecr.us-east-1.amazonaws.com/icp/app@sha256:0000000000000000000000000000000000000000000000000000000000000000"
  log_group_name        = "/ecs/icp-test"
  execution_role_arn    = "arn:aws:iam::111111111111:role/icp-test-task-execution"
  task_role_arn         = "arn:aws:iam::111111111111:role/icp-test-task"
  environment_variables = { APP_ENV = "test" }
}

run "secure_task_and_service_defaults" {
  command = apply

  assert {
    condition     = aws_ecs_service.this.network_configuration[0].assign_public_ip == false
    error_message = "Tasks must not get public IPs."
  }
  assert {
    condition     = aws_ecs_service.this.deployment_circuit_breaker[0].enable && aws_ecs_service.this.deployment_circuit_breaker[0].rollback
    error_message = "Circuit breaker with rollback must be enabled."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].readonlyRootFilesystem == true
    error_message = "Root filesystem must be read-only."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].image == var.container_image
    error_message = "Task definition must use the digest-pinned image."
  }
  assert {
    condition     = aws_ecs_task_definition.this.execution_role_arn != aws_ecs_task_definition.this.task_role_arn
    error_message = "Execution role and task role must be different."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.from_alb.referenced_security_group_id == var.alb_security_group_id && aws_vpc_security_group_ingress_rule.from_alb.from_port == 8080
    error_message = "Service SG must only allow the container port from the ALB SG."
  }
  assert {
    condition     = length(aws_appautoscaling_policy.cpu) == 1 && length(aws_appautoscaling_policy.memory) == 1
    error_message = "CPU and memory target tracking expected."
  }
}

run "spot_weighting" {
  command = apply
  variables {
    fargate_spot_weight = 3
  }
  assert {
    condition     = length(aws_ecs_service.this.capacity_provider_strategy) == 2
    error_message = "Spot weight should add a FARGATE_SPOT strategy."
  }
}

run "rejects_mutable_tag" {
  command = plan
  variables {
    container_image = "111111111111.dkr.ecr.us-east-1.amazonaws.com/icp/app:latest"
  }
  expect_failures = [var.container_image]
}

run "rejects_invalid_cpu" {
  command = plan
  variables {
    cpu = 300
  }
  expect_failures = [var.cpu]
}
