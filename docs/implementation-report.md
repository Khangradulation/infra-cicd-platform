# Implementation report

_Generated 2026-11-07, updated 2026-11-08 after the live setup in AWS account
811290421916 (us-east-2). The repository started with only the initial README in
`Khangradulation/infra-cicd-platform`._

## Status at a glance

| Area | Built | Verified locally | Verified on AWS / GitHub |
|---|---|---|---|
| Repo structure, Makefile, docs | ✅ | ✅ `make help`, `make ci` | n/a |
| Terraform modules (networking, ecr, iam, alb, ecs, monitoring, github-oidc, app-stack) | ✅ | ✅ validate, 29 `terraform test` runs, TFLint, Checkov, Trivy config | ✅ ecr, github-oidc, and the full dev stack applied and destroyed from CI |
| Bootstrap (S3 + KMS, local state, $10 budget) | ✅ | ✅ validate, Checkov | ✅ applied; budget `icp-monthly-cost` with 50/80/100% actual + 100% forecast alerts |
| Remote state + native S3 locking per env | ✅ (`use_lockfile = true`, keys `shared/`, `dev/`, `staging/`, `prod/`) | ✅ validate with `-backend=false` | ✅ `shared` (local admin) and `dev` (CI role) use the real bucket |
| dev / staging / prod roots | ✅ | ✅ validate. Plan-level composition test (dev vs prod profiles). | ✅ dev applied + destroyed by the `demo` workflow. ❌ staging/prod not applied (cost). |
| Flask API + tests | ✅ | ✅ ruff, **21 unit tests, 100% coverage** | ✅ served live through the dev ALB (`/health`, `/version`, `/status`) |
| Docker image | ✅ | ✅ hadolint. Build (arm64, Colima). Hardened smoke test **PASS**. Trivy gate **PASS** (0 fixable HIGH/CRITICAL). | ✅ amd64 CI build, smoke test, Trivy gate, push to ECR by digest |
| GitHub OIDC + IAM roles | ✅ | ✅ module tests for trust subjects (classic, immutable-prefix, ref-bound) | ✅ live `AssumeRoleWithWebIdentity` for plan, ecr-push, deploy-dev/staging, apply-dev/staging (prod roles: see below) |
| Workflows (terraform-pr, terraform-apply, app-ci, deploy, rollback, lint, security-scan, oidc-check) | ✅ | ✅ actionlint (+ embedded shellcheck), yamllint, all 35 action refs SHA-pinned | ✅ `oidc-check`, `demo`, `lint` ran on GitHub. ❌ `deploy`/`rollback`/`terraform-apply` not run (no long-lived environments). |
| Deploy / rollback logic | ✅ | ✅ 7 scenario tests of `deploy-ecs.sh` against a fake AWS CLI | ❌ no ECS rolling deploy (demo creates the service directly) |
| Monitoring (logs, metric filters, 8–9 alarms, dashboard, SNS) | ✅ | ✅ module tests (alarm count, Insights gating, retention, KMS) | ✅ created and destroyed with dev (alarms not exercised) |
| Production approval enforced | ✅ wired (`environment: production`) | n/a | ✅ repo is public; `production` + `infra-production` require **Khangradulation**; jobs paused for approval live |
| Teardown | ✅ docs/cost.md, `demo` destroy job, `demo-local.sh up <min>` timer | ✅ timer tested with stubbed terraform (fires, survives Ctrl+C, cancels) | ✅ `demo` destroy job: 0 resources in dev state; no ECS cluster, ALB, NAT gateway, EIP, or project VPC left in us-east-2 |

**Not verified live yet:** a rolling `deploy` / `rollback` against a long-lived
environment, staging and prod stacks, and alarm notifications. They need long-lived
environments (~$72–150/month each), which this cost-minimal setup avoids.

## Commands executed and results

| Command | Result |
|---|---|
| `terraform fmt -check -recursive terraform` | pass |
| `terraform init -backend=false && terraform validate` across 5 roots, 8 modules, 2 examples | 15/15 valid |
| `terraform test` (8 suites, mocked AWS provider) | 29 runs passed, 0 failed |
| `terraform providers lock` (linux_amd64/arm64, darwin_amd64/arm64) | aws 6.72.0 locked in 5 roots |
| `tflint --recursive` (preset all + aws ruleset 0.50.0) | 0 issues. A canary file with 5 planted violations was caught, so the linter really runs. |
| `checkov --config-file .checkov.yaml` | 366 passed, 0 failed, 34 skipped (each skip justified inline; catalogue in security.md) |
| `trivy config --severity HIGH,CRITICAL --exit-code 1 .` | exit 0 (after documented inline ignores) |
| `trivy fs --scanners secret .` | no secrets |
| `ruff check` / `ruff format --check` | pass |
| `pytest tests/unit` | 21 passed, coverage 100% (gate 90%) |
| `hadolint application/Dockerfile` | pass |
| `docker build` + `scripts/container-smoke-test.sh` | PASS: UID 10001, `/health` `/` `/version` `/status` 200, JSON 404, HEALTHCHECK healthy, JSON logs, under `--read-only --cap-drop ALL --security-opt no-new-privileges` |
| `trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1` | exit 0. 49 HIGH unfixed Debian CVEs (no upstream fix) reported but not gating. |
| `python3 -m unittest discover -s scripts/tests` | 10 passed (plan summariser + deploy scenarios) |
| `actionlint` | pass (8 workflows + 1 composite action) |
| `shellcheck scripts/*.sh` | pass |
| `.gitignore` probe (`tfvars`, `backend.hcl`, `.tfstate`, `.tfplan`, `.env`) | all ignored |

