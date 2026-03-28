# Skill: new-instrument

Scaffold a new GrooveForge instrument (synthesizer, sampler, drum machine, effect, etc.).

## Checklist

### 1. Dart/Flutter side

- [ ] Create `lib/instruments/<instrument_name>/` directory.
- [ ] Implement the instrument class extending or composing the relevant GFPA interface from `packages/grooveforge_plugin_api/`.
- [ ] Keep the audio callback allocation-free (see [audio-safety skill](../gf-audio-safety/SKILL.md)).
- [ ] Create a corresponding UI widget in `lib/instruments/<instrument_name>/<instrument_name>_panel.dart`.
- [ ] Make the UI panel responsive — support at least `desktop`, `tablet`, and `phone` form factors using `LayoutBuilder`.
- [ ] Add the instrument to the rack registry so it can be instantiated from the UI.

### 2. Strings

- [ ] Add all user-visible labels, tooltips, and error messages via the l10n workflow (see [l10n skill](../gf-l10n/SKILL.md)).

### 3. Tests

- [ ] Unit-test the audio logic (parameter math, note generation, envelope shapes) in `test/instruments/<instrument_name>/`.
- [ ] Widget-test the UI panel at multiple viewport widths.

### 4. Changelog

- [ ] Record the new instrument under `### Added` in both changelogs (see [changelog skill](../gf-changelog/SKILL.md)).

## Key packages

| Package | Purpose |
|---|---|
| `packages/grooveforge_plugin_api` | GFPA interfaces — implement these |
| `packages/grooveforge_plugin_ui` | Shared UI widgets (RotaryKnob, GFParameterKnob, …) |
| `packages/flutter_midi_pro` | MIDI note I/O |
| `packages/flutter_vst3` | VST3 host FFI bridge (if the instrument wraps a VST3 plugin) |

## Audio-thread constraints (summary)

- No `new`, no `List.filled` with growable=true, no `print`, no `Future`, no lock acquisition in the audio callback.
- Pass parameter changes from UI to audio via `ValueNotifier` callbacks or atomic writes only.
- Pre-allocate all buffers during `initialize()`, not during `process()`.
