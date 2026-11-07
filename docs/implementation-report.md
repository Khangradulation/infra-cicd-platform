# Implementation report

_Generated 2026-11-07. The repository started with only the initial README in
`Khangradulation/infra-cicd-platform`._

## Status at a glance

| Area | Built | Verified locally | Verified on AWS / GitHub |
|---|---|---|---|
| Repo structure, Makefile, docs | ✅ | ✅ `make help`, `make ci` | n/a |
| Terraform modules (networking, ecr, iam, alb, ecs, monitoring, github-oidc, app-stack) | ✅ | ✅ validate, 29 `terraform test` runs, TFLint, Checkov, Trivy config | ❌ not applied |
| Bootstrap (S3 + KMS, local state) | ✅ | ✅ validate, Checkov | ❌ not applied |
| Remote state + native S3 locking per env | ✅ (`use_lockfile = true`, keys `shared/`, `dev/`, `staging/`, `prod/`) | ✅ validate with `-backend=false` | ❌ `init` against a real bucket not run |
| dev / staging / prod roots | ✅ | ✅ validate. Plan-level composition test (dev vs prod profiles). | ❌ no `plan` (no AWS credentials) |
| Flask API + tests | ✅ | ✅ ruff, **21 unit tests, 100% coverage** | n/a |
| Docker image | ✅ | ✅ hadolint. Build (arm64, Colima). Hardened smoke test **PASS**. Trivy gate **PASS** (0 fixable HIGH/CRITICAL). | ❌ amd64 CI build not run |
| GitHub OIDC + IAM roles | ✅ | ✅ module tests for trust subjects (classic, immutable-prefix, ref-bound) | ❌ no live `AssumeRoleWithWebIdentity` |
| Workflows (terraform-pr, terraform-apply, app-ci, deploy, rollback, lint, security-scan, oidc-check) | ✅ | ✅ actionlint (+ embedded shellcheck), yamllint, all 35 action refs SHA-pinned | ❌ no workflow has run on GitHub |
| Deploy / rollback logic | ✅ | ✅ 7 scenario tests of `deploy-ecs.sh` against a fake AWS CLI | ❌ no real ECS deployment |
| Monitoring (logs, metric filters, 8–9 alarms, dashboard, SNS) | ✅ | ✅ module tests (alarm count, Insights gating, retention, KMS) | ❌ not applied |
| Production approval enforced | ✅ wired (`environment: production`) | n/a | ❌ **blocked by GitHub plan.** See below. |
| Teardown instructions | ✅ docs/cost.md | n/a | ❌ not executed (nothing provisioned) |

**Definition-of-done items not met yet:** OIDC works live, CI workflows pass on GitHub,
images published to ECR, ECS deployments, staging checks, enforced prod approval, verified
teardown. Each needs the external configuration listed under
[Remaining manual steps](#remaining-manual-steps).

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

1. **AWS credentials plus your authorization to provision.** Bootstrap and `shared` create
   billable resources (state bucket and KMS key ~ $2/month). Environments cost about
   $72–150/month each.
2. **Decide on production approval.** The repo is private on the GitHub Free plan, where
   required reviewers, deployment-branch rules, and branch protection are unavailable. The
   API returned *"Upgrade to GitHub Pro or make this repository public"*. Options: make the
   repo public, upgrade to Pro (about $4/month), or accept the weaker gate (ref guard plus
   IAM environment trust, with no human pause).
3. Follow [setup.md](setup.md) steps 2–7, then work through the live checklist in [testing.md](testing.md).
4. Optional: get an ACM certificate (HTTPS) and set alarm email addresses.

## Estimated AWS cost

About $72–78 per month each for dev and staging, $140–150 for prod, and about $2 shared:
**roughly $290/month** with everything running 24/7. See [cost.md](cost.md) for the
breakdown, cost levers, and exact cleanup commands.
