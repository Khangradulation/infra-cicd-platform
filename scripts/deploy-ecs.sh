#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks below are JMESPath literals, not shell expansions
# Deploy an image DIGEST to one environment's ECS service and prove it worked.
#
#   scripts/deploy-ecs.sh <env> <sha256:digest>
#
# Env vars: AWS_REGION (required), ECR_REPOSITORY (default icp/app),
#           NAME_PREFIX (default icp), DEPLOY_TIMEOUT_SECONDS (default 900)
#
# Steps:
#   1. Confirm the digest exists in ECR; build <registry>/<repo>@<digest>.
#   2. Clone the family's LATEST task-definition revision (so Terraform-made
#      changes are kept), swap only the app container image, register it.
#   3. update-service, then poll until the new deployment COMPLETES. If the
#      ECS circuit breaker rolls back (rolloutState FAILED), exit non-zero.
#   4. Verify every running task uses the new revision AND reports the exact
#      image digest, and that the ALB sees healthy targets.
# Writes task_definition_arn, previous_task_definition_arn, url, git_sha to
# $GITHUB_OUTPUT when running in GitHub Actions.
set -euo pipefail

env_name="${1:?usage: $0 <env> <sha256:digest>}"
digest="${2:?usage: $0 <env> <sha256:digest>}"
: "${AWS_REGION:?AWS_REGION must be set}"
repo="${ECR_REPOSITORY:-icp/app}"
prefix="${NAME_PREFIX:-icp}"
timeout="${DEPLOY_TIMEOUT_SECONDS:-900}"

[[ "${digest}" =~ ^sha256:[a-f0-9]{64}$ ]] || { echo "::error::digest must be sha256:<64 hex>, got '${digest}'"; exit 2; }
[[ "${env_name}" =~ ^[a-z][a-z0-9]{1,9}$ ]] || { echo "::error::invalid env '${env_name}'"; exit 2; }

name="${prefix}-${env_name}"
cluster="${name}"; service="${name}"; family="${name}"; container="${CONTAINER_NAME:-app}"
export AWS_DEFAULT_REGION="${AWS_REGION}" AWS_PAGER=""

log() { printf '[deploy %s] %s\n' "${env_name}" "$*"; }
out() { [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "$1=$2" >>"${GITHUB_OUTPUT}"; return 0; }

# ---------------------------------------------------------------- 1. image
img_json="$(aws ecr describe-images --repository-name "${repo}" --image-ids "imageDigest=${digest}" --output json)" \
  || { echo "::error::digest ${digest} not found in ECR repository ${repo}"; exit 1; }
registry_id="$(jq -r '.imageDetails[0].registryId' <<<"${img_json}")"
git_sha="$(jq -r '[.imageDetails[0].imageTags[]? | select(test("^[0-9a-f]{40}$"))][0] // "unknown"' <<<"${img_json}")"
image_uri="${registry_id}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repo}@${digest}"
log "image ${image_uri} (git ${git_sha})"
out git_sha "${git_sha}"

# ------------------------------------------------------- 2. task definition
previous_td="$(aws ecs describe-services --cluster "${cluster}" --services "${service}" \
  --query 'services[0].taskDefinition' --output text)"
[[ "${previous_td}" == arn:* ]] || { echo "::error::service ${cluster}/${service} not found"; exit 1; }
out previous_task_definition_arn "${previous_td}"
log "currently running ${previous_td##*/}"

aws ecs describe-task-definition --task-definition "${family}" --output json \
  | jq --arg img "${image_uri}" --arg c "${container}" '
      .taskDefinition
      | if ([.containerDefinitions[] | select(.name == $c)] | length) != 1
        then error("container \($c) not found in task definition") else . end
      | .containerDefinitions |= map(if .name == $c then .image = $img else . end)
      | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities,
            .registeredAt, .registeredBy, .deregisteredAt)' >"${RUNNER_TEMP:-/tmp}/taskdef-${env_name}.json"

new_td="$(aws ecs register-task-definition --cli-input-json "file://${RUNNER_TEMP:-/tmp}/taskdef-${env_name}.json" \
  --query 'taskDefinition.taskDefinitionArn' --output text)"
log "registered ${new_td##*/}"
out task_definition_arn "${new_td}"

# ------------------------------------------------------------ 3. roll out
aws ecs update-service --cluster "${cluster}" --service "${service}" --task-definition "${new_td}" \
  --query 'service.deployments[?status==`PRIMARY`].id' --output text >/dev/null
