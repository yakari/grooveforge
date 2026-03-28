# Skill: release

Cut a new GrooveForge release when the user provides a version number.

## Steps

### 1. Determine the version

The user must supply the version string (e.g. `3.0.0`). Never invent a version.

### 2. Update changelogs

In **both** `CHANGELOG.md` and `CHANGELOG.fr.md`:

1. Find the `## [X.x.x]` placeholder at the top.
2. Replace it with `## [<version>] - <today's date in YYYY-MM-DD format>`.
3. If no placeholder exists, ask the user what to include before proceeding.

### 3. Update `pubspec.yaml`

1. Read the current `version:` line, e.g. `version: 2.9.0+42`.
2. Set the new version: `version: <new_version>+<previous_build + 1>`.
   - Example: `2.9.0+42` → `3.0.0+43`.

### 4. Verify

- Both changelogs have a dated header for the new version.
- `pubspec.yaml` `version:` reflects the new semver and incremented build number.
- No `[X.x.x]` placeholder remains in either changelog.

### 5. Suggest next steps (do not execute without confirmation)

```
git add CHANGELOG.md CHANGELOG.fr.md pubspec.yaml
git commit -m "chore: release v<version>"
git tag v<version>
```

## Version format

`<major>.<minor>.<patch>+<build>` — build number increments monotonically with every release, never resets.
