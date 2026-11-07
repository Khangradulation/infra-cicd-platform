terraform {
  required_version = "~> 1.17.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.72"
    }
  }

  # LOCAL backend on purpose: this root creates the remote-state bucket.
  # The resulting terraform.tfstate is git-ignored. After the first apply you
  # may migrate it into the bucket it created — see backend.tf.example and
  # docs/setup.md ("Optional: migrate bootstrap state").
}

provider "aws" {
  region = var.region

  default_tags {
    tags = merge(var.tags, {
      Project   = "infra-cicd-platform"
      Component = "terraform-state"
      ManagedBy = "terraform"
    })
  }
}
