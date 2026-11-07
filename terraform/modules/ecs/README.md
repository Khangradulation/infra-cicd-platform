# ecs module

ECS Fargate cluster (optional), digest-pinned task definition, service, service security group, and target-tracking autoscaling on CPU and memory.

Security defaults:

* Read-only root filesystem with an ephemeral `/tmp` volume
* All Linux capabilities dropped and an init process enabled
* No public IP; ingress only from the ALB security group on the container port, egress only on 443
* Deployment circuit breaker with automatic rollback

The service ignores changes to `task_definition` and `desired_count`. CI deploys new revisions and autoscaling owns the task count, so Terraform does not fight either of them. A Terraform change to the task definition (env vars, CPU) creates a new revision that the next CI deploy picks up.

See `examples/complete` for all modules wired together.

Tests: `terraform -chdir=terraform/modules/ecs test` (mocked AWS provider, no credentials needed).

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
| [aws_appautoscaling_policy.cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_policy.memory](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_target.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_target) | resource |
| [aws_ecs_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_cluster_capacity_providers.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster_capacity_providers) | resource |
| [aws_ecs_service.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_security_group.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.from_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_ecs_cluster.existing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ecs_cluster) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alb_security_group_id"></a> [alb\_security\_group\_id](#input\_alb\_security\_group\_id) | ALB security group; the only allowed ingress source for the container port. | `string` | n/a | yes |
| <a name="input_container_image"></a> [container\_image](#input\_container\_image) | Initial image, pinned by digest (repo@sha256:...). Later deploys come from CI; Terraform ignores task-definition drift on the service. | `string` | n/a | yes |
| <a name="input_execution_role_arn"></a> [execution\_role\_arn](#input\_execution\_role\_arn) | Task execution role ARN (image pull, logs). | `string` | n/a | yes |
| <a name="input_log_group_name"></a> [log\_group\_name](#input\_log\_group\_name) | CloudWatch log group the awslogs driver writes to. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name prefix, e.g. "icp-dev". Used for cluster, service, task family and SG names. | `string` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | Private subnets tasks run in (no public IPs are assigned). | `list(string)` | n/a | yes |
| <a name="input_target_group_arn"></a> [target\_group\_arn](#input\_target\_group\_arn) | ALB target group the service registers tasks into. | `string` | n/a | yes |
| <a name="input_task_role_arn"></a> [task\_role\_arn](#input\_task\_role\_arn) | Task (application) role ARN. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC for the service security group. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Existing cluster name when create\_cluster = false. | `string` | `null` | no |
| <a name="input_container_name"></a> [container\_name](#input\_container\_name) | Name of the application container in the task definition. | `string` | `"app"` | no |
| <a name="input_container_port"></a> [container\_port](#input\_container\_port) | Port the application listens on. | `number` | `8080` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | Task CPU units (256 = 0.25 vCPU). | `number` | `256` | no |
| <a name="input_cpu_architecture"></a> [cpu\_architecture](#input\_cpu\_architecture) | X86\_64 or ARM64 (Graviton, ~20% cheaper; image must be built for arm64). | `string` | `"X86_64"` | no |
| <a name="input_cpu_target_percent"></a> [cpu\_target\_percent](#input\_cpu\_target\_percent) | Target average CPU utilisation for scaling. | `number` | `60` | no |
| <a name="input_create_cluster"></a> [create\_cluster](#input\_create\_cluster) | Create a dedicated ECS cluster. Set false to place the service in cluster\_name. | `bool` | `true` | no |
| <a name="input_deployment_maximum_percent"></a> [deployment\_maximum\_percent](#input\_deployment\_maximum\_percent) | Maximum percent during deployments. | `number` | `200` | no |
| <a name="input_deployment_minimum_healthy_percent"></a> [deployment\_minimum\_healthy\_percent](#input\_deployment\_minimum\_healthy\_percent) | Minimum healthy percent during deployments. | `number` | `100` | no |
| <a name="input_desired_count"></a> [desired\_count](#input\_desired\_count) | Initial task count. Autoscaling owns it afterwards (Terraform ignores drift). | `number` | `1` | no |
| <a name="input_egress_cidrs"></a> [egress\_cidrs](#input\_egress\_cidrs) | CIDRs tasks may reach on 443 (ECR, CloudWatch, STS via NAT). Narrow if you use VPC endpoints only. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_enable_autoscaling"></a> [enable\_autoscaling](#input\_enable\_autoscaling) | Enable target-tracking autoscaling on CPU and memory. | `bool` | `true` | no |
| <a name="input_enable_container_insights"></a> [enable\_container\_insights](#input\_enable\_container\_insights) | Enable Container Insights (extra CloudWatch metrics; adds cost). Enables RunningTaskCount alarms. | `bool` | `false` | no |
| <a name="input_enable_execute_command"></a> [enable\_execute\_command](#input\_enable\_execute\_command) | Allow `aws ecs execute-command` into running tasks (requires task role permission). | `bool` | `false` | no |
| <a name="input_environment_variables"></a> [environment\_variables](#input\_environment\_variables) | Plain (non-secret) environment variables for the container. | `map(string)` | `{}` | no |
| <a name="input_fargate_spot_weight"></a> [fargate\_spot\_weight](#input\_fargate\_spot\_weight) | Relative weight for FARGATE\_SPOT (0 = on-demand only). Spot can be reclaimed; avoid in prod. | `number` | `0` | no |
| <a name="input_health_check_grace_period_seconds"></a> [health\_check\_grace\_period\_seconds](#input\_health\_check\_grace\_period\_seconds) | Seconds ECS ignores ALB health checks after a task starts. | `number` | `30` | no |
| <a name="input_max_capacity"></a> [max\_capacity](#input\_max\_capacity) | Autoscaling maximum tasks. | `number` | `2` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Task memory in MiB. Must be a valid pairing for the chosen cpu (e.g. 256 -> 512/1024/2048). | `number` | `512` | no |
| <a name="input_memory_target_percent"></a> [memory\_target\_percent](#input\_memory\_target\_percent) | Target average memory utilisation for scaling. | `number` | `75` | no |
| <a name="input_min_capacity"></a> [min\_capacity](#input\_min\_capacity) | Autoscaling minimum tasks. | `number` | `1` | no |
| <a name="input_secrets"></a> [secrets](#input\_secrets) | Container env vars sourced from Secrets Manager / SSM: { ENV\_NAME = secret\_or\_parameter\_arn }. | `map(string)` | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource. | `map(string)` | `{}` | no |
| <a name="input_wait_for_steady_state"></a> [wait\_for\_steady\_state](#input\_wait\_for\_steady\_state) | Make terraform apply wait until the service is stable. | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | ECS cluster ARN. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | ECS cluster name. |
| <a name="output_container_name"></a> [container\_name](#output\_container\_name) | Application container name. |
| <a name="output_service_arn"></a> [service\_arn](#output\_service\_arn) | ECS service ARN (scope deploy-role permissions to this). |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | ECS service name. |
| <a name="output_service_security_group_id"></a> [service\_security\_group\_id](#output\_service\_security\_group\_id) | Security group attached to tasks. |
| <a name="output_task_definition_arn"></a> [task\_definition\_arn](#output\_task\_definition\_arn) | Terraform-managed task definition revision (CI may have deployed a newer one). |
| <a name="output_task_definition_container_definitions"></a> [task\_definition\_container\_definitions](#output\_task\_definition\_container\_definitions) | Rendered container definitions JSON of the Terraform-managed revision. |
| <a name="output_task_definition_family"></a> [task\_definition\_family](#output\_task\_definition\_family) | Task definition family; CI registers new revisions in it. |
<!-- END_TF_DOCS -->
