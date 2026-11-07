# alb module

Internet-facing Application Load Balancer, a security group (80/443 from `allowed_ingress_cidrs`, egress only to the target port inside the VPC), an IP-type target group with HTTP health checks, and listeners.

* No `certificate_arn`: HTTP:80 forwards to the targets.
* With `certificate_arn`: HTTP:80 returns a 301 redirect, and HTTPS:443 uses a TLS 1.3/1.2 policy and forwards to the targets.
* `enable_access_logs`: creates an encrypted, private, lifecycle-managed S3 bucket with the ELB log-delivery policy.

Tests: `terraform -chdir=terraform/modules/alb test` (mocked AWS provider, no credentials needed).

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
| [aws_lb.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.http_forward](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.http_redirect](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_s3_bucket.access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_security_group.alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.alb_to_targets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_elb_service_account.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/elb_service_account) | data source |
| [aws_iam_policy_document.access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_name"></a> [name](#input\_name) | Name prefix, e.g. "icp-dev". ALB and target group names derive from it (max 32 chars in AWS). | `string` | n/a | yes |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | Public subnets (>= 2 AZs) for the ALB. | `list(string)` | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR; ALB egress is limited to the target port inside this range. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC to place the ALB and target group in. | `string` | n/a | yes |
| <a name="input_access_logs_force_destroy"></a> [access\_logs\_force\_destroy](#input\_access\_logs\_force\_destroy) | Allow destroying the access-log bucket while it still contains logs. | `bool` | `false` | no |
| <a name="input_access_logs_retention_days"></a> [access\_logs\_retention\_days](#input\_access\_logs\_retention\_days) | Days to keep ALB access logs. | `number` | `90` | no |
| <a name="input_allowed_ingress_cidrs"></a> [allowed\_ingress\_cidrs](#input\_allowed\_ingress\_cidrs) | IPv4 CIDRs allowed to reach the ALB on 80/443. Restrict for internal/non-prod environments. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | ACM certificate ARN. When set, HTTPS:443 is served and HTTP:80 redirects to it. | `string` | `null` | no |
| <a name="input_deregistration_delay"></a> [deregistration\_delay](#input\_deregistration\_delay) | Seconds to drain connections from a target before deregistering (affects deploy speed). | `number` | `30` | no |
| <a name="input_enable_access_logs"></a> [enable\_access\_logs](#input\_enable\_access\_logs) | Create an S3 bucket and enable ALB access logs. | `bool` | `false` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Prevent the ALB from being deleted (set true in prod; must be disabled before teardown). | `bool` | `false` | no |
| <a name="input_health_check_interval"></a> [health\_check\_interval](#input\_health\_check\_interval) | Seconds between health checks. | `number` | `15` | no |
| <a name="input_health_check_path"></a> [health\_check\_path](#input\_health\_check\_path) | HTTP path the ALB probes on each target. | `string` | `"/health"` | no |
| <a name="input_healthy_threshold"></a> [healthy\_threshold](#input\_healthy\_threshold) | Consecutive successes before a target is healthy. | `number` | `2` | no |
| <a name="input_idle_timeout"></a> [idle\_timeout](#input\_idle\_timeout) | ALB idle timeout in seconds. | `number` | `60` | no |
| <a name="input_ssl_policy"></a> [ssl\_policy](#input\_ssl\_policy) | TLS policy for the HTTPS listener. | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource. | `map(string)` | `{}` | no |
| <a name="input_target_port"></a> [target\_port](#input\_target\_port) | Container port the target group forwards to. | `number` | `8080` | no |
| <a name="input_unhealthy_threshold"></a> [unhealthy\_threshold](#input\_unhealthy\_threshold) | Consecutive failures before a target is unhealthy. | `number` | `3` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alb_arn"></a> [alb\_arn](#output\_alb\_arn) | ARN of the load balancer. |
| <a name="output_alb_arn_suffix"></a> [alb\_arn\_suffix](#output\_alb\_arn\_suffix) | ARN suffix used as the LoadBalancer CloudWatch dimension. |
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | Public DNS name of the ALB. |
| <a name="output_alb_name"></a> [alb\_name](#output\_alb\_name) | Load balancer name (deploy workflow looks the DNS name up by this). |
| <a name="output_alb_zone_id"></a> [alb\_zone\_id](#output\_alb\_zone\_id) | Route 53 hosted zone ID of the ALB (for alias records). |
| <a name="output_base_url"></a> [base\_url](#output\_base\_url) | URL clients should use. |
| <a name="output_listener_arn"></a> [listener\_arn](#output\_listener\_arn) | ARN of the listener that forwards to the app (HTTPS if enabled, else HTTP). |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ALB security group ID; the app SG allows ingress only from this. |
| <a name="output_target_group_arn"></a> [target\_group\_arn](#output\_target\_group\_arn) | Target group ARN the ECS service registers into. |
| <a name="output_target_group_arn_suffix"></a> [target\_group\_arn\_suffix](#output\_target\_group\_arn\_suffix) | ARN suffix used as the TargetGroup CloudWatch dimension. |
<!-- END_TF_DOCS -->
