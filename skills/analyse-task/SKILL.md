---
name: analyse-task
description: >
  Analyse a ticket from the configured PM tool, gather context from the
  codebase, produce a tech or non-tech plan, update the ticket, prepare
  questions for PM/client, send a Slack notification, and draft a client
  email. Use when the user says "analyse task", "analyze ticket",
  "plan task", "review ticket", "what does this ticket need", or provides
  a ticket URL/ID with analysis intent.
---

# Analyse Task

Gather all information needed to understand and plan a task, then produce artifacts that move it forward: an updated ticket with an implementation plan, questions for PM/client with recommendations, a Slack notification, and a client email draft.

This is an optional step before `start-task`. Devs can skip straight to `start-task` when the task is already well-understood.

This skill reads `pm_tool` from config. Currently supported: `linear`, `jira`.

## Config dependency

Read `<workspace>/.cursor/skills-config.yaml` before acting. If missing, tell the user to run `bootstrap-config` first.

Required config keys:

- `pm_tool` — which PM tool to use (`linear` or `jira`)
- `repos` — to detect current repo from CWD
- `testing.runner`, `testing.prefer_makefile` — for validation defaults
- `testing.custom_input` — per-repo test/lint/migration commands
- `slack.channels.analysis` — Slack channel for analysis notifications (falls back to `slack.channels.review` if missing)
- `release_email.greeting`, `release_email.sign_off` — for email draft formatting

Conditional config keys (based on `pm_tool`):

- If `linear`: `linear.team_name`, `linear.team_id`, `linear.custom_input`
- If `jira`: `jira.instance_url`, `jira.project_key`, `jira.custom_input`

## Guardrails

1. Always enter Plan mode before any analysis work.
2. Always ask the user to choose plan result type (tech vs non-tech) — never assume.
3. Never move the ticket to "In Progress" or any other status.
4. Never create a git branch or make code changes.
5. If the ticket URL/ID does not match the configured `pm_tool`, warn the user and ask how to proceed.

## Required Inputs

Collect from the user's prompt:

- **Task** — a ticket ID or URL. Accepted formats:

| PM tool | ID format | URL format |
|---------|-----------|------------|
| JIRA    | `DST-322` | `https://<site>.atlassian.net/browse/DST-322` |
| Linear  | `ENG-123` | `https://linear.app/<org>/issue/ENG-123/...` |

- **Plan result type** — must be explicitly chosen by the user:

| Type | When to use | Output focus |
|------|-------------|--------------|
| tech | Feature, bugfix, refactor | Implementation steps with specific files/functions, dependency map, migration notes, testing surface, risk assessment |
| non-tech | Business process, documentation, PM task | Same analysis reframed in business language — requirements breakdown, stakeholder impact, process flow, effort sizing, success criteria |

Both types include codebase exploration. The analysis depth is the same — the difference is in the output format and downstream artifacts.

- **Custom instructions** (optional) — additional context, constraints, or directions

If the user does not specify plan result type, ask before proceeding. Present both options with a one-line explanation and ask them to pick.

## Workflow

### Step 1 — Force Plan mode

Switch to **Plan mode** immediately. This skill is analysis-only — all outputs are plans, questions, and communications. No code changes or branch operations are permitted during this workflow.

### Step 2 — Collect plan result type

If the user has not specified "tech" or "non-tech", ask:

> What type of plan do you need?
> 1. **Tech** — implementation plan with specific files, functions, and architecture details
> 2. **Non-tech** — same analysis presented in business language for stakeholders

Do not proceed until the user explicitly chooses.

### Step 3 — Parse the task ID and detect PM tool

Extract the ticket identifier from the user's message:

1. If given a JIRA URL like `https://<site>.atlassian.net/browse/DST-322`, extract `DST-322` and infer `jira`.
2. If given a Linear URL like `https://linear.app/<org>/issue/ENG-123/...`, extract `ENG-123` and infer `linear`.
3. If given a raw ID like `DST-322` or `ENG-123`, use `pm_tool` from config to determine the tool.
4. If the inferred tool from the URL does not match `pm_tool` in config, warn the user:
   > "The URL points to [inferred tool] but your config sets pm_tool to [configured tool]. Which should I use?"
