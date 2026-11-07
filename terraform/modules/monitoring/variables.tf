variable "name" {
  description = "Name prefix, e.g. \"icp-dev\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.name))
    error_message = "name must be 3-32 lowercase alphanumeric/hyphen characters."
  }
}

variable "log_retention_days" {
  description = "Retention for the application log group."
  type        = number
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value accepted by CloudWatch Logs (e.g. 7, 14, 30, 90, 365)."
  }
}

variable "create_kms_key" {
  description = "Create a customer-managed KMS key (~$1/month) to encrypt the log group and alarm SNS topic."
  type        = bool
  default     = true
}

variable "kms_deletion_window_days" {
  description = "Waiting period before the KMS key is deleted on destroy."
  type        = number
  default     = 7

  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "kms_deletion_window_days must be between 7 and 30."
  }
}

# ---------------------------------------------------- Monitored resources

variable "cluster_name" {
  description = "ECS cluster name (CloudWatch ClusterName dimension)."
  type        = string
}

variable "service_name" {
  description = "ECS service name (CloudWatch ServiceName dimension)."
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix (CloudWatch LoadBalancer dimension)."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix (CloudWatch TargetGroup dimension)."
  type        = string
}

variable "container_insights_enabled" {
  description = "Whether Container Insights is enabled on the cluster. RunningTaskCount alarms are only created when true (the metric doesn't exist otherwise)."
  type        = bool
  default     = false
}

variable "min_running_tasks" {
  description = "Alarm if fewer tasks than this are running (requires Container Insights)."
  type        = number
  default     = 1
}

# ------------------------------------------------------------ Thresholds

variable "cpu_alarm_threshold" {
  description = "Average service CPU % that triggers an alarm."
  type        = number
  default     = 80
}

variable "memory_alarm_threshold" {
  description = "Average service memory % that triggers an alarm."
  type        = number
  default     = 85
}

variable "target_5xx_threshold" {
  description = "Target (app) 5xx responses per 5 minutes that trigger an alarm."
  type        = number
  default     = 10
}

variable "elb_5xx_threshold" {
  description = "ALB-generated 5xx responses per 5 minutes that trigger an alarm."
  type        = number
  default     = 10
}

variable "latency_p95_threshold_seconds" {
  description = "p95 target response time (seconds) that triggers an alarm."
  type        = number
  default     = 1.5
}

variable "app_error_threshold" {
  description = "ERROR-level application log lines per 5 minutes that trigger an alarm."
  type        = number
  default     = 5
}

# ------------------------------------------------------------ Notification

variable "alarm_email_addresses" {
  description = "Email addresses subscribed to the alarm topic (each must confirm the subscription)."
  type        = list(string)
  default     = []
  sensitive   = true

  validation {
    condition     = alltrue([for e in var.alarm_email_addresses : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "alarm_email_addresses must be valid email addresses."
  }
}

variable "enable_dashboard" {
  description = "Create a CloudWatch dashboard (first 3 per account free, then $3/month each)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
