---
name: finish-release
description: >
  Wrap up a production release: show one table of the released tickets with
  deploy status, open items and a proposed status, update only the tickets the
  user confirms in the configured PM tool, and draft a client-facing release
  email. Use when the user says "finish release", "close release", "release
  done", "post-release", "release deployed", or asks to prepare a release
  email or mark released tickets as done.
---

# Finish Release

Post-deployment workflow that runs after a release PR has been merged to the release target. Three goals:

1. Show **one table** of the released tickets: deploy status, open items, and a proposed status.
2. Update the tickets the user **confirms** in the configured PM tool. Nothing changes before that.
3. Draft a **client-facing release email** (if enabled in config).

This skill reads `pm_tool` from config. Currently supported: `linear`.

## Config dependency

Read `<workspace>/.cursor/skills-config.yaml` before acting. If missing, tell the user to run `/sdlc-toolkit:bootstrap-config` first.

Required config keys:

- `repos` — to detect current repo from CWD, and `repos.<repo>.remote` for the GitHub `owner/name`
- `git.branches.<repo>.dev` and `git.branches.<repo>.release_target` — branches for this repo
- `linear.ticket_prefix` — for extracting ticket keys from commits
- `release_email.enabled` — whether to draft a release email
- `release_email.greeting`, `release_email.sign_off`
- `release_email.custom_input` — system names, subject pattern, recipients, tone

## Prerequisites

- Remote is `origin`.
- GitHub CLI (`gh`) is available.
- PM tool MCP is available for ticket lookup and status updates.
- The release PR has been merged to the target branch.

## Inputs

Collect release context using these sources (in priority order):

1. **Same-thread context** — if the `create-release` skill ran earlier in this conversation, reuse the release PR URLs, target branches, and ticket list.
2. **User-provided PR URLs or numbers** — one release PR per repo.
3. **User-provided release branch name** — find its PR with `gh pr list --repo <owner>/<name> --head <branch> --state all`.

If none of these are available, ask the user for the release PR URLs.

## Branch rules

Read from config:

- Detect current repo from CWD by matching against `repos.<name>.path`.
- Look up `git.branches.<repo>.release_target`.
- Auto-detect from repo context; ask only if ambiguous.

## Workflow

### 1) Collect the released commits and tickets

For each release PR:

```bash
gh pr view <PR_NUMBER> --repo <owner>/<name> --json number,title,body,state,mergedAt,baseRefName,commits,url
```

Take the commit list from this output. Do not use `git log <target>..HEAD`: after the merge it comes back empty.

If a PR is not merged yet, say so; its tickets get the deploy status "not merged".

Extract all ticket keys from the PR title, body and commit messages using `linear.ticket_prefix` (e.g., `<PREFIX>-\d+`).

### 2) Check deploy status

For each repo, look for a deploy after the merge: a workflow run on the target branch, or whatever the user already said ("deployed", "live").

```bash
gh run list --repo <owner>/<name> --branch <TARGET_BRANCH> --limit 5 --json name,status,conclusion,createdAt,url
```

Use one of: `deployed` (with the run URL or the user's word), `merged, deploy not confirmed`, `not merged`.

### 3) Fetch ticket details and open items

For each ticket key:

1. Call `get_issue` (Linear) or the equivalent PM tool API: title, description, status, priority, assignee, labels, URL.
2. Read its comments as well.
3. Note the **open items**: unchecked acceptance criteria, follow-ups the ticket or its comments say are still owed, and manual steps after deploy (migrations, config changes, checks someone must run).

Store this data for the table and for the email.

### 4) Show the table and wait

Present one table and change nothing yet:

| Ticket | Title | Repo / PR | Deploy status | Current status | Open items | Proposed status |
|---|---|---|---|---|---|---|

Proposed status:

- **Done**: deployed and no open items.
- **Keep open**: name what it waits on (a follow-up, a check after deploy, a client confirmation).
- **Reopen**: the merge automation already moved it to a completed status, but open items remain. Propose the status it should go back to.

Ask the user to confirm the table or change any row. Put the evidence (run URLs, open items) in the table and in the final report. Post it on tickets only when the user asks.

### 5) Apply the confirmed statuses

For each confirmed change:

1. Call `list_issue_statuses` for the ticket's team (cache per team — call once per unique team).
2. Find the target status by name (Done, or the one the user named). If no clear match exists, report the available statuses instead of guessing.
3. Call `save_issue` with `id` and `state`.
4. Track what changed and what was left as is.

### 6) Compose the release email (conditional)

Skip this step if `release_email.enabled` is `false`.

Build a release email focused on client-facing impact. Leave out tickets that were not deployed. Before writing, if any ticket's user impact is unclear from the ticket data alone, ask the user for clarification on those specific tickets.

Read `release_email.custom_input` for:
- System display names (e.g., which friendly name to use for this repo)
- Subject line pattern
- Recipients
- Tone preferences
- Whether to include internal changes

#### Email structure

```
Subject: <from custom_input subject_pattern, or "Release Update — <date>">

<release_email.greeting>

We've deployed the latest updates to <system name from custom_input>. Here's a summary of what's new:

## What's New

<For each change, write 1-2 sentences in plain, non-technical language
 describing the user-visible impact. Group related changes together.
 Focus on what the user can now do, what was fixed, or what improved.
 Avoid technical jargon, code references, or internal ticket IDs.>

<release_email.sign_off>
```

#### Composition guidelines

- Write from the user's perspective. Instead of "Fixed null constraint on practice settings model", write "Practice settings are now preserved correctly when data is updated from external systems."
- Group related changes under a single bullet when they address the same feature area.
- If a change is purely internal (infra, refactoring, CI) with no user-facing impact, omit it unless `custom_input` says to include internal changes.

### 7) Present the email to the user

Output the full email text for the user to review, copy, and send.

Ask if any adjustments are needed (tone, missing context, grouping).

## After the release: syncing dev with the target

A back-merge (target into dev) is needed only when the target holds changes dev lacks, for example a hotfix merged straight to the target. Check first:

```bash
git fetch origin && git diff --stat origin/<DEV_BRANCH> origin/<TARGET_BRANCH>
```

If one is needed, never open the back-merge PR with the target branch as head. When the repo deletes merged branches automatically, merging that PR deletes the target branch. Cut a temporary branch from the target (e.g. `backmerge/YYYY-MM-DD`) and open the PR from it into dev.

## Final output

When finished, report:

- The confirmed table
- Tickets whose status changed, and tickets left open (with what each waits on)
- Any ticket that could not be updated, and why
- The full email draft (if enabled)
- Any tickets where you lacked context and made assumptions
