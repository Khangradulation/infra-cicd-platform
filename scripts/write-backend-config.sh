#!/usr/bin/env bash
# Write terraform/environments/<root>/backend.hcl (git-ignored) from the
# bootstrap root's outputs, so local `terraform init` uses the remote state.
#
# Usage: scripts/write-backend-config.sh            # all roots
#        scripts/write-backend-config.sh dev prod   # selected roots
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap="${repo_root}/terraform/bootstrap"

if ! out="$(terraform -chdir="${bootstrap}" output -json 2>/dev/null)" || [[ "${out}" == "{}" ]]; then
  echo "error: no outputs in ${bootstrap}. Apply the bootstrap root first (docs/setup.md, step 2)." >&2
  exit 1
fi

read_output() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]]["value"])' "$1" <<<"${out}"; }
bucket="$(read_output state_bucket_name)"
region="$(read_output region)"
kms="$(read_output state_kms_key_arn)"

roots=("$@")
[[ ${#roots[@]} -eq 0 ]] && roots=(shared dev staging prod)

for r in "${roots[@]}"; do
  dir="${repo_root}/terraform/environments/${r}"
  [[ -d "${dir}" ]] || { echo "error: unknown root '${r}'" >&2; exit 1; }
  cat >"${dir}/backend.hcl" <<EOF
bucket     = "${bucket}"
region     = "${region}"
kms_key_id = "${kms}"
EOF
  echo "wrote ${dir#"${repo_root}/"}/backend.hcl"
done
