# Cost management and teardown

## Estimated monthly cost (us-east-1, running 24/7, low traffic)

These are **estimates** from public on-demand list prices (ALB $0.0225/h, NAT gateway
$0.045/h + $0.045/GB, public IPv4 $0.005/h, Fargate x86 $0.04048/vCPU-h + $0.004445/GB-h,
KMS $1/key, standard alarm $0.10). Check them in the
[AWS Pricing Calculator](https://calculator.aws/) for your region before relying on them.
Data transfer and log volume depend on traffic and aren't fully included.

| Item | dev | staging | prod | shared |
|---|---|---|---|---|
| ALB (hourly + about 1 LCU) | ~$17–22 | ~$17–22 | ~$18–25 | |
| ALB public IPv4 (2 AZs) | $7.30 | $7.30 | $7.30 | |
| NAT gateway(s) + EIP | $36.50 (1) | $36.50 (1) | $73.00 (2) | |
| Fargate tasks | $9.01 (1 × 0.25 vCPU / 0.5 GB) | $9.01 | $36.04 (2 × 0.5 vCPU / 1 GB) | |
| KMS key | $1 | $1 | $1 | $1 (state) |
| CloudWatch alarms / logs / dashboard | ~$1–2 | ~$1–2 | ~$3–8 (Insights, flow logs) | |
| ALB access logs (S3) | | | <$1 | |
| ECR storage (about 100 images × ~70 MB) | | | | ~$0.70 |
| **≈ total** | **~$72–78** | **~$72–78** | **~$140–150** | **~$2** |

That's about **$290/month** with everything running all the time. Most of it is fixed hourly
cost: NAT gateways are about 40% and ALBs about 30%.

## Default: pay only while a demo runs

With `TF_AUTO_APPLY` and `AUTO_DEPLOY` unset (the default), no environment exists between
runs of the **demo** workflow:

| What | While a demo runs | Between demos |
|---|---|---|
| dev (ALB, NAT, 1 task, KMS key, alarms) | ~$0.10–0.15/hour | $0 (destroyed; its KMS key waits 7 days pending deletion, free) |
| State bucket + state KMS key | | ~$1/month |
| ECR images | | a few cents/month (lifecycle keeps the newest 100) |
| GitHub Actions | free (public repository) | free |

A budget alert (`budget_alert_emails` in `terraform/bootstrap`) emails you if this project's
spend passes 50% / 100% of $5, or is forecast to exceed it. It only counts resources tagged
`Project=infra-cicd-platform`, so other workloads in the account don't trigger it. Activate
the `Project` cost-allocation tag (`activate_cost_allocation_tag = true`) about a day after
the first apply so the filter starts counting.

## Cost levers

| Lever | Saving | Trade-off |
|---|---|---|
| Destroy dev/staging when idle (teardown below, then recreate with `terraform-apply`) | ~$72/month each | 10–15 min to recreate |
| `fargate_spot_weight = 3` in dev | ~70% of the Fargate line | Tasks can be reclaimed with 2 min notice |
| `cpu_architecture = "ARM64"` (needs arm64 image builds) | ~20% of the Fargate line | Multi-arch builds in CI |
| `nat_gateway_mode = "none"` + VPC interface endpoints | NAT $33, minus endpoints (~$7.30/AZ each for ecr.api, ecr.dkr, logs, sts) | Usually costs *more* at 2 AZs; only worth it at high egress volume |
| Shared ALB across non-prod envs (host-based routing) | ~$24/month | Couples environments |
| Prod `az_count = 3` | | Costs ~+$40/month (NAT + IPv4) for better AZ-loss tolerance |

## Teardown

> **Destructive and irreversible.** None of these commands were executed while building this
> project. Run them in this order: environments first, then `shared`, then `bootstrap`.

### 1. Environments (repeat for staging, dev)

```bash
scripts/write-backend-config.sh dev
terraform -chdir=terraform/environments/dev init -backend-config=backend.hcl
terraform -chdir=terraform/environments/dev plan -destroy -out=destroy.tfplan
terraform -chdir=terraform/environments/dev apply destroy.tfplan
```

### 2. Production (deletion protection must be lifted first)

```bash
# a) in terraform/environments/prod/main.tf set:
#      enable_deletion_protection = false
#      force_destroy_log_buckets  = true
#    then apply that change (via PR + terraform-apply, or locally):
scripts/tf.sh plan prod && CONFIRM=prod scripts/tf.sh apply prod
# b) destroy
terraform -chdir=terraform/environments/prod plan -destroy -out=destroy.tfplan
terraform -chdir=terraform/environments/prod apply destroy.tfplan
```

KMS keys enter a 7-day pending-deletion window, during which they cost nothing. CloudWatch
log groups are deleted along with them.

### 3. Shared (ECR + CI roles)

```bash
# ECR refuses to delete a repo that still has images (force_delete = false).
aws ecr batch-delete-image --repository-name icp/app \
  --image-ids "$(aws ecr list-images --repository-name icp/app --query 'imageIds[*]' --output json)"
terraform -chdir=terraform/environments/shared plan -destroy -out=destroy.tfplan
terraform -chdir=terraform/environments/shared apply destroy.tfplan
```

### 4. Bootstrap (state bucket and key)

The bucket and key have `prevent_destroy = true`, and a versioned bucket must be emptied of
**all versions** first. Only do this once every other root is destroyed, because their state
lives here.

```bash
# a) remove both `lifecycle { prevent_destroy = true }` blocks in terraform/bootstrap/main.tf
# b) empty every object version and delete marker
BUCKET=$(terraform -chdir=terraform/bootstrap output -raw state_bucket_name)
aws s3api list-object-versions --bucket "$BUCKET" --output json \
  --query '{Objects: [Versions, DeleteMarkers][][].{Key: Key, VersionId: VersionId}}' > /tmp/versions.json
aws s3api delete-objects --bucket "$BUCKET" --delete file:///tmp/versions.json
# c) destroy (the KMS key is scheduled for deletion after 30 days)
terraform -chdir=terraform/bootstrap plan -destroy -out=destroy.tfplan
terraform -chdir=terraform/bootstrap apply destroy.tfplan
```

### 5. Verify nothing billable remains

```bash
aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=infra-cicd-platform \
  --query 'ResourceTagMappingList[].ResourceARN'
aws ec2 describe-nat-gateways --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId'
aws elbv2 describe-load-balancers --query 'LoadBalancers[?starts_with(LoadBalancerName, `icp-`)].LoadBalancerName'
aws ec2 describe-addresses --query 'Addresses[].PublicIp'
```

All four should return empty lists, except KMS keys pending deletion, which are listed but not billed.
