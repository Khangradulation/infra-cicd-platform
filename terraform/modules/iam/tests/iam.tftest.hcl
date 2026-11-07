mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

variables {
  name                     = "icp-test"
  ecr_repository_arns      = ["arn:aws:ecr:us-east-1:111111111111:repository/icp/app"]
  log_group_arn            = "arn:aws:logs:us-east-1:111111111111:log-group:/ecs/icp-test"
  permissions_boundary_arn = "arn:aws:iam::111111111111:policy/icp-workload-boundary"
}

run "separate_roles_with_boundary" {
  command = apply

  assert {
    condition     = aws_iam_role.execution.name == "icp-test-task-execution" && aws_iam_role.task.name == "icp-test-task"
    error_message = "Role names must follow <name>-task[-execution]."
  }
  assert {
    condition     = aws_iam_role.execution.permissions_boundary == var.permissions_boundary_arn && aws_iam_role.task.permissions_boundary == var.permissions_boundary_arn
    error_message = "Both roles must carry the permissions boundary."
  }
  assert {
    condition     = length(aws_iam_role_policy.task_custom) == 0 && length(aws_iam_role_policy.exec_command) == 0
    error_message = "Task role must have no permissions by default."
  }
}

run "exec_command_adds_ssm_channel" {
  command = apply
  variables {
    enable_execute_command = true
  }
  assert {
    condition     = length(aws_iam_role_policy.exec_command) == 1
    error_message = "ECS Exec permissions expected."
  }
}

run "rejects_non_ecr_arn" {
  command = plan
  variables {
    ecr_repository_arns = ["arn:aws:s3:::bucket"]
  }
  expect_failures = [var.ecr_repository_arns]
}
