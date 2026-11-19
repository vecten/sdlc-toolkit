---
name: triage-security
description: >
  Triage security advisories (CVEs, breach notices, dependency vulnerabilities)
  against the workspace stack, draft a Slack response stating whether the
  project is affected, and hand off follow-up work to the create-ticket skill.
  Use when the user says "triage security", "security advisory", "security
  news", "check security brief", or provides a Slack permalink, CVE ID, or
  pasted advisory text.
---

# Triage Security

Use this workflow when a security advisory lands and the team needs to confirm whether the workspace is affected and respond on Slack.

This skill reads `pm_tool` from config for optional ticket hand-off. Currently supported: `linear`.

## Config dependency

Read `skills-config.yaml` before acting. Look in `.cursor/`, then `.claude/`, then the folder itself, starting from the current folder and moving up to the workspace root; use the first file found. If two copies differ, use the first and name both in one line. Every `custom_input` block applies and overrides this skill's defaults. If no file exists, tell the user to run `/sdlc-toolkit:bootstrap-config` first.

Required config keys:

- `slack.channels.security_news` — channel name where advisories are published
- `slack.channels.security_news_id` — cached channel ID (avoids a lookup per run)
- `slack.channels.security_draft` — channel where the draft response is posted. Defaults to `slack.channels.security_news` so replies thread on the original advisory; override only when drafts should go to a separate channel (e.g. a team-internal review channel)
- `security.draft_only` — when `true`, always use `slack_send_message_draft` instead of sending
- `security.custom_input` — free-form rules (escalation contacts, standard wording, vendors known not to be in use)
- `security.scanners.auto_scan` — when `true` (default), run the bundled scanner scripts before manual grepping. Scanners whose CLI is missing are skipped, and a run where none ran reports `INCONCLUSIVE`, so this is safe to leave on
- `security.scanners.enabled` — list selecting which scanners to run: `osv`, `trivy`, `npm-audit`, `pip-audit`, `snyk`, `installed-pip`, `installed-npm`. Defaults to `auto` (all installed scanners)
- `security.scanners.severity` — minimum severity threshold for noisy scanners: `low`, `medium`, `high` or `critical` (`high` by default; lower to `low` for breach/runtime advisories). Passed to the scripts in Step 3; trivy and snyk honour it, while osv-scanner, pip-audit and npm audit have no severity filter and always report every severity
- `repos` — every repo listed here is scanned; the stack is inferred from each repo's manifests and IaC, never from a hardcoded list

## Prerequisites

At least one scanner CLI must be installed. Run the bundled helper to see which scanners are missing:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/install-deps.sh"
```

The helper never installs anything: it only prints the install commands for the missing scanners. Show those commands to the user and let them decide what to run; do not run them yourself.

Individual tools and their install commands:

| Scanner | macOS | Linux / other |
|---------|-------|---------------|
| osv-scanner | `brew install osv-scanner` | `go install github.com/google/osv-scanner/v2/cmd/osv-scanner@latest` |
| trivy | `brew install aquasecurity/trivy/trivy` | [aquasecurity.github.io/trivy](https://aquasecurity.github.io/trivy/) |
| npm audit | `brew install node` | `sudo apt-get install nodejs npm` |
| pip-audit | `pipx install pip-audit` | `pipx install pip-audit` |
| snyk | `npm install -g snyk && snyk auth` | `npm install -g snyk && snyk auth` (free account required) |

Missing scanners are skipped gracefully — the scripts print a `SKIP:` line for each absent tool and continue with whatever is installed. When no scanner runs at all, `auto-scan.sh` prints an `INCONCLUSIVE:` line and exits with code 3, and Step 5 must treat that repo as **Uncertain**. Install at least `osv-scanner` or `trivy` for a useful scan.

## Required Input

One of:

- A Slack permalink to an advisory (e.g. `https://<workspace>.slack.com/archives/<CHANNEL_ID>/p<TS>`)
- A CVE ID or vendor name
- Pasted advisory text
- Nothing — default to reading the latest message from `slack.channels.security_news`

