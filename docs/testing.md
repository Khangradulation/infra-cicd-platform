# Testing and validation

## Automated test matrix

| Layer | Command (local) | CI workflow | Needs AWS? |
|---|---|---|---|
| Terraform format | `make fmt-check` | terraform-pr | no |
| Terraform validate: 5 roots, 8 modules, 2 examples | `make validate` | terraform-pr | no |
| Module unit tests: `terraform test`, 8 suites, mocked provider | `make tf-test` | terraform-pr | no |
| TFLint (preset `all` + AWS ruleset 0.50.0) | `make tflint` | terraform-pr | no |
| Checkov | `make checkov` | terraform-pr, security-scan | no |
| Trivy IaC + secrets | `trivy config .` / `trivy fs --scanners secret .` | security-scan | no |
| Terraform plan per env | `scripts/tf.sh plan <env>` | terraform-pr, terraform-apply | **yes** |
| App lint (ruff) + unit tests (21, coverage gate 90%) | `make app-lint app-test` | app-ci | no |
| Dockerfile lint | `make hadolint` | app-ci, lint | no |
| Docker build + hardened container smoke test | `make docker-build docker-smoke` | app-ci | no (Docker) |
| Image scan (fixable HIGH/CRITICAL gate) | `make trivy` | app-ci | no |
| Workflow lint (actionlint + embedded shellcheck) | `make actionlint` | lint | no |
| Script lint + script tests (plan summariser, deploy logic against a fake AWS CLI) | `make shellcheck`; `python3 -m unittest discover -s scripts/tests` | lint | no |
| Deploy verification: rollout, digest, ALB health | `scripts/deploy-ecs.sh` | deploy | **yes** |
| Smoke via ALB | `scripts/smoke-test-url.sh` | deploy (all envs) | **yes** |
| Integration tests | `pytest tests/integration -m integration` | deploy (staging) | **yes** |
| OIDC claims + role assumption | n/a | oidc-check | **yes** |

`make ci` runs every row that needs neither AWS nor Docker.

## What the deploy-logic tests prove (offline)

`scripts/tests/test_scripts.py` runs the real `deploy-ecs.sh` against `fake_aws.py`:

| Scenario | Expected | Asserted |
|---|---|---|
| success | registers `repo@digest`, strips read-only task-def fields, verifies digest, outputs URL | ✔ |
| circuit-breaker rollback | job fails with "circuit breaker rolled … back" | ✔ |
| rollout FAILED | job fails | ✔ |
| task running a different digest | job fails | ✔ |
| digest not in ECR | job fails **before** `update-service` is called | ✔ |
| rollout never completes | job fails on timeout | ✔ |
| malformed digest (`latest`) | exit 2 | ✔ |

These tests show the script's decisions are correct. They don't show that real ECS behaves
the way the fake does. The live checklist below covers that.

## Per-environment verification checklist (live AWS)

Tick an item only when you have the evidence listed for it.

### Once (shared)

- [ ] **OIDC works.** `oidc-check` run shows `sub` equal to a value in `terraform output trusted_subjects`, and prints `Assumed: icp-gha-terraform-plan/...`.
- [ ] **ECR receives the image.** The `app-ci` run on `main` shows "Published image" with tag = commit SHA and a digest. `aws ecr describe-images --repository-name icp/app --image-ids imageTag=<sha>` returns the same digest.
- [ ] **Tag immutability.** Re-running the same `app-ci` run logs "already exists (immutable); reusing".
- [ ] **PR cannot apply.** On a PR, the jobs list shows no `apply` job. CloudTrail shows only `icp-gha-terraform-plan` sessions for that run.

### dev / staging / prod (repeat for each)

- [ ] **Plan before apply.** The `terraform-apply` run shows a plan summary for the env, and the apply step logs "Change set matches the reviewed plan".
- [ ] **ECS runs the expected digest.** The deploy log shows "verified N running task(s) … with digest sha256:…". To check independently:
      `aws ecs describe-tasks --cluster icp-<env> --tasks $(aws ecs list-tasks --cluster icp-<env> --service-name icp-<env> --query 'taskArns' --output text) --query 'tasks[].containers[].imageDigest'`
- [ ] **ALB health checks pass.** `aws elbv2 describe-target-health --target-group-arn <tg>` shows all targets `healthy`. The dashboard's healthy-host widget is ≥ 1.
- [ ] **Smoke test passes.** The deploy log shows `ok serving expected commit <sha>`.
- [ ] **Logs are structured.** CloudWatch Logs Insights on `/ecs/icp-<env>` with `fields level, path, status | limit 20` returns parsed fields.
- [ ] **Alarms are wired.** `aws cloudwatch describe-alarms --alarm-name-prefix icp-<env>-` lists 8 alarms (9 in prod). After the first traffic, none are `INSUFFICIENT_DATA` except `no-healthy-targets` before the first deploy.
- [ ] **staging only: integration tests pass.** The `integration-report` artifact shows 5 passed.

### Gates

- [ ] **Production approval blocks promotion.** The `production` job shows "Waiting for review". Rejecting it (or not approving) leaves prod on the previous digest; check with the ECS describe command above. *Needs required reviewers to be available on your GitHub plan.*
- [ ] **Unauthorized ref blocked.** Running `deploy` from a feature branch fails in `validate` with "Deployments run only from main or a v* release tag".
- [ ] **Failed staging tests stop prod.** Temporarily break `/version` on a branch, merge to a throwaway env or use a PR preview, and confirm the `production` job is skipped. *Optional: only in a sandbox account.*

### Rollback

- [ ] **Automatic rollback.** Deploy an image whose `/health` returns 500, or set `GUNICORN_WORKERS=0` in a test task definition. ECS events show the circuit breaker, the service returns to the previous revision, and the deploy job fails with the "circuit breaker" message. *Do this in dev only.*
- [ ] **Manual rollback.** `rollback` workflow for dev with no revision. The summary shows the previous revision, and `/version` serves the previous commit.

### Teardown (see cost.md)

- [ ] After destroying dev, `aws ecs describe-clusters --clusters icp-dev` shows `INACTIVE` or missing, and `aws ec2 describe-nat-gateways --filter Name=tag:Environment,Values=dev` shows none `available`.

## Evidence recorded so far

See [implementation-report.md](implementation-report.md). It separates what was executed
from what still needs AWS access.
