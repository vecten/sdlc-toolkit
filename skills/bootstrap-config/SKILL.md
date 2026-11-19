---
name: bootstrap-config
description: >
  Auto-generate or update the skills-config.yaml file for the current workspace.
  Scans repos, resolves PM tool and Slack IDs, asks structured questions for gaps.
  Run it by typing /sdlc-toolkit:bootstrap-config (in Cursor: /bootstrap-config); other skills point here
  when skills-config.yaml is missing.
disable-model-invocation: true
---

# Bootstrap Config

Generate or update the `skills-config.yaml` that all sdlc-toolkit skills depend on. The config lives at `<workspace>/.cursor/skills-config.yaml`.

## Guardrails

1. Never overwrite user-edited values without explicit confirmation.
2. When updating an existing config, only fill `null` or missing fields.
3. Always validate repo paths exist on disk before writing them.
4. Always confirm the final config with the user before writing.

## Workflow

### Step 1 — Check for existing config

Look for `skills-config.yaml` in the workspace `.cursor/` directory.

- If found, read it and enter **update mode** (Step 6).
- If not found, enter **create mode** (Step 2).

Also read the example config from `references/skills-config-example.yaml` in this plugin to understand the full schema.

### Step 2 — Ask about tool integrations

Ask the user which external tools the project uses:

1. **PM tool**: Linear (default), Jira, or Shortcut?
2. **Knowledge base**: Notion (default) or Confluence?
3. **Error tracking**: Sentry (default)?

Write the answers to the top-level `pm_tool`, `knowledge_base_tool`, and `error_tracking_tool` keys. These keys tell skills which MCP tools to call and how to phrase instructions. Currently only Linear, Notion, and Sentry have full skill support — if the user picks an unsupported tool, note that the skill behavior may be limited.

### Step 3 — Scan for repositories

Scan the workspace root for directories containing `.git/`:

```bash
for d in */; do [ -d "$d/.git" ] && echo "$d"; done
```

For each git directory:

1. Resolve remote URL: `git -C "$d" remote get-url origin`
2. Extract GitHub org from the remote URL.
3. Detect the current branch as a candidate dev branch.
4. Look for common release target branches: `production`, `prod`, `main`, `master`.

Build the `repos` and `git.branches` sections from this data.

### Step 4 — Query the PM tool

If `pm_tool` is `linear`, use Linear MCP tools to populate the `linear` section:

1. `list_teams` — present teams and ask user to pick the default.
2. `list_projects` — for the selected team, present projects and ask user to pick defaults.
3. `list_issue_labels` — for the selected team, present labels and ask user to select which should be available for ticket creation.
4. Ask for the ticket prefix (e.g., `EXC`, `PROJ`) — this is used in commit messages and ticket extraction regex.
5. Ask for default priority (1=Urgent, 2=High, 3=Medium, 4=Low).

Cache all resolved IDs.

If `pm_tool` is `jira`, use Atlassian MCP tools to populate the `jira` section:

1. `getAccessibleAtlassianResources` — present available Atlassian sites and ask user to confirm the instance URL.
2. `getVisibleJiraProjects` — for the selected site, present projects and ask user to pick the default project key.
3. Ask for default priority (e.g., "Medium", "High").
4. Ask for any custom input (board URL, workflow-specific statuses, custom fields).

### Step 5 — Query Slack

Use Slack MCP tools to populate the `slack` section:

1. Ask user for the PR review channel name.
2. Ask user for the release notification channel name (can be the same).
3. Ask user for reviewer names (comma-separated list).
4. For each reviewer name, call `slack_search_users` and cache the Slack user ID.
5. Ask whether to enable `notify_on_pr` and `notify_on_release` (default: both true).
6. Ask user for the analysis notification channel name (can be the same as review/release). This is used by `analyse-task` for posting analysis summaries.
7. Ask user for the security news channel name (e.g. `#security-news`). Resolve its ID with `slack_search_channels` and cache as `slack.channels.security_news_id`. This is the source channel for `triage-security`.
8. Ask user for the security draft channel (where `triage-security` posts its response draft). Default to the same channel as `security_news` so replies thread on the original advisory; the user can override if drafts should land in a separate channel.

