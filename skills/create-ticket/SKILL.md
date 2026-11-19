---
name: create-ticket
description: >
  Create a structured issue in the configured PM tool with required metadata
  prompts, defaults from skills-config.yaml, and a short Context / Requested
  change / Acceptance criteria description. Use when user says "create
  ticket", "open ticket", "log request", or similar.
---

# Create Ticket

Use this workflow when the user asks to create a ticket (for example: "create ticket", "open ticket", "log request").

This skill reads `pm_tool` from config to determine which PM integration to use. Currently supported: `linear`. The instructions below use Linear-specific MCP tools; when support for other PM tools is added, the tool calls will change but the workflow structure remains the same.

## Config dependency

Read `skills-config.yaml` before acting. Look in `.cursor/`, then `.claude/`, then the folder itself, starting from the current folder and moving up to the workspace root; use the first file found. If two copies differ, use the first and name both in one line. Every `custom_input` block applies and overrides this skill's defaults. If no file exists, tell the user to run `/sdlc-toolkit:bootstrap-config` first.

Required config keys:

- `pm_tool` — which PM tool to use (default: `linear`)
- `linear.team_name`, `linear.team_id`
- `linear.default_project`, `linear.default_project_id`
- `linear.projects[]`
- `linear.labels[]`
- `linear.default_priority`
- `linear.default_assignee` — optional; when set, the assignee question is skipped
- `linear.custom_input`

## Guardrails

1. If any required data is unclear, ask the user before creating the issue.
2. Keep the final issue description structured for both humans and AI agents.

## Names, not cached IDs

Pass team, project and label **names** from the config; the Linear tools accept names and resolve them. The config lists are the preferred choices to offer, not a cache: projects get renamed and closed. Ignore any `*_id` values in the config.

If Linear rejects a name (not found), look the entity up live (`list_projects`, `list_issue_labels`, `list_teams`), offer the current matches, and tell the user which config entry is out of date.

## Required metadata policy

Team is always fixed to the value in config. If the user does not provide a field, ask whether to apply the default:

| Field    | Default                    | Prompt style              |
|----------|----------------------------|---------------------------|
| Project  | `linear.default_project`   | Choose from list          |
| Priority | `linear.default_priority`  | Apply default? Y/N        |
| Label    | —                          | Choose from list + None   |
| Assignee | `linear.default_assignee`  | me / Unassigned / Other   |
| Cycle    | —                          | Current / None            |

Incorporate any additional rules from `linear.custom_input`.

## Intake flow

1. Parse provided inputs from user message: title, optional body/context, optional metadata.
2. Ask for missing fields using structured multiple-choice questions.
3. For each missing field, ask "Apply default?" when a default exists.
4. For label, require one explicit choice from the config label list including `None`.
5. For assignee, use `linear.default_assignee` when it is set (report it under "Defaults used"); otherwise require one explicit choice: `me`, `Unassigned`, or `Other`.
6. For cycle, require explicit choice: `Current` or `None`.
7. Pass the chosen names to `save_issue`; see "Names, not cached IDs".

## Ticket content standard (human + AI)

When creating a ticket description, use this template unless `linear.custom_input` gives another:

```markdown
## Context
<background, the current gap, and why this is needed>

## Requested change
<what needs to be done>

## Acceptance criteria
- <criterion 1>
- <criterion 2>
```

Add a section only when the user's input calls for it (for example a known risk, or a check needed in production), and keep sentences short.

If user gives loose notes, normalize them into the template before creating the issue.

Never write `#<number>` in a ticket's title or description: Linear turns it into a link to an unrelated issue. Write `item 3` or `step 3` instead.

## Issue creation call

Use `save_issue` with:

- `team`: from `linear.team_name`
- `title`: concise, action-oriented
- `description`: the markdown template above
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

