#!/usr/bin/env bash
# install-deps.sh — check the scanner CLIs used by the triage-security skill
# and print the commands to install the missing ones.
#
# Usage:
#   bash install-deps.sh
#
# Behaviour:
#   - Never installs anything. It only detects what is missing and prints the
#     install commands for the user to run.
#   - Prints Homebrew commands on macOS, Linux commands everywhere else.
#   - Snyk also needs a free account and `snyk auth`; printed as a reminder.
#   - Runs on bash 3.2 (the macOS default).
#   - Exit 0 when every scanner is installed (snyk may still need auth).
#   - Exit 1 when one or more scanners are missing.

set -uo pipefail

OS="$(uname -s)"

# ── helpers ──────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}!${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; }

has() { command -v "$1" >/dev/null 2>&1; }

# Install commands for missing tools, one per line.
COMMANDS=""
MISSING=0

# check <tool> <macOS command> <Linux command>
check() {
  local tool="$1" mac_cmd="$2" linux_cmd="$3" cmd
  if has "${tool}"; then
    ok "${tool} ($("${tool}" --version 2>/dev/null | head -1))"
    return
  fi
  if [ "${OS}" = "Darwin" ]; then cmd="${mac_cmd}"; else cmd="${linux_cmd}"; fi
  fail "${tool} — not installed"
  COMMANDS="${COMMANDS}  ${cmd}"$'\n'
  MISSING=1
}

# ── checks ───────────────────────────────────────────────────────────────────

echo
echo "Checking scanner CLIs (this script installs nothing)…"

check osv-scanner \
  "brew install osv-scanner" \
  "go install github.com/google/osv-scanner/v2/cmd/osv-scanner@latest"
check trivy \
  "brew install aquasecurity/trivy/trivy" \
  "# trivy: see https://aquasecurity.github.io/trivy/ (apt/yum repos or binaries)"
check npm \
  "brew install node" \
  "sudo apt-get install nodejs npm"
check pip-audit \
  "pipx install pip-audit" \
  "pipx install pip-audit"
check snyk \
  "npm install -g snyk && snyk auth" \
  "npm install -g snyk && snyk auth"

# Same check as scan-snyk.sh, so both agree on "authenticated".
if has snyk && [ -z "${SNYK_TOKEN:-}" ] && ! snyk config get api >/dev/null 2>&1; then
  warn "snyk is installed but not authenticated. Run: snyk auth (free account at snyk.io)"
fi

# ── summary ──────────────────────────────────────────────────────────────────

echo
if [ "${MISSING}" -eq 0 ]; then
  echo "All scanners are installed."
  exit 0
fi

echo "Nothing was installed. To install the missing scanners, run these yourself:"
echo
printf '%s' "${COMMANDS}"
if [ "${OS}" = "Darwin" ] && ! has brew; then
  echo
  echo "  # Homebrew is not installed: see https://brew.sh"
fi
echo
echo "At least one scanner (osv-scanner or trivy) is enough for a useful scan — see SKILL.md."
exit 1
