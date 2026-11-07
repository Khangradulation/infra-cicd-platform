data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  repo       = "${var.github_owner}/${var.github_repository}"
  sub_prefix = coalesce(var.oidc_sub_claim_prefix, "repo:${local.repo}")
  oidc_host  = "token.actions.githubusercontent.com"

  provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn

  branch_ref = "refs/heads/${var.trusted_branch}"
  tag_ref    = "refs/tags/${var.release_tag_pattern}"

  # --- OIDC `sub` claim values ------------------------------------------
  # Default GitHub template: repo:<o>/<r>:<context>
  # Custom template (repo, context, ref): repo:<o>/<r>:<context>:ref:<ref>
  sub_pull_request = var.oidc_subject_includes_ref ? "${local.sub_prefix}:pull_request:ref:refs/pull/*" : "${local.sub_prefix}:pull_request"
  sub_branch       = var.oidc_subject_includes_ref ? "${local.sub_prefix}:ref:${local.branch_ref}:ref:${local.branch_ref}" : "${local.sub_prefix}:ref:${local.branch_ref}"

  env_subjects = {
    for k, e in var.environments : k => {
      deploy = var.oidc_subject_includes_ref ? concat(
        ["${local.sub_prefix}:environment:${e.deploy_environment}:ref:${local.branch_ref}"],
        e.allow_release_tags ? ["${local.sub_prefix}:environment:${e.deploy_environment}:ref:${local.tag_ref}"] : [],
      ) : ["${local.sub_prefix}:environment:${e.deploy_environment}"]
      infra = var.oidc_subject_includes_ref ? ["${local.sub_prefix}:environment:${e.infra_environment}:ref:${local.branch_ref}"] : ["${local.sub_prefix}:environment:${e.infra_environment}"]
    }
  }

  state_bucket_arn = "arn:${local.partition}:s3:::${var.state_bucket_name}"
}

# --------------------------------------------------------- OIDC provider
# AWS validates GitHub's certificate chain itself; no thumbprint pinning needed.

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]

  tags = var.tags
}

# Reusable trust-policy builder.
data "aws_iam_policy_document" "trust" {
  for_each = merge(
    { plan = [local.sub_pull_request, local.sub_branch], ecr_push = [local.sub_branch] },
    { for k, s in local.env_subjects : "apply_${k}" => s.infra },
    { for k, s in local.env_subjects : "deploy_${k}" => s.deploy },
  )

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # StringLike so tag globs / PR refs work; every value is still anchored to this exact repo.
    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values   = each.value
    }
  }
}

# ------------------------------------------- Workload permissions boundary
# Every IAM role the apply roles create must carry this boundary, so CI can
# never mint a role more powerful than an ECS task / flow-log role needs.

data "aws_iam_policy_document" "workload_boundary" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrPull"
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    resources = [var.ecr_repository_arn]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["arn:${local.partition}:logs:*:${local.account_id}:log-group:*"]
  }

  statement {
    sid       = "AppSecrets"
    actions   = ["secretsmanager:GetSecretValue", "ssm:GetParameters", "kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid = "EcsExec"
    actions = [
      "ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "workload_boundary" {
  name        = "${var.name_prefix}-workload-boundary"
  description = "Permissions boundary for roles created by ${var.name_prefix} Terraform apply roles."
  policy      = data.aws_iam_policy_document.workload_boundary.json

  tags = var.tags
}

# ======================================================== ROLES

resource "aws_iam_role" "plan" {
  name                 = "${var.name_prefix}-gha-terraform-plan"
  description          = "GitHub Actions: read-only terraform plan for ${local.repo} (PRs and ${var.trusted_branch})."
  assume_role_policy   = data.aws_iam_policy_document.trust["plan"].json
  max_session_duration = var.max_session_duration

  tags = var.tags
}

resource "aws_iam_role_policy" "plan" {
  name   = "terraform-plan"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan.json
}

resource "aws_iam_role" "apply" {
  for_each = var.environments

  name                 = "${var.name_prefix}-gha-terraform-apply-${each.key}"
  description          = "GitHub Actions: terraform apply for ${each.key} (GitHub Environment ${each.value.infra_environment})."
  assume_role_policy   = data.aws_iam_policy_document.trust["apply_${each.key}"].json
  max_session_duration = var.max_session_duration

  tags = merge(var.tags, { Environment = each.key })
}

resource "aws_iam_role_policy" "apply" {
  for_each = var.environments

  name   = "terraform-apply"
  role   = aws_iam_role.apply[each.key].id
  policy = data.aws_iam_policy_document.apply[each.key].json
}

resource "aws_iam_role" "ecr_push" {
  name                 = "${var.name_prefix}-gha-ecr-push"
  description          = "GitHub Actions: push application images from ${var.trusted_branch}."
  assume_role_policy   = data.aws_iam_policy_document.trust["ecr_push"].json
  max_session_duration = var.max_session_duration

  tags = var.tags
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.ecr_push.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

resource "aws_iam_role" "deploy" {
  for_each = var.environments

  name                 = "${var.name_prefix}-gha-deploy-${each.key}"
  description          = "GitHub Actions: deploy an image digest to ${each.key} ECS (GitHub Environment ${each.value.deploy_environment})."
  assume_role_policy   = data.aws_iam_policy_document.trust["deploy_${each.key}"].json
  max_session_duration = var.max_session_duration

  tags = merge(var.tags, { Environment = each.key })
}

resource "aws_iam_role_policy" "deploy" {
  for_each = var.environments

  name   = "ecs-deploy"
  role   = aws_iam_role.deploy[each.key].id
  policy = data.aws_iam_policy_document.deploy[each.key].json
}
