#!/usr/bin/env bash
# Local-only demo for accounts where GitHub OIDC is blocked (e.g. by an AWS
# Organizations SCP). Uses YOUR short-lived `aws login` session; no keys.
#
#   scripts/demo-local.sh bootstrap   # state bucket + KMS (once, ~USD 1/month)
#   scripts/demo-local.sh shared      # ECR repository (once, cents/month)
#   scripts/demo-local.sh image       # build (arm64) + push :<git-sha>, prints digest
#   scripts/demo-local.sh up [MIN]    # create dev with that image + health checks;
#                                     #   with MIN, auto-runs 'down' MIN minutes after start
#   scripts/demo-local.sh down        # destroy dev (stops the hourly cost; cancels the timer)
#   scripts/demo-local.sh status      # what exists right now (and any pending teardown)
#
# The auto-teardown timer is a detached background process: it survives Ctrl+C
# and closing the terminal (not a reboot or sleep). It starts BEFORE the apply,
# so dev is destroyed even if 'up' fails or is interrupted. Log: .demo/auto-down.log.
# It uses your cached `aws login` session, so keep the session valid until then.
#
# Env: AWS_REGION (default us-east-2), AWS_PROFILE (optional).
set -euo pipefail

usage="usage: $0 bootstrap|shared|image|up [minutes]|down|status"
cmd="${1:-}"
[[ -n "${cmd}" ]] || { echo "${usage}" >&2; exit 2; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AWS_REGION="${AWS_REGION:-us-east-2}"
export AWS_DEFAULT_REGION="${AWS_REGION}" AWS_PAGER=""
export TF_IN_AUTOMATION=1 TF_INPUT=0
repo="icp/app"
state_dir="${root}/.demo"            # git-ignored: digest of last pushed image
mkdir -p "${state_dir}"
digest_file="${state_dir}/image-digest"
timer_pid_file="${state_dir}/auto-down.pid"
timer_log="${state_dir}/auto-down.log"

tfb() { terraform -chdir="${root}/terraform/bootstrap" "$@"; }
tfe() { local r="$1"; shift; terraform -chdir="${root}/terraform/environments/${r}" "$@"; }
init_env() {
  "${root}/scripts/write-backend-config.sh" "$1" >/dev/null
  tfe "$1" init -input=false -reconfigure -backend-config=backend.hcl >/dev/null
}
account() { aws sts get-caller-identity --query Account --output text; }
say() { printf '\n==> %s\n' "$*"; }
clock() { date -d "@$1" '+%H:%M %Z' 2>/dev/null || date -r "$1" '+%H:%M %Z'; }  # GNU || BSD

timer_pid() {  # prints the pid of a live auto-down timer, if any
  local pid
  pid="$(cat "${timer_pid_file}" 2>/dev/null)" || return 1
  [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null && echo "${pid}"
}

cancel_timer() {
  local pid
  if pid="$(timer_pid)"; then
    pkill -P "${pid}" 2>/dev/null || true   # its sleep
    kill "${pid}" 2>/dev/null || true
    echo "cancelled auto-teardown timer (pid ${pid})"
  fi
  rm -f "${timer_pid_file}"
}

start_timer() {  # minutes
  local minutes="$1" at
  cancel_timer >/dev/null
  at=$(( $(date +%s) + minutes * 60 ))
  # Background jobs of a non-interactive shell ignore SIGINT, so Ctrl+C on this
  # script doesn't reach it; nohup covers closing the terminal (SIGHUP).
  # shellcheck disable=SC2016  # $1/$2 expand in the child shell, on purpose
  nohup bash -c '
    sleep "$1"
    echo "$(date "+%F %T") auto-teardown: running down"
    ICP_AUTO_DOWN=1 "$2" down
  ' auto-down "$(( minutes * 60 ))" "${root}/scripts/demo-local.sh" >>"${timer_log}" 2>&1 </dev/null &
  echo "$!" >"${timer_pid_file}"
  echo "$(date '+%F %T') timer pid $! scheduled 'down' at $(clock "${at}")" >>"${timer_log}"
  say "Auto-teardown scheduled for $(clock "${at}") (in ${minutes} min, pid $!). Survives Ctrl+C."
  echo "    Cancel: $0 down (destroys now)  |  log: ${timer_log#"${root}/"}"
}

dev_vars=(
  -var "region=${AWS_REGION}"
  -var "permissions_boundary_name="
  -var "cpu_architecture=ARM64"
)

case "${cmd}" in
  bootstrap)
    say "Creating Terraform state bucket + KMS key in ${AWS_REGION} (local state)"
    tfb init -input=false >/dev/null
    tfb apply -auto-approve -var "region=${AWS_REGION}"
    ;;

  shared)
    if [[ -f "${root}/terraform/environments/shared/terraform.tfvars" ]]; then
      # This mode applies enable_github_oidc=false, which would DESTROY the CI roles.
      echo "refusing: environments/shared/terraform.tfvars exists (GitHub OIDC mode)." >&2
      echo "Manage shared with: scripts/tf.sh plan shared && CONFIRM=shared scripts/tf.sh apply shared" >&2
      exit 1
    fi
    say "Creating ECR repository (GitHub OIDC disabled: blocked by an Organizations SCP)"
    init_env shared
    tfe shared apply -auto-approve \
      -var "region=${AWS_REGION}" -var "enable_github_oidc=false" \
      -var "state_bucket_name=$(tfb output -raw state_bucket_name)" \
      -var "state_kms_key_arn=$(tfb output -raw state_kms_key_arn)"
    ;;

  image)
    sha="$(git -C "${root}" rev-parse HEAD)"
    registry="$(account).dkr.ecr.${AWS_REGION}.amazonaws.com"
    if ! aws ecr describe-images --repository-name "${repo}" --image-ids "imageTag=${sha}" >/dev/null 2>&1; then
      say "Building image for commit ${sha:0:7} (linux/arm64)"
      docker build -q --platform linux/arm64 --build-arg "GIT_SHA=${sha}" \
        --build-arg "APP_VERSION=demo-${sha:0:7}" -t "icp-app:demo" "${root}/application" >/dev/null
      say "Container smoke test"
      "${root}/scripts/container-smoke-test.sh" icp-app:demo "${sha}" | tail -1
      say "Pushing to ECR"
      aws ecr get-login-password | docker login --username AWS --password-stdin "${registry}" >/dev/null
      docker tag icp-app:demo "${registry}/${repo}:${sha}"
      docker push -q "${registry}/${repo}:${sha}" >/dev/null
    else
      say "Image for ${sha:0:7} already in ECR (tags are immutable); reusing it"
    fi
    aws ecr describe-images --repository-name "${repo}" --image-ids "imageTag=${sha}" \
      --query 'imageDetails[0].imageDigest' --output text | tee "${digest_file}"
    ;;

  up)
    minutes="${2:-}"
    if [[ -n "${minutes}" ]] && ! [[ "${minutes}" =~ ^[0-9]+$ && "${minutes}" -ge 1 && "${minutes}" -le 720 ]]; then
      echo "minutes must be a whole number from 1 to 720 (got '${minutes}')" >&2; exit 2
    fi
    [[ -s "${digest_file}" ]] || { echo "run '$0 image' first" >&2; exit 1; }
    image="$(account).dkr.ecr.${AWS_REGION}.amazonaws.com/${repo}@$(cat "${digest_file}")"
    [[ -n "${minutes}" ]] && start_timer "${minutes}"
    say "Creating dev (this takes ~5-8 minutes; billing ~USD 0.10-0.15/hour starts now)"
    init_env dev
    tfe dev apply -auto-approve "${dev_vars[@]}" -var "container_image=${image}"
    url="$(tfe dev output -raw app_url)"
    say "Health checks through the public load balancer"
    SMOKE_TIMEOUT_SECONDS=420 "${root}/scripts/smoke-test-url.sh" "${url}" "$(git -C "${root}" rev-parse HEAD)" dev
    say "dev is UP: ${url}"
    if pid="$(timer_pid)"; then
      echo "Auto-teardown pending (pid ${pid}). '$0 down' destroys it now instead."
    else
      echo "Remember: '$0 down' stops the cost."
    fi
    ;;

  down)
    if [[ -n "${ICP_AUTO_DOWN:-}" ]]; then rm -f "${timer_pid_file}"; else cancel_timer; fi
    say "Destroying dev"
    init_env dev
    # lock-timeout: a timer firing while 'up' is still applying waits for it.
    tfe dev destroy -auto-approve -lock-timeout=15m "${dev_vars[@]}" \
      -var "container_image=placeholder.invalid/icp/app@sha256:$(printf '0%.0s' {1..64})"
    left="$(tfe dev state list | wc -l | tr -d ' ')"
    if [[ "${left}" != "0" ]]; then echo "WARNING: ${left} resources remain"; exit 1; fi
    say "dev destroyed: 0 resources left"
    ;;

  status)
    for r in shared dev; do
      if [[ -f "${root}/terraform/environments/${r}/backend.hcl" ]]; then
        init_env "${r}" 2>/dev/null || true
        printf '%-7s %s resources\n' "${r}" "$(tfe "${r}" state list 2>/dev/null | wc -l | tr -d ' ')"
      fi
    done
    printf 'state   %s\n' "$(tfb output -raw state_bucket_name 2>/dev/null || echo 'not bootstrapped')"
    if pid="$(timer_pid)"; then printf 'timer   auto-teardown pending (pid %s), see %s\n' "${pid}" "${timer_log#"${root}/"}"; fi
    ;;

  *) echo "unknown command ${cmd}" >&2; exit 2 ;;
esac
