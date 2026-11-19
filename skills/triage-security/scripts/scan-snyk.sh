#!/usr/bin/env bash
# scan-snyk.sh — run Snyk test against a repo path.
# Snyk requires authentication: either a SNYK_TOKEN env var or a prior
# `snyk auth` run. The wrapper skips silently if the CLI is missing or
# unauthenticated, so it is safe to enable by default.
#
# Usage: scan-snyk.sh <repo-path> [severity]
#   severity  minimum severity: low, medium, high or critical (default: high)

set -uo pipefail

REPO_PATH="${1:?Usage: $0 <repo-path> [severity]}"
SEVERITY="$(echo "${2:-high}" | tr '[:upper:]' '[:lower:]')"

if ! command -v snyk >/dev/null 2>&1; then
  echo "SKIP: snyk not installed. See https://docs.snyk.io/snyk-cli"
  exit 0
fi

if [ -z "${SNYK_TOKEN:-}" ] && ! snyk config get api >/dev/null 2>&1; then
  echo "SKIP: snyk not authenticated. Set SNYK_TOKEN or run 'snyk auth'."
  exit 0
fi

# --all-projects walks every supported manifest in the tree.
# --severity-threshold keeps the noise down (high unless the skill lowers it).
( cd "${REPO_PATH}" && snyk test \
    --all-projects \
    --severity-threshold="${SEVERITY}" 2>&1 ) || true
