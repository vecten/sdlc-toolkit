---
name: manage-timeline
description: >
  Scan Linear projects, analyze issue progress, detect schedule slippage or
  early completion, and cascade date adjustments across a sequential or
  multi-developer timeline. Use when the user says "manage timeline",
  "update timeline", "refresh timeline", "check timeline", "timeline status",
  "are we on track", or "adjust project dates".
---

# Manage Timeline

Use this workflow to keep a project timeline in the configured PM tool accurate and current. The skill scans every active project, computes completion progress from issue statuses, detects slippage or early completion, and proposes cascading date adjustments that respect team capacity and execution order.

This skill reads `pm_tool` from config. Currently supported: `linear`.

## Config dependency

Read `<workspace>/.cursor/skills-config.yaml` before acting. If missing, tell the user to run `/sdlc-toolkit:bootstrap-config` first.

Required config keys:

- `pm_tool` — which PM tool to use (default: `linear`)
- `linear.team_id` — team scope for project queries
- `linear.projects[]` — cached project names and IDs

Optional config keys (from `timeline` section):

- `timeline.developers` — team capacity (default: `1`)
- `timeline.scheduling` — `sequential`, `parallel`, or `custom` (default: `sequential`)
- `timeline.ongoing_projects` — project names that never get auto-scheduled dates
- `timeline.execution_order` — ordered list of project names defining the work sequence
- `timeline.parallel_groups` — groups of projects that share a single lane and overlap
- `timeline.no_target_date` — project names to skip when auto-dating
- `timeline.custom_input` — free-form scheduling rules

If the `timeline` section is missing, offer to bootstrap it (see Step 1).

## Guardrails

1. Never auto-apply date changes — always present proposed changes and wait for user confirmation.
2. Never modify start/target dates for projects listed in `ongoing_projects`.
3. Never archive, delete, or rename projects or milestones.
4. If a project has no issues, warn and skip it rather than resetting its dates.
5. When `developers` changes, ask the user to confirm before re-laying out the entire schedule.

## Required Inputs

No mandatory user input is needed beyond the trigger phrase. The skill reads everything from config and the PM tool.

Optional user input:

- Specific project name(s) to focus on (default: all projects)
- Whether to post a status update to the PM tool after applying changes
- Override values for individual project dates

## Workflow

### Step 1 — Read config

Load `linear.projects[]` and `timeline.*` from `skills-config.yaml`.

If the `timeline` section is missing entirely, bootstrap it:

1. Ask the user for `developers` count (default: 1).
2. Ask which projects are ongoing (never auto-dated).
3. Ask for execution order (present the project list for reordering).
4. Ask which projects should have no target date.
5. Ask if any projects should run in parallel (parallel groups).
6. Write the `timeline` section to config and proceed.

### Step 2 — Fetch project state

For each project in `linear.projects[]`, call `list_projects` with the team filter and `includeArchived: false`. Collect current `startDate`, `targetDate`, and `state` for each.

Then call `list_milestones` for each project to capture existing milestone names, target dates, and descriptions.

### Step 3 — Fetch issue progress

For each project, call `list_issues` with the project filter. Group issues by status and compute:

| Metric | Formula |
|--------|---------|
| Total | all non-canceled issues |
| Done | issues in `Done` or `Canceled` status type |
| In Progress | issues in `started` status type |
| Blocked | issues with `Blocked` status |
| Remaining | total - done |
| Completion % | done / total |

### Step 4 — Detect schedule health

For each time-bounded project (not in `ongoing_projects` or `no_target_date`):

- **Ready to close**: completion >= 100% and project state is not `completed`
- **Overdue**: `targetDate` is in the past and completion < 100%
- **At risk**: linear interpolation from `startDate` to `targetDate` predicts the target will be missed at current burn rate
- **On track**: progress matches or exceeds the expected pace

Assign a health indicator: `onTrack`, `atRisk`, or `offTrack`.

### Step 5 — Propose date adjustments

Compute the schedule using `timeline.developers`, `execution_order`, and `parallel_groups`:

1. Calculate available lanes: `developers - len(ongoing_projects)`. If <= 0, warn and fall back to 1 lane.
2. Walk `execution_order` top to bottom, assigning projects to lanes. Projects in the same `parallel_groups` entry share one lane and overlap.
3. For each lane, chain projects sequentially: the next project starts the day after the previous one's `targetDate`.
4. Preserve each project's original duration (difference between `startDate` and `targetDate`) unless the user overrides.
5. If a project finished early (completion >= 100%), compress: start the next project from today (or the completion date if known).
6. If a project is overdue, extend: push its `targetDate` forward by a proportional estimate and cascade downstream.
7. Recalculate milestone dates proportionally within each project's adjusted window.
8. Skip `ongoing_projects` and `no_target_date` projects.
9. If `developers` count changed since the last run, re-layout the entire schedule from today forward.

### Step 6 — Present changes for review

Show the user a comparison table:

```
| Project                    | Current Start | Current Target | Proposed Start | Proposed Target | Health   |
|----------------------------|---------------|----------------|----------------|-----------------|----------|
| Example Project  | 2026-03-30    | 2026-04-16     | (unchanged)    | (unchanged)     | On Track |
| ...                        | ...           | ...            | ...            | ...             | ...      |
```

Below the table, list milestone changes if any.

Ask the user to confirm, adjust individual entries, or skip.

### Step 7 — Apply changes

After user confirms:

1. Call `save_project` for each project with changed `startDate` or `targetDate`.
2. Call `save_milestone` for each milestone with a changed `targetDate`.

Process updates in small batches (3-4 at a time) to avoid API rate limits.

### Step 8 — Optional status update

If the user requests it, create a project status update for each project via `save_status_update`:

- `health`: the computed indicator (`onTrack`, `atRisk`, `offTrack`)
- `body`: markdown summary with completion %, key flags, and next milestone

### Step 9 — Report

Output a summary:

```markdown
Timeline updated.

| Project | Start | Target | Completion | Health |
|---------|-------|--------|------------|--------|
| ...     | ...   | ...    | ...        | ...    |

Milestone changes:
- <project>: <milestone> target moved from <old> to <new>

Flags:
- <project>: <flag description>

Projected timeline end: <date> (with <N> developer(s))
```

## Safety Rules

- Never auto-apply date changes without user confirmation.
- Never modify `ongoing_projects` start/target dates.
- Never archive or delete projects or milestones.
- If a project has no issues, warn but skip — do not reset its dates.
- Process API updates in small batches to avoid rate limits.
- If the PM tool API rejects a cached ID, log a warning and skip that project rather than failing the entire run.
