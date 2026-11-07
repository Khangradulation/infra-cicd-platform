# SHARED (account-wide) resources. Applied by an administrator, NOT by CI:
# this root defines the CI roles themselves, so letting CI apply it would let
# CI widen its own permissions.

module "ecr" {
  source = "../../modules/ecr"

  name                 = var.ecr_repository_name
  max_tagged_images    = 100
  untagged_expiry_days = 7
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  github_owner               = var.github_owner
  github_repository          = var.github_repository
  oidc_sub_claim_prefix      = var.oidc_sub_claim_prefix
  oidc_subject_includes_ref  = var.oidc_subject_includes_ref
  create_oidc_provider       = var.create_oidc_provider
  existing_oidc_provider_arn = var.existing_oidc_provider_arn

  state_bucket_name  = var.state_bucket_name
  state_kms_key_arn  = var.state_kms_key_arn
  ecr_repository_arn = module.ecr.repository_arn
  allowed_regions    = [var.region]
}
