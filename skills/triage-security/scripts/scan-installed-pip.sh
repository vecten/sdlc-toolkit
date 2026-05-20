#!/usr/bin/env bash
# scan-installed-pip.sh — audit actually-installed Python packages.
# Manifests can drift from reality: transitive resolution, dev installs,
# `pip install` inside a running container. This script audits what is
# actually present in any virtualenv found under the repo path, and (when
# the arg is a venv directly) audits that venv.
#
# Usage: scan-installed-pip.sh <repo-or-venv>

set -uo pipefail

TARGET="${1:?Usage: $0 <repo-or-venv>}"

if ! command -v pip-audit >/dev/null 2>&1; then
  echo "SKIP: pip-audit not installed. Install with: pipx install pip-audit"
  exit 0
fi

audit_venv() {
  local venv="$1"
  local pybin="${venv}/bin/python"
  if [ ! -x "${pybin}" ]; then
    pybin="${venv}/Scripts/python.exe"  # Windows venv layout
  fi
  if [ ! -x "${pybin}" ]; then
    echo "SKIP: ${venv} has no python binary"
    return
  fi
  echo "--- pip-audit (installed): ${venv} ---"
  # Freeze the venv's actual installed set, pipe to pip-audit -r.
  # This audits what is loadable at runtime, not just what was pinned.
  "${pybin}" -m pip freeze --local 2>/dev/null | pip-audit -r /dev/stdin 2>&1 || true
}

# Case 1: TARGET is itself a venv.
if [ -x "${TARGET}/bin/python" ] || [ -x "${TARGET}/Scripts/python.exe" ]; then
  audit_venv "${TARGET}"
  exit 0
fi

# Case 2: TARGET is a repo — find venvs inside it.
FOUND=0
while IFS= read -r -d '' pyvenv_cfg; do
  FOUND=1
  audit_venv "$(dirname "${pyvenv_cfg}")"
done < <(find "${TARGET}" \
  -type d \( -name node_modules -o -name .git \) -prune -o \
  -type f -name 'pyvenv.cfg' -print0 2>/dev/null)

if [ "${FOUND}" -eq 0 ]; then
  echo "SKIP: no virtualenvs found under ${TARGET}"
fi
