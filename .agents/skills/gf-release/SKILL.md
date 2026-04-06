---
name: gf-release
description: Cut a new GrooveForge release by updating changelogs and pubspec.yaml to the user-supplied version number.
argument-hint: "<version>  e.g. 3.0.0"
allowed-tools: Read, Edit
---

## Danger zone

`gf-release` makes permanent changes to version metadata. Never invent a version number — the user must supply it. If any pre-release check fails, stop and report before proceeding.

---

## Pre-release checklist

Verify each item before making any changes:

| Check | How to verify | Expected result |
|---|---|---|
| No analysis warnings | Run `flutter analyze` | `No issues found` |
| Both changelogs updated | Read top of each file | A `## [X.x.x]` placeholder block exists |
| Version in pubspec | Read `pubspec.yaml` | Shows the previous version (not the new one yet) |
| Placeholder not already dated | Grep for `[X.x.x]` | Match found (i.e. it is still a placeholder, not yet a date) |

If no `## [X.x.x]` placeholder exists in either changelog, stop and ask the user what entries to include before proceeding.

---

## Steps

### 1. Determine the version

The user must supply the version string (e.g. `3.0.0`). Never invent a version.

### 2. Update changelogs

In **both** `CHANGELOG.md` and `CHANGELOG.fr.md`:

1. Find the `## [X.x.x]` placeholder at the top.
2. Replace it with `## [<version>] - <today's date in YYYY-MM-DD format>`.

### 3. Update `pubspec.yaml`

1. Read the current `version:` line, e.g. `version: 2.9.0+42`.
2. Set the new version: `version: <new_version>+<previous_build + 1>`.
   - Example: `2.9.0+42` → `3.0.0+43`.

### 4. Verify

- Both changelogs have a dated header for the new version.
- `pubspec.yaml` `version:` reflects the new semver and incremented build number.
- No `[X.x.x]` placeholder remains in either changelog.

### 5. Suggest next steps (do not execute without confirmation)

Present the following as a copyable block for the user to run when ready:

```bash
git add CHANGELOG.md CHANGELOG.fr.md pubspec.yaml
git commit -m "chore: release v<version>"
git tag v<version>
# Push when ready: git push && git push --tags
```

---

## Version format

`<major>.<minor>.<patch>+<build>` — the build number increments monotonically with every release and never resets to zero.

| Field | Example | Rule |
|---|---|---|
| `major` | `3` | Breaking changes or major milestones |
| `minor` | `1` | New features, backwards-compatible |
| `patch` | `2` | Bug fixes only |
| `build` | `+43` | Always `previous + 1`, never reused |
