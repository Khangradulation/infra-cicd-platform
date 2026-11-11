# Security

## Threat model (summary)

| Threat | Control |
|---|---|
| Leaked long-lived AWS keys | None exist. GitHub OIDC issues 1-hour STS sessions. Trust policies pin `aud=sts.amazonaws.com` and an exact per-repo `sub`. Immutable subjects (owner and repo IDs) defeat repo-rename and resurrection takeover. |
| A PR changes workflows to steal power | PR jobs can only assume the **plan** role (read-only, can only touch `*.tflock`). Apply and deploy roles trust only GitHub *Environment* subjects, which PR jobs don't have. `pull_request` (not `pull_request_target`) gives fork PRs no token. |
| CI creates an admin role | Apply roles may only create roles named `icp-<env>-*` **and** only with the `icp-workload-boundary` permissions boundary. Removing or editing the boundary is explicitly denied. `iam:PassRole` is limited to `ecs-tasks` and `vpc-flow-logs`. |
| CI modifies its own permissions | The `shared` stack, which holds the CI roles, is applied by an admin, never by CI. |
| One environment affects another | Per-env apply and deploy roles are scoped by name (`icp-<env>-*`), by state prefix (`s3://…/<env>/*`), and by KMS tag (`Environment=<env>`). |
| Unreviewed production change | `infra-production` / `production` Environments with required reviewers. Apply re-plans and refuses if the change set differs from the approved one. Prod deploys are allowed only from `main` or `v*` tags. |
| Supply-chain tampering | Actions pinned to commit SHAs (lint job enforces). Tools installed from release binaries with hard-coded SHA-256. Python deps installed `--require-hashes --no-deps`. Base image pinned by digest. Dependabot opens update PRs. |
| Vulnerable image reaches prod | Trivy gate fails on fixable HIGH/CRITICAL and secrets. Weekly re-scan. ECR scan-on-push. |
| Compromised container | Non-root UID 10001, read-only root FS, all capabilities dropped, no pip in the image, private subnets, no public IP, ingress only from the ALB SG, egress only on 443. The task role has no permissions. |
| State or plan exposure | State: SSE-KMS (CMK), TLS ≥ 1.2 only, versioned, public access blocked, access scoped per env. Binary plans never leave the runner; only value-free summaries are uploaded or commented. `.gitignore` blocks `*.tfstate`, `*.tfplan`, `terraform.tfvars`, `backend.hcl`. |
| Secrets in logs | Logger redacts `authorization`, `token`, `password`, `secret`, `cookie`, `api_key`. Plan logs print errors only. `mask-aws-account-id`, ECR `mask-password`. |

## Least-privilege IAM

| Role | Highlights |
|---|---|
| Task execution | `ecr:GetAuthorizationToken` (no resource support), pull from **one** repo, write to **one** log group |
| Task | Nothing. Optional `ssmmessages` for ECS Exec (dev only). |
| Plan | Describe/List/Get only. State `GetObject`. `Put/DeleteObject` on `*.tflock` only. |
| Apply `<env>` | Network actions (region-conditioned). `ecs:*` and `elasticloadbalancing:*` on `icp-<env>*` ARNs. `logs`, `cloudwatch`, and `sns` on `icp-<env>` names. KMS by tag. IAM roles with the boundary only. Own state prefix. |
| ECR push | Push and describe on one repository |
| Deploy `<env>` | Register task definitions. Update and describe **one** service. `PassRole` on that env's two roles. Describe ECR images and ALB health. |

## Network

* The ALB is the only internet-facing component. Ports 80/443 from `allowed_ingress_cidrs`.
  Egress only to the container port inside the VPC CIDR.
* Tasks are in private subnets with no public IP. Ingress is the container port from the ALB
  SG only. Egress is TCP 443 only.
* The default security group has its rules removed. Prod has VPC flow logs (ALL traffic) in
  KMS-encrypted CloudWatch Logs.
* ALB settings: `drop_invalid_header_fields`, `desync_mitigation_mode = defensive`. With a
  certificate: the `ELBSecurityPolicy-TLS13-1-2-2021-06` policy and an HTTP→HTTPS 301.

## Encryption

