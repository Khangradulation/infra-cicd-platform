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
