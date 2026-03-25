# GrooveForge Coding Standards

**Activation: Always On**

GrooveForge is a Flutter/Dart cross-platform music application (Android, iOS, Linux, macOS, Windows) with VST3 plugin support in C++, real-time audio processing, and the GrooveForge Plugin API (GFPA). Version is tracked in `pubspec.yaml` (`version: <semver>+<build>`).

---

## Rule 1 — Responsive UI

Every screen and widget must render correctly on all form factors — no fixed-width top-level layout containers.

| Breakpoint | Width | Strategy |
|---|---|---|
| Desktop | ≥ 1280 px | Full layout, side panels, expanded controls |
| Tablet landscape | 900–1279 px | Two-column, compact sidebars |
| Tablet portrait | 600–899 px | Single-column, collapsible panels |
| Phone portrait/landscape | < 600 px | Stacked layout, bottom sheets for secondary controls |

Use `LayoutBuilder` / `MediaQuery` to branch at these thresholds. Validate every new screen in at least three form factors.

```dart
// ✅ responsive branch
final wide = constraints.maxWidth >= 900;
return wide ? const _WideRackLayout() : const _NarrowRackLayout();
```

---

## Rule 2 — Real-Time Audio — Zero Tolerance for Latency

Audio is the core product. Latency and dropouts are critical failures.

- **Audio thread rules**: no memory allocation, no logging, no Dart `Future`/`async`, no lock acquisition on the audio callback path.
- Use lock-free ring buffers or pre-allocated pools to pass data between the audio thread and the UI/Dart isolate.
- **Android**: request low-latency mode (`PERFORMANCE_MODE_LOW_LATENCY`); use `AAudio` or `Oboe`; avoid `AudioTrack` on the hot path.
- **VST3 plugins**: `process()` must be allocation-free and finish well inside the buffer deadline.
- Propagate parameter changes (knobs, BPM, presets) to the audio engine via `ValueNotifier` callbacks or atomic writes — never through `await`.

```dart
// ✅ non-blocking parameter propagation
_engine.gainProvider = () => _gainNotifier.value;

// ❌ blocks Dart event loop — do NOT do this on audio-sensitive paths
await _engine.setGain(value);
```

---

## Rule 3 — Changelog Discipline

Every fix and every new feature must be recorded **before ending a session** in both:

- `CHANGELOG.md` — English
- `CHANGELOG.fr.md` — French

### Writing entries

Add a new `[X.x.x]` placeholder header at the very top of each changelog (above existing dated versions). Use Keep a Changelog categories: `Added`, `Fixed`, `Changed`, `Removed`, `Architecture`.

**CRITICAL — no duplicate section headers**: within a single `[X.x.x]` block there must be exactly one of each category heading. When adding new bullets in a follow-up session, merge them into the existing section — never create a second `### Added` (or `### Fixed`, etc.) block inside the same version.

**CRITICAL — `### Fixed` is only for regressions in shipped code**: a bug discovered during development of a brand-new feature is not a regression. If the feature didn't exist in the previous release, it cannot be "fixed" — it was never broken. Such notes belong in `### Added` or `### Architecture`, or can be omitted. Test: "Was this broken in the last release?" If the feature wasn't there, the answer is no.

```
## [X.x.x]

### Added
- …

### Fixed
- …
```

### Releasing a version (when the user supplies the version number)

1. Replace `[X.x.x]` with the supplied version in **both** changelogs.
2. Append today's date: `## [2.4.0] - YYYY-MM-DD`.
3. In `pubspec.yaml`: set `version: <new_version>+<previous_build_number + 1>`.

---

## Rule 4 — Internationalization (l10n) — Mandatory

All user-visible strings must go through Flutter's `AppLocalizations`. **No hardcoded strings in the UI.**

- Template (source of truth): `lib/l10n/app_en.arb`
- Translation: `lib/l10n/app_fr.arb`
- Generated class: `AppLocalizations` (via `flutter_localizations`)

Workflow for every new string:
1. Add the key + English value to `app_en.arb`.
2. Add the French translation to `app_fr.arb`.
3. Use `context.l10n.<key>` (or `AppLocalizations.of(context)!.<key>`) in widget code.

```dart
// ✅ localized
Text(context.l10n.bpmLabel)

// ❌ hardcoded — never do this
Text('BPM')
```

Never call `.toString()` on a domain object for display — expose a localized label through the ARB files.

---

## Rule 5 — Code Clarity — Low Complexity and Exhaustive Comments

### Keep complexity low

- **No bracket/parenthesis hell**: never nest more than 2–3 levels of callbacks, conditionals, or expressions in a single block.
- Extract named methods for every distinct logical step — aim for methods that fit on one screen and do one thing.
- Prefer early returns and guard clauses over deeply nested `if/else` trees.

```dart
// ❌ BAD – deeply nested
void process(List<Note> notes) {
  if (notes.isNotEmpty) {
    for (final n in notes) {
      if (n.isActive) {
        if (n.velocity > 0) {
          _send(n.pitch, (n.velocity * _gainProvider()).clamp(0, 127).toInt());
        }
      }
    }
  }
}

// ✅ GOOD – flat, each step named
void process(List<Note> notes) {
  for (final note in notes) _processNote(note);
}

void _processNote(Note note) {
  if (!note.isActive || note.velocity == 0) return;
  _send(note.pitch, _applyGain(note.velocity));
}

int _applyGain(int velocity) =>
    (velocity * _gainProvider()).clamp(0, 127).toInt();
```

### Comment everything — assume the reader is not a DAW developer

Every **class, enum, typedef, mixin, extension, method, and function** must have a doc comment (`///` in Dart, `/** */` in C++):

- **What** the entity represents or does.
- **Why** it exists if not obvious from the name.
- **Key parameters** and return value when non-trivial.

Inside algorithms, add **inline comments on each logical step** explaining the audio/music concept, not just the mechanics — the goal is that a non-developer can follow the intent:

```dart
/// Snaps [midiNote] to the nearest pitch class allowed by the current
/// jam-mode scale. Uses DOWN-first tie-breaking: when two candidates are
/// equidistant, the lower one wins, matching Western harmonic conventions.
int snapToScale(int midiNote, Set<int> allowedPitchClasses) {
  final pc = midiNote % 12; // pitch class: 0=C, 1=C#, … 11=B
  if (allowedPitchClasses.contains(pc)) return midiNote; // already in scale

  // Search outward from the original note (down first) until a pitch
  // class that belongs to the active scale is found.
  for (int delta = 1; delta <= 6; delta++) {
    final down = midiNote - delta;
    if (allowedPitchClasses.contains(down % 12)) return down;
    final up = midiNote + delta;
    if (allowedPitchClasses.contains(up % 12)) return up;
  }
  return midiNote; // fallback: no match within an octave, keep original
}
```

## Rule 6 — Research Before Implementing

Before writing non-trivial code or selecting a library/approach:

1. Query the **Context7 MCP** (`user-context7` server) for current documentation and idiomatic patterns.
2. Fall back to a **targeted web search** if Context7 returns nothing relevant — include the current year for recency.
3. Prefer official idiomatic APIs over workarounds.
4. When the implementation choice is non-obvious, add a concise comment explaining the rationale (not restating what the code does).
