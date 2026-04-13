---
name: gf-changelog
description: Write changelog entries for GrooveForge in both CHANGELOG.md (English) and CHANGELOG.fr.md (French), following the project's changelog discipline.
argument-hint: "[description of changes to record]"
allowed-tools: Read, Edit
---

## When to invoke

Claude should offer to run `/gf-changelog` automatically after any fix or feature is implemented. The entry must be written in the same session as the code change — never deferred.

If arguments are provided, use them directly as the basis for the entries. If no arguments are provided, infer the changes from the code modifications made in the current session.

**If there is no clear context** (no arguments, no recent code changes in this session), ask the user:

> What changes should I record in the changelog? For example:
> - What feature was added or what bug was fixed?
> - What classes or files were involved?
> - Is this a user-facing change (`### Added` / `### Fixed`) or an internal one (`### Architecture`)?

---

## Files

| File | Language |
|---|---|
| `CHANGELOG.md` | English — primary |
| `CHANGELOG.fr.md` | French — must always mirror the English entry |

---

## Rules

- Always update **both** `CHANGELOG.md` (English) and `CHANGELOG.fr.md` (French).
- Entries go under a `## [X.x.x]` placeholder header at the **very top** of each file, above any dated release.
- Use Keep a Changelog categories: `Added`, `Fixed`, `Changed`, `Removed`, `Architecture`.
- **No duplicate section headers** within a single version block. If `### Added` already exists, merge new bullets into it — never create a second one.
- **`### Fixed` is only for regressions in previously shipped code.** Ask: "Was this broken in the last release?" If the feature didn't exist then, the answer is no — use `### Added` or `### Architecture` instead.

### Conciseness — hard rule

**A changelog is a release note for end users, not a design doc.** Readers skim it. Every entry must survive being read at a glance.

- **Top bullet: one sentence.** What changed, from the user's perspective, in plain language. Target 25 words, hard cap at 40.
- **Sub-bullets are optional and rare.** At most 2 or 3, only when the *why* or a specific gotcha genuinely helps a reader. Never use sub-bullets to narrate the implementation.
- **No code identifiers.** No class names, no method names, no variable names, no file paths, no FFI symbol names, no CMake targets. The changelog is for users, and users don't read the code. If an entry can't be written without naming `FooEngine.process()`, rewrite it around the user-visible behavior instead.
- **No markdown links to source files.** Links are for the roadmap and commit messages, not user-facing release notes.
- **Never recount the debugging story, the options considered, the first attempt that didn't work, the session number, or what was deferred.** That belongs in commit messages, the roadmap, or decision logs — not the changelog.
- **No tables, no ASCII diagrams, no code fences** inside a changelog entry.
- **No "known limitations" paragraphs.** If a limitation matters, file a roadmap task. The changelog doesn't mention it.
- **Strip hedges and meta-commentary**: "we realised", "it turned out", "worth noting", "the first attempt", "tracked but not implemented", "as of this session". Deletable.
- If a single entry is longer than **3 rendered lines** it is almost certainly too long. Cut until it fits.

Think of each entry as a tweet-length announcement a user would read in the app's "What's new" dialog. If technical detail feels essential, it belongs in the commit message or the roadmap — not here.

---

## Workflow

1. Read the current top of `CHANGELOG.md` and `CHANGELOG.fr.md` to check whether a `[X.x.x]` placeholder block already exists.
2. If yes, merge new bullets into the correct existing section — never add a duplicate heading.
3. If no, create a new `## [X.x.x]` block with the appropriate sections.
4. Write the English entry in `CHANGELOG.md`, then the French equivalent in `CHANGELOG.fr.md`.

---

## Template

```markdown
## [X.x.x]

### Added
- <One sentence describing the user-visible behavior. Plain language. No class or file names.>

### Fixed
- <One sentence describing the regression fix and the user symptom. Only if it shipped before.>

### Architecture
- <Internal change too technical to phrase for users. Still one sentence, still no code identifiers.>
```

---

## Examples

### Good entries

```markdown
### Added
- Jam Mode can now lock the active chord to the transport, so the scale stays in sync when the tempo changes.
- The audio looper snaps playback to the next downbeat when you press Play within the last 100 ms of a bar.

### Fixed
- The looper could start playback one beat early when Play was pressed near a downbeat. (Regression from v2.3.0.)

### Architecture
- Removed per-block heap allocations from the synth audio callback to eliminate GC pressure on the audio thread.
```

### Bad entries (do not write these)

```markdown
### Fixed
- Fixed `LooperEngine.snapToBeat()` bug              ← names a method; users don't know what that is
- Fixed looper bug                                    ← too vague; no user symptom
- Various improvements                                ← meaningless
- Fixed crash in new feature added this release       ← not a regression; belongs in Added/Architecture

### Added
- New `ChordGridEngine` class in `lib/engine/chord_grid.dart` ← names a class and a file; rewrite around behavior
- First we tried approach A, then switched to approach B ← debugging narrative
```

Good bullets describe what a user *experiences*. Bad bullets describe what a developer *did*.

---

## French translation tips

| English section | French section |
|---|---|
| `### Added` | `### Ajouté` |
| `### Fixed` | `### Corrigé` |
| `### Changed` | `### Modifié` |
| `### Removed` | `### Supprimé` |
| `### Architecture` | `### Architecture` |

Write the French entry as a proper translation — not a literal word-for-word rendering. Preserve all class and method names exactly (they are code identifiers, not prose).
