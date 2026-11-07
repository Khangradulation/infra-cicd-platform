terraform {
  required_version = "~> 1.17.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.72"
    }
  }

  backend "s3" {
    key          = "shared/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
