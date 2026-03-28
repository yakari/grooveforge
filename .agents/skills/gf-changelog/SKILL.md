# Skill: changelog

Write changelog entries for GrooveForge following the project's changelog discipline.

## Rules

- Always update **both** `CHANGELOG.md` (English) and `CHANGELOG.fr.md` (French).
- Entries go under a `## [X.x.x]` placeholder header at the **very top** of each file, above any dated release.
- Use Keep a Changelog categories: `Added`, `Fixed`, `Changed`, `Removed`, `Architecture`.
- **No duplicate section headers** within a single version block. If `### Added` already exists, merge new bullets into it — never create a second one.
- **`### Fixed` is only for regressions in previously shipped code.** Ask: "Was this broken in the last release?" If the feature didn't exist then, the answer is no — use `### Added` or `### Architecture` instead.

## Workflow

1. Read the current top of `CHANGELOG.md` and `CHANGELOG.fr.md` to check whether a `[X.x.x]` placeholder block already exists.
2. If yes, merge new bullets into the correct existing section.
3. If no, create a new `## [X.x.x]` block with the appropriate sections.
4. Write the English entry in `CHANGELOG.md`, then the French equivalent in `CHANGELOG.fr.md`.

## Template

```markdown
## [X.x.x]

### Added
- <English description of new feature>

### Fixed
- <English description of regression fix — only if it existed in a previous release>

### Architecture
- <Internal/technical change not directly visible to users>
```

## French translation tips

- "Added" → "Ajouté"
- "Fixed" → "Corrigé"
- "Changed" → "Modifié"
- "Removed" → "Supprimé"
- "Architecture" → "Architecture"