| Data | At rest | In transit |
|---|---|---|
| Terraform state | SSE-KMS (CMK, rotation) | TLS ≥ 1.2 enforced by bucket policy |
| App logs, flow logs | KMS CMK per env (rotation) | TLS |
| SNS alarm topic | Same CMK | TLS enforced by topic policy |
| ECR images | AES256 (KMS optional via `kms_key_arn`) | TLS |
| ALB access logs | SSE-S3 (the only option ALB supports) | TLS enforced |

## GitHub settings checklist

- [ ] Branch protection on `main`: PR required, status checks `lint` and `gate` required (`gate` enforces `terraform-pr` and `app-ci` when they apply), no force-push, no deletion
- [ ] Environments `production` and `infra-production`: required reviewers, deployment branches `main` (and `v*` tags for production)
- [ ] Actions → General: "Read repository contents" default token permission; don't allow Actions to approve PRs
- [ ] Optional: custom OIDC subject template with `ref` (`scripts/github-setup.sh --oidc-sub-with-ref`) and `oidc_subject_includes_ref = true`

> Required reviewers, deployment-branch rules and branch protection need a **public repo or a
> paid plan for private repos**. See [setup.md](setup.md#production-approval-and-github-plans).

## Approved exceptions

Scanner findings that were reviewed and accepted. Each one is annotated inline with
`#checkov:skip` or `trivy:ignore`, so a new instance of the same rule still fails CI.

| ID | Rule(s) | Resource | Rationale | Revisit when |
|---|---|---|---|---|
| SEC-01 | CKV_AWS_18 | state bucket | State access auditing belongs in CloudTrail S3 data events, not a second log bucket | You enable org CloudTrail |
| SEC-02 | CKV_AWS_144 | state / ALB log buckets | Versioning + 90-day history is the recovery path. CRR doubles cost for a single-region platform. | You go multi-region |
| SEC-03 | CKV2_AWS_62 | buckets | No consumer for object event notifications | A consumer exists |
| SEC-04 | CKV_AWS_18 | ALB log bucket | It *is* the log bucket; logging it would recurse | n/a |
| SEC-05 | CKV_AWS_145, AWS-0132 | ALB log bucket | ALB log delivery supports SSE-S3 only | AWS adds SSE-KMS support |
| SEC-06 | CKV_AWS_2, CKV_AWS_103, CKV2_AWS_20, AWS-0054 | HTTP listener | Created **only** when no `certificate_arn` is set. With a cert, HTTP 301-redirects to HTTPS. Prod warns via a `check` block. | You add ACM certs (recommended) |
| SEC-07 | CKV2_AWS_28, AWS-0053 | ALB | Public API by design. WAF is an opt-in upgrade (about $5/month per ACL plus rules). | Public launch / abuse |
| SEC-08 | CKV_AWS_378, AWS-0054 | target group | TLS terminates at the ALB. The ALB→task hop stays inside the VPC, restricted by security groups. | Compliance needs end-to-end TLS |
| SEC-09 | CKV_AWS_65 | ECS cluster | Container Insights is a per-env cost toggle; on in prod | n/a |
| SEC-10 | AWS-0104 | task SG egress | 443-only egress via NAT to ECR, CloudWatch and STS. Narrow with `egress_cidrs` after adding VPC interface endpoints. | You add endpoints |
| SEC-11 | CKV_AWS_356, AWS-0345 | CI role policies | `"*"` appears only on actions without resource-level support, with region or tag conditions. `s3:*` covers only the env's own log-bucket ARN. | n/a |
| SEC-12 | CKV_AWS_109/111/356 | KMS key policies | In a key policy, `"*"` means *this key*. The root-admin statement is AWS's recommended default. | n/a |
| SEC-13 | CKV_AWS_394 | AZ data source | The first `az_count` sorted AZ names are used. New AZs don't reorder existing ones. | n/a |

**Trivy (image):** the gate fails on *fixable* HIGH/CRITICAL. When this was written, the
Debian base image had 49 HIGH CVEs with **no fix available**. Those are reported in the job
summary but don't block, and the weekly scan re-checks them. To accept a *fixable* CVE, add
it to `.trivyignore` with a reason, an owner, and an `exp:` date. Trivy enforces the expiry.
