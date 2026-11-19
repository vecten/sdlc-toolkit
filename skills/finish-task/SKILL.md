---
name: finish-task
description: >
  Finalize an implementation for a ticket by preparing a branch, drafting a
  commit message from the actual changes, committing, pushing, and preparing
  or creating a PR. Use when the user says "finish task", "wrap up ticket",
  "prepare branch and PR", or asks to finish work for a ticket.
---

# Finish Task

Use this workflow when the user wants to wrap up completed changes for a ticket.

This skill reads `pm_tool` from config. Currently supported: `linear`.

Default outcome:

- branch name: `<prefix>/<ticket-id>-<short-slug>`
- commit based on the actual staged/unstaged changes
- push branch to `origin`
- prepare or create a PR
- move the issue to the proper review status
- optionally send a Slack update about the PR

## Config dependency

Read `skills-config.yaml` before acting. Look in `.cursor/`, then `.claude/`, then the folder itself, starting from the current folder and moving up to the workspace root; use the first file found. If two copies differ, use the first and name both in one line. Every `custom_input` block applies and overrides this skill's defaults. If no file exists, tell the user to run `/sdlc-toolkit:bootstrap-config` first.

Required config keys:

- `pm_tool` — which PM tool to use (default: `linear`)
- `repos` — to detect the current repo from CWD, and `repos.<repo>.remote` for the GitHub `owner/name`
- `git.branches.<repo>.dev` — the branch the PR targets
- `git.branch_prefixes` — prefix rules for feature/bugfix/hotfix
- `git.commit_prefix_pattern` — commit message format
- `slack.channels.review` — Slack channel for PR notifications
- `slack.reviewers[]` — list of reviewers with pre-resolved Slack IDs
- `slack.notify_on_pr` — whether to send Slack notification
- `slack.custom_input` — any overrides
- `testing.runner` — "docker", "host", or "ci-only"
- `testing.prefer_makefile` — whether to prefer Makefile targets
- `testing.custom_input` — per-repo test/lint/migration commands

## Required Inputs

Collect these before acting:

- Ticket ID, for example `ENG-123`
- Ticket title or short summary
- Optional ticket URL

If the user provides only the ticket ID or URL and the title is not available, ask for the title before creating the branch name and PR title.

## Branch Prefix Rules

Choose the prefix from the ticket context, using `git.branch_prefixes` from config:

- `feature/` for new functionality, enhancements, and general product work
- `bugfix/` for bug fixes that are not urgent production incidents
- `hotfix/` only for urgent production fixes or explicitly urgent user requests

If the correct prefix is unclear, ask the user before creating the branch.

## Safety Rules

- Do not amend commits unless the user explicitly asks.
- Follow the repository's recent commit message style instead of inventing a new format.
- Never present host-run checks as the primary test evidence when Docker-based validation should have been used.

## Workflow

Work in the right folder first. If start-task created a worktree for this ticket (`<workspace>/<worktrees_dir>/<ticket-id>-<repo>`), run every git command there with `git -C <path>`. If CWD is not inside a configured repo, ask which repo the change is in.

Run the git inspection commands in parallel first:

```bash
git status --short
git diff --stat && git diff
git log --oneline -5
```

### Step 1: Review the current state

Use the inspection output to confirm:

- which files are changing
- whether there are unrelated changes
- what commit message style the repo is using

If the branch already matches `<prefix>/<ticket-id>-<short-slug>`, keep it.

If the current branch does not match, create a branch with:

```bash
git checkout -b <prefix>/<ticket-id>-<short-slug>
```

Create the slug from the ticket title:

- lowercase
- words separated with `-`
- keep it short, usually 3-6 words
- remove punctuation

### Step 2: Stage only relevant changes

Add only files that belong to the task. If there are unrelated files in the worktree, ask before staging anything else.

### Step 3: Verify (config-driven)

Before committing, run the most relevant validation for the change set.

Read `testing.runner` from config:

