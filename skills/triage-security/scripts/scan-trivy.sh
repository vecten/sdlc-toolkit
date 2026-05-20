#!/usr/bin/env bash
# scan-trivy.sh — run Trivy filesystem scan against a repo path.
# Trivy covers OS packages, language deps, IaC misconfigurations, and secrets.
#
# Usage: scan-trivy.sh <repo-path>

set -uo pipefail

REPO_PATH="${1:?Usage: $0 <repo-path>}"

if ! command -v trivy >/dev/null 2>&1; then
  echo "SKIP: trivy not installed. See https://aquasecurity.github.io/trivy/"
  exit 0
fi

# --scanners vuln,misconfig,secret keeps output focused.
# --severity HIGH,CRITICAL filters noise; the skill can rerun with a wider
# severity range if a low-severity advisory arrives.
trivy fs \
  --scanners vuln,misconfig,secret \
  --severity HIGH,CRITICAL \
  --quiet \
  "${REPO_PATH}" 2>&1 || true
