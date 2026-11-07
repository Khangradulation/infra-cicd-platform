variable "region" {
  description = "AWS region."
  type        = string
}

variable "container_image" {
  description = "Initial digest-pinned image (<account>.dkr.ecr.<region>.amazonaws.com/icp/app@sha256:...). Only used when the task definition is first created; CI deploys afterwards."
  type        = string
}

variable "alarm_email_addresses" {
  description = "Emails subscribed to alarms (each must confirm)."
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS; null serves HTTP only."
  type        = string
  default     = null
}

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "repository_tag" {
  description = "Value of the Repository tag (e.g. owner/repo)."
  type        = string
  default     = "infra-cicd-platform"
}

variable "permissions_boundary_name" {
  description = "Workload permissions boundary from environments/shared. Empty string = none (local-only mode without GitHub OIDC)."
  type        = string
  default     = "icp-workload-boundary"
}

variable "cpu_architecture" {
  description = "X86_64 or ARM64. ARM64 (Graviton) is ~20% cheaper and matches images built on Apple Silicon."
  type        = string
  default     = "X86_64"
}
