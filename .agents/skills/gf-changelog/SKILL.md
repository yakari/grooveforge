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
- <English description of new feature — include class/method names and user scenario>

### Fixed
- <English description of regression fix — only if it existed in a previous release>

### Architecture
- <Internal/technical change not directly visible to users>
```

---

## Examples

### Good entries

```markdown
### Added
- New `ChordGridEngine` that advances the active chord on each beat tick from `TransportEngine`, enabling transport-synced scale locking in Jam Mode.
- `LooperEngine.snapToBeat()` — when the user taps Play within the last 100 ms of a bar, playback now starts precisely on the next downbeat instead of the tap position.

### Fixed
- `LooperEngine` could produce a 1-beat timing offset when tapping Play within 100 ms of a downbeat — now snaps immediately. (Regression introduced in v2.3.0.)

### Architecture
- Replaced `List<Note>` live allocation in `SynthEngine.process()` with a pre-allocated `_noteBuffer` pool to eliminate GC pressure on the audio thread.
```

### Bad entries (do not write these)

```markdown
### Fixed
- Fixed looper bug          ← too vague, no class names, unclear if regression
- Added chord stuff         ← no class names, no user scenario
- Various improvements      ← meaningless
- Fixed crash in new feature ← new feature was never shipped; belongs in Added/Architecture
```

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
