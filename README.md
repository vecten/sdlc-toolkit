# SDLC Toolkit

End-to-end software development lifecycle skills for AI agents. Config-driven, team-agnostic, and composable.

Covers the full loop: pick up a ticket, plan, implement, verify, commit, push, PR, release, and notify — all powered by a single `skills-config.yaml` that adapts to any project.

## Installation

### Claude Code

```
/plugin marketplace add vecten/sdlc-toolkit
/plugin install sdlc-toolkit@vecten
```

### Cursor

Add this repository as a plugin source in Cursor's plugin settings, then install `sdlc-toolkit`.

## Getting started

**First time?** Run the bootstrap skill to generate your project config:

```
/sdlc-toolkit:bootstrap-config
```

The setup skills (`bootstrap-config`, `migrate-cursor`, `generate-skill`) run only when you type them; the agent does not pick them automatically. In Cursor, type `/bootstrap-config`, `/migrate-cursor` or `/generate-skill`.

This scans your workspace, discovers repos, resolves PM tool and Slack IDs, and writes `.cursor/skills-config.yaml` — the single config file all skills read from.

## What's included

| Skill | What it does |
|-------|-------------|
| `bootstrap-config` | Auto-generate or update `skills-config.yaml` by scanning repos, querying the configured PM tool and Slack, and asking structured questions for gaps. |
| `analyse-task` | Analyse a ticket (Linear or JIRA), explore the codebase, produce a tech or non-tech plan, update the ticket, prepare PM/client questions, notify Slack, and draft a client email. Optional step before `start-task`. |
| `start-task` | Fetch a ticket's details, move it to In Progress, prepare the local repo on the correct dev branch, and enter Plan mode. |
| `finish-task` | Stage relevant changes, verify (Docker/host/CI), commit, push, create a PR, move the issue to review, and notify Slack. |
| `create-ticket` | Create a structured issue in the configured PM tool with config-driven defaults, cached IDs, and a standardized description template. |
| `create-release` | Cut a release branch from dev, enrich notes with ticket metadata, create a PR, and notify Slack. |
| `finish-release` | Move released tickets to Done and draft a client-facing release email. |
| `debug-sentry` | Investigate a Sentry issue, diagnose root cause, create a ticket, then hand off to `start-task` and `finish-task`. |
| `triage-security` | Triage a security advisory (Slack brief, CVE, or pasted text) against the workspace stack, run bundled deterministic scanners (osv-scanner, trivy, npm audit, pip-audit, snyk, installed-pip/npm for runtime drift, and Docker image scans), draft a Slack response with affected/not-affected verdicts, and hand off remediations to `create-ticket`. |
| `manage-priorities` | Manage a priorities tracker in the configured knowledge base with Table/Board views, status cards, and detail subpages. |
| `manage-timeline` | Scan PM tool projects, detect schedule slippage, and cascade date adjustments across a sequential or multi-developer timeline. |
| `migrate-cursor` | Migrate workspace configuration, local skills, and rules from Cursor to Claude Code. Two-phase: export in Cursor, import in Claude Code. |
| `generate-skill` | Scaffold a new sdlc-toolkit skill with config awareness, proper structure, and consistency with existing skills. |

Also includes:

| Type | Name | What it does |
|------|------|-------------|
| Rule | `commit-message-task-id-prefix` | Require task ID prefix on every commit message. Template with `{{TICKET_PREFIX}}` filled by bootstrap. |

## Skill composability

Skills chain together for complex workflows:

```
debug-sentry     --> [analyse-task] -->  start-task  -->  (implementation)  -->  finish-task
triage-security  -->  create-ticket  -->  start-task  -->  (implementation)  -->  finish-task
create-ticket    --> [analyse-task] -->  start-task  -->  (implementation)  -->  finish-task
                                        create-release  -->  (deployment)  -->  finish-release
migrate-cursor   -->  bootstrap-config  (verify/update migrated config)
```

