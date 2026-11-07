#!/usr/bin/env bash
# Local Terraform wrapper with guard rails.
#
#   scripts/tf.sh init  <root>          init against remote state (needs backend.hcl)
#   scripts/tf.sh plan  <root>          plan to <root>/.terraform/<root>.tfplan (never applies)
#   scripts/tf.sh apply <root>          apply THAT saved plan only; prod/shared require CONFIRM=<root>
#
# <root> is one of: shared dev staging prod
# Day-to-day applies of dev/staging/prod should go through GitHub Actions.
set -euo pipefail

cmd="${1:-}"; root="${2:-}"
case "${root}" in shared|dev|staging|prod) ;; *) echo "usage: $0 {init|plan|apply} {shared|dev|staging|prod}" >&2; exit 2 ;; esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="${repo_root}/terraform/environments/${root}"
plan_file="${dir}/.terraform/${root}.tfplan"   # inside .terraform/: git-ignored, never committed

if [[ ! -f "${dir}/backend.hcl" ]]; then
  echo "error: ${dir}/backend.hcl missing. Run scripts/write-backend-config.sh ${root}" >&2
  exit 1
fi

tf() { terraform -chdir="${dir}" "$@"; }

case "${cmd}" in
  init)
    tf init -input=false -backend-config=backend.hcl
    ;;
  plan)
    tf init -input=false -backend-config=backend.hcl >/dev/null
    tf plan -input=false -lock-timeout=5m -out="${plan_file}"
    echo "plan saved to ${plan_file#"${repo_root}/"} (sensitive: contains state data; do not share)"
    ;;
  apply)
    [[ -f "${plan_file}" ]] || { echo "error: no saved plan. Run: $0 plan ${root}" >&2; exit 1; }
    if [[ "${root}" == "prod" || "${root}" == "shared" ]] && [[ "${CONFIRM:-}" != "${root}" ]]; then
      echo "refusing to apply ${root} without CONFIRM=${root}" >&2
      exit 1
    fi
    tf apply -input=false -lock-timeout=5m "${plan_file}"
    rm -f "${plan_file}"
    ;;
  *)
    echo "usage: $0 {init|plan|apply} {shared|dev|staging|prod}" >&2; exit 2 ;;
esac
