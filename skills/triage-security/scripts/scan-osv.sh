#!/usr/bin/env bash
# scan-osv.sh — run osv-scanner against a repo path.
# OSV-Scanner is the recommended default: no auth, supports npm/PyPI/Go/Rust/
# Maven/Gradle/Composer/Cargo/etc., and reads the OSV.dev database.
#
# Usage: scan-osv.sh <repo-path>

set -uo pipefail

REPO_PATH="${1:?Usage: $0 <repo-path>}"

if ! command -v osv-scanner >/dev/null 2>&1; then
  echo "SKIP: osv-scanner not installed. See https://github.com/google/osv-scanner"
  exit 0
fi

# --recursive walks lockfiles in subdirs; --skip-git avoids scanning .git history.
osv-scanner --recursive --skip-git "${REPO_PATH}" 2>&1 || true
