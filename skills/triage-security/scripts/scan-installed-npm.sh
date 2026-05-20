#!/usr/bin/env bash
# scan-installed-npm.sh — audit actually-installed Node packages.
# Complements scan-npm-audit.sh (which reads package-lock.json): this one
# inspects the real node_modules tree so installed-vs-locked drift is
# visible. Useful when a developer ran `npm install <pkg>` ad-hoc, or when
# a CI image differs from the lockfile.
#
# Usage: scan-installed-npm.sh <repo-path>

set -uo pipefail

REPO_PATH="${1:?Usage: $0 <repo-path>}"

if ! command -v npm >/dev/null 2>&1; then
  echo "SKIP: npm not installed."
  exit 0
fi

FOUND=0
while IFS= read -r -d '' nm_dir; do
  # Only care about top-level node_modules (skip nested ones inside deps).
  parent="$(dirname "${nm_dir}")"
  case "${parent}" in
    */node_modules/*) continue ;;
  esac
  FOUND=1
  echo "--- installed tree: ${parent} ---"
  ( cd "${parent}" && npm ls --all --json --omit=dev 2>/dev/null \
      | head -c 200000 ) || true
  echo
  echo "--- npm audit (installed): ${parent} ---"
  ( cd "${parent}" && npm audit --omit=dev --audit-level=high 2>&1 ) || true
done < <(find "${REPO_PATH}" \
  -type d -name node_modules -print0 2>/dev/null)

if [ "${FOUND}" -eq 0 ]; then
  echo "SKIP: no node_modules directories found in ${REPO_PATH}"
fi