## Live verification (2026-11-08)

Account 811290421916 ("Escape Velocity"), region us-east-2, admin via `aws login` (no access keys).

| Step | Result |
|---|---|
| `aws sts get-caller-identity` | account 811290421916 |
| `aws iam list-open-id-connect-providers` | empty, so `create_oidc_provider = true` |
| `gh api …/actions/oidc/customization/sub` | `repo:Khangradulation@86319847/infra-cicd-platform@1446438077` |
| `scripts/tf.sh apply shared` | 18 added (OIDC provider, boundary, 8 roles + policies), 1 ECR tag fix. `trusted_subjects` all use the prefix above. |
| bootstrap apply (budget) | `icp-monthly-cost`, $10/month, all spend in the account |
| `scripts/github-setup.sh … --reviewer Khangradulation` | 6 environments, `main`-only deploy branches (+ `v*` tags on production), reviewers on production + infra-production, 6 repo + 6 environment variables |
| `oidc-check` (extended) | assumed `icp-gha-terraform-plan`, `icp-gha-ecr-push`, and the deploy/apply roles via `dev`, `staging`, `infra-dev`, `infra-staging`. The production jobs paused for the required reviewer. `deploy-prod` and `apply-prod` are pending that approval, so they're not yet proven live. |
| `demo` (keep_minutes=15), run 42513128957 | build + Trivy + push, dev apply, health checks through `http://icp-dev-alb-399186190.us-east-2.elb.amazonaws.com`, 15-min hold, destroy. All 4 jobs succeeded; afterwards 0 resources in dev state and no ECS/ALB/NAT/EIP/VPC left. |

Issues found by the live run and fixed:

1. **Linked account can't use the tag-scoped budget.** A member account can't list or
   activate cost-allocation tags, so the `Project` filter would have kept the budget at $0
   forever. Added `budget_scope_to_project_tag` (default `true`; `false` here) and the 80% alert.
2. **Base image lagged Debian security.** Trivy failed on `zlib1g` CVE-2026-76844 and
   CVE-2026-85091 (fixed in `+deb13u1`). Bumping to the newest upstream digest wasn't
   enough, because upstream hadn't rebuilt yet. The runtime stage now runs `apt-get upgrade`.
3. **Apply role couldn't read the shared ECR repo.** The AWS provider calls
   `ecr:ListTagsForResource` for the `aws_ecr_repository` data source. Added it, and
   `iam:ListPolicyTags` for the boundary lookup.
4. **`oidc-check` only proved the plan role.** It now assumes every role, each from its own
   GitHub Environment.
5. **`demo-local.sh shared` would destroy the CI roles** now that OIDC is enabled. It refuses
   when `environments/shared/terraform.tfvars` exists.

## Issues found and fixed during the build

1. **OIDC subject format.** `gh api …/actions/oidc/customization/sub` showed this repo uses
   GitHub's immutable subject prefix `repo:Khangradulation@86319847/infra-cicd-platform@1446438077`.
   Trust policies built from `repo:<owner>/<repo>` would have **rejected every CI login**.
   I added `oidc_sub_claim_prefix` with validation and tests, and documented how to read the value.
2. **Dockerfile shell precedence.** `a && b && c || true && d` would have hidden a failed
   `useradd`. It's now grouped as `{ c || true; }`.
3. **BuildKit-only syntax.** `COPY --chmod` broke legacy builders and was redundant with the
   `chmod` that follows. Removed.
4. **Deploy from feature branches.** `deploy.yml` dispatched from a branch would have reached
   dev and staging. The validate job now allows only `main` or `v*`.
5. **Deploy role** was missing `elasticloadbalancing:DescribeListeners`, needed for HTTPS URL detection. Added.

## Tools installed on this machine

* `trivy`, `actionlint`, `hadolint`, and `terraform-docs` via Homebrew.
* `tflint` 0.65.0 into the session scratchpad, from the official release, with the SHA-256 verified.
* `checkov` and `yamllint` into a scratchpad virtualenv.
* The existing Colima VM was started for Docker builds, then stopped again.

## Remaining manual steps

1. **Confirm the AWS Budgets subscription** if AWS emails a confirmation to the alert address.
2. **Protect `main`** (Settings → Branches): require a PR plus the `terraform-pr`, `app-ci`,
   and `lint` checks, and block force-pushes. It's unprotected today.
3. To run long-lived environments: set `BOOTSTRAP_IMAGE_URI`, then run `terraform-apply`
   (setup.md steps 6–7). This is billable.
4. Optional: get an ACM certificate (HTTPS) and set alarm email addresses.

## Estimated AWS cost

**Idle (what runs now):** the state bucket (a few KB), the state KMS key ($1/month), and ECR
(3 images, ~135 MB, about $0.01/month), so **about $1/month**. Destroyed dev KMS keys
sit in a free 7-day pending-deletion window. IAM, OIDC, and the budget are free. A demo costs
~$0.10–0.15 per hour that dev exists.

**Everything running 24/7:**

About $72–78 per month each for dev and staging, $140–150 for prod, and about $2 shared:
**roughly $290/month** with everything running 24/7. See [cost.md](cost.md) for the
breakdown, cost levers, and exact cleanup commands.
