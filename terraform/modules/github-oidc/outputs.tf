output "oidc_provider_arn" {
  description = "GitHub OIDC provider ARN."
  value       = local.provider_arn
}

output "workload_boundary_arn" {
  description = "Permissions boundary environment roots must attach to every IAM role they create."
  value       = aws_iam_policy.workload_boundary.arn
}

output "workload_boundary_name" {
  description = "Permissions boundary policy name (environment roots look it up by name)."
  value       = aws_iam_policy.workload_boundary.name
}

output "terraform_plan_role_arn" {
  description = "Set as repository variable AWS_PLAN_ROLE_ARN."
  value       = aws_iam_role.plan.arn
}

output "terraform_apply_role_arns" {
  description = "Per-env apply roles; set AWS_APPLY_ROLE_ARN on each infra-<env> GitHub Environment."
  value       = { for k, r in aws_iam_role.apply : k => r.arn }
}

output "ecr_push_role_arn" {
  description = "Set as repository variable AWS_ECR_PUSH_ROLE_ARN."
  value       = aws_iam_role.ecr_push.arn
}

output "deploy_role_arns" {
  description = "Per-env deploy roles; set AWS_DEPLOY_ROLE_ARN on each dev/staging/production GitHub Environment."
  value       = { for k, r in aws_iam_role.deploy : k => r.arn }
}

output "trusted_subjects" {
  description = "OIDC sub claims each role trusts (useful when debugging AssumeRoleWithWebIdentity denials)."
  value = merge(
    { plan = [local.sub_pull_request, local.sub_branch], ecr_push = [local.sub_branch] },
    { for k, s in local.env_subjects : "apply_${k}" => s.infra },
    { for k, s in local.env_subjects : "deploy_${k}" => s.deploy },
  )
}
