# infra-cicd-platform

Reusable Terraform modules and GitHub Actions CI/CD for a containerised API on
**AWS ECS Fargate**. It covers remote state with native S3 locking, GitHub **OIDC** auth
(no static keys), security scanning (Checkov, TFLint, Trivy, Dependabot), CloudWatch
monitoring, and an **immutable-digest promotion** pipeline: dev → staging → (approval) → prod.

```text
.
├── application/              Flask API, tests, multi-stage Dockerfile
│   ├── src/app/
│   └── tests/{unit,integration}/
├── terraform/
│   ├── bootstrap/            S3 state bucket + KMS (local state, run once)
│   ├── modules/              networking · ecr · ecs · iam · alb · monitoring · github-oidc · app-stack
│   └── environments/
│       ├── shared/           ECR, OIDC provider, CI roles, permissions boundary
│       ├── dev/  staging/  prod/
├── .github/workflows/        terraform-pr · terraform-apply · app-ci · deploy · rollback · lint · pr-gate · security-scan · oidc-check
├── scripts/                  bootstrap, deploy, smoke-test and tool-install helpers
└── docs/                     architecture · setup · deployment · security · troubleshooting · cost
```

## Documentation

| Doc | What's in it |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Diagrams, dependency graph, OIDC role matrix, design trade-offs |
| [docs/setup.md](docs/setup.md) | AWS + GitHub prerequisites, bootstrap, first deploy |
| [docs/deployment.md](docs/deployment.md) | Day-to-day flow, approvals, promotion, rollback |
| [docs/security.md](docs/security.md) | Threat model, controls, approved scanner exceptions |
| [docs/testing.md](docs/testing.md) | Test matrix and per-environment verification checklist |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common failures and fixes |
| [docs/cost.md](docs/cost.md) | Monthly estimates, cost levers, teardown |
| [docs/upgrades.md](docs/upgrades.md) | How to bump Terraform, providers, actions and Python deps |
| [docs/implementation-report.md](docs/implementation-report.md) | What is built, what was tested (with evidence), what still needs AWS |

## Status

The code is built and statically verified. **Nothing has been provisioned in AWS yet.**
See the [implementation report](docs/implementation-report.md) and [setup.md](docs/setup.md).

## Run it without leaving it running (one-click demo)

The platform is **cost-safe by default**. Merging to `main` doesn't create or keep any
environment running.

**Actions → demo → Run workflow**, then pick 15/30/60/120 minutes. The workflow:

1. Builds and scans the image, then pushes it to ECR.
2. Creates `dev` and checks it is healthy through the public load balancer. The run page shows the URL.
3. Keeps it up for the chosen time.
4. **Destroys it**, and confirms that 0 resources are left.

The destroy step also runs if anything fails or you cancel the run. As a safety net,
`demo-cleanup` destroys any leftover dev stack every day.

A 30-minute demo costs about **$0.05–0.10**. Between demos, only the state bucket, its KMS
key and stored images remain (about $1–2/month). [docs/cost.md](docs/cost.md) shows how to remove those too.

| Repository variable | Default | Effect when `true` |
|---|---|---|
| `TF_AUTO_APPLY` | unset | Pushes to `main` apply Terraform to dev → staging → prod |
| `AUTO_DEPLOY` | unset | Pushes to `main` promote new images dev → staging → prod. Also disables the daily dev cleanup. |

## Quick start (local, no AWS needed)

```bash
make help
make venv app-test        # unit tests
make ci                   # fmt, validate, TFLint, Checkov, terraform test, lint, actionlint
make docker-build docker-smoke trivy   # needs a Docker daemon
```

## Pinned versions

| Component | Version |
|---|---|
| Terraform | 1.17.1 (`required_version = "~> 1.17"`) |
| AWS provider | `~> 6.72` (locked in `.terraform.lock.hcl`) |
| Python base image | `python:3.14-slim-trixie` (digest-pinned) |
| Flask / gunicorn | 3.1.3 / 26.2.0 |
| TFLint / AWS ruleset | 0.65.0 / 0.50.0 |
| Trivy / Checkov / actionlint | 0.76.2 / 3.4.3 / 1.7.12 |

All GitHub Actions are pinned to full commit SHAs. Dependabot proposes bumps.
See [docs/upgrades.md](docs/upgrades.md).
