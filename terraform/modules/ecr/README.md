# ecr module

Private ECR repository with **immutable tags**, scan-on-push, AES256 or KMS encryption, and a lifecycle policy that expires untagged images after N days and keeps the newest N tagged images. That retention is your rollback window.

```hcl
module "ecr" {
  source = "../../modules/ecr"
  name   = "icp/app"
}
```

Tests: `terraform -chdir=terraform/modules/ecr test` (mocked AWS provider, no credentials needed).

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
| [aws_ecr_lifecycle_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_lifecycle_policy) | resource |
| [aws_ecr_repository.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_ecr_repository_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository_policy) | resource |
| [aws_iam_policy_document.pull](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_name"></a> [name](#input\_name) | Repository name, e.g. "icp/app". | `string` | n/a | yes |
| <a name="input_force_delete"></a> [force\_delete](#input\_force\_delete) | Allow `terraform destroy` to delete the repository even if it contains images. Keep false outside sandboxes. | `bool` | `false` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key ARN for image encryption. null uses AES256 (SSE-S3, no extra cost). | `string` | `null` | no |
| <a name="input_max_tagged_images"></a> [max\_tagged\_images](#input\_max\_tagged\_images) | Keep at most this many tagged images; older ones expire (rollback window). | `number` | `50` | no |
| <a name="input_pull_principal_arns"></a> [pull\_principal\_arns](#input\_pull\_principal\_arns) | Additional IAM principal ARNs (e.g. other accounts) allowed to pull. Same-account roles use IAM policies instead. | `list(string)` | `[]` | no |
| <a name="input_scan_on_push"></a> [scan\_on\_push](#input\_scan\_on\_push) | Enable ECR basic scanning on push (free). Trivy in CI is the blocking gate. | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource. | `map(string)` | `{}` | no |
| <a name="input_untagged_expiry_days"></a> [untagged\_expiry\_days](#input\_untagged\_expiry\_days) | Expire untagged images (e.g. failed/partial pushes) after this many days. | `number` | `7` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_repository_arn"></a> [repository\_arn](#output\_repository\_arn) | Repository ARN (scope IAM push/pull policies to this). |
| <a name="output_repository_name"></a> [repository\_name](#output\_repository\_name) | Repository name. |
| <a name="output_repository_url"></a> [repository\_url](#output\_repository\_url) | Registry URL without tag, e.g. <account>.dkr.ecr.<region>.amazonaws.com/icp/app. |
<!-- END_TF_DOCS -->
