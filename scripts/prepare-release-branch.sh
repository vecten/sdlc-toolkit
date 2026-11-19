#!/usr/bin/env bash
# prepare-release-branch.sh — deterministic git steps for cutting a release branch.
# Called by the create-release skill. Works in a temporary worktree, so the
# caller's checkout is never switched. On a conflict it aborts, cleans up and
# exits 2: conflicts are reported to the user, never resolved by guesswork.
#
# Run from inside the repository.
#
# Usage: prepare-release-branch.sh <dev-branch> <target-branch> [release-date] (--all | --pick <commit>...)
#   dev-branch     branch the changes come from (e.g. dev)
#   target-branch  branch releases are merged into (e.g. production)
#   release-date   optional, YYYY-MM-DD, defaults to today
#   --all          full release: merge all of origin/<dev-branch>
#   --pick         selected-tickets release: cherry-pick only these commits;
#                  they are applied in the order they sit on the dev branch
#
# On success the last two lines are:
#   RELEASE_BRANCH=<name>
#   WORKTREE=<path>
# Exit codes: 0 ready; 1 usage or git error; 2 conflict; 3 nothing to release.
# On any non-zero exit the worktree and the local release branch are removed.

set -euo pipefail

usage() {
  echo "Usage: $0 <dev-branch> <target-branch> [release-date] (--all | --pick <commit>...)" >&2
  exit 1
}

[ $# -ge 3 ] || usage
DEV_BRANCH="$1"
TARGET_BRANCH="$2"
shift 2
RELEASE_DATE="$(date +%Y-%m-%d)"
case "$1" in
  --all | --pick) ;;
  *) RELEASE_DATE="$1"; shift ;;
esac
[ $# -gt 0 ] || usage
MODE="$1"
shift
PICKS=()
case "$MODE" in
  --all) [ $# -eq 0 ] || usage ;;
  --pick) [ $# -gt 0 ] || usage; PICKS=("$@") ;;
  *) usage ;;
esac

WORKTREE=""
RELEASE_BRANCH=""
cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$WORKTREE" ]; then
    git worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
    git branch -D "$RELEASE_BRANCH" >/dev/null 2>&1 || true
  fi
  exit "$rc"
}
trap cleanup EXIT

unmerged() { git -C "$WORKTREE" diff --name-only --diff-filter=U; }

conflict() {
  echo "!! CONFLICT while $1. Files:" >&2
  unmerged | sed 's/^/   /' >&2
  git -C "$WORKTREE" merge --abort >/dev/null 2>&1 || git -C "$WORKTREE" cherry-pick --abort >/dev/null 2>&1 || true
  exit 2
}

failed() {
  echo "!! git failed while $1:" >&2
  echo "$2" | sed 's/^/   /' >&2
  exit 1
}

echo "==> Fetching origin/${DEV_BRANCH} and origin/${TARGET_BRANCH}"
git fetch --quiet origin "$DEV_BRANCH" "$TARGET_BRANCH"

ORDERED=()
if [ "$MODE" = "--pick" ]; then
  wanted=""
  for c in "${PICKS[@]}"; do
    full="$(git rev-parse --verify --quiet "${c}^{commit}")" || { echo "!! Unknown commit: $c" >&2; exit 1; }
    if ! git merge-base --is-ancestor "$full" "origin/${DEV_BRANCH}"; then
      echo "!! $c is not on origin/${DEV_BRANCH}; only merged work can be released" >&2
      exit 1
    fi
    wanted="${wanted}${full}"$'\n'
  done
  while read -r sha; do
    if printf '%s' "$wanted" | grep -qxF "$sha"; then
      ORDERED+=("$sha")
    fi
  done < <(git rev-list --topo-order --reverse "origin/${TARGET_BRANCH}..origin/${DEV_BRANCH}")
  # Picks already reachable from the target are not in that range; keep them so they report as skipped.
  for c in "${PICKS[@]}"; do
    full="$(git rev-parse "${c}^{commit}")"
    if git merge-base --is-ancestor "$full" "origin/${TARGET_BRANCH}"; then
      ORDERED+=("$full")
    fi
  done
fi

BASE_NAME="release/${RELEASE_DATE}"
RELEASE_BRANCH="$BASE_NAME"
n=2
while git show-ref --verify --quiet "refs/heads/${RELEASE_BRANCH}" \
  || git ls-remote --exit-code --heads origin "$RELEASE_BRANCH" >/dev/null 2>&1; do
  RELEASE_BRANCH="${BASE_NAME}-${n}"
  n=$((n + 1))
done

WORKTREE="$(mktemp -d "${TMPDIR:-/tmp}/release.XXXXXX")"
rmdir "$WORKTREE"
echo "==> Creating ${RELEASE_BRANCH} from origin/${TARGET_BRANCH} in ${WORKTREE}"
git worktree add --quiet --no-track -b "$RELEASE_BRANCH" "$WORKTREE" "origin/${TARGET_BRANCH}"

if [ "$MODE" = "--all" ]; then
  echo "==> Merging origin/${DEV_BRANCH}"
  if ! out="$(git -C "$WORKTREE" merge --no-edit "origin/${DEV_BRANCH}" 2>&1)"; then
    if [ -n "$(unmerged)" ]; then
      conflict "merging origin/${DEV_BRANCH}"
    fi
    failed "merging origin/${DEV_BRANCH}" "$out"
  fi
else
  for c in "${ORDERED[@]}"; do
    echo "==> Cherry-picking $(git log -1 --format='%h %s' "$c")"
    mainline=()
    if [ "$(git rev-list --parents -n 1 "$c" | wc -w)" -gt 2 ]; then
      mainline=(-m 1)
    fi
    if ! out="$(git -C "$WORKTREE" cherry-pick -x ${mainline[@]+"${mainline[@]}"} "$c" 2>&1)"; then
      if [ -n "$(unmerged)" ]; then
        conflict "cherry-picking $c"
      elif git -C "$WORKTREE" diff --cached --quiet && git -C "$WORKTREE" diff --quiet; then
        echo "    SKIPPED $c: already on origin/${TARGET_BRANCH}"
        git -C "$WORKTREE" cherry-pick --skip >/dev/null 2>&1
      else
        failed "cherry-picking $c" "$out"
      fi
    fi
  done
fi

AHEAD="$(git -C "$WORKTREE" rev-list --count "origin/${TARGET_BRANCH}..HEAD")"
if [ "$AHEAD" -eq 0 ]; then
  echo "!! Nothing to release: origin/${TARGET_BRANCH} already has these changes" >&2
  exit 3
fi

echo "==> Release branch ready: ${RELEASE_BRANCH} (${AHEAD} commits ahead of origin/${TARGET_BRANCH})"
echo "RELEASE_BRANCH=${RELEASE_BRANCH}"
echo "WORKTREE=${WORKTREE}"
