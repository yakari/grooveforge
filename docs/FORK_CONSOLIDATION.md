# Fork Consolidation & Dependency Hygiene — Plan

> **Status:** Deferred — do this **after** `gf_audio_core` and the new rehearsal app
> exist. This is GrooveForge maintenance, not part of the rehearsal mutualization
> (none of these packages are needed by the rehearsal app).
> **Created:** 2026-06-04
> **Forks already created:**
> - https://github.com/yakari/flutter_vst3
> - https://github.com/yakari/flutter_midi_pro
> - https://github.com/yakari/FlutterMidiCommand

---

## 1. Current state (verified by inspection)

All three packages are **vendored as plain files** committed directly into the
GrooveForge repo (`packages/…`), referenced via `path:` dependencies. **None has any
real local git lineage to upstream** — so we cannot `git merge`/`rebase` onto upstream;
we'll commit the modified snapshot as a visible diff on top of the fork's upstream
history instead.

| Package (local) | pubspec name / version | How referenced | Imported by |
|---|---|---|---|
| `packages/flutter_vst3` | (host under `/dart_vst_host`) | `path: packages/flutter_vst3/dart_vst_host` | VST host (GrooveForge core) |
| `packages/flutter_midi_pro` | `flutter_midi_pro` 3.1.6 | `path: packages/flutter_midi_pro` | `lib/services/audio_engine.dart` only |
| `packages/flutter_midi_command_linux` | `flutter_midi_command_linux` 0.3.0 | `path:` (federated Linux impl) | **No direct Dart imports** |
| (pub.dev) `flutter_midi_command` | `^0.5.3` (unmodified, from pub) | normal dep | 4 files (preferences, rack, midi_service, audio_engine) |

