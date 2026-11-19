---
name: manage-priorities
description: >
  Manage a priorities tracker in the configured knowledge base tool with
  canonical Table/Board views, status-based cards, and per-priority detail
  subpages linked from a Link property. Use when the user asks to manage
  priorities, update top priorities, add priority cards, create priority
  detail subpages, or bootstrap the tracker.
---

# Manage Priorities

Use this workflow to manage a priorities board in the configured knowledge base tool.

This skill reads `knowledge_base_tool` from config. Currently supported: `notion`.

Primary outcomes:

- keep a clean priorities database with `Status` and `Link`
- keep two canonical views: `Table` and `Board`
- add and update priorities quickly
- create a detail subpage per priority and store its URL in `Link`

## Config dependency

Read `skills-config.yaml` if available (look in `.cursor/`, then `.claude/`, then the folder itself, from the current folder up to the workspace root). This skill works without config but benefits from it.

Optional config keys:

- `notion.priorities_statuses` — custom status options
- `notion.priorities_database_id` — cached database ID to skip discovery
- `notion.custom_input` — additional properties, custom view names

## Guardrails

1. Ask for clarification when target page/database is ambiguous.
2. Do not perform destructive schema/view cleanup unless the user explicitly asks.
3. Keep responses concise and include resulting URLs.

## Required Inputs

Collect from the user prompt:

- target scope (teamspace/page/database), if provided
- requested operation:
  - maintain existing tracker
  - add/update priorities
  - create subpages and link them
  - bootstrap tracker (only when explicitly requested)
- priority text and desired status when adding/updating items

If critical inputs are missing, ask using structured choices when possible.

## Canonical Tracker Definition

### Data source properties

Use these canonical properties:

- `Priority` (title property)
- `Status` (select): read options from `notion.priorities_statuses` in config, or default to `On Track`, `Planned`, `At Risk`, `Blocked`, `Done`
- `Link` (URL): detail subpage URL for the priority

If equivalent properties exist with different names, prefer renaming to canonical names after confirmation.

### Canonical views

- `Table`
  - visible properties: `Priority`, `Status`, `Link`
  - default sort: `Status` ascending
- `Board`
  - grouped by: `Status`
  - card properties: `Priority` (and optional `Link`)

If one or both are missing, create them. If they exist, update them.

Read `notion.custom_input` for any custom view names or additional properties.

## Runtime Discovery Flow

### Step 1 — Locate target workspace context

1. If `notion.priorities_database_id` is set in config, fetch that database directly.
2. If the user provided a page/database URL or ID, fetch it directly.
3. If not, search for likely pages (for example: "Top Priorities", "Current Priorities").
4. If multiple plausible targets are found, ask the user to pick one.

### Step 2 — Resolve database/data source

1. Fetch the selected page or database.
2. If the page contains more than one priorities-like database, ask the user which one to use.
3. Capture: page ID (parent), database ID, data source ID, existing views and schema.
4. If `notion.priorities_database_id` is null in config and config exists, cache the discovered ID back into config.

### Step 3 — Normalize schema and views

Apply canonical schema and views carefully:

- add missing properties (`Status`, `Link`) without deleting unknown columns
- enforce `Status` options from config or defaults
- create/update `Table` and `Board`

Only remove extra properties/views when the user asks for cleanup.

## Operation: Maintain Existing Tracker (Default)

When the user asks to "manage priorities" without bootstrap intent:

1. Run runtime discovery.
2. Ensure canonical schema.
3. Ensure `Table` and `Board` views.
4. Report concise summary.

## Operation: Bootstrap Tracker (Explicit Opt-In)

Run only when user explicitly asks to create/setup/bootstrap a tracker.

1. Pick target parent page/teamspace (ask if unclear).
2. Create page (for example, `Current Priorities`) if missing.
3. Create database under that page with canonical properties.
4. Create/update canonical views.
5. Return page URL, database URL, and data source ID.

## Operation: Add Priority

When user provides new priorities:

1. Ensure tracker is normalized (schema/views).
2. Create one database row per priority with:
   - `Priority`: provided text
   - `Status`: provided value (default to `Planned` if unspecified)
   - optional icon if provided
3. For each new row, create a detail subpage and write its URL to `Link`.
4. Return created items with their row URLs and detail page URLs.

## Operation: Update Priority

When user asks to update existing priorities:

1. Locate target item(s) by exact title first.
2. If multiple items match, ask user to disambiguate.
3. Update requested fields.
4. If `Link` is empty and user wants detail pages, create subpage and store URL.
5. Return list of updated items with final status and links.

## Subpage + Link Workflow

Use this flow whenever the request includes "details", "subpage", or "link property".

1. For each priority row, create a page under the row page (preferred) or parent tracker page (fallback).
2. Use title pattern: `<Priority> - Details`
3. Add minimal content scaffold:

```markdown
## Context

## Notes

## Related Links
```

4. Save the subpage URL into the row's `Link` property.
5. If an existing `Link` is stale or blank, replace it after confirming intent.

## Output Format

```markdown
Updated priorities tracker.

- Page: <title> (<url>)
- Database: <title> (<url>)
- Views: Table, Board
- Changes:
  - <change 1>
  - <change 2>

Priority items:
- <priority title> — Status: <status> — Link: <url or None>
```

