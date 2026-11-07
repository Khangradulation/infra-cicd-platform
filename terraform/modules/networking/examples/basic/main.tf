# Minimal usage: a 2-AZ VPC with a single NAT gateway.
# `terraform init -backend=false && terraform validate` works without credentials.
terraform {
  required_version = ">= 1.11.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

module "networking" {
  source = "../.."

  name             = "icp-example"
  vpc_cidr         = "10.99.0.0/16"
  az_count         = 2
  nat_gateway_mode = "single"
}

output "private_subnet_ids" {
  description = "Private subnets."
  value       = module.networking.private_subnet_ids
}
