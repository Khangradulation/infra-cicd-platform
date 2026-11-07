variable "name_prefix" {
  description = "Project prefix used in every role/policy name and to scope permissions, e.g. \"icp\". Environment resources are expected to be named <prefix>-<env>-*."
  type        = string
  default     = "icp"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.name_prefix))
    error_message = "name_prefix must be 2-10 lowercase alphanumeric characters starting with a letter."
  }
}

variable "github_owner" {
  description = "GitHub organisation or user that owns the repository (case-sensitive, as shown in the URL)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$", var.github_owner))
    error_message = "github_owner must be a valid GitHub user/organisation name."
  }
}

variable "github_repository" {
  description = "Repository name (without owner)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.github_repository))
    error_message = "github_repository must be a valid GitHub repository name."
  }
}

variable "oidc_sub_claim_prefix" {
  description = <<-EOT
    Exact prefix GitHub puts in this repository's OIDC `sub` claim. null = classic "repo:<owner>/<repo>".
    Repositories using GitHub's immutable subject format use "repo:<owner>@<owner_id>/<repo>@<repo_id>".
    Read it, never guess it:  gh api repos/OWNER/REPO/actions/oidc/customization/sub --jq .sub_claim_prefix
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.oidc_sub_claim_prefix == null || can(regex("^repo:[^:*]+$", var.oidc_sub_claim_prefix))
    error_message = "oidc_sub_claim_prefix must look like repo:<owner>/<repo> or repo:<owner>@<id>/<repo>@<id>, without wildcards."
  }
}

variable "trusted_branch" {
  description = "The protected branch allowed to push images, run trusted plans and deploy."
  type        = string
  default     = "main"
}

variable "release_tag_pattern" {
  description = "Git tag glob (IAM StringLike) also allowed to deploy to production when the subject includes the ref."
  type        = string
  default     = "v*"
}

variable "oidc_subject_includes_ref" {
  description = <<-EOT
    Set true AFTER customising the repository's OIDC subject template to include the ref:
      gh api -X PUT repos/OWNER/REPO/actions/oidc/customization/sub \
        -F use_default=false -f 'include_claim_keys[]=repo' -f 'include_claim_keys[]=context' -f 'include_claim_keys[]=ref'
    Environment subjects then end in ":ref:refs/heads/<branch>", letting IAM reject environment jobs
    from untrusted branches even where GitHub deployment-branch rules are unavailable.
  EOT
  type        = bool
  default     = false
}

variable "create_oidc_provider" {
  description = "Create the account-wide GitHub OIDC provider. Set false if it already exists and pass existing_oidc_provider_arn."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "ARN of an existing token.actions.githubusercontent.com provider (when create_oidc_provider = false)."
  type        = string
  default     = null
}

variable "environments" {
  description = <<-EOT
    Deployable environments. Keys are short names used in resource names (<prefix>-<key>-*) and state keys (<key>/...).
    deploy_environment / infra_environment are the GitHub Environment names whose jobs may assume the deploy / apply roles.
  EOT
  type = map(object({
    deploy_environment = string
    infra_environment  = string
    allow_release_tags = optional(bool, false)
  }))
  default = {
    dev     = { deploy_environment = "dev", infra_environment = "infra-dev" }
    staging = { deploy_environment = "staging", infra_environment = "infra-staging" }
    prod    = { deploy_environment = "production", infra_environment = "infra-production", allow_release_tags = true }
  }

  validation {
    condition     = alltrue([for k in keys(var.environments) : can(regex("^[a-z][a-z0-9]{1,9}$", k))])
    error_message = "environment keys must be 2-10 lowercase alphanumeric characters."
  }
}

variable "state_bucket_name" {
  description = "Terraform state bucket name (from terraform/bootstrap output)."
  type        = string
}

variable "state_kms_key_arn" {
  description = "KMS key ARN encrypting the state bucket (from terraform/bootstrap output)."
  type        = string
}

variable "ecr_repository_arn" {
  description = "Shared application ECR repository ARN."
  type        = string
}

variable "allowed_regions" {
  description = "Regions the apply roles may create resources in."
  type        = list(string)

  validation {
    condition     = length(var.allowed_regions) > 0
    error_message = "allowed_regions must contain at least one region."
  }
}

variable "max_session_duration" {
  description = "Maximum CI role session duration in seconds."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 900 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 900 and 43200."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
