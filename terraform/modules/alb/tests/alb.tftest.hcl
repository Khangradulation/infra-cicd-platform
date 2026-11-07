mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/icp-test-alb/0123456789abcdef"
      arn_suffix = "app/icp-test-alb/0123456789abcdef"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:111111111111:targetgroup/icp-test-tg/0123456789abcdef"
      arn_suffix = "targetgroup/icp-test-tg/0123456789abcdef"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_elb_service_account" {
    defaults = { arn = "arn:aws:iam::127311923021:root" }
  }
}

variables {
  name              = "icp-test"
  vpc_id            = "vpc-0123456789abcdef0"
  vpc_cidr          = "10.0.0.0/16"
  public_subnet_ids = ["subnet-aaaa", "subnet-bbbb"]
}

run "http_only_by_default" {
  command = apply

  assert {
    condition     = length(aws_lb_listener.http_forward) == 1 && length(aws_lb_listener.https) == 0 && length(aws_lb_listener.http_redirect) == 0
    error_message = "Without a certificate only the HTTP forward listener should exist."
  }
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.alb) == 1
    error_message = "Only port 80 should be open without a certificate."
  }
  assert {
    condition     = aws_lb.this.drop_invalid_header_fields
    error_message = "Invalid header fields must be dropped."
  }
  assert {
    condition     = aws_lb_target_group.app.target_type == "ip" && aws_lb_target_group.app.health_check[0].path == "/health"
    error_message = "Fargate target group must be ip-type with /health check."
  }
  assert {
    condition     = aws_vpc_security_group_egress_rule.alb_to_targets.from_port == 8080 && aws_vpc_security_group_egress_rule.alb_to_targets.cidr_ipv4 == "10.0.0.0/16"
    error_message = "ALB egress must be limited to the target port inside the VPC."
  }
}

run "https_redirect_and_access_logs" {
  command = apply

  variables {
    certificate_arn       = "arn:aws:acm:us-east-1:111111111111:certificate/abc"
    allowed_ingress_cidrs = ["203.0.113.0/24", "198.51.100.0/24"]
    enable_access_logs    = true
  }

  assert {
    condition     = length(aws_lb_listener.https) == 1 && length(aws_lb_listener.http_redirect) == 1 && length(aws_lb_listener.http_forward) == 0
    error_message = "With a certificate HTTP must redirect and HTTPS must forward."
  }
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.alb) == 4
    error_message = "Expected 2 CIDRs x 2 ports = 4 ingress rules."
  }
  assert {
    condition     = length(aws_s3_bucket.access_logs) == 1 && aws_s3_bucket_public_access_block.access_logs[0].block_public_policy
    error_message = "Access log bucket must exist and block public access."
  }
}

run "rejects_single_subnet" {
  command = plan
  variables {
    public_subnet_ids = ["subnet-aaaa"]
  }
  expect_failures = [var.public_subnet_ids]
}
