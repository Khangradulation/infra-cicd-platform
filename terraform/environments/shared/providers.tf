provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "infra-cicd-platform"
      Environment = "shared"
      ManagedBy   = "terraform"
      Repository  = "${var.github_owner}/${var.github_repository}"
    }
  }
}
