---
name: gf-roadmap
description: Manage the GrooveForge development roadmap — list tasks, add items, reprioritize, mark complete, clean up shipped milestones, and sync bidirectionally with Linear using the API.
argument-hint: "[next|list|add|sync|cleanup|linear-pull|linear-push] [args]"
allowed-tools: Read, Edit, Grep, Bash(curl *), Bash(bash *), Bash(grep *), Bash(awk *), Bash(cat *), Bash(head *), Bash(wc *)
---

## Source of truth

**`docs/dev/ROADMAP.md`** — single Markdown file, all pending work.
- Pending: `- [ ]` / Done: `- [x]`
- Milestones: `## vX.Y.Z` headings
- Unscheduled work: `## Backlog — Unscheduled`

Always re-read the file before editing. Never work from memory.

---

## Roadmap quality standard

`docs/dev/ROADMAP.md` is a **didactic, living design document** — not a flat task list. Every section and every task entry must meet this bar:

### Content requirements

- **Why, not just what**: each milestone section must open with a short paragraph explaining the motivation (user need, technical constraint, dependency on prior work). A reader who has never touched the codebase should understand why this work exists.
- **Task descriptions are self-contained**: task bullets must name the specific class, file, or concept they touch, e.g. `- [ ] Remove \`chordsPerBar\` from \`LoopTrack.toJson\`/\`fromJson\`` — never `- [ ] Fix the looper`.
- **Design notes for non-obvious choices**: when a task involves a deliberate design decision (algorithm, data model, API shape), add a sub-bullet or blockquote explaining the rationale.

### Formatting requirements

- **Emojis on section headings** for visual scanning: ✅ complete, 🔜 next/upcoming, ⏸ deferred/blocked, 🧪 testing phase, 🏗️ architecture, 🎸 instruments, 🎛️ audio/DSP, 🖥️ platform-specific.
- **Tables** for anything comparative: platform support matrices, parameter ranges, API surface comparisons.
- **Mermaid diagrams** whenever depicting flow, architecture, or data model relationships. Use \`\`\`mermaid blocks. Prefer `graph TD` for architecture, `sequenceDiagram` for data flow between components, `classDiagram` for data models.
- **Code blocks** for JSON schema examples, Dart/C++ signatures, or CLI invocations that clarify the interface.

### When adding a new feature or section

1. Write a **motivation paragraph** first — what problem does this solve, what user scenario does it enable?
2. Add a **Mermaid diagram** if the feature involves >2 components interacting.
3. Add a **platform support table** if platform coverage is uneven.
4. Group tasks into named sub-steps (e.g. `### Step 1 — Engine`, `### Step 2 — UI`, `### Step 3 — Testing`).
5. End every new section with a `### Smoke test` or `### Testing` sub-section with concrete, observable acceptance criteria.

---

## Commands

### `/gf-roadmap` (no args) — status overview
Read `docs/dev/ROADMAP.md` and show: current version, next milestone, count of pending tasks per section.

### `/gf-roadmap next` — next tasks
List the first 10 unchecked `- [ ]` items from the active milestone (first `## vX.Y.Z` that is not complete). Format as numbered list with sub-phase context.

### `/gf-roadmap list [area]` — all remaining tasks
If no area given: list every `- [ ]` grouped by `## vX.Y.Z` heading.
If area given (e.g. `ios`, `audio`, `ui`, `looper`, `vst3`): filter to matching lines.

### `/gf-roadmap add <description>` — add a task
1. Determine which version/section it belongs in (ask if ambiguous).
2. If adding to an **existing** section: insert as `- [ ] <description>` under the correct heading. Task text must name specific classes/files/concepts — no vague bullets.
3. If **creating a new section** (new milestone or new backlog sub-group): apply the full quality standard — motivation paragraph, Mermaid diagram if ≥2 components interact, platform table if coverage varies, named sub-steps, smoke test sub-section.
4. If unscheduled, add under `## Backlog — Unscheduled` in the right sub-group (create the sub-group with a motivation sentence if it doesn't exist).

### `/gf-roadmap done <partial task text>` — mark complete
Find the matching `- [ ]` line and change to `- [x]`. Confirm the match before writing.

### `/gf-roadmap cleanup` — archive a shipped milestone
When a version has been released:
1. Move all `- [x]` items into the **Completed Phases** table as a one-line summary.
2. Delete the `## vX.Y.Z` section from the active area.
3. Update the **At a Glance** row to `✅ Complete`.
4. Update `> Current released version:` at the top.
5. Update `> Last updated:` to today.

### `/gf-roadmap linear-push [milestone]` — push pending tasks to Linear
Requires `LINEAR_API_KEY` and `LINEAR_TEAM_ID` env vars.
1. Read all `- [ ]` items for the given milestone (or all if not specified).
2. For each, call `bash ${CLAUDE_SKILL_DIR}/scripts/linear_create.sh` to create a Linear issue (skips if already exists by checking title).
3. Report created vs. skipped.

### `/gf-roadmap linear-pull` — pull Linear completions back
Requires `LINEAR_API_KEY` and `LINEAR_TEAM_ID` env vars.
1. Call `bash ${CLAUDE_SKILL_DIR}/scripts/linear_list.sh` to fetch completed issues from Linear.
2. For each completed issue, find the matching `- [ ]` in the roadmap and mark `- [x]`.
3. Report which lines were updated.

### `/gf-roadmap linear-status` — show Linear project status
Requires `LINEAR_API_KEY` and `LINEAR_TEAM_ID` env vars.
Run `bash ${CLAUDE_SKILL_DIR}/scripts/linear_list.sh` and display a summary table of open issues grouped by state.

---

## Environment variables

Set in `.claude/settings.local.json` under `env` (never commit API keys):

```json
{
  "env": {
    "LINEAR_API_KEY": "lin_api_xxxx",
    "LINEAR_TEAM_ID": "TEAM-UUID",
    "LINEAR_PROJECT_ID": "PROJECT-UUID"
  }
}
```

`LINEAR_PROJECT_ID` is optional — if set, issues are created inside that project.

To find your team ID and project ID, run:
```bash
bash .claude/skills/linear_find_ids.sh
```

---

## Label mapping

When creating Linear issues, apply labels based on task content:

| Keyword in task | Linear label |
|---|---|
| `iOS`, `AUv3`, `macOS` | `platform:apple` |
| `Android`, `AAP`, `Oboe` | `platform:android` |
| `Linux`, `ALSA`, `X11` | `platform:linux` |
| `web`, `WASM`, `flutter_web` | `platform:web` |
| `VST3`, `vst3`, `dvh_` | `area:vst3` |
| `GFPA`, `gfpd`, `.gfpd` | `area:gfpa` |
| `MIDI`, `looper`, `LoopTrack` | `area:midi` |
| `audio`, `DSP`, `PCM`, `FFI` | `area:audio` |
| `UI`, `widget`, `layout`, `responsive` | `area:ui` |
| `l10n`, `ARB`, `locali` | `area:l10n` |
| `pub.dev`, `publish` | `area:publishing` |
| `smoke test`, `verify`, `Testing` | `type:test` |

---

## See also

- [scripts/linear_create.sh](scripts/linear_create.sh) — create a Linear issue via GraphQL
- [scripts/linear_list.sh](scripts/linear_list.sh) — list issues from the team/project
- [scripts/linear_update.sh](scripts/linear_update.sh) — update issue state
