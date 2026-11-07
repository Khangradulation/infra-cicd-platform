mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:us-east-1:111111111111:icp-test-alarms" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::111111111111:policy/icp-workload-boundary" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  name                    = "icp-test"
  cluster_name            = "icp-test"
  service_name            = "icp-test"
  alb_arn_suffix          = "app/icp-test-alb/0123456789abcdef"
  target_group_arn_suffix = "targetgroup/icp-test-tg/0123456789abcdef"
}

run "baseline_alarms_without_container_insights" {
  command = apply

  assert {
    condition     = length(output.alarm_names) == 8
    error_message = "Expected the 8 baseline alarms."
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.running_tasks_low) == 0
    error_message = "RunningTaskCount alarm must not exist without Container Insights (metric would never report)."
  }
  assert {
    condition     = aws_cloudwatch_log_group.app.retention_in_days == 14
    error_message = "Default retention should be 14 days."
  }
  assert {
    condition     = length(aws_kms_key.this) == 1 && aws_kms_key.this[0].enable_key_rotation
    error_message = "A rotating CMK should be created by default."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.unhealthy_targets.dimensions["TargetGroup"] == var.target_group_arn_suffix
    error_message = "Unhealthy target alarm must use the target group dimension."
  }
}

run "container_insights_adds_task_alarm" {
  command = apply
  variables {
    container_insights_enabled = true
    alarm_email_addresses      = ["ops@example.com"]
  }
  assert {
    condition     = length(output.alarm_names) == 9
    error_message = "RunningTaskCount alarm expected with Container Insights."
  }
  assert {
    condition     = length(aws_sns_topic_subscription.email) == 1
    error_message = "Email subscription expected."
  }
}

run "rejects_invalid_retention" {
  command = plan
  variables {
    log_retention_days = 10
  }
  expect_failures = [var.log_retention_days]
}
