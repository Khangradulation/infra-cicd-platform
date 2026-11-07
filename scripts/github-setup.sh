#!/usr/bin/env bash
# Configure the GitHub side of the platform from `environments/shared` outputs:
#   * GitHub Environments: dev, staging, production, infra-dev, infra-staging, infra-production
#   * deployment-branch policies (main; production also v* tags)
#   * required reviewers on production + infra-production
#   * repository + environment variables (role ARNs, bucket, region, ...)
#   * optional: OIDC subject template that includes the git ref
#
# Usage:
#   scripts/github-setup.sh <owner/repo> --reviewer <github-login> [--reviewer <login>] [--oidc-sub-with-ref]
#   DRY_RUN=1 scripts/github-setup.sh ...   # print what would change
#
# Requires: gh (authenticated with admin on the repo), terraform, jq.
# Required reviewers and deployment-branch policies need a public repo or
# GitHub Pro/Team/Enterprise for private repos; the script warns if unavailable.
set -euo pipefail

repo="${1:?usage: $0 <owner/repo> --reviewer <login> [--oidc-sub-with-ref]}"; shift
reviewers=(); oidc_ref=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reviewer) reviewers+=("$2"); shift 2 ;;
    --oidc-sub-with-ref) oidc_ref=true; shift ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
done
[[ ${#reviewers[@]} -gt 0 ]] || { echo "at least one --reviewer is required for production approvals" >&2; exit 2; }

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run() { if [[ -n "${DRY_RUN:-}" ]]; then printf 'DRY_RUN:'; printf ' %q' "$@"; echo; else "$@"; fi; }
warn() { echo "::warning::$*" >&2; }

vars_json="$(terraform -chdir="${root}/terraform/environments/shared" output -json github_variables)" \
  || { echo "error: apply terraform/environments/shared first (docs/setup.md)" >&2; exit 1; }

reviewer_ids="$(for r in "${reviewers[@]}"; do gh api "users/${r}" --jq '{type: "User", id: .id}'; done | jq -s .)"

ensure_env() {  # name, with_reviewers(true|false), allow_tags(true|false)
  local name="$1" with_reviewers="$2" allow_tags="$3" body
  body="$(jq -n --argjson rv "$( [[ "${with_reviewers}" == true ]] && echo "${reviewer_ids}" || echo '[]')" \
    '{wait_timer: 0, prevent_self_review: false, reviewers: $rv,
      deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}}')"
  if ! run gh api -X PUT "repos/${repo}/environments/${name}" --input - <<<"${body}" >/dev/null 2>/tmp/gh-env-err; then
    warn "${name}: reviewers/branch policy rejected ($(head -c 200 /tmp/gh-env-err)). Creating environment without protection rules."
    run gh api -X PUT "repos/${repo}/environments/${name}" >/dev/null
    return 0
  fi
  run gh api -X POST "repos/${repo}/environments/${name}/deployment-branch-policies" \
    -f name=main -f type=branch >/dev/null 2>&1 || true
  if [[ "${allow_tags}" == true ]]; then
    run gh api -X POST "repos/${repo}/environments/${name}/deployment-branch-policies" \
      -f 'name=v*' -f type=tag >/dev/null 2>&1 || true
  fi
  echo "environment ${name}: ok (reviewers=${with_reviewers}, tags=${allow_tags})"
}

ensure_env dev              false false
ensure_env staging          false false
ensure_env production       true  true
ensure_env infra-dev        false false
ensure_env infra-staging    false false
ensure_env infra-production true  false

# Repository-level variables (none are secrets: ARNs, names, region).
while IFS=$'\t' read -r k v; do
  run gh variable set "${k}" --repo "${repo}" --body "${v}"
done < <(jq -r '.repository | to_entries[] | [.key, .value] | @tsv' <<<"${vars_json}")

# Environment-level variables.
while IFS=$'\t' read -r env k v; do
  run gh variable set "${k}" --repo "${repo}" --env "${env}" --body "${v}"
done < <(jq -r '.environments | to_entries[] | .key as $e | .value | to_entries[] | [$e, .key, .value] | @tsv' <<<"${vars_json}")

if [[ "${oidc_ref}" == true ]]; then
  run gh api -X PUT "repos/${repo}/actions/oidc/customization/sub" --input - >/dev/null <<'EOF'
{"use_default": false, "include_claim_keys": ["repo", "context", "ref"]}
EOF
  echo "OIDC subject template now includes ref. Set oidc_subject_includes_ref = true in environments/shared and re-apply it."
fi

echo
echo "Remaining manual step: set repository variable BOOTSTRAP_IMAGE_URI after the first image push (docs/setup.md, step 6)."
