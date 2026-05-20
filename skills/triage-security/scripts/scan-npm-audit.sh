#!/usr/bin/env bash
# scan-npm-audit.sh — run `npm audit` for any package-lock.json found in the repo.
#
# Usage: scan-npm-audit.sh <repo-path>

set -uo pipefail

REPO_PATH="${1:?Usage: $0 <repo-path>}"

if ! command -v npm >/dev/null 2>&1; then
  echo "SKIP: npm not installed."
  exit 0
fi

# Find every package-lock.json (skip node_modules so we don't audit deps' deps).
# NUL-delimited so paths with spaces or newlines are handled correctly.
FOUND=0
while IFS= read -r -d '' lock; do
  FOUND=1
  pkg_dir="$(dirname "${lock}")"
  echo "--- npm audit: ${pkg_dir} ---"
  ( cd "${pkg_dir}" && npm audit --omit=dev --audit-level=high 2>&1 ) || true
done < <(find "${REPO_PATH}" \
  -type d -name node_modules -prune -o \
  -type f -name package-lock.json -print0 2>/dev/null)

if [ "${FOUND}" -eq 0 ]; then
  echo "SKIP: no package-lock.json found in ${REPO_PATH}"
fi