`[analyse-task]` is optional — devs can skip straight to `start-task` when the task is already well-understood.

## MCP integrations

| MCP Server | Config key | Used by |
|------------|-----------|---------|
| Linear | `pm_tool: linear` | `analyse-task`, `create-ticket`, `start-task`, `finish-task`, `create-release`, `finish-release`, `debug-sentry`, `manage-timeline` |
| Jira (Atlassian) | `pm_tool: jira` | `analyse-task` |
| Sentry | `error_tracking_tool: sentry` | `debug-sentry` |
| Slack | — | `analyse-task`, `finish-task`, `create-release`, `finish-release`, `triage-security` |
| Notion | `knowledge_base_tool: notion` | `manage-priorities` |

## Configuration

All skills read from `<workspace>/.cursor/skills-config.yaml`. Run `/sdlc-toolkit:bootstrap-config` (in Cursor: `/bootstrap-config`) to generate it. See `references/skills-config-example.yaml` for the full annotated schema.

Key sections:

- **pm_tool / knowledge_base_tool / error_tracking_tool** — which external tools the project uses (e.g., `linear`, `notion`, `sentry`). Skills read these to decide which MCP tools to call.
- **repos** — workspace repositories with paths and remotes
- **git** — per-repo branch names, prefixes, commit format
- **linear** — team, projects, labels, ticket prefix (used when `pm_tool: linear`)
- **jira** — instance URL, project key, default priority (used when `pm_tool: jira`)
- **slack** — channels (review, release, analysis, security_news, security_draft), reviewers with Slack IDs, notification toggles
- **security** — `draft_only`, `scanners` (toggle automated scans, pick which scanners to run, set severity threshold), and `custom_input` for `triage-security`. The skill always scans every repo in `repos` and detects the stack from manifests — no hardcoded stack list.
- **testing** — runner type (docker/host/ci-only), per-repo commands
- **notion** — priority statuses, cached database ID (used when `knowledge_base_tool: notion`)
- **timeline** — developer capacity, execution order, parallel groups, ongoing projects (used by `manage-timeline`)
- **release_email** — greeting, sign-off, and custom instructions

Each section includes a `custom_input` area for free-form, repo-specific instructions that skills incorporate as context.

## Trigger examples

| Skill | Example phrases |
|-------|----------------|
| `bootstrap-config` | typed only: `/sdlc-toolkit:bootstrap-config` (Cursor: `/bootstrap-config`) |
| `analyse-task` | `analyse task DST-322`, `analyze ticket ENG-123`, `plan task`, `review ticket`, `what does this ticket need` |
| `start-task` | `start task ENG-123`, `begin task ENG-456`, `pick up ticket ENG-789` |
| `finish-task` | `finish task ENG-123`, `wrap up ticket ENG-123`, `prepare branch and PR for ENG-123` |
| `create-ticket` | `create ticket`, `open ticket for this`, `log this request` |
| `create-release` | `create release`, `cut release`, `prepare release` |
| `finish-release` | `finish release`, `close release`, `release deployed` |
| `debug-sentry` | `debug sentry <url>`, `fix sentry issue <url>`, `investigate this Sentry issue` |
| `triage-security` | `triage security`, `security advisory`, `security news`, `check security brief`, `any security issues today` |
| `manage-priorities` | `manage top priorities`, `update priorities board`, `bootstrap priorities tracker` |
| `manage-timeline` | `manage timeline`, `update timeline`, `check timeline`, `are we on track` |
| `migrate-cursor` | typed only: `/sdlc-toolkit:migrate-cursor` (Cursor: `/migrate-cursor`) |
| `generate-skill` | typed only: `/sdlc-toolkit:generate-skill` (Cursor: `/generate-skill`) |

## References

- `references/skills-config-example.yaml` — full annotated config example

## License

MIT — see [LICENSE](LICENSE).
