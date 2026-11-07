variable "region" {
  description = "AWS region for the state bucket (use the same region as your environments)."
  type        = string
}

variable "name_prefix" {
  description = "Project prefix; the bucket defaults to <prefix>-tfstate-<account>-<region>."
  type        = string
  default     = "icp"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.name_prefix))
    error_message = "name_prefix must be 2-10 lowercase alphanumeric characters."
  }
}

variable "state_bucket_name" {
  description = "Override the generated bucket name (must be globally unique)."
  type        = string
  default     = null

  validation {
    condition     = var.state_bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "state_bucket_name must be a valid S3 bucket name."
  }
}

variable "noncurrent_version_retention_days" {
  description = "Days to keep previous state versions (your recovery window for a bad apply)."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_retention_days >= 30
    error_message = "Keep at least 30 days of state history."
  }
}

variable "state_admin_principal_arns" {
  description = <<-EOT
    Optional IAM principal ARN patterns (e.g. your SSO admin role) that are the ONLY principals allowed to
    delete the bucket or change its policy/versioning/encryption. Leave empty to rely on IAM alone.
    WARNING: a wrong value here can lock you out of managing the bucket; root can always recover.
  EOT
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Extra tags (merged into provider default_tags)."
  type        = map(string)
  default     = {}
}

variable "budget_alert_emails" {
  description = "Emails for the project cost budget alerts. Empty = no budget created."
  type        = list(string)
  default     = []
  sensitive   = true

  validation {
    condition     = alltrue([for e in var.budget_alert_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "budget_alert_emails must be valid email addresses."
  }
}

variable "monthly_budget_usd" {
  description = "Monthly budget for resources tagged Project=infra-cicd-platform."
  type        = number
  default     = 5

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd must be positive."
  }
}

variable "activate_cost_allocation_tag" {
  description = "Activate 'Project' as a cost-allocation tag (only possible ~24h after AWS first sees the tag)."
  type        = bool
  default     = false
}
