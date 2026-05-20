#!/usr/bin/env bash
# scan-pip-audit.sh — run pip-audit against any Python manifest found in the repo.
#
# Usage: scan-pip-audit.sh <repo-path>

set -uo pipefail

REPO_PATH="${1:?Usage: $0 <repo-path>}"

if ! command -v pip-audit >/dev/null 2>&1; then
  echo "SKIP: pip-audit not installed. Install with: pipx install pip-audit"
  exit 0
fi

FOUND=0

# requirements*.txt files (one of the most common shapes).
# NUL-delimited iteration so paths with spaces or newlines are handled.
while IFS= read -r -d '' req; do
  FOUND=1
  echo "--- pip-audit: ${req} ---"
  pip-audit -r "${req}" 2>&1 || true
done < <(find "${REPO_PATH}" \
  -type d \( -name .venv -o -name node_modules -o -name .git \) -prune -o \
  -type f -name 'requirements*.txt' -print0 2>/dev/null)

# pyproject.toml (PEP 621 / poetry / hatch / uv).
while IFS= read -r -d '' pyproject; do
  FOUND=1
  proj_dir="$(dirname "${pyproject}")"
  echo "--- pip-audit: ${proj_dir} (pyproject.toml) ---"
  ( cd "${proj_dir}" && pip-audit 2>&1 ) || true
done < <(find "${REPO_PATH}" \
  -type d \( -name .venv -o -name node_modules -o -name .git \) -prune -o \
  -type f -name 'pyproject.toml' -print0 2>/dev/null)

if [ "${FOUND}" -eq 0 ]; then
  echo "SKIP: no Python manifests found in ${REPO_PATH}"
fi
