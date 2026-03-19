# GrooveForge Features

GrooveForge was mainly developed as a tool to **learn scales** through the **Jam Mode** plugin: play a chord or bass note on a master instrument and all connected keyboards lock to that scale, with wrong notes snapped to the nearest degree and key highlighting as visual feedback. From that core, it grew into a full cross-platform music workstation: a plugin rack with multi-timbral synthesis, **VST3 hosting** (desktop), a **MIDI looper**, and built-in instruments such as the vocoder, Stylophone, and Theremin. It runs on Linux, macOS, Windows, Android, and as a web app (WASM).

---

## Platform & Deployment

*   **Desktop (Linux, macOS, Windows)**  
    Full support: FluidSynth synthesis, Vocoder (native C/FFI), VST3 plugin hosting, ALSA (Linux) / CoreAudio (macOS) / WASAPI (Windows) audio. Linux uses a background FluidSynth CLI process for low latency; macOS and Windows use in-process engines.

*   **Android**  
    GrooveForge Keyboard with SoundFont and Vocoder, Stylophone, Theremin (including CAM mode), Jam Mode, MIDI Looper, and external MIDI. VST3 hosting is desktop-only. Uses Oboe for low-latency audio.

*   **iOS**  
    Unsupported for now: the iOS build has never been tested.

*   **Web (WASM)**  
    Flutter web build deployable to GitHub Pages. SF2 playback via a SpessaSynth JavaScript bridge; Stylophone and Theremin use the Web Audio API. Project “Save As…” triggers a browser download of a `.gf` file. No persistent project storage; each session starts from defaults.

---

## Plugin Rack & Patch View

*   **Dynamic Rack**  
    An ordered, drag-and-drop list of plugin slots. Add, remove, and reorder slots at any time. Each slot has its own MIDI channel (or shared channel 0 for MIDI FX like Jam Mode and Looper).

*   **Add Plugin Sheet**  
    Choose from: GrooveForge Keyboard, Virtual Piano, Vocoder, Stylophone, Theremin, Jam Mode (single instance), MIDI Looper (single instance), or Browse VST3 (desktop only).

*   **Back-of-Rack Patch View**  
    Toggle via the cable icon in the app bar. Each slot shows a rear panel with coloured jacks: MIDI IN / MIDI OUT, Audio IN L/R, Audio OUT L/R, Send/Return, and Data (chord/scale for Jam Mode). Cables are drawn as bezier curves; long-press an output to start a cable, drop on a compatible input to connect. Tap a cable to disconnect.

*   **Audio Graph**  
    A directed graph validates port compatibility, prevents duplicate edges, and detects cycles. MIDI and audio routing are persisted in `.gf` project files and restored on load.

---

## Built-in Instruments & Plugins

### GrooveForge Keyboard

*   **Multi-timbral engine**  
    Up to 16 independent MIDI channels, each with its own SoundFont (`.sf2`), bank, and program patch. Load multiple soundfonts and assign different instruments per channel.

