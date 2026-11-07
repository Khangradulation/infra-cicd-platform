#!/usr/bin/env bash
# Run the image the way ECS does (read-only root FS, /tmp as a volume seeded
# from the image like Fargate's ephemeral mount, all caps
# dropped, no-new-privileges, non-root) and probe every endpoint.
#
# Usage: scripts/container-smoke-test.sh <image> [expected_git_sha]
set -euo pipefail

image="${1:?usage: $0 <image> [expected_git_sha]}"
expected_sha="${2:-}"
name="icp-smoke-$$"
port="${SMOKE_PORT:-18080}"

cleanup() {
  local rc=$?
  if [[ ${rc} -ne 0 ]]; then
    echo "---- container logs ----"; docker logs "${name}" 2>&1 | tail -50 || true
  fi
  docker rm -f "${name}" >/dev/null 2>&1 || true
  exit "${rc}"
}
trap cleanup EXIT

docker run -d --name "${name}" -p "127.0.0.1:${port}:8080" \
  --read-only --mount type=volume,target=/tmp \
  --cap-drop ALL --security-opt no-new-privileges \
  -e APP_ENV=smoke -e LOG_LEVEL=INFO "${image}" >/dev/null

user="$(docker inspect -f '{{.Config.User}}' "${name}")"
[[ "${user}" == "10001:10001" ]] || { echo "FAIL: image runs as '${user}', expected 10001:10001"; exit 1; }
echo "ok   runs as non-root (${user})"

base="http://127.0.0.1:${port}"
for _ in $(seq 1 30); do
  curl -fsS "${base}/health" >/dev/null 2>&1 && break
  sleep 1
done

check() {  # path expected_status jq-ish python assertion
  local path="$1" want="$2" assertion="$3" body code
  body="$(curl -sS -w '\n%{http_code}' "${base}${path}")"
  code="${body##*$'\n'}"; body="${body%$'\n'*}"
  [[ "${code}" == "${want}" ]] || { echo "FAIL ${path}: HTTP ${code} (want ${want}): ${body}"; exit 1; }
  python3 -c "import json,sys; b=json.loads(sys.argv[1]); assert ${assertion}, b" "${body}" \
    || { echo "FAIL ${path}: assertion '${assertion}' on ${body}"; exit 1; }
  echo "ok   GET ${path} -> ${code} ${body}"
}

check /health  200 'b == {"status": "ok"}'
check /        200 'b["environment"] == "smoke"'
check /version 200 '"git_sha" in b'
check /status  200 'b["status"] == "ok"'
check /missing 404 'b["status"] == 404'

if [[ -n "${expected_sha}" ]]; then
  check /version 200 "b['git_sha'] == '${expected_sha}'"
fi

# Docker's own HEALTHCHECK (same probe ECS runs) must report healthy.
for _ in $(seq 1 40); do
  state="$(docker inspect -f '{{.State.Health.Status}}' "${name}")"
  [[ "${state}" == "healthy" ]] && break
  sleep 1
done
[[ "${state}" == "healthy" ]] || { echo "FAIL: container health is '${state}'"; exit 1; }
echo "ok   container HEALTHCHECK healthy"

# Logs must be JSON lines (CloudWatch metric filters depend on it).
docker logs "${name}" 2>&1 | grep -m1 '"message":"request"' | python3 -c 'import json,sys; json.loads(sys.stdin.read()); print("ok   structured JSON request log")'
echo "PASS smoke test: ${image}"
