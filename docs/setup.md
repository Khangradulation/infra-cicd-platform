# Setup: from an empty AWS account to a first production deploy

Every command here is run by a human administrator. Steps 2–4 create billable AWS
resources. [cost.md](cost.md) has the estimates and the teardown steps.

## 0. Prerequisites

| Need | Version used / notes |
|---|---|
| AWS account + admin credentials for the one-time bootstrap | Prefer IAM Identity Center (`aws sso login`) over long-lived keys. CI never uses keys. |
| Terraform | `1.17.x` (pinned with `required_version = "~> 1.17.0"`; CI uses 1.17.1) |
| AWS CLI v2, `jq`, `gh` (logged in as a repo admin), Python 3.12+, Docker | |
| GitHub repository | This repo. Note whether it's public or private, and your GitHub plan. See [Production approval](#production-approval-and-github-plans). |

Pick one region (examples use `us-east-1`) and use it for everything.

## 1. Clone and check locally (no AWS needed)

```bash
make venv ci          # fmt, validate, TFLint, Checkov, terraform test, ruff, pytest, actionlint
```

## 2. Bootstrap the state bucket (local state, once per account)

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars    # set region
terraform init
terraform plan -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
terraform output                                 # state_bucket_name, state_kms_key_arn, region
cd ../..
scripts/write-backend-config.sh                  # writes git-ignored backend.hcl for each root
```

This creates:

* A versioned S3 bucket with SSE-KMS (customer-managed key, rotation on, bucket key on).
* Public access blocked and ACLs disabled (BucketOwnerEnforced).
* A bucket policy that denies non-TLS access, TLS below 1.2, and writes encrypted with a different KMS key.
* A lifecycle rule keeping 90 days of old state versions.
* `prevent_destroy` on both the bucket and the key.

Locking uses Terraform's native S3 lockfile (`use_lockfile = true`), so no DynamoDB table is needed.

The bootstrap state stays in `terraform/bootstrap/terraform.tfstate`. It's git-ignored, so keep
it safe. To move it into the bucket afterwards, follow `terraform/bootstrap/backend.tf.example`.

## 3. Shared stack: ECR, OIDC provider, CI roles

Look up this repository's exact OIDC subject prefix. **Don't guess it.** Newer repositories
use GitHub's immutable format, which embeds numeric owner and repo IDs:

```bash
gh api repos/<OWNER>/<REPO>/actions/oidc/customization/sub --jq .sub_claim_prefix
# e.g. repo:<owner>@<owner_id>/<repo>@<repo_id>
```

```bash
cd terraform/environments/shared
cp terraform.tfvars.example terraform.tfvars
#   region, github_owner, github_repository, state_bucket_name, state_kms_key_arn  (from step 2)
#   oidc_sub_claim_prefix = "<value printed above>"
cd ../../..
scripts/tf.sh plan shared
CONFIRM=shared scripts/tf.sh apply shared
terraform -chdir=terraform/environments/shared output trusted_subjects   # check these match your repo
```

> If the account already has a `token.actions.githubusercontent.com` provider, set
> `create_oidc_provider = false` and `existing_oidc_provider_arn`.

## 4. Configure GitHub

```bash
DRY_RUN=1 scripts/github-setup.sh <OWNER>/<REPO> --reviewer <your-github-login>   # preview
scripts/github-setup.sh <OWNER>/<REPO> --reviewer <your-github-login>
```

The script:

* Creates the environments `dev`, `staging`, `production`, `infra-dev`, `infra-staging`, and `infra-production`.
* Restricts deployment branches to `main`. `production` also allows `v*` tags.
* Adds required reviewers to `production` and `infra-production`.
* Sets these variables (none of them are secrets):

| Scope | Variable | Source |
|---|---|---|
| repo | `AWS_REGION` | your region |
| repo | `TF_STATE_BUCKET`, `TF_STATE_KMS_KEY_ARN` | bootstrap outputs |
| repo | `ECR_REPOSITORY` | `icp/app` |
| repo | `AWS_PLAN_ROLE_ARN`, `AWS_ECR_PUSH_ROLE_ARN` | shared outputs |
| `infra-dev`, `infra-staging`, `infra-production` | `AWS_APPLY_ROLE_ARN` | shared outputs |
| `dev`, `staging`, `production` | `AWS_DEPLOY_ROLE_ARN` | shared outputs |
| repo | `BOOTSTRAP_IMAGE_URI` | **step 6** |

Then, in repository settings:

* Protect `main`: require a PR, require the `terraform-pr`, `app-ci`, and `lint` checks, and block force-pushes.
* Optionally require signed commits.

Verify OIDC: **Actions → oidc-check → Run workflow**. The printed `sub` must appear in
`trusted_subjects`, and the job must print `Assumed: icp-gha-terraform-plan/...`.

## 5. Push the first image

Merge or push to `main` with a change under `application/`. `app-ci` tests and scans the
image, then pushes it to ECR as `:<git-sha>`. The `deploy` job fails at this point, because
the environments don't exist yet.

```bash
aws ecr describe-images --repository-name icp/app --query 'sort_by(imageDetails,&imagePushedAt)[-1].[imageDigest,imageTags[0]]'
```

## 6. Create the environments

```bash
gh variable set BOOTSTRAP_IMAGE_URI --body "<ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/icp/app@sha256:<DIGEST>"
```

Run **Actions → terraform-apply → Run workflow** on `main`. dev and staging apply
automatically when their plan has changes. `prod` waits for an `infra-production` reviewer.

To do it locally instead:

```bash
cp terraform/environments/dev/terraform.tfvars.example terraform/environments/dev/terraform.tfvars
scripts/tf.sh plan dev && scripts/tf.sh apply dev
```

## 7. First real deploy

Re-run the failed `deploy` workflow from step 5, or use **Actions → deploy → Run workflow**
with the digest. Promotion runs dev → staging → (approval) → production. See
[deployment.md](deployment.md).

## Optional hardening (recommended for production)

1. **ACM certificate.** Set `certificate_arn` in `terraform/environments/prod` (and the others).
   HTTP then redirects to HTTPS on TLS 1.3/1.2. The prod root's `check` block warns until you do.
2. **Ref-bound OIDC subjects.**
   1. Run `scripts/github-setup.sh <OWNER>/<REPO> --reviewer <login> --oidc-sub-with-ref`.
   2. Re-read `sub_claim_prefix` with the `gh api` command from step 3, because the format can change.
   3. Set `oidc_subject_includes_ref = true` and re-apply `shared`.

   IAM then rejects environment jobs from any ref other than `main` (or `v*` tags for production).
3. **Alarm emails.** Set `alarm_email_addresses` and confirm the SNS subscription emails.
4. **State bucket admins.** Set `state_admin_principal_arns` in bootstrap.

## Production approval and GitHub plans

Required reviewers and deployment-branch rules on Environments are available on **public
repositories (any plan)** or **private repositories on GitHub Pro, Team, or Enterprise**. On a
private repo on the Free plan, the `production` environment still exists, but GitHub
**doesn't pause for approval**. These controls still apply in that case:

* The workflow only allows `main` or `v*` tags into production (an `if:` guard and a validate job).
* IAM trusts only the `production` environment subject. With ref-bound subjects, it also requires `main` or `v*`.
* `CODEOWNERS` and branch protection need the same paid plan for private repos.

To get an enforced human approval gate, make the repository public or upgrade the plan.