### Anomaly to clean up
- `packages/flutter_vst3/.git/` is an **empty stray directory** (not a repo — git
  resolves up to grooveforge's `.git`). **Delete it** (`rm -rf packages/flutter_vst3/.git`)
  so tooling doesn't get confused.

### Key realizations
- **None of these are needed by the rehearsal app** (no VST hosting, no MIDI I/O, no
  soundfont synth there). Forking them is purely GrooveForge provenance/license hygiene
  and the ability to pull upstream fixes — **not** mutualization.
- The base `flutter_midi_command` is consumed **unmodified** from pub.dev (`^0.5.3`).
  Yann's only MIDI modification lives in the separate `flutter_midi_command_linux`
  (v0.3.0), which is an **old Linux port** and is **not imported directly** — it's
  endorsed as the Linux platform implementation.

---

## 2. Per-package plan

### 2.1 `flutter_midi_command_linux` → likely DROP (highest-value simplification)

This old 0.3.0 Linux port may now be redundant: upstream `flutter_midi_command` gained
Linux support in the 0.5.x line (which we already use from pub.dev).

**Decision tree:**
1. **Verify** upstream `flutter_midi_command ^0.5.3` ships a working Linux
   implementation (check its repo/pub, or just remove and test).
2. **If YES (expected):**
   - Remove the `flutter_midi_command_linux:` path entry from `pubspec.yaml`.
   - Delete `packages/flutter_midi_command_linux/`.
   - Keep stock `flutter_midi_command` (pub.dev or fork — see 2.2).
   - **Test Linux MIDI** (in/out) end-to-end before committing.
   - Result: one fewer vendored package, no fork needed for it.
3. **If NO:**
   - Backport the 0.3.0 Linux changes onto the `yakari/FlutterMidiCommand` fork (the
     federated plugin already includes platform impls), and depend on the fork.

### 2.2 `flutter_midi_command` (base) → fork is optional / dormant

We currently use stock `^0.5.3` from pub.dev with **no modifications**.
- If 2.1 resolves to "drop the Linux package," we likely need **no changes** here —
  keep the pub.dev dependency.
- Keep `yakari/FlutterMidiCommand` as the **dormant home** for any *future* base
  changes; switch to a git dependency only when/if we actually modify it.

### 2.3 `flutter_midi_pro` → push modified snapshot to fork, depend via git

GrooveForge-only (imported solely by `audio_engine.dart`). Modified, vendored.
1. Clone `yakari/flutter_midi_pro` (pristine upstream).
2. Copy the vendored `packages/flutter_midi_pro/` contents over the clone's tree.
3. Commit as **"Apply GrooveForge modifications"** (one visible diff vs upstream);
   note the original upstream version it was based on in the message.
4. Push; tag (e.g. `gf-1`) or note the commit hash.
5. In `pubspec.yaml`, replace the `path:` dep with a **pinned git dependency**:
   ```yaml
   flutter_midi_pro:
     git:
       url: https://github.com/yakari/flutter_midi_pro.git
       ref: <commit-or-tag>
   ```
6. Remove `packages/flutter_midi_pro/` from the GrooveForge repo.

### 2.4 `flutter_vst3` → delete stray `.git`, push snapshot to fork, depend via git

GrooveForge-only.
1. `rm -rf packages/flutter_vst3/.git` (empty stray dir).
2. Clone `yakari/flutter_vst3` (pristine upstream).
3. Copy the vendored `packages/flutter_vst3/` contents over the clone.
4. Commit **"Apply GrooveForge modifications"** (note base upstream version), push, tag.
5. Switch the `path: packages/flutter_vst3/dart_vst_host` dep to a pinned git dep
   (mind the subdirectory — use `path:` inside the `git:` block):
   ```yaml
   dart_vst_host:
     git:
       url: https://github.com/yakari/flutter_vst3.git
       ref: <commit-or-tag>
       path: dart_vst_host
   ```
6. Remove `packages/flutter_vst3/` from the GrooveForge repo.

---

## 3. General mechanics (apply to every fork)

- **Pin** every git dependency to a **commit hash or tag**, never a moving branch —
  reproducible builds; immune to upstream force-push.
- In each fork, add the original as an `upstream` remote so future upstream fixes can be
  merged:
  ```bash
  git remote add upstream <original-repo-url>
  git fetch upstream
  ```
- **Preserve `LICENSE` + copyright/attribution** from upstream (they're already in the
  tree — don't strip them).
- **License compliance (GrooveForge app is closed → matters):** if any package is
  **LGPL**, the public fork *is* how you satisfy "publish your modifications to the
  library." Keep these forks **public**. MIT/BSD/Apache: just keep notices intact.
- After each switch: `flutter pub get`, `flutter analyze` (zero issues — Rule 6), and a
  smoke test of the affected feature.

---

## 4. Suggested order (when the time comes)

1. `flutter_midi_command_linux`: verify upstream Linux support → drop (or backport).
2. `flutter_midi_pro`: push to fork → git dep → remove vendored copy.
3. `flutter_vst3`: delete stray `.git` → push to fork → git dep → remove vendored copy.
4. Final `flutter pub get` + `flutter analyze` + smoke tests (MIDI I/O, soundfont
   playback, VST host). Changelog entry per Rule 3.

## 5. Checklist

- [ ] Verify `flutter_midi_command` 0.5.3 Linux support; drop `flutter_midi_command_linux` if covered (test Linux MIDI)
- [ ] `rm -rf packages/flutter_vst3/.git` (stray empty dir)
- [ ] Populate `yakari/flutter_midi_pro` fork; pin git dep; remove vendored copy
- [ ] Populate `yakari/flutter_vst3` fork; pin git dep (subdir `dart_vst_host`); remove vendored copy
- [ ] Add `upstream` remote to each fork
- [ ] Confirm LICENSE/attribution preserved; forks public (LGPL compliance)
- [ ] `flutter pub get` + `flutter analyze` (0 issues) + smoke tests
- [ ] Changelog entry (EN + FR)
