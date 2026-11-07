# app-stack module

Composes networking, alb, monitoring, iam and ecs into one environment stack. Environment roots call this with their own settings, so dev, staging and prod always run the same reviewed code. It looks up the shared ECR repository and the workload permissions boundary by name.

Tests: `terraform -chdir=terraform/modules/app-stack test` (plan-level, mocked provider).

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

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_alb"></a> [alb](#module\_alb) | ../alb | n/a |
| <a name="module_ecs"></a> [ecs](#module\_ecs) | ../ecs | n/a |
| <a name="module_iam"></a> [iam](#module\_iam) | ../iam | n/a |
| <a name="module_monitoring"></a> [monitoring](#module\_monitoring) | ../monitoring | n/a |
| <a name="module_networking"></a> [networking](#module\_networking) | ../networking | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_ecr_repository.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ecr_repository) | data source |
| [aws_iam_policy.boundary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_container_image"></a> [container\_image](#input\_container\_image) | Initial digest-pinned image (<repo>@sha256:...). | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment key: dev, staging or prod. Resources are named <prefix>-<environment>-*. | `string` | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR (use a distinct range per environment). | `string` | n/a | yes |
| <a name="input_alarm_email_addresses"></a> [alarm\_email\_addresses](#input\_alarm\_email\_addresses) | Alarm notification emails. | `list(string)` | `[]` | no |
| <a name="input_allowed_ingress_cidrs"></a> [allowed\_ingress\_cidrs](#input\_allowed\_ingress\_cidrs) | CIDRs allowed to reach the ALB. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_az_count"></a> [az\_count](#input\_az\_count) | Availability zones. | `number` | `2` | no |
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | ACM certificate for HTTPS (null = HTTP only). | `string` | `null` | no |
| <a name="input_container_port"></a> [container\_port](#input\_container\_port) | Application port. | `number` | `8080` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Task CPU units. | `number` | `256` | no |
| <a name="input_cpu_architecture"></a> [cpu\_architecture](#input\_cpu\_architecture) | X86\_64 or ARM64. | `string` | `"X86_64"` | no |
| <a name="input_desired_count"></a> [desired\_count](#input\_desired\_count) | Initial task count. | `number` | `1` | no |
| <a name="input_ecr_repository_name"></a> [ecr\_repository\_name](#input\_ecr\_repository\_name) | Name of the shared ECR repository created by environments/shared. | `string` | `"icp/app"` | no |
| <a name="input_enable_alb_access_logs"></a> [enable\_alb\_access\_logs](#input\_enable\_alb\_access\_logs) | ALB access logs to S3. | `bool` | `false` | no |
| <a name="input_enable_container_insights"></a> [enable\_container\_insights](#input\_enable\_container\_insights) | Container Insights on the cluster. | `bool` | `false` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | ALB deletion protection. | `bool` | `false` | no |
| <a name="input_enable_execute_command"></a> [enable\_execute\_command](#input\_enable\_execute\_command) | Allow ECS Exec. | `bool` | `false` | no |
| <a name="input_enable_flow_logs"></a> [enable\_flow\_logs](#input\_enable\_flow\_logs) | Enable VPC flow logs. | `bool` | `false` | no |
| <a name="input_environment_variables"></a> [environment\_variables](#input\_environment\_variables) | Extra plain env vars for the container (APP\_ENV is always set). | `map(string)` | `{}` | no |
| <a name="input_fargate_spot_weight"></a> [fargate\_spot\_weight](#input\_fargate\_spot\_weight) | FARGATE\_SPOT weight (0 = none). | `number` | `0` | no |
| <a name="input_force_destroy_log_buckets"></a> [force\_destroy\_log\_buckets](#input\_force\_destroy\_log\_buckets) | Allow destroy to delete non-empty log buckets (non-prod convenience). | `bool` | `false` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Application log retention. | `number` | `14` | no |
| <a name="input_max_capacity"></a> [max\_capacity](#input\_max\_capacity) | Autoscaling max. | `number` | `2` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Task memory MiB. | `number` | `512` | no |
| <a name="input_min_capacity"></a> [min\_capacity](#input\_min\_capacity) | Autoscaling min. | `number` | `1` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Project prefix (must match the github-oidc module's name\_prefix so CI role scoping lines up). | `string` | `"icp"` | no |
| <a name="input_nat_gateway_mode"></a> [nat\_gateway\_mode](#input\_nat\_gateway\_mode) | single \| per\_az \| none. | `string` | `"single"` | no |
| <a name="input_permissions_boundary_name"></a> [permissions\_boundary\_name](#input\_permissions\_boundary\_name) | Name of the workload permissions boundary created by environments/shared (null = no boundary). | `string` | `"icp-workload-boundary"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alarm_topic_arn"></a> [alarm\_topic\_arn](#output\_alarm\_topic\_arn) | Alarm SNS topic. |
| <a name="output_alb_name"></a> [alb\_name](#output\_alb\_name) | ALB name. |
| <a name="output_app_url"></a> [app\_url](#output\_app\_url) | Application base URL. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | ECS cluster. |
| <a name="output_container_name"></a> [container\_name](#output\_container\_name) | Container name in the task definition. |
| <a name="output_dashboard_name"></a> [dashboard\_name](#output\_dashboard\_name) | CloudWatch dashboard. |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | Application log group. |
| <a name="output_name"></a> [name](#output\_name) | Resource name prefix for this environment. |
| <a name="output_nat_gateway_count"></a> [nat\_gateway\_count](#output\_nat\_gateway\_count) | NAT gateways (cost driver). |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | ECS service. |
| <a name="output_task_definition_family"></a> [task\_definition\_family](#output\_task\_definition\_family) | Task definition family CI deploys into. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID. |
<!-- END_TF_DOCS -->
