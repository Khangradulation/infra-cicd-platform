variable "name" {
  description = "Name prefix, e.g. \"icp-dev\". ALB and target group names derive from it (max 32 chars in AWS)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,24}[a-z0-9]$", var.name))
    error_message = "name must be 3-26 lowercase alphanumeric/hyphen characters (AWS limits ALB/TG names to 32)."
  }
}

variable "vpc_id" {
  description = "VPC to place the ALB and target group in."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR; ALB egress is limited to the target port inside this range."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets (>= 2 AZs) for the ALB."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "An ALB requires subnets in at least two availability zones."
  }
}

variable "target_port" {
  description = "Container port the target group forwards to."
  type        = number
  default     = 8080

  validation {
    condition     = var.target_port > 0 && var.target_port < 65536
    error_message = "target_port must be a valid TCP port."
  }
}

variable "health_check_path" {
  description = "HTTP path the ALB probes on each target."
  type        = string
  default     = "/health"

  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "health_check_path must start with '/'."
  }
}

variable "health_check_interval" {
  description = "Seconds between health checks."
  type        = number
  default     = 15
}

variable "healthy_threshold" {
  description = "Consecutive successes before a target is healthy."
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Consecutive failures before a target is unhealthy."
  type        = number
  default     = 3
}

variable "deregistration_delay" {
  description = "Seconds to drain connections from a target before deregistering (affects deploy speed)."
  type        = number
  default     = 30

  validation {
    condition     = var.deregistration_delay >= 0 && var.deregistration_delay <= 3600
    error_message = "deregistration_delay must be between 0 and 3600."
  }
}

variable "allowed_ingress_cidrs" {
  description = "IPv4 CIDRs allowed to reach the ALB on 80/443. Restrict for internal/non-prod environments."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for c in var.allowed_ingress_cidrs : can(cidrhost(c, 0))])
    error_message = "allowed_ingress_cidrs must contain valid IPv4 CIDRs."
  }
}

variable "certificate_arn" {
  description = "ACM certificate ARN. When set, HTTPS:443 is served and HTTP:80 redirects to it."
  type        = string
  default     = null

  validation {
    condition     = var.certificate_arn == null || can(regex("^arn:aws[a-z-]*:acm:", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN or null."
  }
}

variable "ssl_policy" {
  description = "TLS policy for the HTTPS listener."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "idle_timeout" {
  description = "ALB idle timeout in seconds."
  type        = number
  default     = 60
}

variable "enable_deletion_protection" {
  description = "Prevent the ALB from being deleted (set true in prod; must be disabled before teardown)."
  type        = bool
  default     = false
}

variable "enable_access_logs" {
  description = "Create an S3 bucket and enable ALB access logs."
  type        = bool
  default     = false
}

variable "access_logs_retention_days" {
  description = "Days to keep ALB access logs."
  type        = number
  default     = 90
}

variable "access_logs_force_destroy" {
  description = "Allow destroying the access-log bucket while it still contains logs."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
