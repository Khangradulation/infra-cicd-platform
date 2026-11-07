#!/usr/bin/env bash
# Install pinned CI tools on a linux/amd64 GitHub runner, verifying SHA-256.
# Using release binaries with hard-coded digests instead of third-party
# wrapper actions keeps the supply chain short and tamper-evident.
#
# Usage: scripts/install-ci-tools.sh tflint trivy actionlint hadolint
# Upgrading: bump the version AND digest together (docs/upgrades.md).
set -euo pipefail

TFLINT_VERSION="0.65.0"
TFLINT_SHA256="d4c545ed2e29d6338604b586f34f544f380f70f243aa72f7b484713835eaec61"   # tflint_linux_amd64.zip
TRIVY_VERSION="0.76.2"
TRIVY_SHA256="bc0fc726e017b8927a62b2d3531d7a84ee01769daf5c99ed866dced54089fdbf"    # trivy_0.76.2_Linux-64bit.tar.gz
ACTIONLINT_VERSION="1.7.12"
ACTIONLINT_SHA256="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8" # actionlint_1.7.12_linux_amd64.tar.gz
HADOLINT_VERSION="2.15.1"
HADOLINT_SHA256="c7187db94eeeeca956519a6af171adc31453941a1e777961f6e680f697c8c507" # hadolint-linux-x86_64 (computed; upstream publishes no checksum file)

bin_dir="${CI_TOOLS_BIN:-${HOME}/.local/bin}"
mkdir -p "${bin_dir}"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

fetch() {  # url sha256 dest
  curl -fsSL --retry 3 --proto '=https' --tlsv1.2 -o "$3" "$1"
  echo "$2  $3" | sha256sum -c --quiet - || { echo "checksum mismatch for $1" >&2; exit 1; }
}

for tool in "$@"; do
  case "${tool}" in
    tflint)
      fetch "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip" "${TFLINT_SHA256}" "${work}/tflint.zip"
      unzip -oq "${work}/tflint.zip" -d "${bin_dir}" ;;
    trivy)
      fetch "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" "${TRIVY_SHA256}" "${work}/trivy.tgz"
      tar -xzf "${work}/trivy.tgz" -C "${bin_dir}" trivy ;;
    actionlint)
      fetch "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" "${ACTIONLINT_SHA256}" "${work}/actionlint.tgz"
      tar -xzf "${work}/actionlint.tgz" -C "${bin_dir}" actionlint ;;
    hadolint)
      fetch "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-linux-x86_64" "${HADOLINT_SHA256}" "${bin_dir}/hadolint"
      chmod +x "${bin_dir}/hadolint" ;;
    *) echo "unknown tool: ${tool}" >&2; exit 2 ;;
  esac
  echo "installed ${tool}"
done

[[ -n "${GITHUB_PATH:-}" ]] && echo "${bin_dir}" >>"${GITHUB_PATH}"
exit 0
