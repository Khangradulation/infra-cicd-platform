output "log_group_name" {
  description = "Application log group name."
  value       = aws_cloudwatch_log_group.app.name
}

output "log_group_arn" {
  description = "Application log group ARN (without :*)."
  value       = aws_cloudwatch_log_group.app.arn
}

output "kms_key_arn" {
  description = "Observability KMS key ARN, or null when create_kms_key = false."
  value       = local.kms_key_arn
}

output "alarm_topic_arn" {
  description = "SNS topic alarms publish to."
  value       = aws_sns_topic.alarms.arn
}

output "alarm_names" {
  description = "Names of all CloudWatch alarms created."
  value = concat(
    [
      aws_cloudwatch_metric_alarm.cpu_high.alarm_name,
      aws_cloudwatch_metric_alarm.memory_high.alarm_name,
      aws_cloudwatch_metric_alarm.unhealthy_targets.alarm_name,
      aws_cloudwatch_metric_alarm.no_healthy_targets.alarm_name,
      aws_cloudwatch_metric_alarm.target_5xx.alarm_name,
      aws_cloudwatch_metric_alarm.elb_5xx.alarm_name,
      aws_cloudwatch_metric_alarm.latency_p95.alarm_name,
      aws_cloudwatch_metric_alarm.app_errors.alarm_name,
    ],
    aws_cloudwatch_metric_alarm.running_tasks_low[*].alarm_name,
  )
}

output "dashboard_name" {
  description = "CloudWatch dashboard name (null if disabled)."
  value       = var.enable_dashboard ? aws_cloudwatch_dashboard.this[0].dashboard_name : null
}