5. If no ticket ID can be found, ask the user to provide one.

Retain the resolved PM tool and ticket ID for all subsequent steps.

### Step 4 — Fetch full task details

#### If PM tool is `linear`:

Use `get_issue` with `includeRelations: true`.

Extract and retain: title, description (full markdown body), priority, labels, assignee, current status, parent issue, blocking/blocked-by relations, acceptance criteria (if present in description).

#### If PM tool is `jira`:

Use `getJiraIssue` with the ticket key as `issueIdOrKey`.

Extract and retain: summary (title), description, priority, labels, assignee, current status, issue type, parent/epic link, linked issues (blocks/is-blocked-by), acceptance criteria (from description or custom field).

If the Atlassian MCP requires a cloud ID, call `getAccessibleAtlassianResources` to resolve it, then retry.

---

If the fetch fails for either tool, stop and tell the user.

After fetching, also check for:

- **Related/linked tickets**: fetch their titles and statuses to avoid analysing in isolation.
- **Existing work in progress**: check if branches or PRs already exist for this ticket (`git branch -a | grep <ticket-id>`). If found, warn the user — they might be duplicating effort.
- **Prior analysis comments**: scan existing comments for a previous "Analysis" section. If found, warn the user and ask whether to add a new analysis or skip the ticket update.

Incorporate any additional rules from `linear.custom_input` or `jira.custom_input`.

### Step 5 — Analyse

Detect current repo from CWD by matching against `repos.<name>.path`.

Both tech and non-tech plans require codebase exploration. Perform a thorough analysis driven by the ticket requirements:

1. **Identify affected areas**: Based on the ticket description and acceptance criteria, identify which parts of the codebase are likely involved.
2. **Explore the codebase**: Read relevant files, trace code paths, understand data models, API endpoints, service boundaries, and component relationships.
3. **Map dependencies**: Identify upstream and downstream dependencies that the change will affect (database migrations, API contracts, shared utilities, external service calls).
4. **Assess testing surface**: Using `testing.custom_input` for the current repo, identify which test suites, fixtures, and validation commands are relevant.
5. **Identify risks**: Flag potential breaking changes, migration requirements, performance implications, and security considerations.
6. **Draft plan**: Produce the plan in the format matching the chosen plan result type.

#### Tech output format:

Numbered implementation steps with specific files, functions, and architectural decisions. Include:
- Files to create or modify (with paths)
- Database migrations needed
- API contract changes
- Infrastructure impact — new services, config changes, or other infra-level additions/modifications required by the task
- Code structure considerations — module boundaries, decoupling opportunities, or ongoing refactors that the change should align with
- Testing approach
- Estimated complexity per step

#### Non-tech output format:

Same analysis reframed in business language:
- Requirements breakdown with concrete deliverables
- Stakeholder impact and mapping
- Process flow (current vs target)
- External dependencies (client decisions, approvals)
- Effort sizing and timeline considerations
- Success criteria in measurable terms

**Scope-creep detection**: If the implementation plan has significantly more steps than the acceptance criteria suggest, flag this to the user and ask whether to proceed with the larger scope, reduce scope, or split into multiple tickets.

### Step 6 — Ask questions to the dev

Based on the analysis, compile a list of questions grouped by category:

- **Clarifications** — ambiguities in the ticket that affect the plan
- **Unknowns** — information not in the ticket or codebase that is needed
- **Edge cases** — scenarios not addressed by the acceptance criteria
- **Scope decisions** — choices that affect effort or approach

Present the questions and wait for the user to answer. The user may answer all at once, partially, or ask to proceed with assumptions. If proceeding with assumptions, document each assumption explicitly in the outputs.

### Step 7 — Update the ticket with analysis results

Add a structured comment to the ticket (do not edit the description).

#### If PM tool is `linear`:

Use `save_comment` with the issue ID.

#### If PM tool is `jira`:

Use `addCommentToJiraIssue`.

