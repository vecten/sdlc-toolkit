---
name: create-release
description: >
  Prepares and opens a release branch from the dev branch using release/YYYY-MM-DD,
  supports per-repo target branches from config, collects changes, enriches release
  notes with PM tool metadata, pushes branch, creates a PR, and optionally
  notifies Slack. Use when the user asks to create, cut, or prepare a release.
---

# Create Release

Automates a full release cut flow:

1. Sync the dev branch (per-repo from config)
2. Sync the release target branch (per-repo from config)
3. Create `release/YYYY-MM-DD`
4. Bring dev changes into release branch
5. Build a review-ready summary enriched with ticket context
6. Push and create a PR
7. Optionally notify Slack

## Config dependency

Read `<workspace>/.cursor/skills-config.yaml` before acting. If missing, tell the user to run `/sdlc-toolkit:bootstrap-config` first.

Required config keys:

- `repos` — to detect current repo from CWD
- `git.branches.<repo>.dev` — the dev branch for this repo
- `git.branches.<repo>.release_target` — the target branch for releases
- `linear.ticket_prefix` — for extracting ticket keys from commits
- `slack.channels.release` — Slack channel for release notifications
- `slack.reviewers[]` — list of reviewers with pre-resolved Slack IDs
- `slack.notify_on_release` — whether to send Slack notification
- `git.custom_input` — any repo-specific release notes

## Repo detection

Detect the current repo by matching CWD against `repos.<name>.path`. If CWD doesn't match any configured repo, ask the user which repo this release is for.

## Branch rules

Read from config — do not hardcode branch names:

- Dev branch: `git.branches.<repo>.dev`
- Release target: `git.branches.<repo>.release_target`

If `release_target` is `null` for this repo, stop and tell the user this repo has no release branch workflow configured.

Auto-detect and proceed without asking for target branch confirmation when the config mapping is unambiguous. Ask only if the repo is not in config.

## Prerequisites

- Current directory is a git repository.
- Remote is `origin`.
- Working tree is clean, or user explicitly approves proceeding with local changes.
- GitHub CLI (`gh`) is available for PR creation.
- PM tool MCP is available for issue metadata lookup.

## Workflow

### 1) Prepare release branch

Run the script from this plugin's `scripts/` directory:

```bash
bash <plugin-path>/scripts/prepare-release-branch.sh <DEV_BRANCH> <TARGET_BRANCH> [YYYY-MM-DD]
```

The script handles checkout, pull, branch creation (with automatic suffix if a branch already exists), and merging dev into the release branch.

If the script fails (merge conflicts, network errors, missing branches), read the error output, attempt to resolve the issue (e.g., resolve conflicts, retry fetch), and re-run. Only abort and ask the user if the problem requires a decision (e.g., conflicting files that need manual resolution).

Capture `RELEASE_BRANCH` from the script's last output line.

### 2) Prepare release review summary (with PM tool enrichment)

Generate commit list and changed-file stats:

```bash
git log <TARGET_BRANCH>..<DEV_BRANCH> --oneline --no-decorate
git diff <TARGET_BRANCH>..<DEV_BRANCH> --stat
```

Then enrich the release summary:

1. Extract ticket keys from commits using `linear.ticket_prefix` (e.g., `<PREFIX>-\d+`).
2. Query the PM tool for each ticket key (title, status, priority, assignee, URL).
3. Group tickets by status and call out risky/high-priority items.
4. Include any notes from `git.custom_input`.
5. Produce a concise markdown summary.

Suggested summary format:

```markdown
## Summary

- Release branch: release/YYYY-MM-DD
- Source: <dev-branch>
- Target: <target-branch>
- Commit count: <n>

## Included changes

- <ticket-key> <title> — <short impact>

## Ticket context

- <ticket-key>: <status>, <priority>, <assignee>

## Risk notes

- <data migrations / breaking changes / infra dependencies / none>

## Commit list

<output of git log target..dev --oneline>
```

### 3) Push release branch

```bash
git push -u origin "$RELEASE_BRANCH"
```

### 4) Create PR

Use `gh pr create` with the prepared markdown summary as body.

- Base: `<TARGET_BRANCH>`
- Head: `$RELEASE_BRANCH`

```bash
gh pr create --base <TARGET_BRANCH> --head "$RELEASE_BRANCH" --title "Release $(date +%Y-%m-%d)" --body "$(cat <<'EOF'
<release-summary-markdown>
EOF
)"
```

### 5) Send Slack notification (conditional)

Skip this step if `slack.notify_on_release` is `false`.

Post a short blocker-check message to the channel in `slack.channels.release`.

Mention each reviewer from `slack.reviewers[]` using their pre-resolved `slack_id`:

```text
*Release branch is ready*
• Branch: `$RELEASE_BRANCH`
• PR: <$PR_URL|Release PR>

Please share any blockers, testing still in progress, or anything that should stop this release.

cc <@SLACK_ID_1> <@SLACK_ID_2>
```

Keep this message short (3-6 lines). Do not include the full release summary in Slack.

Read `slack.custom_input` for any overrides (e.g., different channel per repo, extra people to cc).

## Final output to user

Return:

- Release branch name
- Target branch used
- Number of commits included
- PM-enriched summary
- PR URL
- Whether Slack notification was sent (and to which channel)
