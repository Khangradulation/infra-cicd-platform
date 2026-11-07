# Plan-level composition test with a mocked provider (no AWS credentials).
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_ecr_repository" {
    defaults = { arn = "arn:aws:ecr:us-east-1:111111111111:repository/icp/app" }
  }
  mock_data "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::111111111111:policy/icp-workload-boundary" }
  }
  mock_data "aws_elb_service_account" {
    defaults = { arn = "arn:aws:iam::127311923021:root" }
  }
}

variables {
  container_image = "111111111111.dkr.ecr.us-east-1.amazonaws.com/icp/app@sha256:1111111111111111111111111111111111111111111111111111111111111111"
}

run "dev_profile" {
  command = plan

  variables {
    environment = "dev"
    vpc_cidr    = "10.10.0.0/16"
  }

  assert {
    condition     = module.networking.nat_gateway_count == 1
    error_message = "dev should run a single NAT gateway."
  }
  assert {
    condition     = output.name == "icp-dev"
    error_message = "Naming contract <prefix>-<env> broken (CI IAM scoping depends on it)."
  }
  assert {
    condition     = jsondecode(module.ecs.task_definition_container_definitions)[0].environment[0].name == "APP_ENV"
    error_message = "APP_ENV must be injected."
  }
}

run "prod_profile" {
  command = plan

  variables {
    environment                = "prod"
    vpc_cidr                   = "10.30.0.0/16"
    nat_gateway_mode           = "per_az"
    enable_flow_logs           = true
    enable_deletion_protection = true
    enable_alb_access_logs     = true
    enable_container_insights  = true
    min_capacity               = 2
    desired_count              = 2
  }

  assert {
    condition     = module.networking.nat_gateway_count == 2
    error_message = "prod should run one NAT gateway per AZ."
  }
}
