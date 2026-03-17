#!/usr/bin/env bash
# prepare-release-branch.sh — deterministic git steps for cutting a release branch.
# Called by the create-release skill. If any step fails, the skill should
# inspect the error and attempt to resolve it before aborting.
#
# Usage: ./prepare-release-branch.sh <dev-branch> <target-branch> [release-date]
#   dev-branch     — branch to pull changes from (e.g. dev, main)
#   target-branch  — branch releases are merged into (e.g. production, main)
#   release-date   — optional, defaults to today's date (YYYY-MM-DD)

set -euo pipefail

DEV_BRANCH="${1:?Usage: $0 <dev-branch> <target-branch> [release-date]}"
TARGET_BRANCH="${2:?Usage: $0 <dev-branch> <target-branch> [release-date]}"
RELEASE_DATE="${3:-$(date +%Y-%m-%d)}"
RELEASE_BRANCH="release/${RELEASE_DATE}"

echo "==> Checking out ${DEV_BRANCH}"
git checkout "${DEV_BRANCH}"

echo "==> Pulling latest from origin/${DEV_BRANCH}"
git pull origin "${DEV_BRANCH}"

echo "==> Checking out ${TARGET_BRANCH}"
git checkout "${TARGET_BRANCH}"

echo "==> Pulling latest from origin/${TARGET_BRANCH}"
git pull origin "${TARGET_BRANCH}"

echo "==> Creating release branch ${RELEASE_BRANCH} from ${TARGET_BRANCH}"
if git show-ref --verify --quiet "refs/heads/${RELEASE_BRANCH}" 2>/dev/null; then
  SUFFIX=2
  while git show-ref --verify --quiet "refs/heads/${RELEASE_BRANCH}-${SUFFIX}" 2>/dev/null; do
    ((SUFFIX++))
  done
  RELEASE_BRANCH="${RELEASE_BRANCH}-${SUFFIX}"
  echo "    Branch already exists, using ${RELEASE_BRANCH}"
fi
git checkout -B "${RELEASE_BRANCH}" "${TARGET_BRANCH}"

echo "==> Pulling changes from origin/${DEV_BRANCH} into ${RELEASE_BRANCH}"
git pull origin "${DEV_BRANCH}"

echo "==> Release branch ready: ${RELEASE_BRANCH}"
echo "RELEASE_BRANCH=${RELEASE_BRANCH}"
