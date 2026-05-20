#!/usr/bin/env bash
# scan-snyk.sh — run Snyk test against a repo path.
# Snyk requires authentication: either a SNYK_TOKEN env var or a prior
# `snyk auth` run. The wrapper skips silently if the CLI is missing or
# unauthenticated, so it is safe to enable by default.
#
# Usage: scan-snyk.sh <repo-path>

set -uo pipefail

REPO_PATH="${1:?Usage: $0 <repo-path>}"

if ! command -v snyk >/dev/null 2>&1; then
  echo "SKIP: snyk not installed. See https://docs.snyk.io/snyk-cli"
  exit 0
fi

if [ -z "${SNYK_TOKEN:-}" ] && ! snyk config get api >/dev/null 2>&1; then
  echo "SKIP: snyk not authenticated. Set SNYK_TOKEN or run 'snyk auth'."
  exit 0
fi

# --all-projects walks every supported manifest in the tree.
# --severity-threshold=high keeps the noise down; lower it from the skill
# when an advisory is low-severity.
( cd "${REPO_PATH}" && snyk test \
    --all-projects \
    --severity-threshold=high 2>&1 ) || true