If the input is ambiguous (e.g. a CVE ID with no version info), ask one clarifying question before scanning.

## Workflow

### Step 1 — Resolve the advisory source

Parse the user input:

- **Slack permalink**: extract `channel_id` from the URL path and `message_ts` from the `p<digits>` segment (insert a `.` six digits from the end, e.g. `p1776747784617779` → `1776747784.617779`). Use `slack_read_thread` with those values.
- **Pasted text**: skip Slack entirely; treat the text as the advisory body.
- **CVE / vendor name only**: ask the user whether to search the security channel or pull from an external source.
- **No input**: use `slack_read_channel` on `slack.channels.security_news_id` with `limit: 1` to fetch the latest brief. If the ID is missing, fall back to `slack_search_channels` with `slack.channels.security_news`, then tell the user to run `/sdlc-toolkit:bootstrap-config` to cache the ID.

### Step 2 — Extract advisories

A single brief often contains multiple findings (breach notices + CVEs + version bumps). For each advisory, record:

- Short title
- Severity (CVSS score or vendor severity if stated)
- Affected technology / vendor
- Affected version range (if a CVE) or scope (if a breach)
- Action stated by the source (rotate, upgrade, mitigate)

Keep this list compact — one bullet per advisory. Do not paraphrase beyond what the source says.

### Step 3 — Run automated scanners (deterministic pass)

Before any manual grepping, run the bundled scanner scripts against every repo listed in `repos`. The scanners are the deterministic backbone of this skill: they hit real vulnerability databases (OSV, GitHub Advisory, vendor-specific) so verdicts do not rely on the LLM "knowing" a CVE.

The skill ships these scripts under `${CLAUDE_SKILL_DIR}/scripts/`:

| Script | Purpose |
|---|---|
| `auto-scan.sh <repo> [scanners] [severity]` | Orchestrator — runs every available scanner, emits one section per scanner and ends with a `scanners run:` line, or `INCONCLUSIVE:` when none ran |
| `scan-osv.sh <repo>` | OSV-Scanner (Google) — broad coverage, no auth, recommended default |
| `scan-trivy.sh <repo>` | Trivy filesystem scan — vulns, IaC misconfig, secrets |
| `scan-npm-audit.sh <repo>` | `npm audit` for every `package-lock.json` in the tree (declared deps) |
| `scan-pip-audit.sh <repo>` | `pip-audit` for `requirements*.txt` and `pyproject.toml` (declared deps) |
| `scan-installed-pip.sh <repo-or-venv>` | Audit actually-installed packages in any virtualenv found under the path; catches lockfile drift and ad-hoc `pip install` |
| `scan-installed-npm.sh <repo>` | `npm audit` against `node_modules` plus the installed tree from `npm ls --all`; catches drift between lockfile and what's on disk |
| `scan-snyk.sh <repo>` | Snyk — only runs when `SNYK_TOKEN` is set or `snyk auth` was done |
| `scan-docker-image.sh <image-ref> [severity]` | Trivy image scan; useful when the advisory targets runtime layers (CPython, libc, OpenSSL, Postgres) that source-tree scanners can't see |
| `check-cve.sh <CVE-ID> <repo> [scanners] [severity]` | Targeted check when the advisory names one specific CVE |

Manifests show what's *declared*; installed-package scanners show what's actually loadable at runtime. Run both — drift is the common reason a "Not affected" verdict turns out to be wrong.

For each repo:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/auto-scan.sh" <repo-path>
```

If `security.scanners.enabled` selects a subset, pass it comma-separated as the second argument. If `security.scanners.severity` is set, pass it as the third argument (use `auto` as the second when no subset is selected):

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/auto-scan.sh" <repo-path> osv,trivy
bash "${CLAUDE_SKILL_DIR}/scripts/auto-scan.sh" <repo-path> auto low
```

