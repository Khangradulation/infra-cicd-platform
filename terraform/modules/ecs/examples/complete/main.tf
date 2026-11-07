# Complete wiring of networking + alb + monitoring + iam + ecs for one service,
# using an existing ECR repository and an image already pushed to it.
# The environment roots under terraform/environments/ follow the same pattern.
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

variable "ecr_repository_name" {
  description = "Existing ECR repository holding the image."
  type        = string
  default     = "icp/app"
}

variable "container_image" {
  description = "Digest-pinned image, e.g. <account>.dkr.ecr.<region>.amazonaws.com/icp/app@sha256:<digest>."
  type        = string
}

locals {
  name = "icp-example"
}

data "aws_ecr_repository" "app" {
  name = var.ecr_repository_name
}

module "networking" {
  source = "../../../networking"
  name   = local.name
}

module "alb" {
  source            = "../../../alb"
  name              = local.name
  vpc_id            = module.networking.vpc_id
  vpc_cidr          = module.networking.vpc_cidr
  public_subnet_ids = module.networking.public_subnet_ids
}

module "monitoring" {
  source                  = "../../../monitoring"
  name                    = local.name
  cluster_name            = local.name
  service_name            = local.name
  alb_arn_suffix          = module.alb.alb_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
}

module "iam" {
  source              = "../../../iam"
  name                = local.name
  ecr_repository_arns = [data.aws_ecr_repository.app.arn]
  log_group_arn       = module.monitoring.log_group_arn
}

module "ecs" {
  source                = "../.."
  name                  = local.name
  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnet_ids
  alb_security_group_id = module.alb.security_group_id
  target_group_arn      = module.alb.target_group_arn
  container_image       = var.container_image
  log_group_name        = module.monitoring.log_group_name
  execution_role_arn    = module.iam.execution_role_arn
  task_role_arn         = module.iam.task_role_arn
}

output "url" {
  description = "Application URL."
  value       = module.alb.base_url
}