### Step 6 — Collect remaining sections

Ask structured questions for:

**Testing:**
- Runner preference: Docker, host, or CI-only?
- Prefer Makefile targets? (yes/no)
- Any per-repo custom test/lint/migration commands? (free text -> `custom_input`)

**Notion:**
- Priority board status options (default: On Track, Planned, At Risk, Blocked, Done)
- Any custom input?

**Release email:**
- Enabled? (yes/no)
- Greeting text (default: "Hi,")
- Sign-off text (default: "Best regards")
- Any custom input? (system names, recipients, subject pattern -> `custom_input`)

**Git:**
- Confirm branch prefixes (default: feature/, bugfix/, hotfix/)
- Commit prefix pattern (default: `<TICKET_ID>: <message>`)
- Any custom git conventions? (free text -> `custom_input`)

**Security** (used by `triage-security`):
- `draft_only`: always draft the Slack response instead of sending (default: `true`).
- `scanners.auto_scan`: run the bundled scanner scripts (osv-scanner, trivy, npm audit, pip-audit, snyk) before manual grep (default: `true` — scripts skip silently when CLIs are missing, so this is safe to leave on).
- `scanners.enabled`: keep `"auto"` (run every installed scanner) or pick a subset like `["osv", "trivy", "installed-pip"]`. The `installed-*` entries audit actual venv/node_modules contents to catch lockfile drift.
- `scanners.severity`: minimum severity threshold for noisy scanners (default: `"high"`).
- Any custom input? (vendors explicitly not in use, escalation contacts, standard wording.)

Do not ask for a stack list or a `repos_to_scan` subset — the skill always scans every repo in `repos` and detects the stack from manifests at runtime.

**Timeline** (optional — skip if the user does not use `manage-timeline`):
- Developer count (default: 1)
- Scheduling mode: sequential, parallel, or custom? (default: sequential)
- Which projects are ongoing and should never be auto-dated?
- Execution order of remaining projects
- Any parallel groups?
- Any projects that should have no target date?

For each section, present sensible defaults and ask for confirmation.

### Step 7 — Update mode (existing config)

When a config already exists:

1. Read the current config.
2. Re-scan repos: detect any new git directories not in config, flag removed ones.
3. For any field that is `null`, attempt to resolve it:
   - `linear.team_id`, `linear.default_project_id`, label IDs -> query Linear.
   - `slack.reviewers[].slack_id` -> query Slack.
   - `notion.priorities_database_id` -> skip (resolved by manage-priorities at runtime).
4. Present a diff of proposed changes to the user.
5. Write only after user confirms.

Never change fields that already have non-null values unless the user explicitly asks.

### Step 8 — Write the config

Write the final YAML to `<workspace>/.cursor/skills-config.yaml`.

After writing, also update the commit-message rule if a rule template exists:
- Look for `.cursor/rules/commit-message-task-id-prefix.mdc`.
- Replace `{{TICKET_PREFIX}}` with the configured `linear.ticket_prefix`.
- If the rule file doesn't exist, skip this step.

### Step 9 — Validate

After writing:

1. Re-read the file and confirm it parses correctly.
2. Validate all repo paths exist.
3. Report summary: what was created/updated, any unresolved fields.

## Output format

```markdown
Config written to `.cursor/skills-config.yaml`.

- Tools: pm=<pm_tool>, kb=<knowledge_base_tool>, errors=<error_tracking_tool>
- Repos: <count> configured (<list>)
- PM: team=<name>, project=<name>, <count> labels, prefix=<prefix>
- Slack: channel=<channel>, <count> reviewers with IDs resolved
- Testing: runner=<runner>, makefile=<yes/no>
- Knowledge base: <count> statuses configured
- Release email: <enabled/disabled>
- Unresolved: <list of null fields, if any>
```