When the advisory targets a runtime layer (e.g. "CPython 3.11.x prior to 3.11.10", "OpenSSL", "Postgres 16.x"), also scan the relevant container image — `scan-docker-image.sh` is intentionally separate from `auto-scan.sh` because it takes an image reference, not a repo path. It takes the same optional severity:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/scan-docker-image.sh" postgres:16.13
```

Scanners whose CLI is missing are skipped — never abort the workflow because a tool isn't installed. Record which scanners ran from the final `scanners run:` line. `auto-scan.sh` exits 0 when at least one scanner ran, 2 when the repo path does not exist and 3 when no scanner ran; both 2 and 3 print an `INCONCLUSIVE:` line and mean that repo has no scanner evidence. `check-cve.sh` uses the same exit codes. A `SKIP:` from `scan-docker-image.sh` means the image was not scanned. If `security.scanners.auto_scan` is `false`, skip this step and rely on the manual evidence pass below.

Capture each scanner's output verbatim. When the advisory names a specific CVE, prefer `bash "${CLAUDE_SKILL_DIR}/scripts/check-cve.sh" <CVE-ID> <repo-path>` for a focused yes/no signal.

### Step 4 — Manual evidence pass (fill the gaps scanners miss)

Scanners cover dependency CVEs well but miss runtime versions, IaC, and vendor breaches. For every advisory, also pick the right place to look based on the technology named:

| Advisory target | Where to look |
|---|---|
| npm package (axios, react, etc.) | `package.json`, `package-lock.json`, `yarn.lock` |
| Python package | `pyproject.toml`, `requirements*.txt`, `poetry.lock`, `uv.lock` |
| Python runtime / CPython | `Dockerfile`, `pyproject.toml`, `.python-version` |
| Postgres / Snowflake / DB engine | `docker-compose*.yml`, terraform, helm values, `.env.example` |
| Vendor/platform (Vercel, Azure, AWS, n8n) | `*.yml` CI files, IaC, `README`, deployment docs |

Use `Grep` for package names and `Read` for version pins. Record: repo, file path, pinned version, whether it satisfies the advisory's "safe" range. If neither the scanner output nor the manifests reference the advisory's technology in any repo, mark **Not applicable** — but only after scanning each repo, not from a config shortcut.

If a repo path does not exist on disk (`auto-scan.sh` prints `INCONCLUSIVE:` and exits 2), note it but do not fail the run. Honour any exclusions stated in `security.custom_input` (e.g. "Vercel not in use") but still record the check in the draft so reviewers can see the diligence.

### Step 5 — Classify each advisory

For every advisory produce one verdict:

- **Not affected** — stack match but evidence shows we are on a safe version, or the vendor is explicitly excluded in `security.custom_input`.
- **Affected — action required** — evidence shows we use an affected version, or the advisory is a breach touching a vendor we rely on.
- **Affected — monitoring** — we use the tech but the advisory is low-severity / awaiting patch / mitigation already applied.
- **Uncertain** — scan was inconclusive. This includes every repo where `auto-scan.sh` or `check-cve.sh` printed `INCONCLUSIVE:` (no scanner ran, or the repo path is missing): with no scanner evidence the verdict is **Uncertain**, never **Not affected**. Do not guess; list the uncertainty in the draft.

When scanner output and manual evidence agree, state the verdict with high confidence. When they disagree (e.g. `npm audit` flags a dep but the lockfile shows a patched version), prefer the manifest evidence and note the disagreement in the user-only report.

### Step 6 — Create tickets for affected items first

Before drafting the Slack message, hand off every **Affected — action required** item to the `create-ticket` skill so the ticket URL can be embedded in the Slack draft.

- Title: `Security: <advisory short title>`
- Description: advisory link, affected repo + file evidence (path:line), proposed fix, notification/escalation policy from `security.custom_input`, verification checklist.
- Labels: `Hotfix` (plus any domain label such as `Infrastructure` when the evidence is scoped).
- Cycle: current cycle of the team.
- Priority: High (2) by default for confirmed affected items; adjust down only if the advisory itself calls it low-severity.
- State: `Todo`.

Confirm with the user once before creating (batch-confirm when multiple). Do not open tickets silently. Capture each ticket ID + URL for the Slack draft.

### Step 7 — Draft the Slack response (Affected-only)

Compose one short message. **Only include Affected items.** Uncertain and Not affected items stay in the end-of-run report to the user, never in Slack — the security channel only needs to see what we're acting on.

Use this exact template:

```text
:warning: *<Workspace> triage — action required*

