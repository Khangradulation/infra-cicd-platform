variable "name" {
  description = "Name prefix, e.g. \"icp-dev\". Roles are named <name>-task-execution and <name>-task."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,40}$", var.name))
    error_message = "name must be 2-41 alphanumeric/hyphen characters so derived role names stay under 64 chars."
  }
}

variable "ecr_repository_arns" {
  description = "ECR repositories the execution role may pull from."
  type        = list(string)

  validation {
    condition     = length(var.ecr_repository_arns) > 0 && alltrue([for a in var.ecr_repository_arns : can(regex("^arn:aws[a-z-]*:ecr:", a))])
    error_message = "ecr_repository_arns must be a non-empty list of ECR repository ARNs."
  }
}

variable "log_group_arn" {
  description = "CloudWatch log group ARN (without :*) the containers write to."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:logs:", var.log_group_arn))
    error_message = "log_group_arn must be a CloudWatch Logs log group ARN."
  }
}

variable "secret_arns" {
  description = "Secrets Manager secret / SSM parameter ARNs the execution role may read to inject as container secrets."
  type        = list(string)
  default     = []
}

variable "kms_key_arns" {
  description = "KMS keys the execution role may use to decrypt secrets (only if secrets use a CMK)."
  type        = list(string)
  default     = []
}

variable "task_role_policy_json" {
  description = "Optional inline policy JSON granting the application itself AWS permissions. Default: none."
  type        = string
  default     = null
}

variable "enable_execute_command" {
  description = "Grant the task role the SSM channel permissions needed for `aws ecs execute-command`."
  type        = bool
  default     = false
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary attached to both roles. Required by the CI apply roles' IAM conditions."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
