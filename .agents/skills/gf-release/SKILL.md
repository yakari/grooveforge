---
name: gf-release
description: Cut a new GrooveForge release by updating changelogs, pubspec.yaml, the Fastlane store changelogs and the F-Droid metadata to the user-supplied version number.
argument-hint: "<version>  e.g. 3.0.0"
allowed-tools: Read, Write, Edit, Bash
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
| Working tree clean | `git status --short` | Nothing uncommitted that belongs in the release |

If no `## [X.x.x]` placeholder exists in either changelog, stop and ask the user what entries to include before proceeding.

---

## Files a release touches

Every release commit must update **all** of these. Forgetting one ships a version the stores or F-Droid cannot ingest.

| File | What changes |
|---|---|
| `CHANGELOG.md` | `## [X.x.x]` → `## [<version>] - <today>` |
| `CHANGELOG.fr.md` | same, French |
| `pubspec.yaml` | `version: <new_version>+<previous_build + 1>` |
| `fastlane/metadata/android/en-US/changelogs/<build>.txt` | new file, English store notes |
| `fastlane/metadata/android/en-US/changelogs/<build>{1,2,3}.txt` | same content, one per ABI version code |
| `fastlane/metadata/android/fr-FR/changelogs/<build>*.txt` | same four files, French |
| `packaging/fdroid/com.grooveforge.grooveforge.yml` | three `Builds:` blocks + `CurrentVersion` / `CurrentVersionCode` |

---

## Steps

### 1. Determine the version

The user must supply the version string (e.g. `3.0.0`). Never invent a version.

### 2. Update changelogs

In **both** `CHANGELOG.md` and `CHANGELOG.fr.md`:

1. Find the `## [X.x.x]` placeholder at the top.
2. Replace it with `## [<version>] - <today's date in YYYY-MM-DD format>`.

Do **not** add a fresh empty `## [X.x.x]` block — it gets created when the next change lands.

### 3. Update `pubspec.yaml`

1. Read the current `version:` line, e.g. `version: 2.9.0+42`.
2. Set the new version: `version: <new_version>+<previous_build + 1>`.
   - Example: `2.9.0+42` → `3.0.0+43`.

The new build number is `B`. Everything below is derived from it.

### 4. Write the Fastlane store changelogs

Android splits per ABI, so `android/app/build.gradle.kts` overrides the version code as
`versionCode * 10 + abiCode`, with `armeabi-v7a → 1`, `arm64-v8a → 2`, `x86_64 → 3`.
Both the Play Store and F-Droid look up release notes by the **final** version code, so each
build needs four identical files per language:

```
fastlane/metadata/android/en-US/changelogs/<B>.txt
fastlane/metadata/android/en-US/changelogs/<B>1.txt
fastlane/metadata/android/en-US/changelogs/<B>2.txt
fastlane/metadata/android/en-US/changelogs/<B>3.txt
fastlane/metadata/android/fr-FR/changelogs/<B>.txt      (and <B>1, <B>2, <B>3)
```

Content rules:

- Plain text, **500 characters max** per file (Google's hard limit).
- Mirror the existing files' shape: an `Added` / `Fixed` heading (`Ajouté` / `Corrigé` in French) followed by `- ` bullets.
- **Android-relevant entries only.** A macOS or Linux build fix has no place in the Play Store notes; drop it.
- No emojis, no markdown, no version numbers — see the `gf-playstore-whatsnew` skill for the tone and the Play Console paste format.
- Keep the English and French files content-equivalent.

### 5. Update the F-Droid metadata

`packaging/fdroid/com.grooveforge.grooveforge.yml` holds three `Builds:` blocks, one per ABI,
plus the current-version footer. Update all of them:

| Field | New value |
|---|---|
| `versionName` (×3) | `<version>` |
| `versionCode` | `<B>1`, `<B>2`, `<B>3` — in the armeabi-v7a, arm64-v8a, x86_64 blocks respectively (match the `output:` APK name, not the block order) |
| `commit` (×3) | `v<version>` — the tag this release will carry |
| `CurrentVersion` | `<version>` |
| `CurrentVersionCode` | `<B>3` (the highest ABI code) |

The `commit:` field must point at the tree the release is actually built from. Using a tag name
rather than a hash is deliberate: the tag does not exist yet when the release commit is written,
and F-Droid resolves it at build time. A stale hash left over from an older release makes F-Droid
build the wrong source for the claimed `versionName`.

### 6. Verify

- Both changelogs have a dated header for the new version, and no `[X.x.x]` placeholder remains.
- `pubspec.yaml` `version:` reflects the new semver and incremented build number.
- Eight new Fastlane files exist (4 English + 4 French) and each is ≤ 500 characters.
- The F-Droid YAML shows the new version name in all three build blocks, three distinct version codes, and a `commit:` matching the tag about to be created.

### 7. Suggest next steps (do not execute without confirmation)

Present the following as a copyable block for the user to run when ready:

```bash
git add CHANGELOG.md CHANGELOG.fr.md pubspec.yaml fastlane packaging/fdroid
git commit -m "chore: release v<version>"
git tag v<version>
# Push when ready: git push && git push --tags
```

The tag name must match the `commit:` field written into the F-Droid metadata.

---

## Version format

`<major>.<minor>.<patch>+<build>` — the build number increments monotonically with every release and never resets to zero.

| Field | Example | Rule |
|---|---|---|
| `major` | `3` | Breaking changes or major milestones |
| `minor` | `1` | New features, backwards-compatible |
| `patch` | `2` | Bug fixes only |
| `build` | `+43` | Always `previous + 1`, never reused |
