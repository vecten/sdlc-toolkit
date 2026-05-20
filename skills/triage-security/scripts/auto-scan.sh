#!/usr/bin/env bash
# auto-scan.sh — run every available security scanner against a repo path
# and emit unified, section-headed output for the triage-security skill.
#
# Usage:
#   auto-scan.sh <repo-path> [scanners]
#
#   repo-path  Path to the repo to scan (absolute or relative to CWD).
#   scanners   Optional comma-separated list selecting a subset:
#                osv,trivy,npm-audit,pip-audit,snyk
#              Defaults to "auto" — runs every scanner whose CLI is installed.
#
# Behavior:
#   - Each scanner is best-effort: missing CLIs are reported and skipped.
#     A non-installed scanner is not an error; the script continues.
#   - Output is plain text with one "=== <scanner> ===" section per run,
#     so the calling skill can parse it without JSON tooling.
#   - Exit code is 0 unless the repo path is invalid or no scanner ran.

set -uo pipefail

REPO_PATH="${1:?Usage: $0 <repo-path> [scanners]}"
SELECTION="${2:-auto}"

if [ ! -d "${REPO_PATH}" ]; then
  echo "ERROR: repo path does not exist: ${REPO_PATH}" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_PATH="$(cd "${REPO_PATH}" && pwd)"

# Allowlist — any scanner name must match one of these. Prevents path-style
# values in SELECTION from constructing wrapper paths like ../../foo.sh.
ALLOWED_SCANNERS=(osv trivy npm-audit pip-audit snyk installed-pip installed-npm)

is_allowed() {
  local needle="$1"
  local s
  for s in "${ALLOWED_SCANNERS[@]}"; do
    [ "${s}" = "${needle}" ] && return 0
  done
  return 1
}

if [ "${SELECTION}" = "auto" ]; then
  SELECTED=("${ALLOWED_SCANNERS[@]}")
else
  IFS=',' read -ra SELECTED <<< "${SELECTION}"
fi

echo "auto-scan target: ${REPO_PATH}"
echo "scanners requested: ${SELECTED[*]}"
echo

RAN_ANY=0
for scanner in "${SELECTED[@]}"; do
  if ! is_allowed "${scanner}"; then
    echo "=== ${scanner} ==="
    echo "SKIP: not in scanner allowlist (${ALLOWED_SCANNERS[*]})"
    echo
    continue
  fi
  wrapper="${SCRIPT_DIR}/scan-${scanner}.sh"
  if [ ! -x "${wrapper}" ]; then
    echo "=== ${scanner} ==="
    echo "SKIP: wrapper not found (${wrapper})"
    echo
    continue
  fi
  echo "=== ${scanner} ==="
  "${wrapper}" "${REPO_PATH}" || true
  RAN_ANY=1
  echo
done

if [ "${RAN_ANY}" -eq 0 ]; then
  echo "WARN: no scanner ran. Run scripts/install-deps.sh to install scanners." >&2
  exit 1
fi
