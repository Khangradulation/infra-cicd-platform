# Upgrading pinned versions

Every version is pinned. Dependabot opens weekly PRs for GitHub Actions (SHA + version
comment), Python dependencies, the Docker base-image digest, and Terraform providers. Each
PR goes through the full CI. The items below are bumped by hand.

| Component | Where pinned | How to bump |
|---|---|---|
| Terraform CLI | `required_version = "~> 1.17.0"` in roots, `TF_VERSION` in `terraform-pr.yml`, `terraform-version` default in `.github/actions/terraform-init` | Change all three together. Run `make ci`. Plan every env and expect no changes. |
| AWS provider | `version = "~> 6.72"` in roots + `.terraform.lock.hcl` | `terraform -chdir=<root> init -upgrade`, then `terraform providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64 -platform=darwin_amd64` for **each root**. Read the provider CHANGELOG. Plan all envs. |
| Module provider range | `>= 6.0.0, < 7.0.0` in `modules/*/versions.tf` | Widen only after testing a major version. |
| TFLint + AWS ruleset | `scripts/install-ci-tools.sh` (version + SHA-256), `.tflint.hcl` (`plugin "aws" version`) | Take the SHA-256 from the release's `checksums.txt`. `make tflint`. |
| Trivy / actionlint / hadolint | `scripts/install-ci-tools.sh` | Bump version **and** SHA-256 from the release checksums. hadolint publishes none: download it, compute `sha256sum`, and record that you did. |
| Checkov | `checkov==` in `terraform-pr.yml` and `security-scan.yml` | Bump both, then `make checkov`. New checks may need new reviewed exceptions in `docs/security.md`. |
| Python deps | `application/requirements*.in` → hash-locked `.txt` | `uv pip compile --generate-hashes --upgrade ...` (see application/README.md), then `make app-test docker-build docker-smoke trivy`. |
| Python base image | `ARG PYTHON_IMAGE=...@sha256:...` in the Dockerfile | Dependabot bumps the digest. For a minor Python version, change the tag **and** digest, plus `python-version` in workflows. |
| GitHub Actions | Commit SHA + `# vX.Y.Z` comment | Dependabot. To do it by hand: `gh api repos/<owner>/<action>/commits/<tag> --jq .sha`. |

Before merging any upgrade: `make ci`, and for provider or Terraform bumps a plan of every
environment showing no unexpected changes.
