# github-oidc module

GitHub Actions to AWS OIDC federation:

* The account-wide OIDC provider
* A workload **permissions boundary**
* Least-privilege CI roles: one plan role, one apply and one deploy role per environment, and an ECR push role

Every trust policy pins `aud=sts.amazonaws.com` and an exact `sub` for this repository: PRs, the trusted branch, or a named GitHub Environment. Set `oidc_subject_includes_ref = true` after customising the repo OIDC subject template. IAM then also checks the git ref (`main` or `v*` tags for production). See `docs/security.md`.

| Role | Trusted subject (default template) |
|---|---|
| `<prefix>-gha-terraform-plan` | `repo:O/R:pull_request`, `repo:O/R:ref:refs/heads/main` |
| `<prefix>-gha-terraform-apply-<env>` | `repo:O/R:environment:infra-<env>` |
| `<prefix>-gha-ecr-push` | `repo:O/R:ref:refs/heads/main` |
| `<prefix>-gha-deploy-<env>` | `repo:O/R:environment:<dev\|staging\|production>` |

Tests: `terraform -chdir=terraform/modules/github-oidc test` (mocked AWS provider, no credentials needed).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0.0, < 7.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.72.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_policy.workload_boundary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.apply](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.deploy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecr_push](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.apply](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.deploy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ecr_push](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.apply](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.deploy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ecr_push](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.workload_boundary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_regions"></a> [allowed\_regions](#input\_allowed\_regions) | Regions the apply roles may create resources in. | `list(string)` | n/a | yes |
| <a name="input_ecr_repository_arn"></a> [ecr\_repository\_arn](#input\_ecr\_repository\_arn) | Shared application ECR repository ARN. | `string` | n/a | yes |
| <a name="input_github_owner"></a> [github\_owner](#input\_github\_owner) | GitHub organisation or user that owns the repository (case-sensitive, as shown in the URL). | `string` | n/a | yes |
| <a name="input_github_repository"></a> [github\_repository](#input\_github\_repository) | Repository name (without owner). | `string` | n/a | yes |
| <a name="input_state_bucket_name"></a> [state\_bucket\_name](#input\_state\_bucket\_name) | Terraform state bucket name (from terraform/bootstrap output). | `string` | n/a | yes |
| <a name="input_state_kms_key_arn"></a> [state\_kms\_key\_arn](#input\_state\_kms\_key\_arn) | KMS key ARN encrypting the state bucket (from terraform/bootstrap output). | `string` | n/a | yes |
| <a name="input_create_oidc_provider"></a> [create\_oidc\_provider](#input\_create\_oidc\_provider) | Create the account-wide GitHub OIDC provider. Set false if it already exists and pass existing\_oidc\_provider\_arn. | `bool` | `true` | no |
| <a name="input_environments"></a> [environments](#input\_environments) | Deployable environments. Keys are short names used in resource names (<prefix>-<key>-*) and state keys (<key>/...).<br/>deploy\_environment / infra\_environment are the GitHub Environment names whose jobs may assume the deploy / apply roles. | <pre>map(object({<br/>    deploy_environment = string<br/>    infra_environment  = string<br/>    allow_release_tags = optional(bool, false)<br/>  }))</pre> | <pre>{<br/>  "dev": {<br/>    "deploy_environment": "dev",<br/>    "infra_environment": "infra-dev"<br/>  },<br/>  "prod": {<br/>    "allow_release_tags": true,<br/>    "deploy_environment": "production",<br/>    "infra_environment": "infra-production"<br/>  },<br/>  "staging": {<br/>    "deploy_environment": "staging",<br/>    "infra_environment": "infra-staging"<br/>  }<br/>}</pre> | no |
| <a name="input_existing_oidc_provider_arn"></a> [existing\_oidc\_provider\_arn](#input\_existing\_oidc\_provider\_arn) | ARN of an existing token.actions.githubusercontent.com provider (when create\_oidc\_provider = false). | `string` | `null` | no |
| <a name="input_max_session_duration"></a> [max\_session\_duration](#input\_max\_session\_duration) | Maximum CI role session duration in seconds. | `number` | `3600` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Project prefix used in every role/policy name and to scope permissions, e.g. "icp". Environment resources are expected to be named <prefix>-<env>-*. | `string` | `"icp"` | no |
| <a name="input_oidc_sub_claim_prefix"></a> [oidc\_sub\_claim\_prefix](#input\_oidc\_sub\_claim\_prefix) | Exact prefix GitHub puts in this repository's OIDC `sub` claim. null = classic "repo:<owner>/<repo>".<br/>Repositories using GitHub's immutable subject format use "repo:<owner>@<owner\_id>/<repo>@<repo\_id>".<br/>Read it, never guess it:  gh api repos/OWNER/REPO/actions/oidc/customization/sub --jq .sub\_claim\_prefix | `string` | `null` | no |
| <a name="input_oidc_subject_includes_ref"></a> [oidc\_subject\_includes\_ref](#input\_oidc\_subject\_includes\_ref) | Set true AFTER customising the repository's OIDC subject template to include the ref:<br/>  gh api -X PUT repos/OWNER/REPO/actions/oidc/customization/sub \<br/>    -F use\_default=false -f 'include\_claim\_keys[]=repo' -f 'include\_claim\_keys[]=context' -f 'include\_claim\_keys[]=ref'<br/>Environment subjects then end in ":ref:refs/heads/<branch>", letting IAM reject environment jobs<br/>from untrusted branches even where GitHub deployment-branch rules are unavailable. | `bool` | `false` | no |
| <a name="input_release_tag_pattern"></a> [release\_tag\_pattern](#input\_release\_tag\_pattern) | Git tag glob (IAM StringLike) also allowed to deploy to production when the subject includes the ref. | `string` | `"v*"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource. | `map(string)` | `{}` | no |
| <a name="input_trusted_branch"></a> [trusted\_branch](#input\_trusted\_branch) | The protected branch allowed to push images, run trusted plans and deploy. | `string` | `"main"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_deploy_role_arns"></a> [deploy\_role\_arns](#output\_deploy\_role\_arns) | Per-env deploy roles; set AWS\_DEPLOY\_ROLE\_ARN on each dev/staging/production GitHub Environment. |
| <a name="output_ecr_push_role_arn"></a> [ecr\_push\_role\_arn](#output\_ecr\_push\_role\_arn) | Set as repository variable AWS\_ECR\_PUSH\_ROLE\_ARN. |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | GitHub OIDC provider ARN. |
| <a name="output_terraform_apply_role_arns"></a> [terraform\_apply\_role\_arns](#output\_terraform\_apply\_role\_arns) | Per-env apply roles; set AWS\_APPLY\_ROLE\_ARN on each infra-<env> GitHub Environment. |
| <a name="output_terraform_plan_role_arn"></a> [terraform\_plan\_role\_arn](#output\_terraform\_plan\_role\_arn) | Set as repository variable AWS\_PLAN\_ROLE\_ARN. |
| <a name="output_trusted_subjects"></a> [trusted\_subjects](#output\_trusted\_subjects) | OIDC sub claims each role trusts (useful when debugging AssumeRoleWithWebIdentity denials). |
| <a name="output_workload_boundary_arn"></a> [workload\_boundary\_arn](#output\_workload\_boundary\_arn) | Permissions boundary environment roots must attach to every IAM role they create. |
| <a name="output_workload_boundary_name"></a> [workload\_boundary\_name](#output\_workload\_boundary\_name) | Permissions boundary policy name (environment roots look it up by name). |
<!-- END_TF_DOCS -->
