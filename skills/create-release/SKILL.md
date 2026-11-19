---
name: create-release
description: >
  Cut a release PR into the release target: either selected tickets
  cherry-picked onto a branch cut from the target, or a full merge of the dev
  branch. Asks which one first, works in a temporary worktree, enriches the PR
  with PM tool metadata, and optionally notifies Slack. Use when the user asks
  to create, cut, or prepare a release, or to release specific tickets.
---

# Create Release

Cuts one release PR per repo, from `release/YYYY-MM-DD` into the release target:

1. Agree the scope: selected tickets, full release, or a runbook only
2. Prepare the release branch in a temporary worktree (the user's checkout is never switched)
3. Build a review-ready summary enriched with ticket context
4. Push and create the PR
5. Optionally notify Slack

## Config dependency

Read `skills-config.yaml` before acting. Look in `.cursor/`, then `.claude/`, then the folder itself, starting from the current folder and moving up to the workspace root; use the first file found. If two copies differ, use the first and name both in one line. Every `custom_input` block applies and overrides this skill's defaults. If no file exists, tell the user to run `/sdlc-toolkit:bootstrap-config` first.

Required config keys:

- `repos` — to detect current repo from CWD, and `repos.<repo>.remote` for the GitHub `owner/name`
- `git.branches.<repo>.dev` — the dev branch for this repo
- `git.branches.<repo>.release_target` — the target branch for releases
- `linear.ticket_prefix` — for extracting ticket keys from commits
- `slack.channels.release` — Slack channel for release notifications
- `slack.reviewers[]` — list of reviewers with pre-resolved Slack IDs
- `slack.notify_on_release` — whether to send Slack notification
- `git.custom_input` — any repo-specific release notes

## Repo detection

Detect the current repo by matching CWD against `repos.<name>.path`. If CWD doesn't match any configured repo, ask the user which repos this release is for.

## Branch rules

Read from config — do not hardcode branch names:

- Dev branch: `git.branches.<repo>.dev`
- Release target: `git.branches.<repo>.release_target`

If `release_target` is `null` for a repo, leave that repo out and tell the user it has no release branch workflow configured.

## Prerequisites

- Remote is `origin`.
- GitHub CLI (`gh`) is available for PR creation.
- PM tool MCP is available for issue metadata lookup.

The user's working tree does not need to be clean: all release work happens in a temporary worktree.

## Rules

- A selected-tickets release never merges the dev branch. Only the selected tickets' merged commits go out.
- Never switch, reset or stash the user's checkout.
- Conflicts are reported to the user, never resolved by guesswork.
- Do not open a second release PR into a target that already has one open unless the user says so.

## Workflow

### 0) Agree the scope

Ask before touching git, unless the request already answers it:

1. **Selected tickets, full release, or a runbook only?**
   - *Selected tickets*: only the named tickets' merged changes go out; everything else stays on dev. This is the default when the request names tickets ("release ENG-123").
   - *Full release*: everything on dev that the target lacks. Use it only when the user asks for the full release or "everything".
   - *Runbook only*: write the steps and cut nothing (see the end of this workflow).
2. **Which repos?** Default: the repos whose dev branch holds the selected tickets' commits, or, for a full release, every configured repo with a `release_target` whose dev branch has unreleased commits. Name them and confirm.

Show the user what each repo's dev branch has that the target lacks, so they choose with the list in front of them:

```bash
git fetch origin
git log --cherry-pick --right-only --no-merges --oneline origin/<TARGET_BRANCH>...origin/<DEV_BRANCH>
```

`--cherry-pick` hides single commits an earlier selected-tickets release already shipped. A PR merged with a merge commit and shipped that way still shows its individual commits: treat it as shipped when the target has its `(cherry picked from commit <merge-commit>)` line (`git log origin/<TARGET_BRANCH> --grep "cherry picked from commit <merge-commit>"`).

### 1) Find the commits (selected tickets only)

For each ticket key, find its PRs merged into the dev branch:

```bash
gh pr list --repo <owner>/<name> --base <DEV_BRANCH> --state merged --search "<TICKET>" --json number,title,headRefName,mergedAt,mergeCommit
git log origin/<DEV_BRANCH> -E --grep "<TICKET>([^0-9]|$)" --format="%H %s"
```

Match the key exactly: `ENG-12` must not pick up `ENG-123`. Drop search hits whose title and branch name lack the exact key.

Use each PR's merge commit: one commit for a squash merge; a merge commit is picked against its first parent. For a rebase merge, the merge commit is only the last of the PR's commits: pick all of them, the `n` commits ending at the merge commit (`git log -n <n> --format="%H %s" <merge-commit>`, after checking their subjects match `gh pr view <number> --json commits`). If a ticket has no PR merged into dev, say so and leave it out. Never pick commits from an unmerged branch.

If a picked change adds a database migration, check that the migrations it depends on are already on the target or also picked. A clean cherry-pick can still fail on deploy.

If anything is ambiguous (several PRs for one ticket, a PR title without the key), show the commit list and wait for the user's go. If no commits remain, stop: never fall back to a full release.

### 2) Prepare the release branch

First check for an open release PR into the same target, and tell the user if one exists:

```bash
gh pr list --repo <owner>/<name> --base <TARGET_BRANCH> --state open --json number,headRefName,url --jq '.[] | select(.headRefName | startswith("release/"))'
```

Then, from the repo's directory, run the bundled script:

```bash
# selected tickets
bash "${CLAUDE_PLUGIN_ROOT}/scripts/prepare-release-branch.sh" <DEV_BRANCH> <TARGET_BRANCH> --pick <commit> [<commit>...]
# full release
bash "${CLAUDE_PLUGIN_ROOT}/scripts/prepare-release-branch.sh" <DEV_BRANCH> <TARGET_BRANCH> --all
```

The script fetches, picks a branch name that is free both locally and on `origin` (`release/YYYY-MM-DD`, then `-2`, `-3`, …), creates it from `origin/<TARGET_BRANCH>` in a temporary worktree, and either cherry-picks the given commits with `-x`, in the order they sit on the dev branch, or merges `origin/<DEV_BRANCH>`. Its last two lines are `RELEASE_BRANCH=<name>` and `WORKTREE=<path>`. Shell variables do not survive between commands, so write those two literal values into every later command where this skill says `<RELEASE_BRANCH>` and `<WORKTREE>`.

A line `SKIPPED <commit>: already on origin/<TARGET_BRANCH>` means that change shipped earlier; list it under the tickets left out.

If it exits non-zero, it has already removed the worktree and the local branch:

- `2`, conflict: the output names the files and the commit. Report that and stop.
  - Selected tickets: a conflicting pick usually depends on an earlier dev commit that was not selected. Name the candidates with `git log --oneline origin/<TARGET_BRANCH>..origin/<DEV_BRANCH> -- <files>` and let the user decide.
  - Full release: the target has changes on the same lines that dev lacks, typically a hotfix or an earlier cherry-pick that dev has changed again. Propose syncing dev with the target first (a back-merge through a temporary branch, see finish-release), then running the release again.
- `3`, nothing to release: the target already has these changes.
- `1`: usage error, a picked commit that is not on the dev branch, or a git failure such as commit signing or a hook. Report the message.

### 3) Prepare the release summary (with PM tool enrichment)

Commits and changed files in the release:

```bash
git -C <WORKTREE> log --oneline --no-decorate origin/<TARGET_BRANCH>..HEAD
git -C <WORKTREE> diff --stat origin/<TARGET_BRANCH>...HEAD
```

Then enrich the release summary:

1. Extract ticket keys from commits using `linear.ticket_prefix` (e.g., `<PREFIX>-\d+`).
2. Query the PM tool for each ticket key (title, status, priority, assignee, URL).
3. Group tickets by status and call out risky/high-priority items.
4. Include any notes from `git.custom_input`.
5. For a selected-tickets release, list what stays on dev: the step 0 list minus the picked tickets.
6. Produce a concise markdown summary.

Suggested summary format:

```markdown
## Summary

- Release branch: release/YYYY-MM-DD
- Scope: selected tickets | full release of <dev-branch>
- Target: <target-branch>
- Commit count: <n>

## Included changes

- <ticket-key> <title> — <short impact>

## Stays on dev (selected-tickets release only)

- <ticket-key> <title>

## Ticket context

- <ticket-key>: <status>, <priority>, <assignee>

## Risk notes

- <data migrations / breaking changes / infra dependencies / none>

## Commit list

<output of git log origin/<target>..HEAD --oneline>
```

### 4) Push, create the PR, remove the worktree

```bash
git -C <WORKTREE> push -u origin <RELEASE_BRANCH> && gh pr create --repo <owner>/<name> --base <TARGET_BRANCH> --head <RELEASE_BRANCH> --title "<title>" --body "$(cat <<'EOF'
<release-summary-markdown>
EOF
)" && git worktree remove <WORKTREE>
```

If the push fails, stop: do not create the PR.

Title: `Release YYYY-MM-DD` for a full release, `Release YYYY-MM-DD: <ticket-key>, <ticket-key>` for selected tickets.

### 5) Send Slack notification (conditional)

Skip this step if `slack.notify_on_release` is `false`.

Post a short blocker-check message to the channel in `slack.channels.release`.

Mention each reviewer from `slack.reviewers[]` using their pre-resolved `slack_id`:

```text
*Release branch is ready*
• Branch: `<RELEASE_BRANCH>`
• PR: <<PR_URL>|Release PR>

Please share any blockers, testing still in progress, or anything that should stop this release.

cc <@SLACK_ID_1> <@SLACK_ID_2>
```

Keep this message short (3-6 lines). Do not include the full release summary in Slack. If the release contents change after this message, reply in its thread with what changed.

Read `slack.custom_input` for any overrides (e.g., different channel per repo, extra people to cc).

### Runbook only

Write the steps for every repo, in the order the repos must ship:

- scope: tickets and commits per repo;
- the commands for steps 2–4;
- dependencies between repos (e.g. infrastructure before the app that needs it);
- migrations or manual steps;
- how to check each deploy.

Stop there: cut no branch and push nothing.

## Final output to user

Return:

- Scope (selected tickets, full release, or runbook)
- Per repo: release branch, target branch, number of commits, PR URL
- PM-enriched summary
- For selected tickets: what stays on dev
- Tickets left out and why (no merged PR, conflict)
- Whether Slack notification was sent (and to which channel)
