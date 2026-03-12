# GrooveForge — Project Guidelines for Gemini Code Assist

## Project Overview

GrooveForge is a Flutter/Dart cross-platform music application (Android, iOS, Linux, macOS, Windows) with VST3 plugin support written in C++, real-time audio processing, and the GrooveForge Plugin API (GFPA). The current version is tracked in `pubspec.yaml`.

---

## Rule 1 — Responsive UI

Every screen and widget must render correctly on **all form factors**:

| Breakpoint | Width | Layout strategy |
|---|---|---|
| Desktop | ≥ 1280 px | Full layout, side panels, expanded controls |
| Tablet landscape | 900–1279 px | Two-column, compact sidebars |
| Tablet portrait | 600–899 px | Single-column, collapsible panels |
| Phone (portrait & landscape) | < 600 px | Stacked layout, bottom sheets for secondary controls |

- Use `LayoutBuilder` and `MediaQuery` to switch layouts at the breakpoints above.
- Never use fixed pixel widths for top-level layout containers.
- Verify every new screen in at least three form factors before considering it done.

---

## Rule 2 — Real-Time Audio — Zero Tolerance for Latency

Audio is the core product. Latency, jitter, and dropouts are unacceptable.

- **Never** allocate memory, log, acquire Dart locks, or do I/O on the audio thread.
- Use lock-free ring buffers and pre-allocated pools for audio↔UI data exchange.
- **Android specifically**: request low-latency audio mode via `AudioManager`, use `AAudio`/`Oboe`; avoid Java `AudioTrack` paths in the hot path.
- VST3 `process()` implementations must be allocation-free and complete well within the buffer deadline.
- Update plugin parameters through `ValueNotifier` callbacks or atomic writes — never block the audio thread on a Dart `Future` or `async`/`await`.

---

## Rule 3 — Changelog Discipline

Every fix and new feature must be recorded **before ending the session** in both:
- `CHANGELOG.md` (English)
- `CHANGELOG.fr.md` (French)

### Adding entries

Prepend a new **`[X.x.x]`** placeholder section at the top of each changelog (above any existing dated version). Use Keep a Changelog sections: `Added`, `Fixed`, `Changed`, `Removed`, `Architecture`.

### Cutting a release (when the user provides the version number)

1. Replace `[X.x.x]` with the version number in **both** changelogs.
2. Append today's date: `## [2.4.0] - YYYY-MM-DD`.
3. Open `pubspec.yaml` and update `version: <new_version>+<previous_build + 1>`.

---

## Rule 4 — Internationalization (l10n) — Mandatory

All user-visible strings must go through Flutter's `AppLocalizations`. **No hardcoded strings in the UI.**

| File | Role |
|---|---|
| `lib/l10n/app_en.arb` | English — source of truth |
| `lib/l10n/app_fr.arb` | French translation |
| `AppLocalizations` | Generated class (import via `flutter_localizations`) |

Workflow for every new string:
1. Add the key + English value to `app_en.arb`.
2. Add the French translation to `app_fr.arb`.
3. Reference in code: `context.l10n.<key>` or `AppLocalizations.of(context)!.<key>`.

Never place a raw string literal directly in a widget. Never use `.toString()` on domain objects as display text — expose a localized label via the ARB files.

## Rule 5 — Code Clarity — Low Complexity and Exhaustive Comments

### Keep complexity low

- **No bracket/parenthesis hell**: never nest more than 2–3 levels of callbacks, conditionals, or expressions in a single block.
- Extract named methods for every distinct logical step — aim for methods that fit on one screen and do one thing.
- Prefer early returns and guard clauses over deeply nested `if/else` trees.

### Comment everything — assume the reader is not a DAW developer

Every **class, enum, typedef, mixin, extension, method, and function** must have a doc comment (`///` in Dart, `/** */` in C++):

- **What** the entity represents or does.
- **Why** it exists if not obvious from the name.
- **Key parameters** and return value when non-trivial.

Inside algorithms, add **inline comments on each logical step** — explain the audio/music concept, not just the code mechanics:

```dart
/// Snaps [midiNote] to the nearest pitch class allowed by the current
/// jam-mode scale. DOWN-first tie-breaking: when two candidates are
/// equidistant, the lower one is preferred.
int snapToScale(int midiNote, Set<int> allowedPitchClasses) {
  final pc = midiNote % 12; // pitch class: 0=C, 1=C#, … 11=B
  if (allowedPitchClasses.contains(pc)) return midiNote; // already in scale

  // Search outward (down first) until a scale pitch class is found.
  for (int delta = 1; delta <= 6; delta++) {
    final down = midiNote - delta;
    if (allowedPitchClasses.contains(down % 12)) return down;
    final up = midiNote + delta;
    if (allowedPitchClasses.contains(up % 12)) return up;
  }
  return midiNote; // fallback: keep original if no match
}
```

## Rule 6 — Research Before Implementing

For any non-trivial feature or library choice:

1. Query the **Context7 MCP** (`user-context7` server) for up-to-date documentation and idiomatic patterns.
2. If Context7 yields no relevant results, perform a **targeted web search** (include the year 2026 for recency).
3. Prefer official, idiomatic APIs over workarounds.
4. Leave a brief explanatory comment when the implementation choice is non-obvious.
