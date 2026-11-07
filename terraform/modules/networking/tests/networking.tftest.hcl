mock_provider "aws" {
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:111111111111:log-group:/vpc/icp-test/flow-logs" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/icp-test-vpc-flow-logs" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"] }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
}

variables {
  name     = "icp-test"
  vpc_cidr = "10.20.0.0/16"
}

run "single_nat_two_azs" {
  command = apply

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2
    error_message = "Expected 2 public and 2 private subnets."
  }
  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "single mode must create exactly one NAT gateway."
  }
  assert {
    condition     = length(aws_route.private_nat) == 2
    error_message = "Every private route table needs a default route."
  }
  assert {
    condition     = aws_subnet.private[0].cidr_block == "10.20.128.0/20" && aws_subnet.public[0].cidr_block == "10.20.0.0/20"
    error_message = "Subnet carving changed unexpectedly."
  }
  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch == false])
    error_message = "Public subnets must not auto-assign public IPs."
  }
  assert {
    condition     = length(aws_flow_log.this) == 0
    error_message = "Flow logs are off by default."
  }
}

run "per_az_nat_with_flow_logs" {
  command = apply

  variables {
    az_count         = 3
    nat_gateway_mode = "per_az"
    enable_flow_logs = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "per_az mode must create one NAT gateway per AZ."
  }
  assert {
    condition     = length(aws_flow_log.this) == 1 && aws_flow_log.this[0].traffic_type == "ALL"
    error_message = "Flow logs should capture ALL traffic when enabled."
  }
}

run "no_nat" {
  command = apply

  variables {
    nat_gateway_mode = "none"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_route.private_nat) == 0
    error_message = "none mode must not create NAT gateways or default routes."
  }
}

run "rejects_single_az" {
  command = plan

  variables {
    az_count = 1
  }

  expect_failures = [var.az_count]
}

run "rejects_bad_nat_mode" {
  command = plan

  variables {
    nat_gateway_mode = "two"
  }

  expect_failures = [var.nat_gateway_mode]
}
