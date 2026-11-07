#!/usr/bin/env bash
# Manually roll an ECS service back to a previous task-definition revision.
# (Failed deployments already roll back automatically via the circuit breaker;
#  use this when a deployment "succeeded" but the release is bad.)
#
#   scripts/rollback-ecs.sh <env> [task-definition-arn|family:revision]
#
# With no target, picks the newest ACTIVE revision older than the one running.
set -euo pipefail

env_name="${1:?usage: $0 <env> [task-definition]}"
target="${2:-}"
: "${AWS_REGION:?AWS_REGION must be set}"
prefix="${NAME_PREFIX:-icp}"
name="${prefix}-${env_name}"
export AWS_DEFAULT_REGION="${AWS_REGION}" AWS_PAGER=""

current="$(aws ecs describe-services --cluster "${name}" --services "${name}" --query 'services[0].taskDefinition' --output text)"
current_rev="${current##*:}"

if [[ -z "${target}" ]]; then
  target="$(aws ecs list-task-definitions --family-prefix "${name}" --status ACTIVE --sort DESC --output json \
    | jq -r --argjson cur "${current_rev}" '[.taskDefinitionArns[] | select((split(":")[-1] | tonumber) < $cur)][0] // empty')"
  [[ -n "${target}" ]] || { echo "::error::no older ACTIVE revision of ${name} to roll back to"; exit 1; }
fi

target_image="$(aws ecs describe-task-definition --task-definition "${target}" \
  --query "taskDefinition.containerDefinitions[?name=='${CONTAINER_NAME:-app}'].image | [0]" --output text)"
echo "rolling ${name}: ${current##*/} -> ${target##*/} (${target_image})"

aws ecs update-service --cluster "${name}" --service "${name}" --task-definition "${target}" >/dev/null
aws ecs wait services-stable --cluster "${name}" --services "${name}"

now="$(aws ecs describe-services --cluster "${name}" --services "${name}" --query 'services[0].taskDefinition' --output text)"
[[ "${now}" == *"${target##*/}" ]] || { echo "::error::service is on ${now##*/}, expected ${target##*/}"; exit 1; }
echo "rolled back ${name} to ${now##*/}"
[[ -n "${GITHUB_OUTPUT:-}" ]] && { echo "task_definition_arn=${now}"; echo "image=${target_image}"; } >>"${GITHUB_OUTPUT}"
exit 0