log "update-service issued; waiting up to ${timeout}s for rollout"

deadline=$(( $(date +%s) + timeout ))
while :; do
  svc="$(aws ecs describe-services --cluster "${cluster}" --services "${service}" --output json)"
  primary="$(jq -c '.services[0].deployments[] | select(.status == "PRIMARY")' <<<"${svc}")"
  p_td="$(jq -r '.taskDefinition' <<<"${primary}")"
  state="$(jq -r '.rolloutState // "UNKNOWN"' <<<"${primary}")"
  reason="$(jq -r '.rolloutStateReason // ""' <<<"${primary}")"
  running="$(jq -r '.runningCount' <<<"${primary}")"; desired="$(jq -r '.desiredCount' <<<"${primary}")"

  if [[ "${p_td}" != "${new_td}" ]]; then
    echo "::error::ECS circuit breaker rolled ${service} back to ${p_td##*/}: ${reason}"
    jq -r '.services[0].events[:10][] | "  \(.createdAt) \(.message)"' <<<"${svc}"
    exit 1
  fi
  case "${state}" in
    COMPLETED) log "rollout COMPLETED (${running}/${desired} running)"; break ;;
    FAILED)
      echo "::error::deployment FAILED: ${reason}"
      jq -r '.services[0].events[:10][] | "  \(.createdAt) \(.message)"' <<<"${svc}"
      exit 1 ;;
  esac
  if (( $(date +%s) > deadline )); then
    echo "::error::timed out after ${timeout}s (state=${state}, ${running}/${desired} running)"
    jq -r '.services[0].events[:10][] | "  \(.createdAt) \(.message)"' <<<"${svc}"
    exit 1
  fi
  log "  ${state} ${running}/${desired} running ..."
  sleep 15
done

# ------------------------------------------------------------- 4. verify
task_arns="$(aws ecs list-tasks --cluster "${cluster}" --service-name "${service}" --desired-status RUNNING \
  --query 'taskArns' --output text)"
[[ -n "${task_arns}" && "${task_arns}" != "None" ]] || { echo "::error::no RUNNING tasks after rollout"; exit 1; }
# shellcheck disable=SC2086  # word-splitting the ARN list is intended
tasks="$(aws ecs describe-tasks --cluster "${cluster}" --tasks ${task_arns} --output json)"
mismatch="$(jq -r --arg td "${new_td}" --arg d "${digest}" --arg c "${container}" '
  [.tasks[] | select(.lastStatus == "RUNNING")
   | {arn: .taskArn, td: .taskDefinitionArn,
      digest: ((.containers[] | select(.name == $c) | .imageDigest) // "none")}
   | select(.td != $td or .digest != $d)] | length' <<<"${tasks}")"
count="$(jq '[.tasks[] | select(.lastStatus == "RUNNING")] | length' <<<"${tasks}")"
if [[ "${mismatch}" != "0" ]]; then
  echo "::error::${mismatch}/${count} running tasks are not on ${new_td##*/} with digest ${digest}"
  jq -r --arg c "${container}" '.tasks[] | "  \(.taskArn | split("/")[-1]) \(.taskDefinitionArn | split("/")[-1]) \((.containers[] | select(.name == $c) | .imageDigest) // "none")"' <<<"${tasks}"
  exit 1
fi
log "verified ${count} running task(s) on ${new_td##*/} with digest ${digest}"

tg_arn="$(jq -r '.services[0].loadBalancers[0].targetGroupArn' <<<"${svc}")"
healthy="$(aws elbv2 describe-target-health --target-group-arn "${tg_arn}" \
  --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' --output text)"
(( healthy >= 1 )) || { echo "::error::ALB reports no healthy targets"; exit 1; }
log "ALB target group: ${healthy} healthy target(s)"

lb_arn="$(aws elbv2 describe-load-balancers --names "${name}-alb" --query 'LoadBalancers[0].LoadBalancerArn' --output text)"
dns="$(aws elbv2 describe-load-balancers --load-balancer-arns "${lb_arn}" --query 'LoadBalancers[0].DNSName' --output text)"
if aws elbv2 describe-listeners --load-balancer-arn "${lb_arn}" --query 'Listeners[?Port==`443`].Port' --output text | grep -q 443; then
  url="https://${dns}"
else
  url="http://${dns}"
fi
out url "${url}"
log "DONE ${env_name} -> ${url}"
