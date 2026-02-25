# Yakalive Features

Yakalive Synthesizer is packed with dynamic, performance-oriented features designed to turn a standard MIDI controller into a powerful, multi-timbral workstation.

## Core Audio & Architecture

*   **Cross-Platform Low Latency**: Achieves native-level zero-latency playback across operating systems.
    *   *Android*: Utilizes Google's ultra-low latency `Oboe` engine.
    *   *Apple*: Runs natively on `AVFoundation`.
    *   *Linux*: Orchestrates a background ALSA `fluidsynth` CLI process capturing direct inputs for desktop-grade performance.
*   **16-Channel Multi-timbral Engine**: A robust state manager tracks 16 independent MIDI channels. Each channel holds its own assigned Soundfont, Program Patch, Bank MSB, and performance settings (like Scale Lock).
*   **Multiple Soundfont Management**: Load multiple `.sf2` files into memory simultaneously. Seamlessly assign different instruments from different files to your 16 channels.

## Performance Tools

### Advanced CC Mapping
Map your hardware's physical knobs, sliders, pads, and ribbons to General MIDI effects or custom Yakalive commands.
*   **Standard MIDI Effects**: Volume, Expression, Reverb, Chorus, Pan, etc.
*   **Custom System Actions**:
    *   `Next/Prev Soundfont`
    *   `Next/Prev Program Patch`
    *   `Absolute Patch Sweep` (map a knob directly to sweep instruments 0-127)
    *   `Next/Prev Bank`
*   **Advanced Routing**: Map a CC control to affect the *Same Channel*, *All Channels (Omni)*, or a specific hardcoded *Target Channel*.

### Interactive Dashboard UI
*   A 16-card grid dashboard actively animates and flashes borders in real-time on channels receiving MIDI data. 
*   Tap on any channel to instantly open the instrument assignment dialogue and tweak patches on the fly.
*   Changes are persisted instantly across sessions via asynchronous local storage.

## Music Theory & Assistance

### Real-Time Chord Detection
*   Yakalive actively listens to the notes played on each channel and analyzes them using advanced interval and bitmask logic.
*   The UI displays exactly what chord you are currently holding down in real-time (e.g., `Cmaj7`, `F#m11`, `G7b9`).
*   **Sustain Memory**: Even after releasing the keys, the last detected chord remains visible on screen (dimmed) as a helpful reference point.

### Scale Snapping (Scale Lock)
*   **Lock to the Groove**: By tapping the chord display in the UI (or pressing a dedicated CC mapped pad), you can "Lock" the channel to the last detected chord.
*   **Automatic Correction**: Once locked, any "wrong" notes you play outside of that chord's harmonious scale will be automatically and mathematically snapped to the nearest correct scale degree before touching the synthesizer.
*   **Multiple Modes**: Choose exactly how you want your notes to snap by selecting a `ScaleType` (Standard, Blues, Pentatonic, Dorian, Harmonic Minor, etc.).
*   **Overlapping Polyphony Safeties**: The audio engine tracks individual physical key "ownership" over logical snapped notes, allowing you to freely slide across the keyboard. The system guarantees clean articulation, instantly cutting and re-triggering overlapping notes without premature muting.
