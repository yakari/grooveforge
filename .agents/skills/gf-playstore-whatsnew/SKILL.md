---
name: gf-playstore-whatsnew
description: Generate a Play Store Console "What's new" release note (EN + FR, 500 chars max each) from GrooveForge changelog entries across a user-specified version range.
argument-hint: "[from-version] [to-version]  e.g. 2.12.2 2.13.0"
allowed-tools: Read
---

## Purpose

Produce a **Play Store Console "What's new"** text, in **English and French**, summarizing the most important user-facing changes from one or more recent GrooveForge versions. Each language block is capped at **500 characters** (Google Play's hard limit) and each bullet sits on its own line.

This skill is read-only — it never edits files. Its only output is the two text blocks for the user to paste into the Play Console.

---

## Step 1 — Ask the user which versions to include

Before reading anything, ask the user:

> **Which versions should I include in the Play Store "What's new"?**
> Give me the oldest version that hasn't shipped to the Play Store yet, and the new version you're about to publish. I'll parse every changelog block in that range (inclusive).
>
> Example: `from 2.12.2 to 2.13.0` would include `2.12.2`, `2.12.3`, …, `2.12.7`, `2.13.0`.

If the user already supplied both versions as arguments, skip the question and confirm the range in one sentence before proceeding.

If the user only gives the new version, ask for the oldest unpublished one — never guess.

---

## Step 2 — Read the changelogs

Read both:

- `CHANGELOG.md` (English source)
- `CHANGELOG.fr.md` (French source)

Locate every `## [X.Y.Z] - YYYY-MM-DD` block whose version is within the inclusive range `[from, to]`. Ignore any `## [X.x.x]` placeholder block (it is unreleased).

Collect, per language, the bullets from `### Added` and `### Fixed` sections across all matched versions. Skip `### Architecture`, `### Changed` internals, and any entry that is purely technical (build system, refactor, code cleanup) — the Play Store audience is end users.

---

## Step 3 — Select and rewrite entries

The raw changelog bullets are too long and too technical for a 500-char store listing. Rewrite them:

### Selection rules
- **Prioritize new features over fixes.** If space is tight, drop fixes first.
- **Prioritize user-visible impact.** A fix that restores a broken flow is worth more than a micro-optimization.
- **Merge duplicates across versions.** If three versions each improved the looper, write one looper line that captures the net effect.
- **Drop internal / developer-only items.** No architecture notes, no "refactored X", no "added debug logging".
- **Cross-platform context matters.** If a feature only landed on Android, it's fine to omit the platform in the store copy unless the omission would mislead (e.g. an iOS-only feature in an Android listing — but this skill targets Play Store, so Android/Linux/macOS relevance is what counts; iOS-only items should be dropped).

### Writing rules
- **One bullet per line.** No wrapping, no sub-bullets.
- **No emojis.** Yann's standing preference: they read as AI-generated output. Lines carry no marker at all — the Play Console does not render markdown, so a leading `-` or `*` would show up literally. `•` is acceptable if the user asks for a visible bullet.
- **Lead with the thing itself.** With no emoji to set the tone, the first two or three words have to do that work: name the feature or the benefit, not the category.
- **Short, punchy, benefit-first.** "Sing live four-voice harmonies with the new Harmonizer effect" beats "Added Audio Harmonizer effect with four pitch-shifted voices".
- **No version numbers, no dates, no platform tags** in the copy itself (the Play Store already shows the version).
- **No markdown.** Plain text only — the Play Console does not render markdown.

---

## Step 4 — Enforce the 500-character limit

Count characters **including spaces and newlines** for each language block independently. Count in UTF-16 code units, which is the most conservative reading of Google's limit. The hard cap is **500**. If either block is over:

1. Drop the lowest-priority bullet (fixes before features).
2. If still over, tighten wording on the remaining bullets.
3. Never truncate mid-sentence.

Report the final character count for each language after the blocks so the user can double-check.

---

## Step 5 — French translation discipline

The French block is not a literal translation of the English one — it's a parallel rewrite with the same intent, following the project's French-translation rule (see `feedback_french_translations.md` in memory): keep English jargon when the literal French is nonsensical. Examples:

- "looper" stays "looper", not "boucleur"
- "vocoder" stays "vocoder"
- "harmonizer" → "harmoniseur" is fine
- "live input" → "entrée live" is fine
- "preset" stays "preset"

The French block must independently fit in 500 characters — don't pad it to match the English length, and don't drop items from one language but not the other unless space forces it (in which case keep both blocks content-equivalent).

---

## Step 6 — Output format

Present the result like this, and nothing else:

```
## English (NNN / 500 chars)

<line 1>
<line 2>
…

## Français (NNN / 500 chars)

<ligne 1>
<ligne 2>
…
```

Print both blocks **inside a fenced code block**. Their line breaks are the format: rendered as ordinary markdown, a terminal or chat client collapses single newlines and runs every bullet into one paragraph, which makes the result impossible to check against the 500-character budget or to paste.

If the user supplied a template (for instance `<en-US>` / `<fr-FR>` tags), use theirs instead of the headings above — still inside a code block.

No preamble, no trailing commentary, no "let me know if you want changes" — the user will ask if they want a revision.

---

## Notes

- **Never invent features.** Every bullet must trace back to a real changelog entry in the selected range.
- **If the range is empty** (no released version blocks match), stop and tell the user — do not fabricate release notes from the `[X.x.x]` placeholder.
- **If the range contains only fixes**, that's fine — write a fix-only "What's new".
