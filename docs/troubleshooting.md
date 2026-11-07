# Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | The `sub` claim doesn't match the trust policy. Most often the repo uses **immutable subjects** (`repo:owner@id/repo@id`) but `oidc_sub_claim_prefix` is unset. Other causes: the job isn't in the expected Environment, or the ref is wrong. | Run **oidc-check**, then compare its `sub` with `terraform -chdir=terraform/environments/shared output trusted_subjects`. Set `oidc_sub_claim_prefix` to the value from `gh api repos/O/R/actions/oidc/customization/sub --jq .sub_claim_prefix` and re-apply `shared`. |
| Same error only after enabling ref-bound subjects | Template changed but `oidc_subject_includes_ref` is still false, or vice versa | Keep the GitHub template and the Terraform variable in sync. Re-run oidc-check. |
| `Credentials could not be loaded` in a PR from a fork | Fork PRs get no OIDC token (by design) | Expected. Plans run only for same-repo branches. |
| `Error acquiring the state lock` / `PreconditionFailed` on `.tflock` | Another run or local session holds the lock | Wait: CI uses `-lock-timeout`. If a run was killed: `terraform force-unlock <ID>`, **only** after confirming no apply is running. |
| Apply step: "change set differs from the reviewed plan" | Infrastructure or state changed between plan and approval | Re-run `terraform-apply` and review the fresh plan. Working as designed. |
| `AccessDenied` on `iam:CreateRole` during apply | Role name doesn't start with `icp-<env>-`, or no permissions boundary attached | Pass `permissions_boundary_arn` to any new role and follow the naming contract. |
| `AccessDenied` on KMS during apply | Key lacks the `Environment=<env>` tag | Keep `default_tags` in the env's `providers.tf`. Don't override `Environment`. |
| `deploy-ecs.sh: digest … not found in ECR` | Wrong digest, or the image expired via lifecycle | `aws ecr describe-images --repository-name icp/app`. Re-run app-ci for that commit if needed. |
| Deploy fails "circuit breaker rolled … back" | New tasks failed health checks or crashed | Read the ECS events printed in the job, then `/ecs/icp-<env>` logs: Logs Insights `filter level="ERROR"`. Common causes: bad env var (invalid `LOG_LEVEL` fails startup), or the app not listening on 8080. |
| Tasks stuck `PENDING`, `CannotPullContainerError` | No egress (NAT missing / `nat_gateway_mode = "none"` without endpoints), or the execution role lacks ECR access | Check the private route table has `0.0.0.0/0 → NAT`. Check the execution role policy names the repo ARN. |
| ALB returns 502 | Container not listening, crashed, or keepalive mismatch | gunicorn `keepalive` (75s) must exceed the ALB idle timeout (60s). Check target health reasons with `describe-target-health`. |
| ALB returns 503 | No registered or healthy targets | Service desired count 0, or all tasks unhealthy. See the `no-healthy-targets` alarm. |
| `RunningTaskCount` alarm missing in dev | By design: it needs Container Insights | Set `enable_container_insights = true` (adds cost). |
| Alarm emails never arrive | SNS email subscription not confirmed | Click the confirmation link AWS sends to each address. |
| `terraform-apply` guard: missing `BOOTSTRAP_IMAGE_URI` | First-time setup step 6 not done | See [setup.md](setup.md#6-create-the-environments). |
| Production job never waits for approval | Required reviewers not available (private repo on GitHub Free) or not configured | See [setup.md](setup.md#production-approval-and-github-plans). |
| TFLint `failed to install plugin` / rate limit | GitHub API rate limit | Export `GITHUB_TOKEN` (CI passes `github.token`). |
| `docker build`: `--chmod requires BuildKit` | Old Docker without buildx | The Dockerfile avoids `--chmod`. Update your Docker if other BuildKit errors appear. |
| Prod plan warns "serving plain HTTP" | `check "prod_should_use_https"` | Set `certificate_arn`. The warning doesn't block the apply. |