*   **Per-slot Vocoder**  
    Optional vocoder on each keyboard slot: mic input shapes a carrier (Saw, Square, Choral, or Natural/PSOLA “autotune” mode). Pitch bend and vibrato (CC#1) supported. Mic gain and device are configurable in the audio settings bar or Preferences.

*   **Per-slot keyboard config**  
    Tap the tune icon (⊞) next to the MIDI channel badge to set visible key count, key height (Compact / Normal / Large / Extra Large), vertical/horizontal gesture actions (pitch bend, vibrato, glissando), and aftertouch destination CC. Stored in the project file.

### Virtual Piano

*   **On-screen piano, no built-in sound**  
    A rack slot with a touch keyboard and MIDI IN / MIDI OUT / Scale IN jacks. Notes and expression (pitch bend, CC) are sent only through cables—e.g. to a GF Keyboard, VST3, or Looper. Ideal for driving other instruments with scale locking (Jam Mode → Scale IN).

*   **Scale locking**  
    When a Jam Mode Scale OUT (or other scale source) is wired to Scale IN, the keyboard highlights allowed notes and snaps played notes to the scale.

### Vocoder (GFPA)

*   **Dedicated slot**  
    Own MIDI channel, on-screen piano, and rear-panel jacks. Multiple vocoder slots can coexist.

*   **Waveforms**  
    Saw, Square, Choral, and Natural. Natural mode uses a PSOLA pitch shifter (autotune-style) that preserves voice timbre instead of the filterbank.

*   **Pitch bend & vibrato**  
    MIDI pitch bend (±2 semitones) and CC#1 (mod wheel) for vibrato depth. Same per-slot keyboard config as GF Keyboard and Virtual Piano.

### Stylophone (GFPA)

*   **Monophonic 25-key chromatic strip**  
    Four waveforms (SQR, SAW, SIN, TRI), click-free legato, octave shift ±2. VIB button toggles a 5.5 Hz ±0.5-semitone LFO (tape wobble). MUTE silences the built-in synth while MIDI OUT keeps sending note data.

*   **MIDI OUT**  
    Connect to a GF Keyboard, VST3, or Looper in the patch view.

### Theremin (GFPA)

*   **Touch pad**  
    Vertical position = pitch, horizontal = volume. Native C sine oscillator with portamento (~42 ms), 6.5 Hz vibrato LFO (0–100 %), configurable base note and range. Pad height (S/M/L/XL) and MIDI OUT / MUTE behave like the Stylophone.

*   **CAM mode (Android, iOS, macOS)**  
    Hand proximity via front camera (autofocus or brightness/contrast fallback) controls pitch. Live semi-transparent preview behind the orb; selfie-mirrored on mobile. Permission described in the privacy policy.

### Jam Mode (GFPA, single instance)

*   **Master → targets**  
    One Jam Mode slot selects a master channel (e.g. a keyboard or Virtual Piano). When the master plays, all target slots (keyboards, vocoders) lock to the same scale. Multiple targets per Jam slot.

*   **Detection**  
    Chord mode: real-time chord detection drives the scale root. Bass note mode: lowest held note on the master sets the root (e.g. walking bass).

*   **Scale types**  
    Standard, Jazz, Blues, Rock, Pentatonic, Dorian, Mixolydian, Harmonic Minor, Melodic Minor, Whole Tone, Diminished, Asiatic, Oriental, Classical. Scale name and type are shown on a live LCD; scale type is selectable in the slot.

*   **BPM lock**  
    Optional sync (Off / 1 beat / ½ bar / 1 bar) so scale root updates only on beat boundaries. Uses the global transport BPM.

*   **Pin below transport**  
    Compact one-line strip (slot name, ON/OFF LED, scale LCD) under the transport bar for quick access without scrolling.

### MIDI Looper (single instance)

*   **Multi-track MIDI looper**  
    MIDI IN / MIDI OUT jacks; record from any connected source (GF Keyboard, Virtual Piano, Stylophone, Theremin, external MIDI), loop back to instruments, overdub additional layers.

*   **Transport**  
    REC, PLAY, OVERDUB (layers icon), STOP, CLEAR. State LCD; per-track chord grid (scrollable bar cells). Mute, reverse (R), and speed (½× / 1× / 2×) per track. Record-stop quantization (off / 1/4 / 1/8 / 1/16 / 1/32) per track; Q chip in the transport strip.

*   **Persistence**  
    Tracks and chord grids saved in `.gf` under `looperSessions`. Global CC mapping for Looper actions (record, play, overdub, stop, clear) and “pin below transport” strip.

### VST3 Hosting (desktop)

*   **Load any .vst3**  
    “Browse VST3” in the Add Plugin sheet. Parameters shown as rotary knobs by category; native plugin editor opens in a separate window (e.g. X11 on Linux).

*   **Audio routing**  
    Draw audio cables in the patch view; source plugin output can feed another plugin’s input instead of the master bus. Topological processing order.

*   **Transport**  
    BPM, play/stop, and beat position are sent to VST3 so tempo-synced effects stay in time.

---

## Transport & Global Controls

*   **Transport bar**  
    BPM (editable, ± nudge, scroll-wheel), Tap Tempo, ▶ Play / ■ Stop, time signature, beat-pulse LED, audible metronome toggle. State saved in the project.

*   **Audio settings bar (collapsible)**  
    Below the transport: FluidSynth gain (Linux), mic sensitivity, mic device, output device (Android). Chevron toggles visibility.

---

## Music Theory & Scale Locking

*   **Real-time chord detection**  
    Per-channel analysis of held notes; UI shows the current chord (e.g. Cmaj7, F#m11). “Sustain memory”: last chord stays visible (dimmed) after release.

*   **Scale lock (classic)**  
    On a keyboard or Virtual Piano slot, tap the chord display (or use a mapped CC) to lock to the last detected chord. New notes outside the scale are snapped to the nearest scale degree. Scale type (Standard, Blues, Pentatonic, etc.) is selectable per channel. Overlapping polyphony is tracked so glissandos articulate cleanly.

*   **Jam Mode scale lock**  
    Same snapping and scale types, but driven by the Jam Mode master (chord or bass note). Piano key highlighting (root, in-scale, wrong notes) and optional borders/dimming are configurable in the Jam Mode slot or Preferences.

---

## CC Mapping & Hardware

*   **Map hardware to MIDI or actions**  
    In Preferences, assign physical CCs to General MIDI effects (volume, expression, reverb, pan, etc.) or to GrooveForge actions: Next/Prev Soundfont, Next/Prev Program, Absolute Patch Sweep, Next/Prev Bank, Global Scale Cycle, Looper Record/Play/Overdub/Stop/Clear, Mute/Unmute Channels (with channel checklist). Same channel, omni, or fixed target channel.

*   **External MIDI**  
    Connect controllers; notes and expression (pitch bend, CC, channel pressure) flow through the rack and cables. Virtual Piano and other slots can relay MIDI to VST3, Looper, or instruments.

---

## Projects & Persistence

*   **.gf project files**  
    JSON format: rack plugins, audio graph, transport (BPM, time sig, metronome), looper sessions, VST3 parameter snapshots, per-slot keyboard and Jam/Looper config. Open/Save/Save As in the project menu.

*   **Autosave**  
    Last session is autosaved on change (desktop and mobile); reloaded on next launch. Web has no persistent storage; use “Save As…” to download a `.gf` file.

*   **Save As on all platforms**  
    Android and web use the file picker with project bytes: on web a download is triggered; on Android the file is written to the chosen location. Linux/macOS/Windows use the native save dialog and path.

---

## UI & Preferences

*   **Rack dashboard**  
    Slots show active state (e.g. blue glow when notes are playing or Looper is playing back). Tap a slot to open its panel or patch assignment.

*   **Preferences**  
    Global defaults for key count, key height, gesture actions, aftertouch CC; MIDI device list and CC mapping; FluidSynth gain (Linux); mic and output devices; Jam Mode borders and wrong-note highlighting. Labels indicate when a setting is overridable per slot.

*   **Localisation**  
    English and French via Flutter `AppLocalizations`; all user-visible strings are localised.

---

*Last updated: 2026-03-19*
