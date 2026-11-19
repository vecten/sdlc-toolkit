---
name: generate-skill
description: >
  Scaffold a new skill for the sdlc-toolkit plugin with config awareness,
  proper structure, and consistency with existing skills. Use when the user
  says "create skill", "new skill", "generate skill", "add a skill to
  sdlc-toolkit", or wants to turn a workflow into a reusable skill.
disable-model-invocation: true
---

# Generate Skill

Scaffold a new skill that fits into the sdlc-toolkit plugin. The generated skill follows the same conventions as existing skills: config-driven, composable, and structured for both humans and AI agents.

## Guardrails

1. Always review existing sdlc-toolkit skills before generating to maintain consistency.
2. Always check `skills-config.yaml` to understand what config sections exist.
3. Keep SKILL.md under 500 lines. Use `references/` for detailed docs.
4. Never duplicate workflow steps that already exist in another skill — compose instead.
5. Ask the user before writing any files.

## Workflow

### Step 1 — Gather requirements

Collect from the user:

1. **Purpose**: What specific task or workflow should this skill automate?
2. **Trigger phrases**: When should the agent activate this skill? (e.g., "deploy staging", "review PR")
3. **MCP tools needed**: Which integrations? (Linear, Slack, Sentry, Notion, GitHub, or none)
4. **Config dependency**: Does this skill need to read from `skills-config.yaml`? Which sections?
5. **Composability**: Does it hand off to or receive from existing skills? (start-task, finish-task, etc.)
6. **Target location**: Plugin only (`agent-toolkit/plugins/sdlc-toolkit/skills/`) or also local workspace (`.cursor/skills/`)?

If the user provides a workflow description or conversation context, infer answers and confirm.

### Step 2 — Review existing skills for patterns

Before writing, read at least 2 existing sdlc-toolkit skills to match:

- Frontmatter format (`name`, `description` with trigger phrases)
- Config dependency section placement and wording
- Workflow step numbering and heading style
- Safety rules section structure
- Output format section

Existing skills to use as reference:

- `start-task` — good example of config-driven repo detection and PM tool integration
- `finish-task` — good example of multi-step workflow with conditional Slack notifications
- `create-ticket` — good example of config-driven defaults and structured output
- `bootstrap-config` — good example of auto-detection and user confirmation flow

### Step 3 — Review config schema

Read `skills-config.yaml` (or `references/skills-config-example.yaml` from this plugin) to understand:

- Available config sections: `repos`, `git`, `linear`, `slack`, `testing`, `notion`, `release_email`
- Each section's `custom_input` area for free-form instructions
- How skills reference config keys (e.g., `git.branches.<repo>.dev`)

Determine which config keys the new skill needs. If it needs a config section that doesn't exist yet, propose adding it to the schema and flag it for a `bootstrap-config` update.

### Step 4 — Draft the skill

Generate the SKILL.md following this template:

```markdown
---
name: <skill-name>
description: >
  <What it does, 1-2 sentences>. Use when the user says <trigger phrase 1>,
  <trigger phrase 2>, or <trigger phrase 3>.
---

# <Skill Title>

<1-2 sentence overview of what this skill does.>

## Config dependency

Read `<workspace>/.cursor/skills-config.yaml` before acting. If missing,
tell the user to run `/sdlc-toolkit:bootstrap-config` first.

Required config keys:

- `<section.key>` — <what it's used for>

[Only include this section if the skill reads from config.
If the skill works without config, say "This skill works without config
but benefits from it." and list optional keys.]

## Guardrails

1. <safety rule>
2. <safety rule>

## Required Inputs

<What the user must provide.>

## Workflow

### Step 1 — <action>

<instructions>

### Step 2 — <action>

<instructions>

[Continue as needed]

## Safety Rules

- <rule>
- <rule>

## Output format

<What the skill returns to the user when done.>
```

### Step 5 — Check composability

Before finalizing, verify:

- Does this skill duplicate steps from `start-task`, `finish-task`, `create-ticket`, or `create-release`?
  - If yes, remove the duplicated steps and add a hand-off: "use the `<skill>` skill for this step."
- Does this skill introduce new config keys?
  - If yes, document them and note that `bootstrap-config` and `references/skills-config-example.yaml` need updating.
- Could existing skills benefit from calling this new skill?
  - If yes, note which skills should add a hand-off reference.

### Step 6 — Present for review

Show the user:

1. The full SKILL.md content.
2. Where it will be written:
   - Plugin: `plugins/sdlc-toolkit/skills/<name>/SKILL.md`
   - Local (if requested): `.cursor/skills/<name>/SKILL.md`
3. Any config schema changes needed.
4. Any catalog.json / README updates needed.
5. Any existing skills that should be updated to reference this one.

Ask: "Does this look right? Any changes before I write it?"

### Step 7 — Write and register

After user confirms:

1. Write `SKILL.md` to the skill directory.
2. Write any `references/` files if needed.
3. If writing to the plugin repo, update:
   - `catalog.json` — add a new skill entry
   - `README.md` — add to the skills table
4. If writing to the local workspace, copy the file to `.cursor/skills/<name>/SKILL.md`.
5. If new config keys were introduced, update:
   - `references/skills-config-example.yaml`
   - `bootstrap-config/SKILL.md` (add detection/prompt for the new section)
   - The workspace `skills-config.yaml` (add the new section with defaults)

### Step 8 — Verify

After writing:

1. Confirm the SKILL.md is under 500 lines.
2. Confirm frontmatter `name` uses lowercase letters, numbers, and hyphens only (max 64 chars).
3. Confirm `description` includes trigger phrases (max 1024 chars).
4. If in the plugin repo, run `node bin/validate-catalog.js` to verify catalog integrity.
5. Report what was created and any follow-up actions needed.

## Conventions reference

- **Naming:** lowercase, hyphen-separated, 2-4 words, action-first `<verb>-<noun>`. No tool vendor names unless disambiguation is needed.
- **Size limit:** keep SKILL.md under 500 lines. Move detailed docs to `references/`.
- **No trigger examples section:** trigger phrases belong only in the frontmatter `description` field.
- **No duplicated instructions:** do not repeat in Safety Rules what is already stated in a Workflow Step. Each instruction should exist in exactly one place.
- **Conciseness:** prefer tables over verbose sub-bullet lists for structured options (e.g., metadata fields with defaults).
- **Deterministic logic to scripts/:** move deterministic shell sequences to `scripts/` instead of inlining multi-step bash in the skill. The skill should call the script and handle errors.
- **Concise hand-offs:** when composing with other skills, keep the hand-off brief (1-2 lines). The target skill handles its own logic.
- **No generic MCP hygiene per skill:** rules like "use X tool only", "read schema first", "don't hardcode IDs" should not repeat in every skill.
- **Tool parameterization:** reference `pm_tool` / `knowledge_base_tool` config keys. Use "the configured PM tool" in prose instead of hardcoding vendor names like "Linear" or "Notion".

All other structural patterns (step numbering, safety rules format, output format, config dependency placement) should be inferred from reading the 2+ sibling skills in Step 2.
