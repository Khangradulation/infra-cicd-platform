variable "name" {
  description = "Repository name, e.g. \"icp/app\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*$", var.name)) && length(var.name) <= 256
    error_message = "name must be a valid ECR repository name (lowercase, digits, '.', '_', '-', '/')."
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN for image encryption. null uses AES256 (SSE-S3, no extra cost)."
  type        = string
  default     = null
}

variable "scan_on_push" {
  description = "Enable ECR basic scanning on push (free). Trivy in CI is the blocking gate."
  type        = bool
  default     = true
}

variable "max_tagged_images" {
  description = "Keep at most this many tagged images; older ones expire (rollback window)."
  type        = number
  default     = 50

  validation {
    condition     = var.max_tagged_images >= 5 && var.max_tagged_images <= 1000
    error_message = "max_tagged_images must be between 5 and 1000."
  }
}

variable "untagged_expiry_days" {
  description = "Expire untagged images (e.g. failed/partial pushes) after this many days."
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_expiry_days >= 1
    error_message = "untagged_expiry_days must be >= 1."
  }
}

variable "pull_principal_arns" {
  description = "Additional IAM principal ARNs (e.g. other accounts) allowed to pull. Same-account roles use IAM policies instead."
  type        = list(string)
  default     = []
}

variable "force_delete" {
  description = "Allow `terraform destroy` to delete the repository even if it contains images. Keep false outside sandboxes."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
