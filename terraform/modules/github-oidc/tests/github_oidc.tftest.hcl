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
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  github_owner       = "example-org"
  github_repository  = "example-repo"
  state_bucket_name  = "example-tfstate"
  state_kms_key_arn  = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000"
  ecr_repository_arn = "arn:aws:ecr:us-east-1:111111111111:repository/icp/app"
  allowed_regions    = ["us-east-1"]
}

run "default_subjects" {
  command = apply

  assert {
    condition     = jsonencode(output.trusted_subjects["plan"]) == jsonencode(["repo:example-org/example-repo:pull_request", "repo:example-org/example-repo:ref:refs/heads/main"])
    error_message = "Plan role must trust PRs and main only."
  }
  assert {
    condition     = jsonencode(output.trusted_subjects["deploy_prod"]) == jsonencode(["repo:example-org/example-repo:environment:production"])
    error_message = "Prod deploy role must trust only the production environment."
  }
  assert {
    condition     = jsonencode(output.trusted_subjects["apply_dev"]) == jsonencode(["repo:example-org/example-repo:environment:infra-dev"])
    error_message = "Dev apply role must trust only the infra-dev environment."
  }
  assert {
    condition     = jsonencode(output.trusted_subjects["ecr_push"]) == jsonencode(["repo:example-org/example-repo:ref:refs/heads/main"])
    error_message = "ECR push must be main-only."
  }
  assert {
    condition     = length(aws_iam_role.apply) == 3 && length(aws_iam_role.deploy) == 3
    error_message = "One apply and one deploy role per environment."
  }
}

run "ref_bound_subjects" {
  command = apply

  variables {
    oidc_subject_includes_ref = true
  }

  assert {
    condition = jsonencode(output.trusted_subjects["deploy_prod"]) == jsonencode([
      "repo:example-org/example-repo:environment:production:ref:refs/heads/main",
      "repo:example-org/example-repo:environment:production:ref:refs/tags/v*",
    ])
    error_message = "Prod deploy must be bound to main or release tags."
  }
  assert {
    condition     = jsonencode(output.trusted_subjects["deploy_staging"]) == jsonencode(["repo:example-org/example-repo:environment:staging:ref:refs/heads/main"])
    error_message = "Staging must not accept release-tag subjects."
  }
}

run "immutable_subject_prefix" {
  command = apply

  variables {
    oidc_sub_claim_prefix = "repo:example-org@123/example-repo@456"
  }

  assert {
    condition     = jsonencode(output.trusted_subjects["ecr_push"]) == jsonencode(["repo:example-org@123/example-repo@456:ref:refs/heads/main"])
    error_message = "Immutable subject prefix must replace the classic repo:<owner>/<repo> prefix."
  }
  assert {
    condition     = jsonencode(output.trusted_subjects["deploy_prod"]) == jsonencode(["repo:example-org@123/example-repo@456:environment:production"])
    error_message = "Environment subjects must use the immutable prefix too."
  }
}

run "rejects_wildcard_prefix" {
  command = plan
  variables {
    oidc_sub_claim_prefix = "repo:example-org/*"
  }
  expect_failures = [var.oidc_sub_claim_prefix]
}

run "existing_provider" {
  command = apply
  variables {
    create_oidc_provider       = false
    existing_oidc_provider_arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
  }
  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0 && output.oidc_provider_arn == var.existing_oidc_provider_arn
    error_message = "Should reuse the existing provider."
  }
}

run "rejects_bad_owner" {
  command = plan
  variables {
    github_owner = "bad owner!"
  }
  expect_failures = [var.github_owner]
}