- **docker**: use Docker-based commands. Prefer Makefile targets if `testing.prefer_makefile` is true.
- **host**: run commands directly on the host machine.
- **ci-only**: skip local verification entirely; note in the PR that verification is deferred to CI.

Read `testing.custom_input` for the current repo's specific commands (e.g., test command, lint command, migration command). Run every test and lint command listed there for the repos the change touches, not just one, and show the last lines of each command's output.

If runner is `docker` and Docker is not running, stop and ask the user to enable it manually.

A check that did not run (skipped, blocked, or `ci-only`) is reported as not run, never as passed. Reflect the actual verification status in the commit and PR summary.

### Step 4: Draft the commit message

Base the message on:

- the actual code changes
- the ticket title
- the repo's recent commit style
- the `git.commit_prefix_pattern` from config

Write a concise message focused on why the change exists, not a file-by-file changelog.

### Step 5: Commit

Commit using a heredoc message:

```bash
git add <relevant files>
git commit -m "$(cat <<'EOF'
<commit subject>

<commit body>
EOF
)"
```

If hooks modify files, stage the hook changes and create a new commit only if needed under the git safety rules.

### Step 6: Push

```bash
git push -u origin HEAD
```

### Step 7: Prepare or create the PR

Use the ticket ID and title in the PR title.

Default PR body:

```markdown
## Summary
- <main change 1>
- <main change 2>

## Testing
- [x] <test or verification step>

## Ticket
- <ticket-id>
```

In the Testing section:
- Reflect actual verification based on `testing.runner`.
- Tick a box only for a check that ran and passed. List the others unticked, with the reason.
- If verification was blocked (Docker not running, ci-only), say that explicitly.

Open the PR ready for review. Use `--draft` only when there is a named blocker (say what it is in the PR body) or when `git.custom_input` asks for drafts.

The PR targets the repo's dev branch from `git.branches.<repo>.dev`, not the repository's default branch on GitHub. Target another branch only when the user says so (for example, a hotfix straight to the release target).

Create the PR with:

```bash
gh pr create --repo <owner>/<name> --base <DEV_BRANCH> --head <branch> --title "<ticket-id>: <ticket title>" --body "$(cat <<'EOF'
<pr-body>
EOF
)"
```

### Step 8: Verify the issue is in review

After the PR is created, check that the PM issue has moved to the appropriate review state:

1. `list_issue_statuses` for the issue's team.
2. Read the current issue state.
3. If not in `In Review` or closest equivalent, fix with `save_issue`.

If no clear review status exists, tell the user which statuses are available.

### Step 9: Send Slack update (conditional)

Skip if `slack.notify_on_pr` is `false`.

Post a message to `slack.channels.review`.

Mention each reviewer from `slack.reviewers[]` using their pre-resolved `slack_id`:

```text
<@SLACK_ID_1> <@SLACK_ID_2> PR ready for review

<ticket-id>: <ticket title>
PR: <pr-url>

Summary:
- <main change 1>
- <main change 2>

Testing:
- <test status>
```

Read `slack.custom_input` for any overrides.

If Slack access is not available, skip this step and tell the user.

### Step 10: Hotfix follow-up (conditional)

If the PR targets the release target instead of the dev branch (a hotfix), offer the matching PR into dev so the fix is not lost at the next release: cherry-pick the commit with `-x` onto a new branch from `origin/<DEV_BRANCH>` in a temporary worktree, push it, and open a PR into the dev branch.

### Step 11: Watch CI (offer)

Offer to watch the PR's checks and report the result:

```bash
gh pr checks <pr-number> --repo <owner>/<name> --watch
```

If a check fails, show the failing job and the end of its log (`gh run view <run-id> --repo <owner>/<name> --log-failed`).

## Response To User

When finished, report:

- branch name
- commit hash and commit subject
- whether the branch was pushed
- PR URL if created
- whether the PM issue was moved to review
- whether the Slack message was sent
- which checks ran locally, and which did not run and why
- the hotfix PR into dev, if opened
- the CI result, if watched

If you could not finish one of the steps, say exactly where the workflow stopped and why.

