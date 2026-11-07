variable "region" {
  description = "AWS region (same as the state bucket and environments)."
  type        = string
}

variable "github_owner" {
  description = "GitHub user/organisation owning the repository (case-sensitive)."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name."
  type        = string
}

variable "state_bucket_name" {
  description = "Output state_bucket_name from terraform/bootstrap."
  type        = string
}

variable "state_kms_key_arn" {
  description = "Output state_kms_key_arn from terraform/bootstrap."
  type        = string
}

variable "ecr_repository_name" {
  description = "Shared application image repository."
  type        = string
  default     = "icp/app"
}

variable "oidc_sub_claim_prefix" {
  description = "Exact OIDC sub prefix for the repo: gh api repos/OWNER/REPO/actions/oidc/customization/sub --jq .sub_claim_prefix"
  type        = string
  default     = null
}

variable "oidc_subject_includes_ref" {
  description = "true once the repo OIDC subject template includes the git ref (see modules/github-oidc)."
  type        = bool
  default     = false
}

variable "create_oidc_provider" {
  description = "false if this account already has a token.actions.githubusercontent.com provider."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "Existing provider ARN when create_oidc_provider = false."
  type        = string
  default     = null
}
