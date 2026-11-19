---
name: debug-sentry
description: >
  Investigate a Sentry issue from a provided Sentry URL, explain the likely root
  cause, propose a mitigation plan, create a ticket in the configured PM tool,
  then hand off implementation start to the start-task skill and wrap-up to the
  finish-task skill when appropriate. Use when the user says "debug sentry",
  "sentry", "fix sentry issue", or provides a Sentry issue link.
---

# Debug Sentry

Use this workflow when the user wants help with a Sentry issue and provides a Sentry issue URL.

This skill reads `pm_tool` from config. Currently supported: `linear`.

## Config dependency

Read `<workspace>/.cursor/skills-config.yaml` before acting. If missing, tell the user to run `/sdlc-toolkit:bootstrap-config` (in Cursor: `/bootstrap-config`) first.

Required config keys:

- `pm_tool` — which PM tool to use
- `linear.team_name`, `linear.team_id`
- `linear.default_project`, `linear.projects[]`
- `linear.custom_input`

## Required Input

- A Sentry issue URL
- Optional extra context from the user

If the user does not provide the Sentry URL, ask for it before doing anything else.

## Goals

1. Inspect the Sentry issue and understand what is failing
2. Explain the likely root cause and impact
3. Propose a mitigation and implementation plan
4. Create an issue in the configured PM tool
5. If implementation should proceed, hand off to the `start-task` skill
6. If the user later asks to wrap up the fix, hand off to the `finish-task` skill

## Workflow

### Step 1 — Read the Sentry issue

Use the Sentry MCP `get_issue_details` tool with the full URL.

Retain:

- Sentry issue ID
- Title
- Error type and message
- Status and assignee
- Project and environment
- Culprit, stacktrace, and relevant tags
- Frequency, latest event time, and any obvious blast radius

If issue details are not enough to form a confident hypothesis, use `analyze_issue_with_seer`.

Use Seer when:

- the user explicitly asks for deeper analysis
- the stacktrace is incomplete or misleading
- the failure path spans multiple layers and root cause is unclear

Do not use Seer reflexively if the issue details already make the cause obvious.

### Step 2 — Summarize the diagnosis

Before making code changes, give the user a short structured diagnosis:

```markdown
## Sentry Issue
<issue id> - <title>

## What is happening
<plain English summary>

## Likely root cause
<best current hypothesis with evidence>

## Impact
<who or what is affected>

## Mitigation Plan
1. <immediate mitigation if any>
2. <code/config/data fix>
3. <verification plan>
```

If the evidence is weak or ambiguous, say so explicitly and list the main assumptions.

### Step 3 — Create the PM issue

Always create an issue in the configured PM tool for the investigation/fix unless the user explicitly says not to.

Use the team from `linear.team_name` in config.

Use the Linear MCP tools in this order:

1. `list_teams` if the team identity needs confirmation
2. `list_cycles` with the team ID to get the current cycle
3. `list_projects` — use `linear.default_project` from config, or ask user to pick from `linear.projects[]`
4. `list_issue_statuses` for the team to find the correct todo/backlog or In Progress state
5. `save_issue` to create the issue
6. `get_issue` to retrieve the created issue and its git branch name
7. `list_issue_labels` to find the right label if a label fallback is needed
8. `create_issue_label` only if the needed fallback label does not exist yet

Always:

- add the issue to the current cycle
- add the configured project
- include the Sentry URL as a link attachment if supported
- include the Sentry issue ID in the title or description
- include a concise problem statement, impact, likely root cause, mitigation plan, and verification notes

Incorporate any additional rules from `linear.custom_input`.

Suggested Linear title format:

```text
Fix Sentry issue: <short problem summary>
```

Suggested Linear description format:

```markdown
## Sentry
- Issue: <sentry issue id>
- URL: <sentry url>

## Problem
<what is failing>

## Impact
<scope and severity>

## Likely Root Cause
<diagnosis>

## Proposed Fix
<implementation outline>

## Verification
- <test or reproduction step>
- <monitoring or Sentry validation step>
```

### Step 4 — Set status, cycle, project, type, and label

When creating the issue:

- team: from `linear.team_name`
- cycle: current cycle for that team
- project: from config

Status rules:

- if only creating a follow-up task, use the closest backlog or todo state
- if the user wants the fix started now, create in backlog/todo first, then use `start-task` to move to In Progress

Type and label rules:

- prefer the native Linear issue type if the available integration exposes a writable type field
- if native type is not writable, add a label that expresses the type instead
- default to bug-oriented classification for Sentry issues

Preferred classification order:

1. `Bug`
2. `Incident`
3. `Tech Debt`
4. `Task`

Use `Bug` by default.

### Step 5 — Ask for confirmation before implementation

Do not start editing code immediately after creating the issue.

Present:

- the Sentry diagnosis
- the mitigation plan
- the new ticket ID

Then ask the user to confirm the implementation approach before writing code.

### Step 6 — Hand off implementation

If the user confirms: invoke `start-task` with the ticket ID and Sentry-specific context.
If no code changes are needed, say so and skip.

### Step 7 — Hand off finalization

When wrapping up: invoke `finish-task` with the ticket ID and title.

### Step 8 — Close the loop in Sentry

After the fix is merged or the user explicitly asks, update the Sentry issue:

- `resolved` when the fix is complete
- `resolvedInNextRelease` when the fix is done but should close with the next release
- `ignored` only when the issue is confirmed to be noise

Do not change Sentry status unless the user asks or the workflow clearly requires it.

## Safety Rules

- Always require a Sentry URL before analysis
- Always create or update the PM issue before implementation work starts
- Always use `start-task` to begin implementation
- Always use `finish-task` to wrap up
- Never guess the team, cycle, project, or status if unclear
- Never make code changes before the user confirms the plan
- Never resolve or ignore a Sentry issue without confidence in the outcome

