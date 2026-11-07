variable "name" {
  description = "Name prefix for all resources, e.g. \"icp-dev\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.name))
    error_message = "name must be 3-32 chars of lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR for the VPC. A /16 to /20 is expected; subnets are carved with +4 bits."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be a valid IPv4 CIDR with a prefix length between /16 and /20."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across (2-4)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4 && floor(var.az_count) == var.az_count
    error_message = "az_count must be an integer between 2 and 4 (an ALB needs at least 2 AZs)."
  }
}

variable "nat_gateway_mode" {
  description = <<-EOT
    Egress for private subnets:
      "single" - one NAT gateway shared by all AZs (cheapest; AZ failure breaks egress)
      "per_az" - one NAT gateway per AZ (production)
      "none"   - no NAT; private subnets have no internet egress (you must add VPC interface endpoints)
  EOT
  type        = string
  default     = "single"

  validation {
    condition     = contains(["single", "per_az", "none"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode must be one of: single, per_az, none."
  }
}

variable "enable_s3_gateway_endpoint" {
  description = "Create a (free) S3 gateway endpoint on private route tables so ECR layer downloads bypass the NAT."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Send VPC flow logs (REJECT + ACCEPT) to CloudWatch Logs."
  type        = bool
  default     = false
}

variable "flow_logs_retention_days" {
  description = "Retention for the flow-log log group."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_logs_retention_days)
    error_message = "flow_logs_retention_days must be a value accepted by CloudWatch Logs (e.g. 7, 14, 30, 90, 365)."
  }
}

variable "flow_logs_kms_key_arn" {
  description = "Optional KMS key ARN to encrypt the flow-log log group. The key policy must allow logs.<region>.amazonaws.com."
  type        = string
  default     = null
}

variable "permissions_boundary_arn" {
  description = "Optional permissions boundary attached to the flow-log IAM role."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource (merged with provider default_tags)."
  type        = map(string)
  default     = {}
}