#### Comment content structure:

```markdown
## Analysis — [plan type] plan

### Implementation Plan
[numbered steps from Step 5]

### Open Questions
[questions that remain unanswered, grouped by category]

### Assumptions
[assumptions made during analysis — each with rationale]

### Risks
[identified risks with severity and mitigation suggestions]

### Validation Approach
[how to verify the implementation — tests, manual checks, acceptance criteria mapping]
```

Do NOT move the ticket to any new status. The ticket stays in its current state.

### Step 8 — Prepare questions for PM/Client

Structure the questions as a standalone document the dev can share with the PM or client. Each question includes a recommendation and any assumptions made:

```markdown
## Questions for [PM/Client] — [ticket-id]: [title]

### Question 1: [concise question]
**Context:** [why this matters for the implementation]
**Our recommendation:** [what we suggest and why]
**Assumption if no answer:** [what we will assume if this is not resolved]

### Question 2: [concise question]
...
```

Guidelines:
- Write questions in business language, not technical jargon.
- Each question should be self-contained — the reader should not need to read the full ticket to understand it.
- Recommendations should be actionable and opinionated — do not just ask without suggesting.
- Assumptions should be conservative (least-risk path).

### Step 9 — Send Slack notification

Post a concise message to `slack.channels.analysis` (fall back to `slack.channels.review` if not configured).

Before sending, present the message to the user for review. Use `slack_send_message_draft` if the user wants to review in Slack first, or `slack_send_message` if the user confirms immediate send.

Message format:

```text
*Task analysed:* [ticket-id] — [title]
Type: [tech | non-tech]

Key findings:
- [1-2 sentence summary of the plan]
- [open questions count] open question(s) for PM/client

Ticket: [ticket-url]
```

Keep the message under 10 lines. Do not include the full implementation plan — link to the ticket instead.

Read `slack.custom_input` for any overrides.

If Slack access is not available, skip and tell the user.

### Step 10 — Draft client email

Compose a professional email summarizing the analysis and outstanding questions.

Read `release_email.greeting` and `release_email.sign_off` from config for consistent tone. Read `release_email.custom_input` for recipient hints and subject patterns.

Email structure:

```text
Subject: Task Analysis — [ticket-id]: [title]

[greeting from config]

We've completed our initial analysis of [ticket title]. Here is a summary of our findings and a few questions that would help us move forward.

## Summary
[2-3 sentences describing what the task involves and the planned approach, in plain business language]

## Questions
[numbered list of questions, each with our recommendation — same content as Step 8 but formatted for email]

## Next Steps
[what happens after the questions are answered]

[sign_off from config]
```

Guidelines:
- Use plain, professional language — no technical jargon even for tech plans.
- Keep it concise — readable in under 2 minutes.
- Never include internal ticket URLs, code snippets, file paths, or architecture details.
- Never mention team members by name unless the user approves.
- If there are no open questions, replace the Questions section with a brief note that the task is well-defined and ready to proceed.

Present the full email text for the user to review and copy.

## Safety Rules

- Never move the ticket to a different status during this workflow.
- Never create a git branch or make code changes.
- Never send the Slack message without showing it to the user first.
- Never assume plan result type — always ask the user to choose.
- If the ticket URL points to a different PM tool than configured, resolve the mismatch before proceeding.
- If codebase analysis reveals that the scope is significantly larger than the ticket suggests, flag this to the user before producing outputs.
- Document all assumptions explicitly — never silently assume.
- Never include internal details (code paths, ticket URLs, architecture) in the client email.
- If the ticket already has a prior analysis comment, warn the user before adding another.

## Output format

When finished, report:

```markdown
Analysis complete:

- Ticket: [ticket-id] — [title]
- Plan type: [tech / non-tech]
- Ticket updated: [yes/no] ([link to comment if yes])
- Open questions: [count] for PM/client
- Slack notification: [sent to #channel / skipped]
- Email draft: [presented / skipped]
- Assumptions made: [count]

Hand-off: When ready to start implementation, use the `start-task` skill with [ticket-id].
```