:red_circle: *Affected* (<count>)
• *<advisory short title>* — <one-line current state + concrete action, e.g. "RDS on 16.8, upgrading to 16.13">. Ticket: <linear-url|PROJ-###>[ · cc <@SLACK_ID>]

:white_check_mark: _No other items applicable to our stack._

*Scanned repos:*
• <repo 1>
• <repo 2>
• <repo 3>
```

If there are zero Affected items, the message is even shorter — skip the `:red_circle:` block and use `:white_check_mark: *<Workspace> triage — no action required*` as the header.

Emoji budget (do not add more):

| Element | Emoji |
|---|---|
| Header when action required | `:warning:` |
| Header when nothing affected | `:white_check_mark:` |
| Affected section bullet | `:red_circle:` |
| "No other items applicable" line | `:white_check_mark:` |

Wording rules:

- Phrase every Affected line so the reader sees the team is handling it — present tense, concrete action (e.g. "upgrading to 16.13"), not "will investigate".
- Append `cc <@SLACK_ID>` inline only when `security.custom_input` names a notification target for that class of change (credential/DB rotations, infra upgrades).
- Use the Linear issue URL as a linked label `<url|PROJ-###>`; never paste bare URLs.

Follow any additional tone/wording rules from `security.custom_input`.

### Step 8 — Post or draft

Default to `slack_send_message_draft` addressed to `slack.channels.security_draft`. When that key is unset, fall back to `slack.channels.security_news` so the draft threads directly on the original advisory.

Only use `slack_send_message` directly if `security.draft_only` is `false` AND `security.custom_input` (or the user in-session) explicitly authorises direct send for this run.

When the source was a Slack message and the draft channel equals the source channel (the default), always thread the reply by passing `thread_ts` equal to the source message's `ts`.

### Step 9 — Report to the user (full picture)

Return a structured summary to the user that covers everything — including the Uncertain and Not-affected items that were deliberately omitted from Slack.

## Safety Rules

- Never claim "Not affected" for an advisory without scanning every repo in `repos`. A scan that printed `INCONCLUSIVE:` does not count as scanned. Uncertain scans go under **Uncertain**, not **Not affected**.
- Never put Uncertain or Not-affected items into the Slack draft. They belong only in the end-of-run user report.
- Never rotate credentials, edit lockfiles, or run package upgrades from this skill. Remediation happens via `create-ticket` → `start-task` → `finish-task`.
- Never post directly to Slack unless `security.draft_only` is `false` and an explicit per-run authorisation is given.
- Never invent CVE details — if the source text does not state a CVSS score or version range, say so.
- Never exceed the emoji budget defined in Step 7. Do not decorate repo names or add per-vendor emojis.
- Never trust scanner output blindly. A clean scan does not prove "Not affected" if the advisory targets a runtime version, a vendor breach, or IaC the scanner cannot see — confirm with the manual evidence pass.

## Output format

```markdown
Security triage — <date>

- Source: <permalink | channel | pasted>
- Advisories: <n>
  - Affected · action required: <n>
  - Affected · monitoring: <n>
  - Uncertain: <n>
  - Not affected: <n>
- Tickets created: <PROJ-###, PROJ-###>
- Slack: draft <id> in <#channel>[, threaded on <source ts>] | posted to <#channel>
- Scanned repos: <list>
- Scanners run: <e.g. osv, trivy, npm-audit | "none — INCONCLUSIVE" | "off — manual evidence only">
- Skipped repos: <list or "none">

### For you only (not in Slack)

**Uncertain (<n>)**
- <advisory> — <specific question blocking classification>

**Not affected (<n>)**
- <advisory> — <one-line reason with file evidence, e.g. "no `axios` in any package.json or lockfile", "dbt profiles.yml uses type: postgres, no Snowflake">
```

Always produce the "For you only" block even when empty (write "none") so the user sees the full picture and can sanity-check what was omitted from Slack.

If a step could not complete, say exactly which step stopped and why.
