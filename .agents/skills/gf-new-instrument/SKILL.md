---
name: gf-new-instrument
description: Scaffold a new GrooveForge instrument, effect, or MIDI FX plugin — creates the Dart class, UI panel, l10n keys, tests, and changelog entry.
argument-hint: "<instrument-name> [instrument|effect|midi-fx]  e.g. theremin instrument"
allowed-tools: Read, Edit, Write
context: fork
---

## Information gathering — ALWAYS do this first

Before writing any code, Claude **must** have clear answers to every item below. If the user's initial request does not cover all of them, **ask** — do not guess or assume defaults silently.

| # | Question | Why it matters | Example answer |
|---|---|---|---|
| 1 | **Name** — what is the instrument called? | Determines directory, class prefix, l10n key prefix | `theremin` |
| 2 | **Type** — instrument, effect, or MIDI FX? | Selects the GFPA interface (see table below) | `instrument` |
| 3 | **Musical purpose** — what does it do, in one sentence? | Drives the class doc-comment and changelog entry | "Monophonic pitch-controlled synth played by dragging a finger along a touch surface" |
| 4 | **Parameters** — what knobs/sliders does the user control? | Defines `GFPluginParameter` list and UI panel layout | `volume`, `waveform` (sine/saw/square), `vibrato depth`, `portamento speed` |
| 5 | **Audio source** — does it generate sound internally, process incoming audio, or transform MIDI? | Confirms the GFPA interface choice and signal routing | "Generates audio from an internal oscillator" |
| 6 | **Native DSP?** — does it need C++ for real-time performance? | Determines whether to scaffold a `.gfpd` bundle | "No, Dart is fast enough for a single oscillator" |
| 7 | **Reference** — is there a real-world instrument or plugin it's inspired by? | Helps Claude make informed design choices | "Inspired by the Moog Theremini" |

### How to ask

If the user provides only a name (e.g. `/gf-new-instrument kalimba`), respond with something like:

> Great — I'll scaffold a **Kalimba** plugin. Before I start, a few quick questions:
> 1. Is this an **instrument** (MIDI → audio), an **effect** (audio → audio), or a **MIDI FX** (MIDI → MIDI)?
> 2. What does it do musically? (e.g. "Sample-based kalimba with per-key panning and a resonance knob")
> 3. What parameters should the user control? (volume, tuning, resonance, …)
> 4. Does it need native C++ DSP or is Dart sufficient?
> 5. Any real-world inspiration? (helps me pick the right approach)

Adapt the questions: skip any that are already answered by the user's initial request. The goal is to have all 7 items covered before writing the first line of code.

---

## Arguments

- `<instrument-name>` — required. Used as the directory name and class name prefix (e.g. `theremin` → `ThereminPlugin`, `theremin_panel.dart`).
- `[type]` — optional. One of `instrument`, `effect`, `midi-fx`. Defaults to `instrument` if not provided.

---

## Choosing the right GFPA interface

| Interface | Input | Output | Use for |
|---|---|---|---|
| `GFInstrumentPlugin` | MIDI IN | AUDIO OUT | Synthesizers, samplers, drum machines |
| `GFEffectPlugin` | AUDIO IN | AUDIO OUT | Reverb, delay, EQ, compressor, distortion |
| `GFMidiFxPlugin` | MIDI IN | MIDI OUT | Arpeggiator, chord harmonizer, quantizer, transposer |
| `GFAnalyzerPlugin` | AUDIO IN | Visual data | Spectrum analyzer, oscilloscope, VU meter |

---

## Checklist

### 1. Dart/Flutter side

- [ ] Create `lib/instruments/<instrument_name>/` directory.
- [ ] Implement the instrument class extending or composing the relevant GFPA interface from `packages/grooveforge_plugin_api/` (see table above).
- [ ] Keep the audio callback allocation-free — no `new`, no `List.filled` with `growable: true`, no `print`, no `Future`, no lock acquisition inside `process()` (see [audio-safety skill](../gf-audio-safety/SKILL.md)).
- [ ] Create a corresponding UI widget in `lib/instruments/<instrument_name>/<instrument_name>_panel.dart`.
- [ ] Make the UI panel responsive — support at least `desktop`, `tablet`, and `phone` form factors using `LayoutBuilder` (breakpoints: ≥1280 desktop, 900–1279 tablet landscape, 600–899 tablet portrait, <600 phone).
- [ ] Add the instrument to the rack registry so it can be instantiated from the UI.

### 2. Strings

- [ ] Add all user-visible labels, tooltips, and error messages via the l10n workflow (see [l10n skill](../gf-l10n/SKILL.md)).
- [ ] Run `/gf-l10n` after implementing the UI to catch any missed hardcoded strings.

### 3. Native DSP (optional)

If the instrument requires C++ DSP (e.g. for real-time synthesis on Android/Linux where Dart latency is too high):

1. Add a `<instrument_name>.gfpd` bundle under `assets/plugins/`.
2. Implement the DSP in `native_audio/<instrument_name>_dsp.c` (or `.cpp`).
3. Declare the bundle in `pubspec.yaml` under `flutter.assets`.
4. Load via `GFpaPluginLoader.fromAsset(context, 'assets/plugins/<name>.gfpd')`.

### 4. Tests

- [ ] Unit-test the audio logic (parameter math, note generation, envelope shapes) in `test/instruments/<instrument_name>/`.
- [ ] Widget-test the UI panel at multiple viewport widths.

### 5. Changelog

- [ ] Run `/gf-changelog` to record the new instrument under `### Added` in both changelogs.

---

## Key packages

| Package | Purpose |
|---|---|
| `packages/grooveforge_plugin_api` | GFPA interfaces — implement these |
| `packages/grooveforge_plugin_ui` | Shared UI widgets (RotaryKnob, GFParameterKnob, …) |
| `packages/flutter_midi_pro` | MIDI note I/O |
| `packages/flutter_vst3` | VST3 host FFI bridge (if the instrument wraps a VST3 plugin) |

---

## Audio-thread constraints (summary)

- No `new`, no `List.filled` with `growable: true`, no `print`, no `Future`, no lock acquisition in the audio callback.
- Pass parameter changes from UI to audio via `ValueNotifier` callbacks or atomic writes only.
- Pre-allocate all buffers during `initialize()`, not during `process()`.

```dart
// ✅ Correct pattern — allocate once, reuse every callback
late final Float64List _outputBuffer;

void initialize(int bufferSize) {
  _outputBuffer = Float64List(bufferSize); // OK: initialize() is not the audio thread
}

void process(AudioBuffer out) {
  // Write into _outputBuffer — no allocation here
  for (int i = 0; i < out.frameCount; i++) {
    _outputBuffer[i] = _generateSample();
  }
}
```

---

## Required l10n keys reminder

After implementing the UI, run `/gf-l10n` to add all new string keys. Then run `/gf-changelog` to record the new instrument. Do not end the session without completing both.
