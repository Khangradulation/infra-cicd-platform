terraform {
  required_version = "~> 1.17.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.72"
    }
  }

  # bucket, region and kms_key_id come from -backend-config (backend.hcl locally,
  # GitHub variables in CI) so no account-specific values are committed.
  backend "s3" {
    key          = "prod/terraform.tfstate"
    encrypt      = true
    use_lockfile = true # native S3 locking (writes prod/terraform.tfstate.tflock)
  }
}
