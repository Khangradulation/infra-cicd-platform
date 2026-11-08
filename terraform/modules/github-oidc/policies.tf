# IAM policy documents for the GitHub Actions roles.
# Naming contract: every environment resource is named "<prefix>-<env>-..."
# (the environment roots use local.name = "<prefix>-<env>"), which is what
# lets these policies scope by ARN pattern.

locals {
  p   = var.name_prefix
  acc = local.account_id
  arn = local.partition
}

# ===================================================== Terraform PLAN
data "aws_iam_policy_document" "plan" {
  #checkov:skip=CKV_AWS_356:Describe/List/Get actions in ReadPlatformResources do not support resource-level permissions
  statement {
    sid = "ReadPlatformResources"
    actions = [
      "ec2:Describe*",
      "ecs:Describe*", "ecs:List*",
      "ecr:DescribeRepositories", "ecr:DescribeImages", "ecr:ListImages", "ecr:ListTagsForResource",
      "ecr:GetLifecyclePolicy", "ecr:GetRepositoryPolicy",
      "elasticloadbalancing:Describe*",
      "application-autoscaling:Describe*", "application-autoscaling:ListTagsForResource",
      "logs:Describe*", "logs:ListTagsForResource", "logs:ListTagsLogGroup",
      "cloudwatch:DescribeAlarms", "cloudwatch:GetDashboard", "cloudwatch:ListDashboards", "cloudwatch:ListTagsForResource",
      "sns:GetTopicAttributes", "sns:GetSubscriptionAttributes", "sns:ListSubscriptionsByTopic", "sns:ListTagsForResource",
      "kms:DescribeKey", "kms:GetKeyPolicy", "kms:GetKeyRotationStatus", "kms:ListResourceTags", "kms:ListAliases",
      "iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicies", "iam:ListPolicyVersions",
      "iam:GetOpenIDConnectProvider", "iam:ListOpenIDConnectProviders", "iam:ListRoleTags", "iam:ListPolicyTags",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ReadAlbLogBuckets"
    actions = [
      "s3:ListBucket", "s3:GetBucket*", "s3:GetAccelerateConfiguration", "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration", "s3:GetEncryptionConfiguration",
    ]
    resources = ["arn:${local.arn}:s3:::${local.p}-*-alb-logs-${local.acc}"]
  }

  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]
  }

  statement {
    sid       = "StateRead"
    actions   = ["s3:GetObject"]
    resources = ["${local.state_bucket_arn}/*"]
  }

  # Plans take the native S3 lock; they may only create/remove the lock object.
  statement {
    sid       = "StateLockOnly"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arn}/*.tflock"]
  }

  statement {
    sid       = "StateKms"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [var.state_kms_key_arn]
  }
}

# ===================================================== Terraform APPLY (per env)
# trivy:ignore:AWS-0345 s3:* is scoped to this env's own ALB log bucket ARN only
data "aws_iam_policy_document" "apply" {
  #checkov:skip=CKV_AWS_356:'*' only on actions without resource-level support (ec2/autoscaling/create), each region- or tag-conditioned
  for_each = var.environments

  # ---- Networking (EC2 has no usable name-based scoping; limited to network actions + region)
  statement {
    sid = "Networking"
    actions = [
      "ec2:Describe*",
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
      "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:AssociateAddress", "ec2:DisassociateAddress",
      "ec2:CreateNatGateway", "ec2:DeleteNatGateway",
      "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
      "ec2:ReplaceRouteTableAssociation", "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:ReplaceRoute",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress", "ec2:ModifySecurityGroupRules",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress", "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:CreateVpcEndpoint", "ec2:DeleteVpcEndpoints", "ec2:ModifyVpcEndpoint",
      "ec2:CreateFlowLogs", "ec2:DeleteFlowLogs",
      "ec2:CreateTags", "ec2:DeleteTags",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }

  # ---- ECS (scoped to this environment's cluster/service/task family)
  statement {
    sid     = "EcsScoped"
    actions = ["ecs:*"]
    resources = [
      "arn:${local.arn}:ecs:*:${local.acc}:cluster/${local.p}-${each.key}",
      "arn:${local.arn}:ecs:*:${local.acc}:service/${local.p}-${each.key}/*",
      "arn:${local.arn}:ecs:*:${local.acc}:task-definition/${local.p}-${each.key}:*",
      "arn:${local.arn}:ecs:*:${local.acc}:task/${local.p}-${each.key}/*",
    ]
  }

  statement {
    sid = "EcsUnscoped"
    actions = [
      "ecs:CreateCluster", "ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition",
      "ecs:DescribeTaskDefinition", "ecs:ListTaskDefinitions", "ecs:ListClusters", "ecs:ListServices",
      "ecs:DescribeClusters", "ecs:DescribeServices",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }

  # ---- Load balancing
  statement {
    sid     = "ElbScoped"
    actions = ["elasticloadbalancing:*"]
    resources = [
      "arn:${local.arn}:elasticloadbalancing:*:${local.acc}:loadbalancer/app/${local.p}-${each.key}-*/*",
      "arn:${local.arn}:elasticloadbalancing:*:${local.acc}:targetgroup/${local.p}-${each.key}-*/*",
      "arn:${local.arn}:elasticloadbalancing:*:${local.acc}:listener/app/${local.p}-${each.key}-*/*/*",
      "arn:${local.arn}:elasticloadbalancing:*:${local.acc}:listener-rule/app/${local.p}-${each.key}-*/*/*/*",
    ]
  }

  statement {
    sid       = "ElbDescribe"
    actions   = ["elasticloadbalancing:Describe*"]
    resources = ["*"]
  }

  # ---- Autoscaling (no resource-level permissions)
  statement {
    sid       = "AppAutoscaling"
    actions   = ["application-autoscaling:*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }

  # ---- Logs / CloudWatch / SNS
  statement {
    sid     = "LogsScoped"
    actions = ["logs:*"]
    resources = [
      "arn:${local.arn}:logs:*:${local.acc}:log-group:/ecs/${local.p}-${each.key}",
      "arn:${local.arn}:logs:*:${local.acc}:log-group:/ecs/${local.p}-${each.key}:*",
      "arn:${local.arn}:logs:*:${local.acc}:log-group:/vpc/${local.p}-${each.key}/*",
    ]
  }

  statement {
    sid       = "LogsDescribe"
    actions   = ["logs:DescribeLogGroups", "logs:DescribeMetricFilters", "cloudwatch:DescribeAlarms", "cloudwatch:ListDashboards"]
    resources = ["*"]
  }

  statement {
    sid     = "CloudWatchScoped"
    actions = ["cloudwatch:*"]
    resources = [
      "arn:${local.arn}:cloudwatch:*:${local.acc}:alarm:${local.p}-${each.key}-*",
      "arn:${local.arn}:cloudwatch::${local.acc}:dashboard/${local.p}-${each.key}",
    ]
  }

  statement {
    sid       = "SnsScoped"
    actions   = ["sns:*"]
    resources = ["arn:${local.arn}:sns:*:${local.acc}:${local.p}-${each.key}-*"]
  }

  # ---- KMS: tag-based (ABAC). Keys must be created with Environment=<env>
  #      (provider default_tags does this) and can only be managed while tagged so.
  statement {
    sid       = "KmsCreateTagged"
    actions   = ["kms:CreateKey", "kms:TagResource"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid       = "KmsManageOwnKeys"
    actions   = ["kms:*"]
    resources = ["arn:${local.arn}:kms:*:${local.acc}:key/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid       = "KmsAliases"
    actions   = ["kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias"]
    resources = ["arn:${local.arn}:kms:*:${local.acc}:alias/${local.p}-${each.key}-*"]
  }

  statement {
    sid       = "KmsList"
    actions   = ["kms:ListAliases", "kms:ListKeys"]
    resources = ["*"]
  }

  # ---- ALB access-log bucket
  statement {
    sid     = "AlbLogBucket"
    actions = ["s3:*"]
    resources = [
      "arn:${local.arn}:s3:::${local.p}-${each.key}-alb-logs-${local.acc}",
      "arn:${local.arn}:s3:::${local.p}-${each.key}-alb-logs-${local.acc}/*",
    ]
  }

  # ---- Read shared resources looked up via data sources
  statement {
    sid = "ReadSharedEcr"
    # the provider reads tags for aws_ecr_repository / aws_iam_policy data sources
    actions   = ["ecr:DescribeRepositories", "ecr:DescribeImages", "ecr:ListImages", "ecr:ListTagsForResource"]
    resources = [var.ecr_repository_arn]
  }

  statement {
    sid       = "ReadBoundary"
    actions   = ["iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicies", "iam:ListPolicyTags"]
    resources = ["*"]
  }

  # ---- IAM: only roles named <prefix>-<env>-*, only with the workload boundary
  statement {
    sid = "IamRolesWithBoundary"
    actions = [
      "iam:CreateRole", "iam:PutRolePermissionsBoundary",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
    ]
    resources = ["arn:${local.arn}:iam::${local.acc}:role/${local.p}-${each.key}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.workload_boundary.arn]
    }
  }

  statement {
    sid = "IamRolesManage"
    actions = [
      "iam:GetRole", "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateRoleDescription", "iam:UpdateAssumeRolePolicy",
      "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
      "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole",
    ]
    resources = ["arn:${local.arn}:iam::${local.acc}:role/${local.p}-${each.key}-*"]
  }

  statement {
    sid       = "IamPassRoles"
    actions   = ["iam:PassRole"]
    resources = ["arn:${local.arn}:iam::${local.acc}:role/${local.p}-${each.key}-*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com", "vpc-flow-logs.amazonaws.com"]
    }
  }

  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "ecs.amazonaws.com",
        "ecs.application-autoscaling.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
      ]
    }
  }

  statement {
    sid    = "ProtectBoundary"
    effect = "Deny"
    actions = [
      "iam:DeleteRolePermissionsBoundary",
      "iam:CreatePolicyVersion", "iam:DeletePolicy", "iam:DeletePolicyVersion", "iam:SetDefaultPolicyVersion",
    ]
    resources = ["*"]
  }

  # ---- This environment's state only
  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${each.key}/*"]
    }
  }

  statement {
    sid       = "StateReadWrite"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arn}/${each.key}/*"]
  }

  statement {
    sid       = "StateKms"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [var.state_kms_key_arn]
  }
}

# ===================================================== ECR PUSH
data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PushToAppRepo"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage",
      "ecr:DescribeImages", "ecr:DescribeImageScanFindings", "ecr:ListImages",
    ]
    resources = [var.ecr_repository_arn]
  }
}

# ===================================================== ECS DEPLOY (per env)
data "aws_iam_policy_document" "deploy" {
  for_each = var.environments

  statement {
    sid = "TaskDefinitions"
    actions = [
      "ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition", "ecs:ListTaskDefinitions",
      "ecs:DescribeServiceDeployments", "ecs:ListServiceDeployments",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
  }

  statement {
    sid       = "TagOwnTaskDefinitions"
    actions   = ["ecs:TagResource"]
    resources = ["arn:${local.arn}:ecs:*:${local.acc}:task-definition/${local.p}-${each.key}:*"]
    condition {
      test     = "StringEquals"
      variable = "ecs:CreateAction"
      values   = ["RegisterTaskDefinition"]
    }
  }

  statement {
    sid       = "UpdateOwnService"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = ["arn:${local.arn}:ecs:*:${local.acc}:service/${local.p}-${each.key}/${local.p}-${each.key}"]
  }

  statement {
    sid       = "InspectOwnTasks"
    actions   = ["ecs:ListTasks"]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "ecs:cluster"
      values   = ["arn:${local.arn}:ecs:*:${local.acc}:cluster/${local.p}-${each.key}"]
    }
  }

  statement {
    sid       = "DescribeOwnTasks"
    actions   = ["ecs:DescribeTasks"]
    resources = ["arn:${local.arn}:ecs:*:${local.acc}:task/${local.p}-${each.key}/*"]
  }

  statement {
    sid     = "PassOwnTaskRoles"
    actions = ["iam:PassRole"]
    resources = [
      "arn:${local.arn}:iam::${local.acc}:role/${local.p}-${each.key}-task",
      "arn:${local.arn}:iam::${local.acc}:role/${local.p}-${each.key}-task-execution",
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "VerifyImage"
    actions   = ["ecr:DescribeImages", "ecr:BatchGetImage"]
    resources = [var.ecr_repository_arn]
  }

  statement {
    sid = "DiscoverEndpoint"
    actions = [
      "elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth", "elasticloadbalancing:DescribeListeners",
    ]
    resources = ["*"]
  }
}
