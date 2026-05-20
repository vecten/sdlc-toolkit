#!/usr/bin/env bash
# install-deps.sh — install scanner CLIs used by the triage-security skill.
#
# Usage:
#   bash install-deps.sh
#
# Behaviour:
#   - Detects macOS (brew) or Linux (apt-get / pip / npm).
#   - Checks each scanner; installs if missing.
#   - Snyk requires a free account: printed as a reminder, not auto-authed.
#   - Prints a summary table at the end.
#   - Exit 0 when all tools are present (or were just installed).
#   - Exit 1 when one or more tools could not be installed.

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

# Status per tool: "present" | "installed" | "needs-auth" | "failed"
declare -A STATUS

install_brew_pkg() {
  local formula="$1"
  if [ "${OS}" = "Darwin" ] && has brew; then
    brew install "${formula}" >/dev/null 2>&1 && return 0
  fi
  return 1
}

install_apt_pkg() {
  local pkg="$1"
  if [ "${OS}" = "Linux" ] && has apt-get; then
    sudo apt-get install -y "${pkg}" >/dev/null 2>&1 && return 0
  fi
  return 1
}

# ── osv-scanner ───────────────────────────────────────────────────────────────

echo
echo "Checking osv-scanner…"
if has osv-scanner; then
  ok "osv-scanner already installed ($(osv-scanner --version 2>/dev/null | head -1))"
  STATUS[osv-scanner]="present"
else
  echo "  Installing osv-scanner…"
  installed=0
  if install_brew_pkg osv-scanner; then
    installed=1
  elif [ "${OS}" = "Linux" ] && has go; then
    go install github.com/google/osv-scanner/cmd/osv-scanner@latest >/dev/null 2>&1 && installed=1
  fi
  if [ "${installed}" -eq 1 ] && has osv-scanner; then
    ok "osv-scanner installed"
    STATUS[osv-scanner]="installed"
  else
    fail "osv-scanner: could not install. See https://github.com/google/osv-scanner"
    STATUS[osv-scanner]="failed"
  fi
fi

# ── trivy ─────────────────────────────────────────────────────────────────────

echo
echo "Checking trivy…"
if has trivy; then
  ok "trivy already installed ($(trivy --version 2>/dev/null | head -1))"
  STATUS[trivy]="present"
else
  echo "  Installing trivy…"
  installed=0
  if install_brew_pkg "aquasecurity/trivy/trivy"; then
    installed=1
  elif [ "${OS}" = "Linux" ]; then
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
      | sh -s -- -b /usr/local/bin >/dev/null 2>&1 && installed=1
  fi
  if [ "${installed}" -eq 1 ] && has trivy; then
    ok "trivy installed"
    STATUS[trivy]="installed"
  else
    fail "trivy: could not install. See https://aquasecurity.github.io/trivy/"
    STATUS[trivy]="failed"
  fi
fi

# ── npm (for npm audit) ────────────────────────────────────────────────────────

echo
echo "Checking npm…"
if has npm; then
  ok "npm already installed ($(npm --version 2>/dev/null))"
  STATUS[npm]="present"
else
  echo "  Installing Node.js (includes npm)…"
  installed=0
  if install_brew_pkg node; then
    installed=1
  elif install_apt_pkg nodejs; then
    installed=1
  fi
  if [ "${installed}" -eq 1 ] && has npm; then
    ok "npm installed"
    STATUS[npm]="installed"
  else
    fail "npm: could not install. See https://nodejs.org/"
    STATUS[npm]="failed"
  fi
fi

# ── pip-audit ─────────────────────────────────────────────────────────────────

echo
echo "Checking pip-audit…"
if has pip-audit; then
  ok "pip-audit already installed ($(pip-audit --version 2>/dev/null))"
  STATUS[pip-audit]="present"
else
  echo "  Installing pip-audit…"
  installed=0
  if has pip3 && pip3 install --quiet pip-audit 2>/dev/null; then
    installed=1
  elif has pip && pip install --quiet pip-audit 2>/dev/null; then
    installed=1
  fi
  if [ "${installed}" -eq 1 ] && has pip-audit; then
    ok "pip-audit installed"
    STATUS[pip-audit]="installed"
  else
    fail "pip-audit: could not install. Run: pip install pip-audit"
    STATUS[pip-audit]="failed"
  fi
fi

# ── snyk ──────────────────────────────────────────────────────────────────────

echo
echo "Checking snyk…"
if has snyk; then
  ok "snyk already installed ($(snyk --version 2>/dev/null))"
  # Check if authenticated
  if snyk whoami >/dev/null 2>&1; then
    STATUS[snyk]="present"
  else
    warn "snyk installed but not authenticated. Run: snyk auth"
    STATUS[snyk]="needs-auth"
  fi
else
  echo "  Installing snyk…"
  if has npm && npm install -g snyk >/dev/null 2>&1 && has snyk; then
    warn "snyk installed. Run 'snyk auth' to authenticate (free account at snyk.io)."
    STATUS[snyk]="needs-auth"
  else
    fail "snyk: could not install. Run: npm install -g snyk"
    STATUS[snyk]="failed"
  fi
fi

# ── summary ───────────────────────────────────────────────────────────────────

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Scanner install summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

FAILED=0
for tool in osv-scanner trivy npm pip-audit snyk; do
  s="${STATUS[$tool]:-failed}"
  case "${s}" in
    present)    ok "${tool} — already installed" ;;
    installed)  ok "${tool} — installed now" ;;
    needs-auth) warn "${tool} — installed, needs auth (snyk auth)" ;;
    failed)     fail "${tool} — not installed"; FAILED=1 ;;
  esac
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

if [ "${FAILED}" -eq 1 ]; then
  echo "One or more scanners could not be installed. Check the messages above." >&2
  exit 1
fi
echo "All scanners ready. At least one missing scanner will not block triage — see SKILL.md."
