variable "name_prefix" {
  description = "Project prefix (must match the github-oidc module's name_prefix so CI role scoping lines up)."
  type        = string
  default     = "icp"
}

variable "environment" {
  description = "Environment key: dev, staging or prod. Resources are named <prefix>-<environment>-*."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.environment))
    error_message = "environment must be 2-10 lowercase alphanumeric characters."
  }
}

# ------------------------------------------------------------ Shared lookups

variable "ecr_repository_name" {
  description = "Name of the shared ECR repository created by environments/shared."
  type        = string
  default     = "icp/app"
}

variable "permissions_boundary_name" {
  description = "Name of the workload permissions boundary created by environments/shared (null = no boundary)."
  type        = string
  default     = "icp-workload-boundary"
}

# ------------------------------------------------------------- Networking

variable "vpc_cidr" {
  description = "VPC CIDR (use a distinct range per environment)."
  type        = string
}

variable "az_count" {
  description = "Availability zones."
  type        = number
  default     = 2
}

variable "nat_gateway_mode" {
  description = "single | per_az | none."
  type        = string
  default     = "single"
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs."
  type        = bool
  default     = false
}

# ----------------------------------------------------------------- ALB

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "certificate_arn" {
  description = "ACM certificate for HTTPS (null = HTTP only)."
  type        = string
  default     = null
}

variable "enable_deletion_protection" {
  description = "ALB deletion protection."
  type        = bool
  default     = false
}

variable "enable_alb_access_logs" {
  description = "ALB access logs to S3."
  type        = bool
  default     = false
}

variable "force_destroy_log_buckets" {
  description = "Allow destroy to delete non-empty log buckets (non-prod convenience)."
  type        = bool
  default     = false
}

# ----------------------------------------------------------------- ECS

variable "container_image" {
  description = "Initial digest-pinned image (<repo>@sha256:...)."
  type        = string
}

variable "container_port" {
  description = "Application port."
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "Task CPU units."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Task memory MiB."
  type        = number
  default     = 512
}

variable "cpu_architecture" {
  description = "X86_64 or ARM64."
  type        = string
  default     = "X86_64"
}

variable "desired_count" {
  description = "Initial task count."
  type        = number
  default     = 1
}

variable "min_capacity" {
  description = "Autoscaling min."
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Autoscaling max."
  type        = number
  default     = 2
}

variable "fargate_spot_weight" {
  description = "FARGATE_SPOT weight (0 = none)."
  type        = number
  default     = 0
}

variable "enable_container_insights" {
  description = "Container Insights on the cluster."
  type        = bool
  default     = false
}

variable "enable_execute_command" {
  description = "Allow ECS Exec."
  type        = bool
  default     = false
}

variable "environment_variables" {
  description = "Extra plain env vars for the container (APP_ENV is always set)."
  type        = map(string)
  default     = {}
}

# ----------------------------------------------------------- Monitoring

variable "log_retention_days" {
  description = "Application log retention."
  type        = number
  default     = 14
}

variable "alarm_email_addresses" {
  description = "Alarm notification emails."
  type        = list(string)
  default     = []
  sensitive   = true
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
