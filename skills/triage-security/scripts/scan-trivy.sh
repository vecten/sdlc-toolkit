#!/usr/bin/env bash
# scan-trivy.sh — run Trivy filesystem scan against a repo path.
# Trivy covers OS packages, language deps, IaC misconfigurations, and secrets.
#
# Usage: scan-trivy.sh <repo-path> [severity]
#   severity  minimum severity: low, medium, high or critical (default: high)

set -uo pipefail

REPO_PATH="${1:?Usage: $0 <repo-path> [severity]}"
SEVERITY="$(echo "${2:-high}" | tr '[:upper:]' '[:lower:]')"

if ! command -v trivy >/dev/null 2>&1; then
  echo "SKIP: trivy not installed. See https://aquasecurity.github.io/trivy/"
  exit 0
fi

# Trivy takes the list of levels to show. "low" also shows UNKNOWN, where
# CVEs without a rating yet land.
case "${SEVERITY}" in
  critical) TRIVY_SEVERITY="CRITICAL" ;;
  medium)   TRIVY_SEVERITY="MEDIUM,HIGH,CRITICAL" ;;
  low)      TRIVY_SEVERITY="UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL" ;;
  *)        TRIVY_SEVERITY="HIGH,CRITICAL" ;;
esac

# --scanners vuln,misconfig,secret keeps output focused.
trivy fs \
  --scanners vuln,misconfig,secret \
  --severity "${TRIVY_SEVERITY}" \
  --quiet \
  "${REPO_PATH}" 2>&1 || true
