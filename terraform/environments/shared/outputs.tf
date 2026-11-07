output "ecr_repository_url" {
  description = "Set as repository variable ECR_REPOSITORY (name) / used to build image URIs."
  value       = module.ecr.repository_url
}

output "ecr_repository_name" {
  description = "Repository name."
  value       = module.ecr.repository_name
}

output "github_variables" {
  description = "Values to configure in GitHub (see docs/setup.md). None are secrets. null in local-only mode."
  value = var.enable_github_oidc ? {
    repository = {
      AWS_REGION            = var.region
      TF_STATE_BUCKET       = var.state_bucket_name
      TF_STATE_KMS_KEY_ARN  = var.state_kms_key_arn
      ECR_REPOSITORY        = module.ecr.repository_name
      AWS_PLAN_ROLE_ARN     = module.github_oidc[0].terraform_plan_role_arn
      AWS_ECR_PUSH_ROLE_ARN = module.github_oidc[0].ecr_push_role_arn
    }
    environments = {
      "infra-dev"        = { AWS_APPLY_ROLE_ARN = module.github_oidc[0].terraform_apply_role_arns["dev"] }
      "infra-staging"    = { AWS_APPLY_ROLE_ARN = module.github_oidc[0].terraform_apply_role_arns["staging"] }
      "infra-production" = { AWS_APPLY_ROLE_ARN = module.github_oidc[0].terraform_apply_role_arns["prod"] }
      "dev"              = { AWS_DEPLOY_ROLE_ARN = module.github_oidc[0].deploy_role_arns["dev"] }
      "staging"          = { AWS_DEPLOY_ROLE_ARN = module.github_oidc[0].deploy_role_arns["staging"] }
      "production"       = { AWS_DEPLOY_ROLE_ARN = module.github_oidc[0].deploy_role_arns["prod"] }
    }
  } : null
}

output "workload_boundary_name" {
  description = "Permissions boundary looked up by environment roots."
  value       = var.enable_github_oidc ? module.github_oidc[0].workload_boundary_name : null
}

output "trusted_subjects" {
  description = "OIDC subjects each CI role trusts."
  value       = var.enable_github_oidc ? module.github_oidc[0].trusted_subjects : null
}
