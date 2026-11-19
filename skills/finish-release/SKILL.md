---
name: finish-release
description: >
  Wrap up a production release by updating tickets to Done in the configured
  PM tool and drafting a client-facing release email. Use when the user says
  "finish release", "close release", "release done", "post-release",
  "release deployed", or asks to prepare a release email or mark released
  tickets as done.
---

# Finish Release

Post-deployment workflow that runs after a release branch has been merged to production. Two goals:

1. Move all included tickets to **Done** in the configured PM tool.
2. Draft a **client-facing release email** (if enabled in config).

This skill reads `pm_tool` from config. Currently supported: `linear`.

## Config dependency

Read `<workspace>/.cursor/skills-config.yaml` before acting. If missing, tell the user to run `/sdlc-toolkit:bootstrap-config` (in Cursor: `/bootstrap-config`) first.

Required config keys:

- `repos` — to detect current repo from CWD
- `git.branches.<repo>.release_target` — target branch for this repo
- `linear.ticket_prefix` — for extracting ticket keys from commits
- `release_email.enabled` — whether to draft a release email
- `release_email.greeting`, `release_email.sign_off`
- `release_email.custom_input` — system names, subject pattern, recipients, tone

## Prerequisites

- Current directory is a git repository.
- Remote is `origin`.
- PM tool MCP is available for ticket lookup and status updates.
- The release has already been merged to the target branch.

## Inputs

Collect release context using these sources (in priority order):

1. **Same-thread context** — if the `create-release` skill ran earlier in this conversation, reuse the release branch name, PR URL, target branch, and ticket list.
2. **User-provided PR URL or number** — extract ticket IDs from the PR body and commits.
3. **User-provided release branch name** — derive the info from git.

If none of these are available, ask the user for the release branch name or PR URL.

## Branch rules

Read from config:

- Detect current repo from CWD by matching against `repos.<name>.path`.
- Look up `git.branches.<repo>.release_target`.
- Auto-detect from repo context; ask only if ambiguous.

## Workflow

### 1) Determine release context

Set target branch from config. Gather the list of commits included:

```bash
git log <TARGET_BRANCH>..HEAD --oneline --no-decorate
```

Or, if the release is already merged and you have the PR number:

```bash
gh pr view <PR_NUMBER> --json body,mergeCommit,commits
```

Extract all ticket keys using `linear.ticket_prefix` from config (e.g., `<PREFIX>-\d+`).

### 2) Fetch ticket details from the PM tool

For each extracted ticket key:

1. Call `get_issue` (Linear) or the equivalent PM tool API with the ticket ID.
2. Collect: title, description, status, priority, assignee, labels, URL.

Store this data for both the status update step and the email composition step.

### 3) Update tickets to Done

For each ticket that is not already in a completed/done state:

1. Call `list_issue_statuses` for the ticket's team (cache per team — call once per unique team).
2. Find the status named **Done** (or the closest completed-type status).
3. Call `save_issue` with `id` and `state` set to the Done status.
4. Track which tickets were updated and which were already done.

If no clear "Done" status exists for a team, report the available statuses instead of guessing.

### 4) Compose the release email (conditional)

Skip this step if `release_email.enabled` is `false`.

Build a release email focused on client-facing impact. Before writing, if any ticket's user impact is unclear from the ticket data alone, ask the user for clarification on those specific tickets.

Read `release_email.custom_input` for:
- System display names (e.g., which friendly name to use for this repo)
- Subject line pattern
- Recipients
- Tone preferences
- Whether to include internal changes

#### Email structure

```
Subject: <from custom_input subject_pattern, or "Release Update — <date>">

<release_email.greeting>

We've deployed the latest updates to <system name from custom_input>. Here's a summary of what's new:

## What's New

<For each change, write 1-2 sentences in plain, non-technical language
 describing the user-visible impact. Group related changes together.
 Focus on what the user can now do, what was fixed, or what improved.
 Avoid technical jargon, code references, or internal ticket IDs.>

<release_email.sign_off>
```

#### Composition guidelines

- Write from the user's perspective. Instead of "Fixed null constraint on practice settings model", write "Practice settings are now preserved correctly when data is updated from external systems."
- Group related changes under a single bullet when they address the same feature area.
- If a change is purely internal (infra, refactoring, CI) with no user-facing impact, omit it unless `custom_input` says to include internal changes.

### 5) Present the email to the user

Output the full email text for the user to review, copy, and send.

Ask if any adjustments are needed (tone, missing context, grouping).

## Final output

When finished, report:

- Number of tickets updated to Done (and list them)
- Any tickets that were already Done or could not be updated (and why)
- The full email draft (if enabled)
- Any tickets where you lacked context and made assumptions

