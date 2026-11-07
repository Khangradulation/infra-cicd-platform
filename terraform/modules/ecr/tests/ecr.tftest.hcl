mock_provider "aws" {}

variables {
  name = "icp/app"
}

run "defaults_are_immutable_and_scanned" {
  command = apply

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE"
    error_message = "Tags must be immutable."
  }
  assert {
    condition     = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push
    error_message = "scan_on_push should default to true."
  }
  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].encryption_type == "AES256"
    error_message = "Default encryption should be AES256."
  }
  assert {
    condition     = length(jsondecode(aws_ecr_lifecycle_policy.this.policy).rules) == 2
    error_message = "Lifecycle policy should have untagged + count rules."
  }
  assert {
    condition     = length(aws_ecr_repository_policy.this) == 0
    error_message = "No repository policy without extra principals."
  }
}

run "kms_encryption" {
  command = apply

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].encryption_type == "KMS"
    error_message = "Providing a key must switch to KMS encryption."
  }
}

run "rejects_uppercase_name" {
  command = plan
  variables {
    name = "ICP/App"
  }
  expect_failures = [var.name]
}
