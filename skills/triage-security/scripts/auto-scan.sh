#!/usr/bin/env bash
# auto-scan.sh — run every available security scanner against a repo path
# and emit unified, section-headed output for the triage-security skill.
#
# Usage:
#   auto-scan.sh <repo-path> [scanners] [severity]
#
#   repo-path  Path to the repo to scan (absolute or relative to CWD).
#   scanners   Optional comma-separated list selecting a subset:
#                osv,trivy,npm-audit,pip-audit,snyk,installed-pip,installed-npm
#              Defaults to "auto" — runs every scanner whose CLI is installed.
#   severity   Optional minimum severity: low, medium, high or critical.
#              Defaults to "high". Passed to trivy and snyk; osv-scanner,
#              pip-audit and npm audit have no severity filter and report
#              every severity.
#
# Behavior:
#   - Each scanner is best-effort: missing CLIs are reported and skipped.
#     A non-installed scanner is not an error; the script continues.
#   - A scanner counts as run only when its wrapper did more than print
#     SKIP lines. The last line lists the scanners that ran.
#   - Output is plain text with one "=== <scanner> ===" section per run,
#     so the calling skill can parse it without JSON tooling.
#
# Exit codes:
#   0  at least one scanner ran (read the output for findings)
#   1  usage error (missing repo path or unknown severity)
#   2  INCONCLUSIVE: the repo path does not exist
#   3  INCONCLUSIVE: no scanner ran (none installed, or nothing to scan)

set -uo pipefail

REPO_PATH="${1:?Usage: $0 <repo-path> [scanners] [severity]}"
SELECTION="${2:-auto}"
SEVERITY="$(echo "${3:-high}" | tr '[:upper:]' '[:lower:]')"

case "${SEVERITY}" in
  low|medium|high|critical) ;;
  *)
    echo "ERROR: severity must be low, medium, high or critical (got: ${SEVERITY})" >&2
    exit 1
    ;;
esac

if [ ! -d "${REPO_PATH}" ]; then
  echo "INCONCLUSIVE: repo path does not exist: ${REPO_PATH}"
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

# A wrapper skipped when it printed SKIP lines and nothing else.
skipped() {
  printf '%s\n' "$1" | grep -q '^SKIP:' || return 1
  ! printf '%s\n' "$1" | grep -v '^SKIP:' | grep -q '[^[:space:]]'
}

if [ "${SELECTION}" = "auto" ]; then
  SELECTED=("${ALLOWED_SCANNERS[@]}")
else
  IFS=',' read -ra SELECTED <<< "${SELECTION}"
fi

echo "auto-scan target: ${REPO_PATH}"
echo "scanners requested: ${SELECTED[*]}"
echo "minimum severity: ${SEVERITY}"
echo

RAN=""
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
  out="$("${wrapper}" "${REPO_PATH}" "${SEVERITY}" 2>&1)"
  printf '%s\n' "${out}"
  skipped "${out}" || RAN="${RAN:+${RAN} }${scanner}"
  echo
done

if [ -z "${RAN}" ]; then
  echo "INCONCLUSIVE: no scanner ran against ${REPO_PATH}. Run install-deps.sh to see which scanners are missing."
  exit 3
fi
echo "scanners run: ${RAN}"
