#!/usr/bin/env bash
# check-cve.sh — focused check for a single CVE in a repo.
# Runs auto-scan and filters for the CVE ID. Useful when an advisory
# names one specific CVE and the skill wants a yes/no signal fast.
#
# Usage: check-cve.sh <CVE-ID> <repo-path> [scanners]

set -uo pipefail

CVE_ID="${1:?Usage: $0 <CVE-ID> <repo-path> [scanners]}"
REPO_PATH="${2:?Usage: $0 <CVE-ID> <repo-path> [scanners]}"
SELECTION="${3:-auto}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Normalise the CVE for case-insensitive grep.
CVE_UPPER="$(echo "${CVE_ID}" | tr '[:lower:]' '[:upper:]')"

OUT="$("${SCRIPT_DIR}/auto-scan.sh" "${REPO_PATH}" "${SELECTION}")"
echo "${OUT}"
echo
echo "=== match for ${CVE_UPPER} ==="
if echo "${OUT}" | grep -i -- "${CVE_UPPER}"; then
  echo "VERDICT: ${CVE_UPPER} referenced in scan output above (review context to confirm fix vs. exposure)."
else
  echo "VERDICT: no scanner mentioned ${CVE_UPPER} in ${REPO_PATH}."
fi
