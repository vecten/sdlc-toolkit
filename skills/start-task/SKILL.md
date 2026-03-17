---
name: start-task
description: >
  Start working on a ticket by fetching its details from the configured PM
  tool, moving it to In Progress, checking out a fresh dev branch, and
  entering Plan mode. Use when the user says "start task", "begin task",
  "pick up ticket", "start working on", or provides a ticket URL/ID.
---

# Start Task

Use this workflow when the user wants to begin work on a ticket. The skill gathers all context from the configured PM tool, prepares the local repo, and enters Plan mode so the user confirms an approach before any code changes.

This skill reads `pm_tool` from config. Currently supported: `linear`.

## Config dependency

Read `<workspace>/.cursor/skills-config.yaml` before acting. If missing, tell the user to run `bootstrap-config` first.

Required config keys:

- `repos` — to detect current repo from CWD
- `git.branches.<repo>.dev` — the dev branch for this repo
- `testing.runner`, `testing.prefer_makefile` — for validation defaults in plan output
- `testing.custom_input` — per-repo test/lint/migration commands

## Required Inputs

Collect from the user's prompt:

- **Ticket** — a ticket ID (e.g. `ENG-123`) or a full ticket URL
- **Custom instructions** (optional) — any additional context, constraints, or directions

## Workflow

### Step 1 — Parse the ticket ID

Extract the ticket identifier from the user's message:

- If given a URL like `https://linear.app/<org>/issue/ENG-123/...`, extract `ENG-123`.
- If given a raw ID like `ENG-123`, use it directly.
- If no ticket ID can be found, ask the user to provide one.

### Step 2 — Fetch issue details

Use the Linear MCP `get_issue` tool with `includeRelations: true`.

Extract and retain:

- Title
- Description (full markdown body)
- Priority
- Labels
- Assignee
- Current status
- Parent issue (if any)
- Blocking / blocked-by relations
- Acceptance criteria (if present in the description)

If the fetch fails, stop and tell the user.

### Step 3 — Move the issue to "In Progress"

1. List available statuses for the issue's team via `list_issue_statuses`.
2. Find the status that matches "In Progress" or the closest equivalent.
3. If the issue is already in that status, skip.
4. Otherwise update it via `save_issue`.

If no clear "In Progress" status exists, tell the user which statuses are available instead of guessing.

### Step 4 — Prepare the local repository

Detect current repo from CWD by matching against `repos.<name>.path`. Look up the dev branch from `git.branches.<repo>.dev`.

1. Check for uncommitted changes:

```bash
git status --porcelain
```

If output is non-empty, warn the user and ask how to proceed (stash, commit, or abort).

2. Switch to the dev branch and pull latest:

```bash
git checkout <DEV_BRANCH> && git pull origin <DEV_BRANCH>
```

If this fails (e.g. branch does not exist or merge conflicts), stop and inform the user.

### Step 5 — Enter Plan mode

After gathering all context, switch to **Plan mode**.

Then present a structured summary combining the ticket details, config context, and any custom user input:

```
## Task: <ticket-id> — <title>

**Priority:** <priority>
**Labels:** <labels>
**Status:** moved to In Progress

### Description
<ticket description>

### Acceptance Criteria
<extracted acceptance criteria, or "None specified">

### Relations
- **Parent:** <parent issue or "None">
- **Blocked by:** <list or "None">
- **Blocks:** <list or "None">

### Custom Instructions
<user-provided custom input, or "None">

### Validation Defaults
<dynamically built from testing.* config for the current repo>
<include per-repo commands from testing.custom_input if present>
```

After presenting this summary, ask the user to confirm the implementation approach before making any code changes.

## Safety Rules

- Never make code changes before the user confirms the plan.
- Never commit or push anything during this workflow.
- If the working tree has uncommitted changes, ask the user before discarding or stashing them.
- Do not create a feature branch during this step — that happens later when work begins.
- Validation defaults are read from config — do not hardcode repo-specific commands.
- If runner is `docker` and Docker is not running when validation needs to happen, stop and ask the user to enable it manually.

