variable "name" {
  description = "Name prefix, e.g. \"icp-dev\". Used for cluster, service, task family and SG names."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.name))
    error_message = "name must be 3-32 lowercase alphanumeric/hyphen characters."
  }
}

# ----------------------------------------------------------- Networking

variable "vpc_id" {
  description = "VPC for the service security group."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets tasks run in (no public IPs are assigned)."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 1
    error_message = "At least one private subnet is required."
  }
}

variable "alb_security_group_id" {
  description = "ALB security group; the only allowed ingress source for the container port."
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group the service registers tasks into."
  type        = string
}

variable "egress_cidrs" {
  description = "CIDRs tasks may reach on 443 (ECR, CloudWatch, STS via NAT). Narrow if you use VPC endpoints only."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ------------------------------------------------------------ Container

variable "container_name" {
  description = "Name of the application container in the task definition."
  type        = string
  default     = "app"
}

variable "container_image" {
  description = "Initial image, pinned by digest (repo@sha256:...). Later deploys come from CI; Terraform ignores task-definition drift on the service."
  type        = string

  validation {
    condition     = can(regex("^[^\\s]+@sha256:[a-f0-9]{64}$", var.container_image))
    error_message = "container_image must be pinned by digest: <repository>@sha256:<64 hex chars>."
  }
}

variable "container_port" {
  description = "Port the application listens on."
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.cpu)
    error_message = "cpu must be a Fargate-supported value: 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}

variable "memory" {
  description = "Task memory in MiB. Must be a valid pairing for the chosen cpu (e.g. 256 -> 512/1024/2048)."
  type        = number
  default     = 512

  validation {
    condition     = var.memory >= 512 && var.memory <= 122880
    error_message = "memory must be between 512 and 122880 MiB."
  }
}

variable "cpu_architecture" {
  description = "X86_64 or ARM64 (Graviton, ~20% cheaper; image must be built for arm64)."
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "environment_variables" {
  description = "Plain (non-secret) environment variables for the container."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Container env vars sourced from Secrets Manager / SSM: { ENV_NAME = secret_or_parameter_arn }."
  type        = map(string)
  default     = {}
}

variable "log_group_name" {
  description = "CloudWatch log group the awslogs driver writes to."
  type        = string
}

variable "execution_role_arn" {
  description = "Task execution role ARN (image pull, logs)."
  type        = string
}

variable "task_role_arn" {
  description = "Task (application) role ARN."
  type        = string
}

# -------------------------------------------------------------- Service

variable "create_cluster" {
  description = "Create a dedicated ECS cluster. Set false to place the service in cluster_name."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Existing cluster name when create_cluster = false."
  type        = string
  default     = null
}

variable "enable_container_insights" {
  description = "Enable Container Insights (extra CloudWatch metrics; adds cost). Enables RunningTaskCount alarms."
  type        = bool
  default     = false
}

variable "desired_count" {
  description = "Initial task count. Autoscaling owns it afterwards (Terraform ignores drift)."
  type        = number
  default     = 1
}

variable "min_capacity" {
  description = "Autoscaling minimum tasks."
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Autoscaling maximum tasks."
  type        = number
  default     = 2

  validation {
    condition     = var.max_capacity >= 1 && var.max_capacity <= 100
    error_message = "max_capacity must be between 1 and 100."
  }
}

variable "enable_autoscaling" {
  description = "Enable target-tracking autoscaling on CPU and memory."
  type        = bool
  default     = true
}

variable "cpu_target_percent" {
  description = "Target average CPU utilisation for scaling."
  type        = number
  default     = 60
}

variable "memory_target_percent" {
  description = "Target average memory utilisation for scaling."
  type        = number
  default     = 75
}

variable "fargate_spot_weight" {
  description = "Relative weight for FARGATE_SPOT (0 = on-demand only). Spot can be reclaimed; avoid in prod."
  type        = number
  default     = 0

  validation {
    condition     = var.fargate_spot_weight >= 0 && var.fargate_spot_weight <= 100
    error_message = "fargate_spot_weight must be between 0 and 100."
  }
}

variable "deployment_minimum_healthy_percent" {
  description = "Minimum healthy percent during deployments."
  type        = number
  default     = 100
}

variable "deployment_maximum_percent" {
  description = "Maximum percent during deployments."
  type        = number
  default     = 200
}

variable "health_check_grace_period_seconds" {
  description = "Seconds ECS ignores ALB health checks after a task starts."
  type        = number
  default     = 30
}

variable "enable_execute_command" {
  description = "Allow `aws ecs execute-command` into running tasks (requires task role permission)."
  type        = bool
  default     = false
}

variable "wait_for_steady_state" {
  description = "Make terraform apply wait until the service is stable."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
