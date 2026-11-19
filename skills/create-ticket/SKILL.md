---
name: create-ticket
description: >
  Create a structured issue in the configured PM tool with required metadata
  prompts, defaults, cached IDs from skills-config.yaml, and fallback ID
  refresh. Use when user says "create ticket", "open ticket", "log request",
  or similar.
---

# Create Ticket

Use this workflow when the user asks to create a ticket (for example: "create ticket", "open ticket", "log request").

This skill reads `pm_tool` from config to determine which PM integration to use. Currently supported: `linear`. The instructions below use Linear-specific MCP tools; when support for other PM tools is added, the tool calls will change but the workflow structure remains the same.

## Config dependency

Read `<workspace>/.cursor/skills-config.yaml` before acting. If the file is missing, tell the user to run `/sdlc-toolkit:bootstrap-config` (in Cursor: `/bootstrap-config`) first.

Required config keys:

- `pm_tool` — which PM tool to use (default: `linear`)
- `linear.team_name`, `linear.team_id`
- `linear.default_project`, `linear.default_project_id`
- `linear.projects[]`
- `linear.labels[]`
- `linear.default_priority`
- `linear.custom_input`

## Guardrails

1. If any required data is unclear, ask the user before creating the issue.
2. Keep the final issue description structured for both humans and AI agents.

## Cached identifiers

Use IDs from `skills-config.yaml` first to avoid repeated lookups. The config contains team ID, project IDs, and label IDs pre-resolved by `bootstrap-config`.

## Fallback cache refresh

If Linear rejects a cached ID (not found/invalid):

1. Refresh only that entity:
   - team -> `list_teams`
   - project -> `list_projects`
   - label -> `list_issue_labels`
2. Update in-memory mapping for this run.
3. Continue without re-fetching unrelated IDs.

## Required metadata policy

Team is always fixed to the value in config. If the user does not provide a field, ask whether to apply the default:

| Field    | Default                    | Prompt style              |
|----------|----------------------------|---------------------------|
| Project  | `linear.default_project`   | Choose from list          |
| Priority | `linear.default_priority`  | Apply default? Y/N        |
| Label    | —                          | Choose from list + None   |
| Assignee | —                          | me / Unassigned / Other   |
| Cycle    | —                          | Current / None            |

Incorporate any additional rules from `linear.custom_input`.

## Intake flow

1. Parse provided inputs from user message: title, optional body/context, optional metadata.
2. Ask for missing fields using structured multiple-choice questions.
3. For each missing field, ask "Apply default?" when a default exists.
4. For label, require one explicit choice from the config label list including `None`.
5. For assignee, require one explicit choice: `me`, `Unassigned`, or `Other`.
6. For cycle, require explicit choice: `Current` or `None`.
7. Resolve names to IDs using config cached mappings.

## Ticket content standard (human + AI)

When creating a ticket description, use this template:

```markdown
## Context
<background and why this is needed>

## Problem statement
<current issue/gap>

## Requested change
<what needs to be implemented>

## Acceptance criteria
- <criterion 1>
- <criterion 2>

## Validation / test plan
- <how to verify behavior>

## Risks / scope guardrails
- <known risk or constraint>

## Production verification notes
<prod checks required later, or "Not required">
```

If user gives loose notes, normalize them into the template before creating the issue.

## Issue creation call

Use `save_issue` with:

- `team`: from `linear.team_name`
- `title`: concise, action-oriented
- `description`: structured markdown template above
- optional metadata from intake:
  - `project`
  - `priority`
  - `labels` (single-item array when label is selected; omit when `None`)
  - `assignee`
  - `cycle` (set current cycle only when user selects `Current`; omit when `None`)

## Completion output format

After creating the issue, return:

1. Issue ID and title
2. URL
3. Applied metadata: team, project, priority, label, assignee, cycle
4. Defaults audit: fields defaulted vs. user-provided

Use this response shape:

```markdown
Created:

- Issue: <ID> — <Title>
- URL: <url>

Applied metadata:
- Team: <value>
- Project: <value>
- Priority: <value>
- Label: <value>
- Assignee: <value>
- Cycle: <value or None>

Defaults used:
- <field>: <default used>

Provided by user:
- <field>: <value>
```

