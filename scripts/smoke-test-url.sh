#!/usr/bin/env bash
# Post-deploy smoke test through the public ALB endpoint.
#
#   scripts/smoke-test-url.sh <base_url> [expected_git_sha] [expected_env]
#
# Retries /health for up to SMOKE_TIMEOUT_SECONDS (default 120), then asserts
# /version serves the expected commit and /status reports the environment.
set -euo pipefail

base="${1:?usage: $0 <base_url> [expected_git_sha] [expected_env]}"; base="${base%/}"
want_sha="${2:-}"; want_env="${3:-}"
deadline=$(( $(date +%s) + ${SMOKE_TIMEOUT_SECONDS:-120} ))

until curl -fsS --max-time 5 "${base}/health" >/dev/null 2>&1; do
  if (( $(date +%s) > deadline )); then echo "::error::${base}/health never returned 200"; exit 1; fi
  sleep 5
done
echo "ok   ${base}/health"

version="$(curl -fsS --max-time 5 "${base}/version")"
status="$(curl -fsS --max-time 5 "${base}/status")"
echo "ok   /version ${version}"
echo "ok   /status  ${status}"

if [[ -n "${want_sha}" && "${want_sha}" != "unknown" ]]; then
  got="$(jq -r .git_sha <<<"${version}")"
  [[ "${got}" == "${want_sha}" ]] || { echo "::error::serving git_sha ${got}, expected ${want_sha}"; exit 1; }
  echo "ok   serving expected commit ${want_sha}"
fi
if [[ -n "${want_env}" ]]; then
  got="$(jq -r .environment <<<"${status}")"
  [[ "${got}" == "${want_env}" ]] || { echo "::error::environment ${got}, expected ${want_env}"; exit 1; }
  echo "ok   environment ${want_env}"
fi
