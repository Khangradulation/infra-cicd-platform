# Deployment, promotion, approvals and rollback

## Workflows at a glance

| Workflow | Trigger | AWS role | Can change AWS? |
|---|---|---|---|
| `terraform-pr` | PR touching `terraform/**` | `icp-gha-terraform-plan` (read-only, lock objects only) | **No** |
| `terraform-apply` | push to `main` (terraform paths), manual | plan role, then `icp-gha-terraform-apply-<env>` inside `infra-<env>` | Yes, gated |
| `app-ci` | PR / push touching `application/**` | `icp-gha-ecr-push` on `main` only | Pushes images only |
| `deploy` | called by `app-ci` on `main`, or manual with a digest | `icp-gha-deploy-<env>` inside `dev` / `staging` / `production` | Updates ECS only |
| `rollback` | manual | `icp-gha-deploy-<env>` | Updates ECS only |
| `lint`, `security-scan`, `oidc-check` | PR/push, weekly, manual | plan role (`oidc-check`) | No |

## Infrastructure changes

1. Open a PR. `terraform-pr` runs fmt, validate, `terraform test`, TFLint, and Checkov.
   It then plans dev, staging, and prod with the read-only role and comments one summary on
   the PR. The comment lists addresses and actions only, never attribute values.
2. Merge. `terraform-apply` runs dev → staging → prod in sequence. For each environment:
   * **plan** with the read-only role. If there are no changes, the environment is skipped
     with no approval prompt.
   * **apply** inside `infra-<env>`. For prod, an `infra-production` reviewer approves after
     reading the plan summary on the run page.
   * The apply job **re-plans and compares a change-set fingerprint** against the approved
     plan. If anything changed between approval and apply, it refuses to apply.
3. A `concurrency: terraform-state-<env>` group (no cancel-in-progress) serialises runs
   against the same state. The native S3 lockfile also protects against local runs.

## Application releases

```
PR ──► app-ci: ruff, pytest(cov≥90%), hadolint, build once, container smoke test, Trivy gate
merge ──► app-ci (main): same checks, then push :<git-sha> (immutable) to ECR, resolve digest
      └─► deploy(digest)
            dev        register task def (image=repo@digest) → update service → wait for
                       COMPLETED → verify every task runs that digest → ALB healthy → smoke via ALB
            staging    same digest → smoke → integration tests (tests/integration) via ALB
            production [required reviewers approve] → same digest → verify → smoke
```

* **Same bytes everywhere.** Every stage deploys `repository@sha256:<digest>`. Tags are
  immutable, and nothing is rebuilt after CI.
* **Safe task-definition updates.** `deploy-ecs.sh` clones the family's *latest* revision,
  so Terraform changes such as env vars and CPU are kept, and it replaces only the `app`
  container image.
* **Stop on failure.** A failed rollout, health check, smoke test, or integration test fails
  the job, and later stages never run.
* **Ref restriction.** Deploys run only from `main` or `v*` tags. Production also has its own
  `if:` guard, plus IAM trust on the `production` environment subject.

### Release tags

To deploy a specific release, run **Actions → deploy** *from the tag* (`Use workflow from: v1.4.0`)
with that release's digest. dev and staging get it first, then production after approval.

## Rollback

| Situation | What happens / what to do |
|---|---|
| New tasks never become healthy | The **ECS deployment circuit breaker** rolls back automatically. `deploy-ecs.sh` sees the PRIMARY deployment revert, prints the ECS events, and **fails the job**, so promotion stops. |
| Release is healthy but wrong | **Actions → rollback**: pick the environment, and optionally a revision such as `icp-prod:41`. With no revision, it uses the newest one older than what's running. Production rollback needs the same approval. |
| Roll forward instead | **Actions → deploy** with the previous good digest (from the prior run's summary or `aws ecr describe-images`). |
| Local emergency (admin creds) | `AWS_REGION=us-east-1 scripts/rollback-ecs.sh prod icp-prod:41` |

Every deploy summary records the *previous* task-definition ARN, which is the rollback target.

## Health checks

| Layer | Check | Failure effect |
|---|---|---|
| Container | `HEALTHCHECK` / task-definition `healthCheck` → `GET /health` every 15s | ECS replaces the task |
| ALB | target group `GET /health`, 200, 2 healthy / 3 unhealthy at 15s | target drained; circuit breaker counts failures |
| Deploy job | rollout COMPLETED + every task on the new revision with the expected digest + ≥1 healthy target | job fails, promotion stops |
| Smoke | `/health` 200, `/version.git_sha` == deployed commit, `/status.environment` == env | job fails |
| Staging | `tests/integration`: health, version/commit, status, JSON 404 through ALB, p90 latency < 1s | job fails before production |
