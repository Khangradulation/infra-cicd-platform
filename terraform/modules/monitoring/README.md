# monitoring module

Observability for one ECS service behind an ALB:

* KMS-encrypted application log group with retention
* Metric filters on structured JSON logs (`level=ERROR|CRITICAL`, `status>=500`)
* KMS-encrypted SNS alarm topic with optional email subscriptions
* Alarms that only use metrics that actually exist: ECS CPU and memory, ALB unhealthy and no-healthy targets, target and ELB 5xx, p95 latency, and app error logs. The RunningTaskCount alarm is created only when Container Insights is enabled, because that metric doesn't exist otherwise.
* A CloudWatch dashboard

Tests: `terraform -chdir=terraform/modules/monitoring test` (mocked AWS provider, no credentials needed).

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
| [aws_cloudwatch_dashboard.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_dashboard) | resource |
| [aws_cloudwatch_log_group.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_metric_filter.app_5xx](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_metric_filter) | resource |
| [aws_cloudwatch_log_metric_filter.app_errors](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_metric_filter) | resource |
| [aws_cloudwatch_metric_alarm.app_errors](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.cpu_high](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.elb_5xx](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.latency_p95](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.memory_high](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.no_healthy_targets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.running_tasks_low](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.target_5xx](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.unhealthy_targets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_sns_topic.alarms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_policy.alarms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy) | resource |
| [aws_sns_topic_subscription.email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.sns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alb_arn_suffix"></a> [alb\_arn\_suffix](#input\_alb\_arn\_suffix) | ALB ARN suffix (CloudWatch LoadBalancer dimension). | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | ECS cluster name (CloudWatch ClusterName dimension). | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name prefix, e.g. "icp-dev". | `string` | n/a | yes |
| <a name="input_service_name"></a> [service\_name](#input\_service\_name) | ECS service name (CloudWatch ServiceName dimension). | `string` | n/a | yes |
| <a name="input_target_group_arn_suffix"></a> [target\_group\_arn\_suffix](#input\_target\_group\_arn\_suffix) | Target group ARN suffix (CloudWatch TargetGroup dimension). | `string` | n/a | yes |
| <a name="input_alarm_email_addresses"></a> [alarm\_email\_addresses](#input\_alarm\_email\_addresses) | Email addresses subscribed to the alarm topic (each must confirm the subscription). | `list(string)` | `[]` | no |
| <a name="input_app_error_threshold"></a> [app\_error\_threshold](#input\_app\_error\_threshold) | ERROR-level application log lines per 5 minutes that trigger an alarm. | `number` | `5` | no |
| <a name="input_container_insights_enabled"></a> [container\_insights\_enabled](#input\_container\_insights\_enabled) | Whether Container Insights is enabled on the cluster. RunningTaskCount alarms are only created when true (the metric doesn't exist otherwise). | `bool` | `false` | no |
| <a name="input_cpu_alarm_threshold"></a> [cpu\_alarm\_threshold](#input\_cpu\_alarm\_threshold) | Average service CPU % that triggers an alarm. | `number` | `80` | no |
| <a name="input_create_kms_key"></a> [create\_kms\_key](#input\_create\_kms\_key) | Create a customer-managed KMS key (~$1/month) to encrypt the log group and alarm SNS topic. | `bool` | `true` | no |
| <a name="input_elb_5xx_threshold"></a> [elb\_5xx\_threshold](#input\_elb\_5xx\_threshold) | ALB-generated 5xx responses per 5 minutes that trigger an alarm. | `number` | `10` | no |
| <a name="input_enable_dashboard"></a> [enable\_dashboard](#input\_enable\_dashboard) | Create a CloudWatch dashboard (first 3 per account free, then $3/month each). | `bool` | `true` | no |
| <a name="input_kms_deletion_window_days"></a> [kms\_deletion\_window\_days](#input\_kms\_deletion\_window\_days) | Waiting period before the KMS key is deleted on destroy. | `number` | `7` | no |
| <a name="input_latency_p95_threshold_seconds"></a> [latency\_p95\_threshold\_seconds](#input\_latency\_p95\_threshold\_seconds) | p95 target response time (seconds) that triggers an alarm. | `number` | `1.5` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention for the application log group. | `number` | `14` | no |
| <a name="input_memory_alarm_threshold"></a> [memory\_alarm\_threshold](#input\_memory\_alarm\_threshold) | Average service memory % that triggers an alarm. | `number` | `85` | no |
| <a name="input_min_running_tasks"></a> [min\_running\_tasks](#input\_min\_running\_tasks) | Alarm if fewer tasks than this are running (requires Container Insights). | `number` | `1` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource. | `map(string)` | `{}` | no |
| <a name="input_target_5xx_threshold"></a> [target\_5xx\_threshold](#input\_target\_5xx\_threshold) | Target (app) 5xx responses per 5 minutes that trigger an alarm. | `number` | `10` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alarm_names"></a> [alarm\_names](#output\_alarm\_names) | Names of all CloudWatch alarms created. |
| <a name="output_alarm_topic_arn"></a> [alarm\_topic\_arn](#output\_alarm\_topic\_arn) | SNS topic alarms publish to. |
| <a name="output_dashboard_name"></a> [dashboard\_name](#output\_dashboard\_name) | CloudWatch dashboard name (null if disabled). |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | Observability KMS key ARN, or null when create\_kms\_key = false. |
| <a name="output_log_group_arn"></a> [log\_group\_arn](#output\_log\_group\_arn) | Application log group ARN (without :*). |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | Application log group name. |
<!-- END_TF_DOCS -->
