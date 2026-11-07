provider "aws" {
  region = var.region

  # Environment tag is REQUIRED: the CI apply role's KMS permissions are tag-scoped (ABAC).
  default_tags {
    tags = {
      Project     = "infra-cicd-platform"
      Environment = "prod"
      ManagedBy   = "terraform"
      Repository  = var.repository_tag
    }
  }
}
