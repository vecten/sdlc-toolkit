# SDLC Toolkit

End-to-end software development lifecycle skills for AI agents. Config-driven, team-agnostic, and composable.

Covers the full loop: pick up a ticket, plan, implement, verify, commit, push, PR, release, and notify — all powered by a single `skills-config.yaml` that adapts to any project.

## Installation

Install the full plugin:

```bash
npx --yes --package "github:vecten/agent-toolkit#main" vecten-toolkit install plugin sdlc-toolkit
```

Or install individual skills:

```bash
npx --yes --package "github:vecten/agent-toolkit#main" vecten-toolkit install skill bootstrap-config
npx --yes --package "github:vecten/agent-toolkit#main" vecten-toolkit install skill start-task
npx --yes --package "github:vecten/agent-toolkit#main" vecten-toolkit install skill finish-task
npx --yes --package "github:vecten/agent-toolkit#main" vecten-toolkit install skill create-ticket
npx --yes --package "github:vecten/agent-toolkit#main" vecten-toolkit install skill create-release
npx --yes --package "github:vecten/agent-toolkit#main" vecten-toolkit install skill finish-release
npx --yes --package "github:vecten/agent-toolkit#main" vecten-toolkit install skill debug-sentry
npx --yes --package "github:vecten/agent-toolkit#main" vecten-toolkit install skill manage-priorities
```

## Getting started

**First time?** Run the bootstrap skill to generate your project config:

```
> bootstrap config
```

This scans your workspace, discovers repos, resolves PM tool and Slack IDs, and writes `.cursor/skills-config.yaml` — the single config file all skills read from.

## What's included

| Skill | What it does |
|-------|-------------|
| `bootstrap-config` | Auto-generate or update `skills-config.yaml` by scanning repos, querying the configured PM tool and Slack, and asking structured questions for gaps. |
| `start-task` | Fetch a ticket's details, move it to In Progress, prepare the local repo on the correct dev branch, and enter Plan mode. |
| `finish-task` | Stage relevant changes, verify (Docker/host/CI), commit, push, create a PR, move the issue to review, and notify Slack. |
| `create-ticket` | Create a structured issue in the configured PM tool with config-driven defaults, cached IDs, and a standardized description template. |
| `create-release` | Cut a release branch from dev, enrich notes with ticket metadata, create a PR, and notify Slack. |
| `finish-release` | Move released tickets to Done and draft a client-facing release email. |
| `debug-sentry` | Investigate a Sentry issue, diagnose root cause, create a ticket, then hand off to `start-task` and `finish-task`. |
| `manage-priorities` | Manage a priorities tracker in the configured knowledge base with Table/Board views, status cards, and detail subpages. |
| `generate-skill` | Scaffold a new sdlc-toolkit skill with config awareness, proper structure, and consistency with existing skills. |

Also includes:

| Type | Name | What it does |
|------|------|-------------|
| Rule | `commit-message-task-id-prefix` | Require task ID prefix on every commit message. Template with `{{TICKET_PREFIX}}` filled by bootstrap. |

## Skill composability

Skills chain together for complex workflows:

```
debug-sentry  -->  start-task  -->  (implementation)  -->  finish-task
create-ticket -->  start-task  -->  (implementation)  -->  finish-task
                   create-release  -->  (deployment)  -->  finish-release
```

## MCP integrations

| MCP Server | Config key | Used by |
|------------|-----------|---------|
| Linear | `pm_tool: linear` | `create-ticket`, `start-task`, `finish-task`, `create-release`, `finish-release`, `debug-sentry` |
| Sentry | `error_tracking_tool: sentry` | `debug-sentry` |
| Slack | — | `finish-task`, `create-release`, `finish-release` |
| Notion | `knowledge_base_tool: notion` | `manage-priorities` |

## Configuration

All skills read from `<workspace>/.cursor/skills-config.yaml`. Run `bootstrap-config` to generate it. See `references/skills-config-example.yaml` for the full annotated schema.

Key sections:

- **pm_tool / knowledge_base_tool / error_tracking_tool** — which external tools the project uses (e.g., `linear`, `notion`, `sentry`). Skills read these to decide which MCP tools to call.
- **repos** — workspace repositories with paths and remotes
- **git** — per-repo branch names, prefixes, commit format
- **linear** — team, projects, labels, ticket prefix (used when `pm_tool: linear`)
- **slack** — channels, reviewers with Slack IDs, notification toggles
- **testing** — runner type (docker/host/ci-only), per-repo commands
- **notion** — priority statuses, cached database ID (used when `knowledge_base_tool: notion`)
- **release_email** — greeting, sign-off, and custom instructions

Each section includes a `custom_input` area for free-form, repo-specific instructions that skills incorporate as context.

## Trigger examples

| Skill | Example phrases |
|-------|----------------|
| `bootstrap-config` | `bootstrap config`, `setup skills config`, `initialize workspace` |
| `start-task` | `start task ENG-123`, `begin task ENG-456`, `pick up ticket ENG-789` |
| `finish-task` | `finish task ENG-123`, `wrap up ticket ENG-123`, `prepare branch and PR for ENG-123` |
| `create-ticket` | `create ticket`, `open ticket for this`, `log this request` |
| `create-release` | `create release`, `cut release`, `prepare release` |
| `finish-release` | `finish release`, `close release`, `release deployed` |
| `debug-sentry` | `debug sentry <url>`, `fix sentry issue <url>`, `investigate this Sentry issue` |
| `manage-priorities` | `manage top priorities`, `update priorities board`, `bootstrap priorities tracker` |
| `generate-skill` | `create a new skill`, `generate skill for this workflow`, `add a skill to sdlc-toolkit` |

## References

- `references/skills-config-example.yaml` — full annotated config example
