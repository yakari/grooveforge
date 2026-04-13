# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [X.x.x]

### Fixed
- **Linux — Audio Looper records silence when a Vocoder is cabled to it**. When the Vocoder was wired into an audio looper slot on Linux/macOS, the looper recorded silence or garbled audio instead of the vocoder's output. Root cause: the JACK callback registers the vocoder as both a **master-render contributor** (so you can hear it through the main output) and an **audio-looper source** (so the looper captures its audio). Both registrations live on the same audio thread, so `_vocoder_render_block_impl` in [native_audio/audio_input.c](native_audio/audio_input.c) was called twice per audio block: once via master render, once via the looper source pull. Each call advanced shared DSP state — voice envelopes, LFO phase, ACF pitch-detection cursor, filter-bank biquads, oscillator `natReadPos` — so the second call read state already mutated by the first and produced a different, state-corrupted output. The looper recorded that second-call output. Master output remained audible (the first call) but the looper captured nonsense.
  - Fix: per-block output cache inside `_vocoder_render_block_impl`. On every call, the function timestamps itself via `clock_gettime(CLOCK_MONOTONIC)`. If the previous call was within 1 ms (shorter than any realistic JACK block period but vastly longer than the microsecond gap between master and looper pulls within one callback) and the frame count matches, the function returns the cached stereo output without touching DSP state. The cache is a plain `float[4096]` per channel — covers every practical JACK block size on Linux desktop. Master-render and looper-source both see identical audio; DSP state advances exactly once per block. No routing layer changes, no new atomics, no cross-module plumbing.
  - Cache window tuning: 1 ms is the smallest value that safely covers intra-callback jitter while still invalidating on the next real block (≥ 1.33 ms at 64 frames / 48 kHz, the smallest realistic JACK buffer). Frame sizes above 4096 fall through to a fresh compute every time — no realistic buffer reaches that, but if one does, the double-call bug re-emerges gracefully rather than silently returning stale audio.
  - An earlier attempt at this session tried to fix the bug in the Dart routing layer by removing the vocoder from master render when it was wired only to a looper. That made the vocoder **completely inaudible** whenever the looper clip was IDLE (waiting to be armed), because the looper source pull only fires during the RECORDING state — there was no always-on path driving the vocoder DSP. Reverted immediately. The C-side cache is the correct fix because it works regardless of which render path calls the function.

### Added
- **Vocoder NATURAL mode — loop-resample rewrite** (all platforms). The old PSOLA grain engine in [native_audio/audio_input.c](native_audio/audio_input.c) produced audibly choppy output whenever the MIDI target frequency was lower than the detected mic voice pitch, because the grain retrigger period (`SR/targetHz`) exceeded the Hanning grain length (2 × detected period), leaving silence between grains. Replaced with a **looped voice-grain resampler**:
  - **Capture step** (`capture_natural_loop`). When the ACF pitch detector's correlation crosses the confidence gate (same `g_naturalMaxCorr * 0.8f || > 0.5f` rule as before), a number of pitch-validated mic samples equal to `numPeriods × detectedLag` is copied into `g_natLoopBuf[]`, where `numPeriods` is the largest integer such that the result fits in the 1024-sample buffer capacity. **Integer-period looping is the key**: for a periodic waveform, sample N·P equals sample 0 by definition, so the seam is continuous by construction and no cross-fade is needed. Captures that can't fit at least 2 full periods (very-low-pitch voices ≲ 95 Hz) are rejected so the renderer doesn't play a single-cycle buzz. RMS-normalised to ~0.4 for consistent filter-bank carrier level.
  - **Render step** (NATURAL branch in `renderOscillator`). Each polyphonic voice keeps a fractional `natReadPos` cursor into the captured loop. The cursor advances by `targetHz / capturedHz` samples per output sample, so a captured voice at 200 Hz played at a MIDI target of 100 Hz advances by 0.5 samples/sample (octave down) and at 400 Hz by 2.0 (octave up). Linear interpolation between adjacent samples — fast and more than good enough for the 80–1000 Hz voice range. The cursor wraps at the per-loop `g_natLoopLen` (not the compile-time buffer size) and defensively clamps against mid-sample length changes published by the capture thread.
  - **Silent startup** — when no loop has been captured yet (no ACF convergence since device init) the branch outputs zero. Previously the PSOLA engine would output whatever stale data was left in the overlap-add buffer, which could be a soft audible "tail" from a prior session.
  - **Memory reclaimed**: removed the per-voice `oaBuffer[PSOLA_OA_SIZE=1024]` float array from the `Oscillator` struct, saving 4 KB × 16 voices = 64 KB of static state. Replaced with a single `float natReadPos` per voice. Also removed the now-unused `pulseTimer` and `oaCursor` fields.
  - **Design decision log** in [docs/dev/ROADMAP.md](docs/dev/ROADMAP.md) under "NATURAL vocoder mode — reality check". The roadmap originally called for replacing PSOLA with `gf_pv_pitch_shift` from the phase vocoder library, but once we mapped what NATURAL mode actually does — generate a sustained MIDI-pitched tone from a short captured mic snippet, potentially seconds after the mic went silent — we recognised a streaming phase vocoder is the wrong tool for that workload. The phase vocoder library remains in place for its real use case (the forthcoming Audio Harmonizer GFPA effect). The first attempt at the loop-resample approach used a fixed 1024-sample loop with a linear cross-fade at the seam and sounded objectively worse than PSOLA — both decisions were wrong (the cross-fade manufactured its own discontinuity, and an arbitrary loop length produced a ~47 Hz subharmonic modulation on top of the fundamental). Integer-period looping without cross-fade is the correct technique.
- **Audio Looper — tempo-synced playback via phase vocoder** (Android, Linux, macOS). A loop recorded at one transport BPM now plays back at the current BPM without pitch change. Previously the looper advanced one recorded sample per output frame, so a 120 BPM loop played at 140 BPM either stayed at 120 BPM (drifted out of sync with the transport) or — if the host retimed it via sample-rate-style resampling — shifted up in pitch. With the phase vocoder engaged, a 120 BPM drum loop played back at 140 BPM actually comes out 16.7% shorter while the snare hits and cymbal shimmer stay at their original pitch.
  - **Engaged automatically** whenever `|1 − recordBpm/currentBpm| ≥ 0.005` (~0.6 BPM at 120). Inside that dead zone the existing zero-cost sample-per-sample fast path runs unchanged, so clips played at their recorded tempo pay zero CPU overhead and are bit-identical to the previous release.
  - **Per-clip vocoder state** lives inside `ALooperClip`: a `gf_pv_context*` plus interleaved in/out scratch buffers, all allocated on the Dart thread inside `dvh_alooper_create` so the audio thread never sees a `malloc`. `gf_pv_reset` is called via an atomic `pvNeedsReset` flag whenever the clip (re-)enters the PLAYING state from any other state — external `dvh_alooper_set_state`, internal RECORDING→PLAYING and STOPPING→PLAYING transitions inside `dvh_alooper_process`, the overdub auto-return, and `dvh_alooper_clear_data`. The flag is cleared with an `exchange` so the reset happens at most once per transition.
  - **Feed/drain loop** in [audio_looper.cpp](packages/flutter_vst3/dart_vst_host/native/src/audio_looper.cpp): `_processPlayingStretched` alternates between draining any output the vocoder has already queued (via `_drainPvInto` → one `gf_pv_process_block` call with null input) and pushing one analysis hop of clip audio (via `_feedPvOneHop` → interleave + `gf_pv_process_block` with zero output capacity). A safety bound of 64 iterations prevents any pathological cold-start case from hanging the audio thread. Reverse playback is honoured by mirroring the read index against the loop length before the interleave step.
  - **FFT size 2048, hop 512** — good spectral resolution for music without excessive latency. First-block ring-in artifact (~46 ms at 44.1 kHz) is a known limitation tracked for session 2b; drum loops will have a very slight fade-in over the first two beats immediately after entering PLAYING, then play cleanly.
  - **Build wiring**: `gf_phase_vocoder.c` is compiled into three targets via relative paths from the repo-root source of truth — [linux/CMakeLists.txt](packages/flutter_vst3/dart_vst_host/linux/CMakeLists.txt) and [macos/CMakeLists.txt](packages/flutter_vst3/dart_vst_host/macos/CMakeLists.txt) for `libdart_vst_host`, and [android/.../cpp/CMakeLists.txt](packages/flutter_midi_pro/android/src/main/cpp/CMakeLists.txt) for `libnative-lib`. Both Linux and macOS CMakeLists now enable the `C` language alongside `CXX`/`OBJCXX` so the `.c` file builds with the platform C compiler.
  - **Not wired into the Dart layer yet** — there is no new FFI symbol or toggle. Tempo sync is implicitly on whenever stretching is needed, which matches the expected UX for a looper synced to the host transport. An opt-out (for users who want pitch-shifted playback as a creative effect) can be added later via a `dvh_alooper_set_tempo_sync` flag if requested.

### Architecture
- **Phase vocoder DSP library** (foundation for audio looper tempo sync, harmonizer effect, and a fix for the vocoder's choppy NATURAL mode). New allocation-free C module [native_audio/gf_phase_vocoder.h](native_audio/gf_phase_vocoder.h) + [gf_phase_vocoder.c](native_audio/gf_phase_vocoder.c) implementing a phase-locked short-time Fourier transform: spectral peaks are detected per analysis frame, their instantaneous-frequency phase advance is computed from the measured phase increment, and the phases of surrounding bins are locked to the peak's rotation (Laroche & Dolson 1999). This preserves vertical phase coherence across partials and keeps transients crisp under stretching — important for drum loops where a classic phase vocoder smears hits. Includes a self-contained iterative radix-2 Cooley-Tukey complex FFT with precomputed twiddles and bit-reversal table (no KissFFT / pffft dependency yet — can be swapped later if profiling demands it). Public API: `gf_pv_create` / `gf_pv_destroy` / `gf_pv_reset` / `gf_pv_set_stretch` / `gf_pv_set_pitch_semitones` / `gf_pv_process_block`, plus an offline helper `gf_pv_time_stretch_offline`. The context owns all buffers (FFT work, mag/phase scratch, per-channel overlap-add tails and ring buffers), so `gf_pv_process_block` is safe to call from the audio thread. OLA compensation is computed from the actual analysis/synthesis window overlap at context creation, so any valid hop size (≤ fft_size/4) yields unity gain through the analysis/synthesis chain. Compiled into `libaudio_input.so` on all desktop platforms; not yet wired into any consumer — the looper and vocoder integrations land in follow-up versions.
- **Phase vocoder offline smoke test** [native_audio/gf_pv_smoke_test.c](native_audio/gf_pv_smoke_test.c): generates a 4-bar 120 BPM loop (440 Hz sine plus per-beat click), time-stretches to 140 BPM via `gf_pv_time_stretch_offline`, writes source and stretched WAVs under `/tmp`, and asserts three properties: duration ratio within 5%, RMS gain drift within 3 dB, and 440 Hz DFT magnitude still dominant after stretching (pitch preservation). Built as a host-only CMake target; not included in Android/iOS builds.

## [2.12.6] - 2026-04-12

### Fixed
- **Android — GF Keyboard MIDI note latency and chord stagger**: playing a chord on the on-screen keyboard or a hardware MIDI controller used to stagger the notes by 3–9 ms each, and single notes felt noticeably "laggy" compared to the snappy Linux/macOS experience. Root cause: every `playNote` on Android went through three sequential Dart → Kotlin → `audioExecutor` → JNI round-trips (pitch bend reset, CC reset, note-on), which turned a 3-note chord into a 9–27 ms serialised burst. The underlying AAudio stream was already configured correctly (`AAUDIO_PERFORMANCE_MODE_LOW_LATENCY` + `AAUDIO_SHARING_MODE_EXCLUSIVE`, ~96–256 frames per burst) — the bottleneck was purely the method-channel dispatch. Two-part fix:
  - **Direct FFI into `libnative-lib.so` for the MIDI hot path.** New `extern "C"` exports `gf_native_note_on / note_off / cc / pitch_bend` in [native-lib.cpp](packages/flutter_midi_pro/android/src/main/cpp/native-lib.cpp) each do a `synths[sfId]` lookup and a single `fluid_synth_*` call. Dart reaches them via `DynamicLibrary.lookupFunction` through the existing `_looperLib` handle in [audio_input_ffi_native.dart](lib/services/audio_input_ffi_native.dart) (same `libnative-lib.so` already used for the audio looper symbols since v2.12.3). `audio_engine.dart` `playNote` / `stopNote` / `_sendControlChange` / `_sendPitchBend` now branch on Android to call `AudioInputFFI.gfNativeNoteOn` etc. directly, bypassing `flutter_midi_pro`'s method channel → Kotlin audioExecutor → JNI chain. Per-note latency drops from ~3 ms (best case) / ~9 ms (with the two resets) to ~0.3 ms — parity with the Linux/macOS direct-FFI path through `libaudio_input.so`. Chord notes now reach `fluid_synth_noteon` synchronously inside the same Dart microtask, so they are effectively simultaneous (well under human perception threshold).
  - **Dropped the pre-emptive pitch bend / modulation CC resets in `playNote`.** These two calls fired before every single note-on to put the synth state back at neutral, but 99% of the time the state was already neutral because nobody was actively bending or modulating. On Android they were the single biggest latency contributor (6 of the 9 ms per chord note). On Linux they were cheap direct-FFI calls but still unnecessary work. The resets are now commented out with a clear restore recipe in case a note-on is ever heard inheriting stale bend/mod state — and an alternative implementation (track last-sent values in `ChannelState`, fire only when non-neutral) is documented inline for the conditional-restore case.
  - **`flutter_midi_pro` still owns the synth lifecycle.** The method-channel JNI entry points (`loadSoundfont` / `unloadSoundfont` / `selectInstrument` / `setGain`) remain the single source of truth for `synths[]`; the new FFI exports are a pure READ + `fluid_synth_*` call. FluidSynth is internally thread-safe between note events and `fluid_synth_process()` running on the audio thread, and soundfont unload blocks on `oboe_stream_remove_synth` which drains any in-flight audio callback, so the small race window between `synths.find` and the direct call is astronomically unlikely. The existing JNI entry points follow the same lock-free pattern and have been stable for months.

## [2.12.5] - 2026-04-12

### Added
- **Audio Looper — Stylophone and Vocoder now routable on Android**: cabling a Stylophone or Vocoder slot to an audio looper, or into any GFPA effect insert chain, now works on Android. Previously both instruments ran on private `miniaudio` devices that never reached the shared Oboe bus, so they showed up in the source selector / back panel but silently recorded silence — the last remaining "known limitation" from v2.12.4's cabled-input routing matrix. Both instruments now follow the same pattern the Theremin has used since v2.12.0: when a slot enters the rack, `NativeInstrumentController` enables capture mode on the private device (which silences miniaudio playback) and registers a `*_bus_render` function on the shared Oboe bus (slot 101 for stylophone, slot 102 for vocoder). Mic input for the vocoder stays on the existing miniaudio capture device — only the playback side moves onto the bus. Teardown reverses the order (remove bus source first, then disable capture mode) to avoid dereferencing freed DSP state from the audio callback.
- **Audio Looper — macOS VST3 plugin-source routing**: cabling a VST3 plugin's output into an audio looper slot now records the plugin's audio on macOS, matching the Linux behaviour. The macOS audio callback's looper fill loop previously iterated only the render-function source list — it called `dvh_alooper_get_plugin_source_count` just to include it in the "skip empty clips" guard but never read the plugin sources themselves, so any `VST3 → looper` cable silently recorded silence. Fixed by adding a second pass that resolves each clip's plugin-source ordinal back to a `void*` handle through `ordered[plugIdx]`, looks it up in the per-plugin `bufs` map that `_processPlugins` already fills, and sums the stereo output into the clip's private source buffer. Zero new allocations on the audio thread — the existing `bufs` map (already a per-callback heap churn point, tracked as a separate TODO) is reused. Defensive bounds-check on the ordinal so a stale cable-list reference from a mid-callback rack mutation cannot crash the callback.
- **Audio Looper — memory cap warning**: the audio looper engine now tracks total pool memory against a soft cap (default 256 MB) and surfaces a toast the first time the cap is crossed in a session, nudging the user to clear unused clips. The per-clip memory label in the volume row tints amber at ≥ 75% and red/bold at ≥ 90% of the cap so the approach to the ceiling is visible before the toast fires. **Not a hard cap** — recording continues past the threshold on purpose so a live performance never gets silently truncated. The warning re-arms when a clip is destroyed, so clearing memory and re-crossing produces a fresh toast.

### Fixed
- **Audio Looper — stopping a loop erased the recorded PCM before autosave could persist it**: the root cause of "the wav loop is saved but not loaded on reopen". User observation that nailed it: if the app was killed while the loop was **playing**, the clip restored correctly on next launch; if it was **stopped**, the clip came back as empty silence. The bug lived entirely inside `dvh_alooper_set_state` (audio_looper.cpp): the `ALOOPER_IDLE` transition zeroed `clip->length`, `loopLengthFrames`, and `loopLengthBeats`. Since IDLE is both the "paused, ready to play" state AND the "empty, ready to record" state, pressing Stop (which sends state=IDLE) was silently wiping the recorded length. The next autosave fired `_exportAudioLooperWavs`, read `alooperGetLength` → got 0 → skipped the export for that clip → the orphan-cleanup pass found the old `loop_$slotId.wav` on disk unreferenced and **deleted** it. Result: the clip JSON metadata survived (Dart side didn't know length was gone) but the sidecar was erased, so reload found no PCM.
  - Fixed in native: the `ALOOPER_IDLE` branch now only resets the playback cursor and the overdub-start marker. It no longer touches `length` or `loopLengthFrames`, so a stopped clip survives any number of autosave passes.
  - New C API `dvh_alooper_clear_data(idx)` provides the explicit "erase recorded audio" path previously implied by the IDLE transition. Called only by Dart's [AudioLooperEngine.clear] (the user-visible Clear button), never by stop/pause.
  - Dart `clear()` now calls `setState(IDLE)` followed by `clearData()` so the wipe semantic is preserved for the Clear button. The other callers of `setState(IDLE)` — `stop()`, `destroyClip()`, `finalizeLoad()`'s reinit loop — correctly no longer erase content.
  - FFI shims added in both `audio_input_ffi_native.dart` (Android path) and `dart_vst_host/lib/src/bindings.dart` + `host.dart` (desktop path). Matching no-op stub in `audio_input_ffi_stub.dart` for web.
  - Affects every platform equally — the bug was in shared C code. Desktop autosaves were quietly losing content on stop too; it was just less noticeable because desktop users rarely kill the app.
- **Audio Looper — `saveProjectAs` never wrote WAV sidecars**: the named "Save As" flow wrote the `.gf` JSON through `file_picker`'s `saveFile(bytes: ...)` path but then returned without ever calling `_exportAudioLooperWavs`, so reopening a project saved that way restored clip metadata but found an empty `.audio/` sidecar directory and played back silence. Fixed by following up a successful `saveProjectAs` with an explicit sidecar export at the returned path — but only when the path looks like a real filesystem path (starts with `/`). On Android vendors that return SAF content:// URIs from their save dialog, sidecars still can't be written; the method now logs a loud warning explaining that reopening will restore metadata only. A full fix for the SAF case needs a dedicated in-app project picker under `getApplicationDocumentsDirectory()` and is tracked separately.
- **Audio Looper — `memoryUsedBytes` returned 0 on Android**: the getter routed through `VstHostService.instance.host` which is null on Android, so the memory label always showed "0 KB" on that platform. Fixed by adding an `alooperMemoryUsed` FFI shim on `AudioInputFFI` and branching on `_useAndroidPath` inside the getter. Both paths now reach the same `dvh_alooper_memory_used` symbol (compiled into `libdart_vst_host.so` on desktop and `libnative-lib.so` on Android).
- **Audio Looper — `styloSetCaptureMode` missing from web stub**: pre-existing gap — the real FFI binding has always existed, but nothing on the non-web path called it until the stylophone Oboe-bus migration landed. The stub now has the method so the web build compiles when `NativeInstrumentController.onStylophoneAdded` reaches it.

### Diagnostics
- **Audio Looper — instrumented the load path**: `AudioLooperEngine.finalizeLoad`, `VstHostService.importAudioLooperWavs`, and `ProjectService._readGfFile` now emit `[ALOOPER]` / `VstHostService` / `ProjectService` debug prints showing the pending-json count, the `.gf` path passed through `setPendingGfPath`, the sidecar directory path and existence, per-clip WAV file existence checks, and the native `alooperLoadData` return code. Added while tracking down the "wav saved but not loaded" bug — kept in place because the load path is otherwise silent and debug-prints are the only way to diagnose similar issues without attaching a debugger.

### Architecture
- **`audio_input.c` — new bus-render trampolines**: `stylophone_bus_render(float*, float*, int, void*)` and `vocoder_bus_render(float*, float*, int, void*)`, both matching the `AudioSourceRenderFn` signature expected by `oboe_stream_add_source`. Each is a thin wrapper around the existing `*_render_block` implementations used by the desktop path; the `userdata` parameter is unused since both instruments have singleton DSP state. Matching `*_bus_render_fn_addr()` exports return the trampoline addresses as `intptr_t` for Dart FFI.
- **`AudioInputFFI` — new typed bindings**: `styloBusRenderFnAddr()` and `vocoderBusRenderFnAddr()` mirror the existing `thereminBusRenderFnAddr()` entry point. Matching no-op stubs added to `audio_input_ffi_stub.dart` for web compatibility.
- **`NativeInstrumentController` — `onStylophoneAdded/Removed` now register on the Oboe bus**: previously the stylophone just called `styloStart()` and played through its own miniaudio device. The method now also calls `styloSetCaptureMode(true)` + `oboeStreamAddSource(fn, kBusSlotStylophone)` on Android, mirroring the theremin pattern. Teardown order reversed (bus-remove before device-stop) for the same drain-wait reason.
- **`NativeInstrumentController.onVocoderAdded/Removed`** — new methods. The vocoder wasn't tracked by the controller before (it's a `GFpaPluginInstance`, not a "native instrument"), so these are pure routing switches: flip capture mode + register/unregister the bus source, without ever touching the mic capture device (that lifecycle is managed globally by `AudioEngine.startCapture/stopCapture`). On non-Android platforms the methods are no-ops because desktop drives the vocoder through the VstHost master-render list instead.
- **`RackState.addPlugin/removePlugin` + `SplashScreen` eager loop** — extended the existing stylophone/theremin `switch` block to cover `com.grooveforge.vocoder` so the new controller methods fire on every add/remove path, including projects reloaded from disk before the first frame renders.
- **`VstHostService._resolveAndroidBusSlotId`** — extended to return `kBusSlotStylophone` for stylophone slots and `kBusSlotVocoder` for vocoder slots. The audio looper's Android cabled-input resolver now handles all five supported upstream source types: GF Keyboard, Drum Generator, Theremin, Stylophone, Vocoder. Only VST3 plugins remain unsupported as upstream sources on Android — and Android doesn't host VST3 plugins at all, so that's a non-issue.

## [2.12.4] - 2026-04-12

### Added
- **Audio Looper — source selector**: the audio looper slot now has a compact "Source" dropdown above the waveform display. Users can pick any audio-producing slot in the rack (GF Keyboard, Drum Generator, Theremin, Stylophone, Vocoder, GFPA audio effects, VST3 instruments/effects) without flipping to the back panel and drawing a cable manually. Picking a source rewrites the audio cables: existing cables into the looper are cleared, and new `audioOutL → audioInL` + `audioOutR → audioInR` cables are drawn in one atomic operation. Picking "None" clears all cables. A "Multiple (N sources)" label is shown when the user has hand-wired several upstream slots from the back panel — the dropdown stays functional and overrides on the next selection. The selector derives its current state from the `AudioGraph` every rebuild, so there is no duplicated per-clip state to keep in sync with the back panel view. "Master mix" capture is deferred to a future milestone — it requires a new native routing kind.

### Fixed
- **Web build broken by `dart:ffi` import in `project_service.dart`** (regression from v2.12.3): the `_exportAudioLooperWavs` path added in v2.12.3 imported `dart:ffi` directly (for the `nullptr` sentinel and `Pointer<Float>.asTypedList` call), which `dart2js` and `dart2wasm` reject on the web target. The GitHub Actions `build web` job failed with `Dart library 'dart:ffi' is not available on this platform`. Fixed by introducing a new `AudioLooperEngine.wavExporter` callback (symmetric to the existing `wavImporter`) and moving the FFI plumbing into `VstHostService.exportAudioLooperWavs` — the latter already lives behind a conditional export that swaps in a no-op stub on web. `project_service.dart` now delegates through `engine.wavExporter` and no longer imports `dart:ffi`, `audio_input_ffi.dart`, or `wav_utils.dart`. Dead helper `_audioDir` removed.

## [2.12.3] - 2026-04-12

### Added
- **Audio Looper — WAV sidecar persistence on Android**: audio looper clips are now saved to and restored from `loop_{slotId}.wav` sidecar files inside the `.gf.audio/` directory on Android, matching the desktop behaviour. Previously `ProjectService._exportAudioLooperWavs` and `VstHostService.importAudioLooperWavs` both short-circuited on Android because they dispatched through a VST host that is null on that platform, so every recorded loop was lost on app restart.

### Fixed
- **Audio Looper — Android recording produced silent clips when cabled from a keyboard**: every call site of `VstHostService.syncAudioRouting` other than `RackState._onAudioGraphChanged` was calling it without the `keyboardSfIds` parameter. The default value is `const {}`, so on Android the new `_syncAudioLooperSourcesAndroid` helper couldn't resolve any keyboard slot to its Oboe bus ID — `_resolveAndroidBusSlotId` returned null for every GF Keyboard and Drum Generator, and the clip's bus source list stayed empty. The AAudio callback then saw `dvh_alooper_get_bus_source_count(c) == 0`, fed the clip a NULL source buffer, and `_recordSample` wrote zeros while the clip's `length` counter advanced normally. Result: the user saw "Cable an instrument to Audio IN" turn into a "recording" clip with the correct duration, but the PCM buffer was all zeros — playback was silent and the waveform preview stayed empty.
  - **`RackState.buildKeyboardSfIds`** (new public method): exposes the existing private `_buildKeyboardSfIds` builder so external call sites don't have to reimplement the channel → sfId lookup.
  - **Five call sites fixed**: two in [splash_screen.dart](lib/screens/splash_screen.dart) (the startup sync and the second sync after `initializeAudioEffects`), one in [audio_looper_slot_ui.dart](lib/widgets/rack/audio_looper_slot_ui.dart) `initState` post-frame callback, two in [vst3_slot_ui.dart](lib/widgets/rack/vst3_slot_ui.dart) (effect add + remove), and one in [rack_screen.dart](lib/screens/rack_screen.dart) new-project reset. All now pass `keyboardSfIds: rack.buildKeyboardSfIds()`.
  - **Defensive warning** in `VstHostService.syncAudioRouting` Android branch: `debugPrint`s a loud message when `keyboardSfIds` is empty but the rack contains `GrooveForgeKeyboardPlugin` slots. Surfaces the "caller forgot the parameter" mistake immediately instead of producing silent recordings.
- **Audio Looper — Android waveform preview and WAV export broken by `Pointer<Float>` dynamic dispatch**: the waveform preview showed "No audio recorded" after a successful recording, and `ProjectService._exportAudioLooperWavs` threw `NoSuchMethodError: Class 'Pointer<Never>' has no instance method '[]'` on every autosave. Three affected call sites, all the same underlying cause — both `FloatPointer.operator []` **and** `FloatPointer.asTypedList` are static extension methods on `Pointer<Float>`, so invoking them through a `dynamic`-typed receiver silently fails. The fix:
  - **New typed-list helpers** in `audio_input_ffi_native.dart`: `alooperGetDataAsListL(idx, length)` and `alooperGetDataAsListR(idx, length)` wrap the raw `Pointer<Float>` in a zero-copy `Float32List` view *inside* the FFI file (the one place in this subtree that is allowed to import `dart:ffi`). They return `null` when the native buffer is `nullptr` or the length is non-positive, making every caller's nullptr check trivial. Matching no-op stubs added to `audio_input_ffi_stub.dart`.
  - **Export path** (`project_service.dart._exportAudioLooperWavs`): now wraps the raw `Pointer<Float>` returned by `alooperGetDataL/R` in a `Float32List` via `ptr.asTypedList(length)` at the call site (desktop and Android) before handing the buffer to `writeWavFile`. The helper's `dataL`/`dataR` parameters are `dynamic` (intentionally, to keep `dart:ffi` out of `wav_utils.dart`), so a `Float32List` is the only type that safely supports `[]` indexing through dynamic dispatch. Plus defensive `nullptr` checks on both pointers.
  - **Waveform path** (`audio_looper_engine.dart.updateWaveform`): now calls `AudioInputFFI.alooperGetDataAsListL/R` on Android instead of routing through `VstHostService.instance.host` (which is null on Android). Previously bailed out early and left `clip.waveformRms` empty forever, so the UI rendered the empty-placeholder even though the clip had valid PCM. An earlier attempted fix tried to do the `asTypedList` wrap inside `audio_looper_engine.dart` through a `dynamic` helper — that silently failed for the same extension-dispatch reason. The new typed-list helpers on `AudioInputFFI` move the wrap to where `dart:ffi` is statically available.
- **Audio Looper UI — full l10n coverage (EN/FR)**: waveform placeholders (`Recording…`, `Cable an instrument to Audio IN`, `No audio recorded`), every transport-strip tooltip (record / play / cancel / stop recording & play / padding to bar / overdub / stop overdub / stop / reverse / bar sync on-off / clear) and every status chip label (`IDLE` / `ARMED` / `REC` / `PLAY` / `ODUB` / `PAD`) now flow through `AppLocalizations`. No more hardcoded strings in `audio_looper_slot_ui.dart`.

### Architecture
- **`AudioInputFFI.alooperGetDataL/R/LoadData`**: new FFI shims for the three `dvh_alooper_*` symbols already compiled into `libnative-lib.so` but not yet reachable from the Dart side on Android. Desktop accesses the same symbols via `libdart_vst_host.so` — the two paths now converge.
- **`VstHostService.importAudioLooperWavs` — platform branch**: the shared wavImporter callback now handles both the desktop `VstHost` path and the Android `AudioInputFFI` path, dispatching on `Platform.isAndroid`. Both paths allocate a `dart:ffi` scratch buffer pair with `malloc`, copy PCM from the decoded WAV, hand it to the loader, and free immediately so lifetime is bounded to the call.
- **`ProjectService._exportAudioLooperWavs` — platform branch**: mirrors the importer's platform split. On Android it resolves clip length + native pointers via `AudioInputFFI.alooperGetLength/DataL/DataR` instead of `VstHost.getAudioLooper*`. `writeWavFile` already accepts a `dynamic` buffer that supports `[]` indexing, so both `Pointer<Float>` and any other indexable source work interchangeably.
- **l10n keys** added in `app_en.arb` / `app_fr.arb`: `audioLooperWaveformRecording`, `audioLooperWaveformCableInstrument`, `audioLooperWaveformEmpty`, `audioLooperTooltipStop/Reverse/BarSyncOn/BarSyncOff/Clear/Record/Play/Cancel/StopRecordingAndPlay/PaddingToBar/Overdub/StopOverdub`, `audioLooperStatusIdle/Armed/Recording/Playing/Overdubbing/Stopping`.
- **`_loopButtonProps` now takes `AppLocalizations` as a parameter** instead of fetching it inside each switch arm — single lookup per build, matches the existing GFPA pattern.

## [2.12.2] - 2026-04-12

### Added
- **Audio Looper — Android cabled-input routing**: the Android audio looper now records only the instruments cabled to its Audio IN ports, matching the Linux behaviour. Previously every active clip recorded the full master mix, which meant loop overdubs captured their own playback and there was no way to record a single instrument. Supported upstream sources on Android: GF Keyboard slots, Drum Generator slots (which ride their MIDI channel's FluidSynth bus), and the Theremin. Stylophone and vocoder remain unsupported upstream sources on Android because they run on separate miniaudio devices that never reach the shared Oboe bus.

### Architecture
- **`audio_looper.h/.cpp` — bus source list**: third per-clip source kind `busSources[ALOOPER_MAX_SOURCES]` (int32 Oboe bus slot IDs) alongside the existing `renderSources` and `pluginSources`. New C API: `dvh_alooper_add_bus_source`, `dvh_alooper_get_bus_source_count`, `dvh_alooper_get_bus_source`. `dvh_alooper_clear_sources` now clears all three lists at once so every routing sync starts from a clean slate.
- **`oboe_stream_android.cpp` — dry capture**: new per-source `g_srcDryL/R[kMaxSources]` scratch buffers. The AAudio callback `memcpy`s each source's render output into the dry buffer BEFORE `gfpa_android_apply_chain_for_sf` runs, so the audio looper records the instrument's raw signal rather than its post-FX signal — matching the Linux `renderCapture[m]` semantic.
- **`oboe_stream_android.cpp` — cabled fill loop**: the previous "feed every clip the master mix" block is replaced with a per-clip fill that iterates `dvh_alooper_get_bus_source`, finds the matching source in the snapshot by `busSlotId`, and sums its dry stereo into `g_alooperSrcL/R[c]`. A clip with no bus sources is skipped (records silence). Zero allocation, zero locks, pointer comparison only.
- **`VstHostService._syncAudioLooperSourcesAndroid`**: called from `_syncAudioRoutingAndroid` on every routing rebuild. Walks incoming audio cables to each `AudioLooperPluginInstance`, resolves each upstream slot to its Oboe bus slot ID (`keyboardSfIds` map for keyboards and drum generators, `kBusSlotTheremin` for the theremin), and pushes the list through `alooperAddBusSource`. The existing pull-based routing discipline (clear + re-add on every sync) handles soundfont swaps automatically because a new soundfont produces a new sfId and the next `_onAudioGraphChanged` rebuilds the list.
- **`RackState._buildKeyboardSfIds` now covers drum generators**: drum slots inherit the FluidSynth sfId of their MIDI channel's keyboard instance, so the same map resolves both keyboard and drum cabling on Android.

## [2.12.1] - 2026-04-12

### Added
- **Audio Looper — CC assign button**: the audio looper slot now has the per-slot CC assign button (settings remote icon) in its header, matching all other modules. Supports "Loop Button" (arm/record/play/overdub cycle) and "Stop" as CC-mappable parameters via the standard `SlotCcAssignDialog` with learn mode.

### Fixed
- **Rack modules silent until scrolled into view**: the rack is a lazy `ReorderableListView.builder`, so any audio-critical work that lived inside a slot widget's `initState()` — session registration, native resource allocation, DSP handle creation, Android AAudio bus wiring — was silently skipped whenever the slot was off-screen. A CC-mapped "start" action aimed at a below-the-fold module would launch the transport but produce silence until the user manually scrolled to the slot. Every audio-producing module type was affected:
  - **Drum Generator**: session registration (`DrumGeneratorEngine.ensureSession`) now runs eagerly in `SplashScreen` for every persisted drum slot, before the first frame renders.
  - **MIDI Looper**: same treatment — `LooperEngine.ensureSession` is called eagerly for every persisted looper slot.
  - **Audio Looper (PCM)**: `AudioLooperEngine.finalizeLoad` is now invoked eagerly in `SplashScreen` right after `vstSvc.startAudio()` so native clips exist before the widget is ever mounted; any missing clips are created in a second pass for brand-new slots.
  - **GFPA audio effect descriptors** (reverb, delay, EQ, compressor, chorus, wah): plugin ownership moved out of `GFpaDescriptorSlotUI` into `RackState`. New `_audioEffectInstances` registry + `initializeAudioEffects()` is called from `SplashScreen` after the VST host is live. `RackState` now owns the `GFDescriptorPlugin` lifetime, the native DSP handle, and the shared param notifier; the widget is purely cosmetic and reads everything via `audioEffectInstanceForSlot` / `audioEffectParamNotifierForSlot`, mirroring the MIDI FX pattern.
  - **Stylophone / Theremin**: new `NativeInstrumentController` service ref-counts the global-singleton native oscillators against rack slot presence. `RackState.addPlugin` / `removePlugin` bring the native synth up/down — not the widget. `initState` / `dispose` no longer touch `AudioInputFFI.styloStart/Stop` or `thereminStart/Stop` / Android AAudio bus, so scrolling the slot off-screen no longer silences the instrument.

## [2.12.0] - 2026-04-11

### Added
- **Audio Looper (PCM)**: new rack module that records and loops live stereo audio with bar-sync, overdub, and reverse. Cable instrument audio outputs into the looper's Audio IN ports on the back panel — only cabled sources are recorded (no metronome, no unwanted instruments). Single-button workflow: idle → arm → record → play → overdub → play, matching the MIDI looper pattern.
- **Audio looper — cabled input routing**: multiple instruments can be cabled to one looper simultaneously. `syncAudioRouting` wires render sources (GF Keyboard, Vocoder, Theremin, Stylophone, Drum Generator) and VST3 plugin outputs to per-clip source buffers, mixed in the JACK callback. No source connected = silence.
- **Audio looper — bar-synced recording with silence padding**: when bar-sync is enabled, recording starts at the exact downbeat sample. When the user stops recording, the `ALOOPER_STOPPING` state pads silence to the next bar boundary so the loop is always whole-bar aligned.
- **Audio looper — optional bar sync**: toggle per clip between bar-synced mode (wait for downbeat) and free-form mode (start immediately). Timer icon button on the looper card.
- **Audio looper — single-pass overdub**: overdub records one full loop pass then auto-returns to playing, matching the MIDI looper behaviour.
- **Audio looper — waveform preview**: `_WaveformPainter` draws RMS envelope from native PCM buffers via FFI with playback head overlay and recording progress indicator.
- **Audio looper — WAV sidecar persistence**: clips saved as 32-bit float stereo WAV files in a `.gf.audio/` directory alongside the project JSON. Deferred load architecture (`finalizeLoad`) handles the JACK-not-ready-at-startup timing.
- **Audio looper — CC bindings**: action codes 1015 (Loop Button) and 1016 (Stop) in CC preferences, wired via `onAudioLooperSystemAction` callback.
- **Vocoder integration into JACK render pipeline**: `vocoder_render_block()` and `vocoder_set_capture_mode()` added to `audio_input.c`. When the vocoder is cabled to the audio looper or a GFPA effect, its miniaudio playback outputs silence and the JACK thread drives the DSP. Vocoder audio can now be captured by the audio looper.
- **Percussion isolation (FluidSynth slot 2)**: `MAX_KB_SLOTS` increased to 3; channel 9 (GM percussion) routed to dedicated slot 2 instead of sharing slot 1 with GF Keyboard 2. Prevents metronome clicks from bleeding into keyboard captures.

### Architecture
- **`audio_looper.h` / `audio_looper.cpp`**: new C module with `ALooperClip` struct (pre-allocated stereo buffers, atomic state machine), 5-state lifecycle (idle/armed/recording/playing/overdubbing + stopping), per-clip multi-source mixing (up to 8 render functions + plugin indices), bar-boundary detection at sample precision.
- **JACK callback — per-clip source buffers**: `alooperSrcL/R[8]` pre-allocated in `AudioState`. Sources filled from `renderCapture[m]` (pre-captured master/chain render outputs) or `pluginBuf[]` (VST3). No double-rendering of FluidSynth.
- **`AudioLooperEngine`** (`ChangeNotifier`): Dart control plane for the C++ looper — clip lifecycle, state transitions, 30Hz native state polling, deferred project load (`finalizeLoad`), WAV import/export, `onDataChanged` autosave hook.
- **`AudioLooperPluginInstance`**: rack slot model (`type: 'audio_looper'`), registered in `PluginInstance.fromJson`, back panel exposes `audioInL`/`audioInR`.
- **Triple-layer render capture**: insert chain sources captured into `renderCapture[m]` during the chain pass, bare master renders captured during the bare pass. Audio looper reads from captures by function pointer matching — never re-calls render functions.
- **`wav_utils.dart`**: `writeWavFile()` / `readWavFile()` for 32-bit float stereo WAV sidecar files.

## [2.11.0] - 2026-04-08

### Added
- **USB audio debug screen (Android)**: new `UsbAudioDebugScreen` accessible from Preferences that displays every `AudioDeviceInfo` on the system — device ID, type, direction, sample rates, channel counts, encodings, and address. Used for investigating multi-USB device routing on different OEMs.
- **AAudio output device routing (Android)**: the synth output stream (FluidSynth keyboards, Theremin, Stylophone, Vocoder) can now be directed to a specific USB audio device via `oboe_stream_set_output_device()` using `AAudioStreamBuilder_setDeviceId()`. Previously, only the vocoder capture/playback path (miniaudio) supported device selection; now both audio paths honour the user's output device choice.
- **Device disconnect notification**: when a selected audio device is unplugged mid-session, `_resetDisconnectedDevices()` falls back to the system default and shows a snackbar via `toastNotifier`. The AAudio `errorCallback` also reopens the stream on the default device automatically.
- **API level gate for device selector**: the output device dropdown in `AudioSettingsBar` is hidden on Android < 28, where AAudio's `setDeviceId()` is not reliable (OpenSL ES silently ignores it).
- **Channel-swap macro**: map a hardware CC to swap two instrument slots' MIDI channels and optionally their entire signal chain (audio cables, Jam Mode references, CC mappings). `RackState.swapSlots()` performs the swap; `AudioGraph.swapSlotReferences()` rewrites cables atomically; `CcMappingService.swapSlotReferences()` keeps CC mappings consistent. Debounced (250 ms) with a toast notification showing the swapped slot names.
- **CC preferences — "Channel Swap" category**: renamed from "Macros" for clarity. Slot pickers now show MIDI channel and rack position to disambiguate duplicates (e.g. "GF Keyboard (Ch 1, #1)" vs "GF Keyboard (Ch 2, #3)").
- **Linux packaging**: GitHub Actions release workflow now produces `.rpm` (Fedora), `.pkg.tar.zst` (Arch/Manjaro), and `.flatpak` bundles alongside the existing `.deb` and `.zip`. All three repackage the Ubuntu-built Flutter bundle with distro-native dependency metadata. Shared desktop file, AppStream metainfo, and RPM spec/PKGBUILD/Flatpak manifest added under `packaging/`.

### Fixed
- **`.deb` package missing runtime dependencies**: `Depends` field now lists verified package names from packages.debian.org (`libgtk-3-0 | libgtk-3-0t64`, `libasound2 | libasound2t64`, `libjack-jackd2-0`, `libfluidsynth3`, `libpulse0`, `libmpv2`). PipeWire stack added as `Recommends`.
- **CC mappings not persisted across app restarts**: `ProjectService` accessed `CcMappingService` via `AudioEngine.ccMappingService` which was null during splash screen (assigned later in `RackScreen.initState`). Mappings were never loaded from the `.gf` file on startup. Fixed by giving `ProjectService` a direct reference to `CcMappingService` from the Provider. Also added a `mappingsNotifier` listener to trigger autosave on every CC mutation.
- **CC preferences — crash when selecting Looper category**: `_systemAction` defaulted to 1001, but the looper actions only contain {1009, 1012}. The `DropdownButtonFormField` received an `initialValue` not in the items list. Fixed by resetting `_systemAction` to the first valid entry when switching categories.
- **Android — GF Keyboard 1 silent after startup**: `_applyAllPluginsToEngine()` fired a concurrent `createKeyboardSlotSynth()` (fire-and-forget) for each keyboard, racing with the sequential `initAndroidKeyboardSlots()` called immediately after by `_readGfFile()`. Both calls saw `_channelSlotSfId[channel] == null` and created duplicate FluidSynth instances — the first one was orphaned on the AAudio bus with no MIDI routing, silencing the keyboard. Fixed by passing `skipAndroidSlotCreation: true` in `_applyAllPluginsToEngine()` so only `initAndroidKeyboardSlots()` creates dedicated synths.

### Architecture
- **CC mapping model rewrite — sealed `CcMappingTarget` hierarchy**: replaced the overloaded `targetCc` int field with a sealed class hierarchy of six target types: `GmCcTarget`, `SystemTarget`, `SlotParamTarget`, `SwapTarget`, `TransportTarget`, `GlobalTarget`. Supports multiple mappings per CC number (one knob can control several targets). JSON serialization for `.gf` project files. Storage changed from `Map<int, CcMapping>` to `List<CcMapping>` with O(1) pre-built index.
- **Per-project CC mapping storage**: CC mappings are now saved/loaded in `.gf` project files via `ProjectService`, replacing the global `SharedPreferences` storage. Switching projects switches the entire CC configuration. Legacy mappings are migrated automatically on first load of an old `.gf` file.
- **CC dispatch refactor**: `AudioEngine.processMidiPacket` CC case rewritten to dispatch via sealed pattern matching (`_dispatchCcMapping`). Each target type routes to its handler: `GmCcTarget` → `_sendRemappedCc`, `SystemTarget` → `_handleSystemCommand`, new types → stub callbacks for Phases C-E.
- **CC orphan cleanup**: `RackState.removePlugin()` now calls `CcMappingService.removeOrphanedSlotMappings()` to clean up any `SlotParamTarget` or `SwapTarget` referencing a deleted slot.
- **`oboe_stream_android.cpp` — output device routing**: added `g_outputDeviceId`, `oboe_stream_set_output_device()`, and `oboe_stream_get_output_device()`. The stream builder calls `AAudioStreamBuilder_setDeviceId()` when a non-default device is selected. A no-change guard skips unnecessary stream restarts.
- **`oboe_stream_android.cpp` — error recovery**: the `errorCallback` now reopens the stream on the default device via a detached thread instead of only logging the error.
- **`native-lib.cpp` — JNI `setOutputDevice`**: new JNI entry point bridging the Kotlin method channel to `oboe_stream_set_output_device()`.
- **`flutter_midi_pro` — `setOutputDevice()` API**: new method across the platform interface, method channel, web stub, and public `MidiPro` class.
- **`MainActivity.kt` — `getAudioDeviceDetails`**: new method channel call returning full `AudioDeviceInfo` data (id, productName, type, isSource, isSink, sampleRates, channelCounts, encodings, address) for the debug screen. Extracted `deviceTypeString()` helper shared with `enumerateDevices()`.
- **`AudioEngine` — `androidSdkVersion`**: cached once during init via method channel; used by UI to gate API-level-dependent features.
- **JACK audio callback — zero-allocation rewrite**: replaced per-frame heap allocations (6 `std::vector`/`std::unordered_map` copies every audio block) with a triple-buffered `RoutingSnapshot` architecture. The Dart thread publishes flat, fixed-size snapshots via `std::atomic`; the JACK callback reads them with a single atomic load — no mutex, no copy, no heap. Eliminates the heap fragmentation that caused crashes under rapid GFPA DSP create/destroy cycles.
- **`dvh_process_stereo_f32` — pre-allocated process buffers**: moved `scratch`, `outPtrs`, `outBufs`, `inBufs` vectors from per-call stack allocation to pre-allocated fields in `DVH_PluginState`, sized once in `dvh_resume()`.
- **`gfpa_dsp.cpp` — C++ member initializer order fix**: `ChorusEffect` and `DelayEffect` declared `bufL`/`bufR` before `maxDelaySamples`, causing the delay-line vectors to be constructed with uninitialized garbage sizes (C++ initializes in declaration order, not initializer-list order). Reordered members so `maxDelaySamples` and `sampleRate` are declared first. Added `-Wreorder` to CMake to catch this class of bug at compile time.

## [2.10.0] - 2026-04-06

### Added
- **Looper — per-track volume slider**: each `LoopTrack` now has a `volumeScale` field (0.0–1.0, persisted in `.gf`). Note-on velocity is multiplied by this factor in `_fireEventsInRange` during playback. A compact `_VolumeSlider` widget appears in each `_TrackRow`.
- **Looper — CC assignment UI**: new `_CcAssignStrip` widget in `LooperSlotUI` displays current CC → action bindings as deletable chips. The "Assign CC" button opens `_CcAssignDialog`: pick an action (Record/Play, Play/Pause, Stop, Clear, Overdub), then move any hardware knob or fader to bind it. Learn mode via `LooperEngine.onCcLearn` callback.
- **Looper — CC routing**: `feedMidiEvent` now detects CC messages (status `0xB0`) and routes them to `handleCc` so hardware CC bindings work without separate wiring in the rack screen.
- **PipeWire / JACK audio backend (Linux)**: replaced the direct ALSA PCM backend (`dart_vst_host_alsa.cpp`) with a JACK client (`dart_vst_host_jack.cpp`) using `jack_client_open` / `jack_set_process_callback`. GrooveForge now registers as a proper JACK client with named stereo output ports (`out_L`, `out_R`) and auto-connects to `system:playback_1` / `system:playback_2`. Works on both PipeWire (JACK shim) and native JACK2 systems. Target latency drops from ~50 ms (ALSA dmix workaround) to < 10 ms.
- **Inter-application audio routing**: GrooveForge audio can now be routed to/from other Linux audio applications (Ardour, Bitwig, Carla) via standard JACK connections — visible in Helvum, qjackctl, or Carla's patchbay.
- **XRUN counter**: `dvh_jack_get_xrun_count` / `VstHost.getXrunCount()` exposes the cumulative XRUN count reported by the JACK server, ready to surface as a latency warning in the UI.

### Fixed
- **GF Keyboard — Slot 1 instrument not restored on restart**: the second GF Keyboard (odd MIDI channels) always played piano (patch 0) after restarting the app, even though the UI displayed the correct instrument. `_restoreState()` in `AudioEngine.init()` sent program changes for all 16 channels, but FluidSynth Slot 1 did not exist yet — `keyboard_program_select()` silently dropped the call when `slot->synth` was NULL. Fixed by initialising Slot 1 via `keyboardInitSlot(1)` immediately after `keyboardInit()`, before `_restoreState()` runs.
- **Web / WASM build broken by Slot 1 fix**: `audio_input_ffi_stub.dart` (the web no-op stub) was missing the `keyboardInitSlot` method added for the Slot 1 init fix, causing `dart2wasm` and `dart2js` compilation to fail. Added the missing no-op stub.

### Architecture
- **JACK audio backend**: `dart_vst_host_jack.cpp` replaces `dart_vst_host_alsa.cpp`. The ALSA `while(running) { snd_pcm_writei }` loop is replaced by a `jack_set_process_callback` that writes native float directly to JACK port buffers (no int16 conversion). Buffer size is negotiated dynamically via `jack_set_buffer_size_callback`. CMake dependencies changed from `find_package(ALSA)` to `pkg_check_modules(JACK REQUIRED jack)`. Dart FFI renamed: `startAlsaThread` → `startJackClient`, `stopAlsaThread` → `stopJackClient`.
- **Looper — chord detection removed**: stripped `chordPerBar`, `detectAndStoreChord`, `_flushBarChord`, `_detectBeatCrossings` recording branch, `notesInBar`, and `prevRelativeBar` from `LoopTrack` and `LooperEngine`. The chord grid UI is replaced by a plain bar-number strip (`_BarStrip`). `ChordDetector` remains in the codebase (used by Jam Mode / keyboard).
- **Looper — bar-aligned recording**: `_beginRecordingPass` now snaps `recordingStartBeat` to the preceding bar-1 downbeat so event offsets are bar-relative from the start. `_activatePlayback` sets `recordingStartBeat = anchorBeat`, making stop/restart and save/reload produce identical playback alignment.
- **Looper — `LoopTrack.barCount(beatsPerBar)`**: new helper replacing the old `chordPerBar.keys` approach; derives bar count from `lengthInBeats` and the transport time signature.
- **Looper — `LooperEngine.beatsPerBar` getter**: exposes `timeSigNumerator` so the UI can compute bar counts without importing `TransportEngine`.

## [2.9.0] - 2026-03-25

### Added
- **GitHub Pages documentation site**: static marketing and handbook at the site root (hero, screenshots, getting started, modules, MIDI FX, VST3 on Linux/macOS, `.gfdrum` / `.gfpd` guides with raw `main`-branch download links); Flutter WASM build moved to `/demo/`. Deploy workflow assembles `website/`, `docs/features.md` + `docs/privacy.md`, splash, icon, and screenshots into the published bundle.
- **Handbook screenshot placement**: the homepage shows one main-window preview only; other screenshots appear as contextual figures on guide, modules, MIDI FX, VST, `.gfdrum`, and `.gfpd` pages (English and French mirror).
- **French website mirror** (`/fr/`): translated static pages plus `docs/features.fr.md` and `docs/privacy.fr.md` for `/fr/features/` and `/fr/privacy/`; EN/FR language switch in the header on all handbook pages.
- **Handbook UX & messaging**: mobile header uses a compact single-row bar with a **Menu** toggle (checkbox) that expands navigation in a short scrollable panel instead of wrapping many links; homepage copy emphasizes **Jam Mode** for harmony/scale practice (hardware MIDI), **`.gfdrum`** grooves vs. a bare metronome, and **Looper + drums** sharing the transport clock.
- **Drum Track Generator**: new rack module with transport-sync beat scheduling, humanization engine (velocity jitter, microtiming, ghost notes), swing slider, and structured fills/breaks.
- **`.gfdrum` pattern format**: YAML-based declarative drum patterns with step grids (X/x/o/g/.), per-instrument velocity and timing configuration, `loop` and `sequence` section types. Users can author and load custom patterns.
- **Ten bundled patterns**: Classic Rock, Jazz Swing, Bossa Nova, Tight Funk, Irish Jig, Breton An Dro, Scottish Reel (pipe-band snare, 150–220 BPM), Batucada (samba percussion ensemble with surdo interlock + tamborim carreteiro), Military March (flam rudiment backbeat, press-roll variation), Jazz Half-Time Shuffle (Rosanna/Purdie shuffle with half-time snare on beat 3 only and swing "trip" hi-hat).
- Breton An Dro uses `type: sequence` for authentic bar-by-bar phrase variation.
- `DrumPatternRegistry` singleton for pattern discovery across the app.
- **Drum Generator — time signature sync**: when a drum pattern is loaded (and the transport is stopped), the transport automatically adopts the pattern's time signature so the metronome LED and bar counter stay in sync with the drum feel (e.g. 6/8 for Bossa Nova, 4/4 for Rock).
- **Drum Generator — all patterns rewritten** from research for musical authenticity: Classic Rock (Bonham kick hemiola + AC/DC variant), Jazz Swing (authentic spang-a-lang ride), Bossa Nova (4-bar clave sequence with open/closed hi-hat variation), Tight Funk (5 variations: Funky Drummer, Cissy Strut, Sly Stone, synco kick, lighter), Irish Jig (bodhran DOWN/UP stroke model + cross-stick "tip" variation), Breton An Dro (double-kick signature), Scottish Reel (reworked from continuous 16th snare to 8th-note hi-hat + backbeat — much more musical at 150–220 BPM), Batucada (5-voice ensemble with agogô cowbell, featured tamborim chamada, repique call, and chamada fill), Country (BPM range extended to 170 + `speedy_wagon` variation), Jazz Waltz (9-resolution binary feel for a natural chabada trio without swing-algorithm colouring).
- **Drum Generator — parameter autosave**: swing override, humanisation amount, soundfont, pattern selection, count-in type, and fill frequency are now persisted automatically on every change (via `DrumGeneratorEngine.onChanged` wired to `ProjectService.autosave`), and saved in `.gf` project files.

### Fixed
- **Web / WASM — Drum Generator and GM percussion**: the browser audio bridge ignored MIDI bank 128 and always used melodic Gleitz samples, so drum notes sounded like piano keys. The bridge now tracks bank/program per channel, routes bank 128 to a lazy-loaded TR-808 kit (smplr), and forces MIDI channel 10 to the percussion bank after the default soundfont loads so the metronome matches native SF2 behaviour.

### Architecture
- **Drum Generator — eliminated ~100 Hz widget rebuild loop**: `RackSlotWidget` wrapped the Drum Generator slot in `ValueListenableBuilder(channelState.activeNotes)` — drum notes firing on the 10 ms tick caused ~100 rebuilds per second, hurting timing in battery-saver and adding latency to chord playback on other slots. The Drum Generator now skips that `ValueListenableBuilder` entirely (no note-activity glow). Jam Mode multi-channel listening is replaced with a two-level approach: outer `ListenableBuilder(gfpaJamEntries)` for config changes, inner `ValueListenableBuilder` on the single relevant master channel only.
- **Drum Generator — `ensureSession()` no longer calls `notifyListeners()` when nothing changed**: the call was unconditional, causing an extra rebuild every `addPostFrameCallback`. Notifications now fire only on first subscribe or when the loaded pattern actually changes.
- **Drum Generator — lookahead rescheduled on parameter change**: `markDirty()` calls `session.refreshSchedule()` on all active sessions, clearing the 2-bar lookahead cache so swing and humanisation updates apply within ≤ 10 ms.

## [2.8.1] - 2026-03-24

### Added
- **MIDI FX bypass toggle**: power button in every MIDI FX slot header. When off, the plugin is fully skipped — no events pass through it, arpeggiators stop.
- **MIDI CC assignment for bypass**: MIDI remote icon next to the bypass button; move any hardware knob/button to bind its CC. Assigned CC shown as a chip; removable from the same dialog.

### Fixed
- **MIDI FX bypass inconsistency**: toggling a MIDI FX plugin off correctly stopped the effect for hardware MIDI controllers, but on-screen GF keyboard and Vocoder notes still passed through the bypassed effect. Both paths now share the same bypass check.
- **MIDI FX not applied to hardware MIDI controller**: cable-connected MIDI FX (Harmonizer, Transposer, …) were silently bypassed for hardware controllers; only the explicit `targetSlotIds` path was checked.
- **Chord latency with hardware MIDI controller**: three root causes eliminated — Note events no longer trigger `CcMappingService` widget rebuilds; chord detection deferred past pending MIDI bytes; audio call now fires before any `ValueNotifier` update (previously a synchronous piano-key rebuild was inserted between each note of a chord). Auto-scroll debounced (60 ms) to prevent CC burst animations.
- **Android chord latency**: `playNote`/`stopNote`/`controlChange`/`pitchBend` previously ran on the Android main thread, sharing it with the Choreographer vsync — a frame render could delay a chord note by 10–20 ms. All real-time audio JNI calls now run on a dedicated `MAX_PRIORITY` thread (`GrooveForge-Audio`).
- **Android gain**: default FluidSynth master gain lowered from `5.0` to `3.0` (matching Linux) to prevent saturation; gain is now correctly applied to every new FluidSynth instance (previously the gain listener fired before any synth existed, so new instances silently inherited FluidSynth's internal default).
- **Patch view — cables invisible when endpoint scrolled off-screen**: switched to a non-virtualizing scroll view so all jack `GlobalKey`s remain mounted.
- **Patch view — edge auto-scroll during cable drag**: dragging near the top or bottom edge now scrolls the rack; cables and the live drag line repaint correctly during scroll.
- **Patch view — jack layout on phones**: jack sections now stack vertically (< 480 dp) instead of overflowing horizontally.
- **Transport bar on narrow phones** (< 500 dp): compact single-row layout — left cluster (LED / play / BPM) and right cluster (TAP / time sig / metronome).
- **Audio settings bar**: device dropdowns no longer overflow — wrapped in `Expanded` to share remaining width after the knobs.

### Architecture
- **MIDI hot-path — zero allocation per note**: per-channel routing cache (`_routingCache`) pre-classifies VST3, MIDI-only, and synth slots; `_looperTargets` / `_looperPlaybackTargets` replace `connectionsFrom()` scans; `AudioGraph.hasMidiOutTo()` probes connections without allocating a `List`; `_cachedTransport` computed once per transport change; all service references cached as fields in `_RackScreenState`, eliminating `context.read<T>()` traversals from the MIDI callback. When no MIDI FX slots exist the entire FX pipeline is bypassed without any allocation.

## [2.8.0] - 2026-03-24

### Added
- **MIDI FX plugin system** (`type: midi_fx` in `.gfpd`): pure-Dart MIDI processing chain — `GFMidiNode` / `GFMidiGraph` / `GFMidiNodeRegistry` — parallel to the audio DSP node system. Plugins connect to instrument slots via MIDI OUT → MIDI FX MIDI IN patch cables in the back-panel view. Six built-in node types ship with this release: `transpose`, `harmonize`, `chord_expand`, `arpeggiate`, `velocity_curve`, `gate`.
- **Harmonizer** (`com.grooveforge.harmonizer`): adds up to two harmony voices above every note. Intervals configurable 0–24 semitones; Scale Lock snaps voices to the active Jam Mode scale.
- **Chord Expand** (`com.grooveforge.chord`): expands each note into a full chord voicing. 11 chord qualities (Major through Dim7); three spread modes — Close (within one octave), Open (drop-2 style), Wide (all tones +1 octave); Scale Lock.
- **Arpeggiator** (`com.grooveforge.arpeggiator`): replaces held notes with a rhythmic sequence. 6 patterns (Up / Down / UpDown / DownUp / AsPlayed / Random), 9 divisions (1/4 → 1/32T), gate 10–100 %, 1–3 octaves. Wall-clock timing — plays independently of transport state.
- **Transposer** (`com.grooveforge.transposer`): shifts all notes ±24 semitones. Virtual piano viewport does not scroll to the transposed pitch — only physically pressed keys trigger scroll (`_pointerNote` logic).
- **Velocity Curve** (`com.grooveforge.velocity_curve`): remaps note-on velocities. Three modes — Power (exponent 0.25–4.0 via one Amount knob; centre = linear), Sigmoid (S-curve centred at velocity 64, steepness 4–20), Fixed (constant output velocity 1–127). Note-offs and non-note events pass through unchanged.
- **Gate** (`com.grooveforge.gate`): filters notes outside a velocity window (Min/Max Vel 0–127) and/or a pitch range (Min/Max Note 0–127). Suppressed note-ons are tracked so matching note-offs are also suppressed — no stuck notes even when parameters change while notes are held.
- **Vocoder MIDI OUT jack**: the Vocoder back panel now exposes a MIDI OUT jack so any MIDI FX plugin can be wired to it in patch view. The vocoder's on-screen piano was already routing through `_applyMidiChain()` — the jack was the only missing piece.
- **Responsive plugin UI groups** (Phase 10): `.gfpd` `ui:` block gains an optional `groups:` key — controls are organised into labelled sections. On screens ≥ 600 px all groups display side-by-side; on narrow phones each group collapses to a tappable `ExpansionTile`. All 12 bundled `.gfpd` files (6 audio effects + 6 MIDI FX) updated with logical groupings.

### Fixed
- **Arpeggiator: three extra step divisions** — Division selector now offers 9 options including 1/64, 1/16T, and 1/32T (at 120 BPM: 31 ms, 83 ms, and 42 ms per step respectively).
- **Arpeggiator: virtual piano no longer scrolls to arp step notes** — `didUpdateWidget` auto-scroll now follows only keys the user is physically pressing (`_pointerNote`). Arp steps cycling through octaves no longer steal the viewport mid-performance.
- **Arpeggiator: keys visually stuck after glissando** — two root causes fixed: (1) `_arpNoteOns` sentinel left unconsumed after inline `_fireStep` in `_handleUserNoteOn`, causing a return-stroke press to be misidentified as an arp event and the eventual note-off to be dropped; (2) `_onNotePressed` forwarded all events from `_applyMidiChain` to `engine.playNote`, including tick-injected gate note-offs that added stale pitches to `activeNotes`.
- **MIDI FX active even when slot is scrolled off-screen** — all MIDI FX slots are now initialised eagerly by `RackState` at project load, independently of widget rendering. Previously a slot scrolled out of the lazy list was never mounted and notes bypassed its MIDI FX chain entirely.
- **All bundled audio effects now have responsive layouts** — the six `.gfpd` effect descriptors (Reverb, Delay, Wah, EQ, Compressor, Chorus) now declare `groups:` sections, enabling the collapsible/column responsive layout on all screen sizes.

### Architecture
- `GFMidiDescriptorPlugin` implements `GFMidiFxPlugin` via an internal `GFMidiGraph`, exactly mirroring how `GFDescriptorPlugin` wraps a `GFDspGraph`.
- `RackState._midiFxTicker`: 10 ms `Timer.periodic` drives time-based nodes (arpeggiator) on all instrument channels even with no incoming events — enables sustained arpeggios when holding a chord.
- `RackState._initMidiFxPlugin`: eagerly initialises every MIDI FX slot at `loadFromJson` / `addPlugin` time; `midiFxInstanceForSlot` exposes the live instance to `_applyMidiChain`.
- `GateNode` extended with `maxVelocity`, `minPitch`, `maxPitch` parameters; backward-compatible (defaults keep the gate fully open).

## [2.7.0] - 2026-03-22

### Added
- **Native GFPA DSP effects** (Android, Linux, macOS): six built-in effects — Auto-Wah, Plate Reverb, Ping-Pong Delay, 4-Band EQ, Compressor, Chorus/Flanger — run as allocation-free native C++ DSP on the real-time audio thread. Multi-effect chains and routing to Theremin/Stylophone are supported on all platforms.
- **`.gfpd` Plugin Descriptor Format**: declarative YAML format to author GFPA plugins without writing Dart code — metadata, DSP signal graph, automatable parameters, and UI layout. Six first-party effects bundled as `.gfpd` assets.
- **GFPA plugin UI controls**: GFSlider (fader), GFVuMeter (20-segment stereo VU meter with peak hold), GFToggleButton (LED stomp-box toggle), GFOptionSelector (segmented selector for discrete parameters).
- **GF Keyboard on macOS via FluidSynth**: replaces the previous `flutter_midi_pro` fallback; GFPA effects and MIDI playback now work identically on Linux and macOS.
- **`HOW_TO_CREATE_A_PLUGIN.md`**: comprehensive authoring guide for `.gfpd` plugins.
- **Auto-rebuild of native C/C++ libraries on macOS**: added `scripts/build_native_macos.sh` and a pre-build Xcode Run Script phase so that `libaudio_input.dylib` and `libdart_vst_host.dylib` are rebuilt automatically (incrementally via CMake) every time `flutter run` or Xcode builds the Runner target. No manual `cmake && make` step required after editing native sources.

### Fixed
- **Autosave crash on Linux** (ENOENT on rename): rapid knob changes triggered concurrent writes to the same `.tmp` file. Debounced with a 500 ms timer.
- **GF Keyboard silent when no VST3 plugin is in the rack (Linux)**: the ALSA render thread now starts unconditionally when the VST3 host is supported.
- **"Sustain pedal always held" sound on macOS**: FluidSynth 2.5.3 (Homebrew) ignored `synth.reverb.active=0`; added runtime `fluid_synth_reverb_on` / `fluid_synth_chorus_on` disable calls after synth creation.
- **Second GF Keyboard significantly quieter than first**: lazily-created keyboard slots now inherit the app gain instead of FluidSynth's factory default (0.2 → 3.0).
- **Keyboard config dialog**: aftertouch/pressure CC description and dropdown now stack vertically instead of being squeezed side-by-side.
- **macOS CI build**: `libaudio_input.dylib` is rebuilt from source and bundled with all transitive FluidSynth Homebrew dependencies via `dylibbundler`.

### Changed
- **Virtual Piano slot removed**: superseded by **GF Keyboard** with soundfont set to *None (MIDI only)*. Existing projects migrate automatically on load.

## [2.6.0] - 2026-03-19

### Added
- **VST3 Effect Plugin Support**: `Vst3PluginType` enum (instrument / effect / analyzer) stored in the model and persisted in `.gf` files. "Add Plugin" sheet now shows separate tiles for VST3 Instrument and VST3 Effect.
- `Vst3EffectSlotUI`: dedicated rack slot body for effect plugins — purple accent, auto-detected effect-type chip (Reverb / Compressor / EQ / Delay / Modulation / Distortion / Dynamics), full knob grid with search, sub-group detection, and pagination identical to the instrument UI.
- **FX Inserts**: collapsible "FX ▸ (N)" chip at the bottom of every VST3 instrument slot. Lists VST3 effect slots whose audio inputs are wired to this instrument's outputs. The + button browses for an effect, adds it as a first-class rack slot, and auto-wires `audioOutL/R → audioInL/R` in the audio graph.
- Effect and analyzer VST3 back panels now expose `AUDIO IN L/R + AUDIO OUT L/R + SEND + RETURN` jacks instead of `MIDI IN + audio` jacks.
- Effect VST3 slots no longer show a MIDI channel badge, a virtual piano, or the note-activity glow.

### Fixed
- **GF Keyboard audio routing not restored on project load**: On startup, `syncAudioRouting` was called while `VstHost` was still uninitialised (`_host == null`), so it returned early and never wired keyboard audio through saved VST3 effect connections. A second `syncAudioRouting` call is now made in `SplashScreen` after all VST3 plugins have been loaded and the ALSA thread has started, restoring the full routing table correctly.
- **VST3 editor crash on XWayland (GLX BadAccess)**: JUCE-based VST3 plugins (e.g. Dragonfly Hall Reverb) crashed the entire app when opening their native editor under a Wayland session. The default Xlib fatal error handler called `exit()` when `glXMakeCurrent` returned `BadAccess` because Flutter's render thread already owned the GLX context. A non-fatal `XSetErrorHandler` is now installed around `createView()` + `attached()` in `dart_vst_host_editor_linux.cpp`; if a GLX error is caught, the editor open is aborted cleanly and a snackbar guides the user to relaunch with `LIBGL_ALWAYS_SOFTWARE=1` or in a pure X11 session.
- **VST3 effect parameters section collapsed by default**: The parameters accordion in both instrument and effect VST3 rack slots now starts collapsed, reducing visual clutter on first load.

### Architecture
- **Theremin / Stylophone → VST3 effect audio routing**: Built-in instruments (Theremin, Stylophone) can now feed audio into VST3 effect plugins via the audio graph. Routing is implemented through three coordinated layers: (1) `native_audio/audio_input.c` exposes `theremin_render_block()` / `stylophone_render_block()` C functions and a capture-mode flag that silences the miniaudio direct-to-ALSA output when a route is active; (2) `dart_vst_host_alsa.cpp` adds an external-render registry (`dvh_set_external_render` / `dvh_clear_external_render`) so the ALSA audio loop calls the render function as the plugin's stereo input each block; (3) `VstHostService.syncAudioRouting` detects non-VST3 → VST3 connections in the `AudioGraph`, registers the correct render function, and toggles capture mode accordingly.
- **GF Keyboard → VST3 effect audio routing**: Replaced the FluidSynth subprocess (`/usr/bin/fluidsynth -a alsa`) on Linux with libfluidsynth linked directly into `libaudio_input.so`. FluidSynth now runs in "no audio driver" mode and is rendered manually via `keyboard_render_block()`. A new master-mix render slot in the dart_vst_host ALSA loop (`dvh_add_master_render` / `dvh_remove_master_render`) lets keyboard audio play normally through the ALSA thread when not routed into a VST3 effect, and routes it through the effect's input when connected. All MIDI commands (note on/off, program select, pitch bend, CC, gain) are now dispatched via FFI instead of stdin pipes.

## [2.5.8] - 2026-03-17

### Fixed
- **Save As (Android & web)**: "Save As…" in the project menu did nothing on Android and web. On web, `FilePicker.platform.saveFile` requires `bytes` and returns `null` after triggering a download; on Android/iOS the plugin also requires `bytes`. The project is now serialized to JSON bytes and passed to `saveFile` on all platforms. On web, the empty-string result is treated as success (download started); on mobile and desktop the plugin writes the file and returns the path. The UI shows "Project saved" in all cases.

### Added
- Static HTML pages for `/features` and `/privacy` routes under `web/features/index.html` and `web/privacy/index.html`, restoring these pages on GitHub Pages after the Flutter web deployment replaced the previous static site.

## [2.5.7] - 2026-03-17

### Fixed
- **Rack keyboard rebuild storm**: Notes on any MIDI channel were triggering a full rebuild of every keyboard slot in the rack (O(N×16) repaints per keypress). The outer `ListenableBuilder` in `_RackSlotPiano` and `GrooveForgeKeyboardSlotUI` was unconditionally merging all 16 channels' `activeNotes` and `lastChord` notifiers, regardless of whether the slot is a GFPA Jam follower. Replaced with a three-layer architecture: layer 1 listens to configuration only, layer 2 (new `_PianoBody` / `_GfkFollowerBody` widgets) subscribes to exactly one master-channel notifier for followers only, and layer 3 (`ValueListenableBuilder<Set<int>>`) handles own-channel note highlighting. Non-follower slots now subscribe to zero cross-channel notifiers, reducing note-on rebuild work from O(N) to O(1) per keypress.

### Added
- **Web target**: GrooveForge now builds and runs as a Flutter web app deployable to GitHub Pages.
- **Web audio (GF Keyboard)**: SF2 soundfont playback on web via a SpessaSynth JavaScript bridge (`web/js/grooveforge_audio.js`). The bridge is loaded as a `<script type="module">` in `web/index.html` and exposed as `window.grooveForgeAudio`. A new `FlutterMidiProWeb` Dart class (using `dart:js_interop` extension types) delegates all MIDI calls to this bridge.
- **Web audio (Stylophone & Theremin)**: Oscillator synthesis on web via the Web Audio API, exposed as `window.grooveForgeOscillator`. Waveform, vibrato, portamento, and amplitude behaviour match the native C implementation.
- **GitHub Actions workflow** (`.github/workflows/web_deploy.yml`): Automatically builds the Flutter web release and deploys to GitHub Pages (`gh-pages` branch) on every push to `main`.

### Architecture
- `lib/services/audio_input_ffi.dart` converted to a conditional re-export: native platforms use `audio_input_ffi_native.dart` (unchanged FFI code); web uses `audio_input_ffi_stub.dart` (JS interop bridge, all Vocoder methods are no-ops).
- `lib/services/vst_host_service.dart` conditional export condition changed from `dart.library.io` to `dart.library.js_interop` — `dart:io` is partially available on Flutter web 3.x, so the old condition was incorrectly selecting the desktop (FFI-heavy) implementation on web.
- `lib/services/rack_state.dart` import changed from the concrete `vst_host_service_desktop.dart` to the conditional re-export `vst_host_service.dart`, ensuring the FFI-free stub is used on web.
- `lib/services/vst_host_service_stub.dart` extended with a `syncAudioRouting` no-op to match the desktop interface.
- `kIsWeb` guards added in `audio_engine.dart`, `midi_service.dart`, and `project_service.dart` to skip all `dart:io` file/directory operations on web.
- `packages/flutter_midi_pro`: SDK constraint raised to `>=3.3.0` (extension types), `flutter_web_plugins` dependency added, web plugin registration (`FlutterMidiProWeb`) added to `pubspec.yaml`. `loadSoundfontAsset` skips temp-file I/O on web and passes the asset path directly to the JS bridge.
- `packages/flutter_midi_pro/analysis_options.yaml` updated to exclude `flutter_midi_pro_web.dart` from non-web analysis (the file uses `dart:js_interop` extension types that are only valid in a web compilation context).

## [2.5.6] - 2026-03-16

### Fixed
- **MacOS crash on startup**: Rebuilt the precompiled macOS `libaudio_input.dylib` to include the `VocoderPitchBend` and `VocoderControlChange` C FFI symbols, preventing a `symbol not found` crash on launch.
- **MacOS crash when adding modules**: Fixed missing `dvh_set_processing_order` symbol in `libdart_vst_host.dylib` by including missing native source files in the macOS build configuration and rebuilding the library. This restores VST3 routing functionality on macOS.
- **MacOS camera permission error**: Fixed a `MissingPluginException` for `permission_handler` on macOS by implementing a native camera permission request directly in `ThereminCameraPlugin.swift` and bypassing the failing plugin on this platform.

## [2.5.5] - 2026-03-16
- **Vocoder keyboard config**: the Vocoder slot now exposes the same ⊞ tune button as the GF Keyboard and Virtual Piano slots — tap it to override the number of visible keys and key height for that slot independently of the global preference.
- **Vocoder Natural mode redesigned as autotune**: the former Natural waveform used the vocoder filterbank and sounded robotic. It is now a PSOLA (Pitch-Synchronous Overlap-Add) pitch shifter that reads raw mic audio, detects the source pitch via ACF, and retimes grains to the target MIDI note frequency — bypassing the filterbank entirely so the voice timbre is preserved.

## [2.5.4] - 2026-03-15

### Added
- **Theremin & Stylophone**: two new GFPA instrument plugins. The Theremin is a large touch pad (vertical = pitch, horizontal = volume) with a native C sine oscillator — portamento (τ ≈ 42 ms), 6.5 Hz vibrato LFO (0–100 %), adjustable base note and range. The Stylophone is a monophonic 25-key chromatic strip keyboard with four waveforms (SQR/SAW/SIN/TRI), click-free legato, and octave shift ±2.
- **Theremin CAM mode** (Android / iOS / macOS): hand proximity via camera autofocus controls pitch. Falls back to brightness/contrast analysis on fixed-focus cameras (no error on webcams). Live semi-transparent camera preview displayed behind the orb at ≈ 10 fps.
- **Stylophone VIB button**: toggles a 5.5 Hz ±0.5-semitone LFO for a vintage tape-wobble effect. State persists.
- **MIDI OUT jack** on both instruments (rack rear view): connect to a GF Keyboard, VST3, or Looper slot. The Theremin sends note-on/off on semitone crossings; the Stylophone on each key press/release.
- **MUTE toggle** on both instruments: silences the built-in synthesiser while MIDI OUT keeps flowing — use them as expressive MIDI controllers without double-triggering sound.
- **Theremin pad height**: four sizes (S/M/L/XL) via a new HEIGHT control in the sidebar. Persists in the project file.
- **Camera preview mirror**: CAM overlay now shows a selfie-mirrored image; rotation correctly accounts for device orientation (Android). EMA smoothing lag reduced from ~400 ms to ~67 ms.
- **Theremin pad scroll lock**: touching the pad no longer accidentally scrolls the rack.

## [2.5.3] - 2026-03-14

### Added
- Per-slot keyboard configuration modal: tap the tune icon (⊞) just before the MIDI channel badge on any Keyboard or Virtual Piano slot to open the config dialog.
- Settings available per slot: number of visible keys (overrides the global default), key height (Compact / Normal / Large / Extra Large), vertical and horizontal swipe gesture actions, and aftertouch destination CC.
- Key height options map to explicit pixel values (110 / 150 / 175 / 200 px), making the piano usable on phones without changing the global layout.
- Per-slot config is saved in the project `.gf` file and fully backward-compatible (old projects load without changes).
- Preferences screen labels for key count, gesture actions, and aftertouch CC now indicate they are global defaults overridable per slot.

## [2.5.2] - 2026-03-14

### Fixed
- **UI text contrast and readability** — increased font sizes and opacity across the Jam Mode rack, MIDI Looper rack, and rack rear view (patch panel) to improve legibility on dark backgrounds:
  - **Rear view**: section labels (MIDI / AUDIO / DATA) raised from 9 px to 10 px and from near-invisible grey to visible blue-grey; port labels (MIDI IN, AUDIO OUT L, etc.) raised from 8 px to 10 px; display name and [FRONT] button brightened.
  - **Looper**: "IDLE" state badge no longer nearly invisible (white24 → white54); transport button inactive icons brightened; track labels 10 → 11 px; chord bar cells, M/R toggles, speed chips, and Q chip all raised from 9 px to 10 px with higher contrast inactive colours; delete and pin toggle icons/text brightened.
  - **Jam Mode**: ON/OFF LED label 8 → 10 px; MASTER and TARGETS section labels 8 → 10 px; SCALE TYPE hint 7 → 9 px; DETECT/SYNC section labels 7 → 9 px; sync chip and BPM chip unselected text raised from white30/white38 to white54/white60; BPM chip text 9 → 11 px; dropdown placeholder colours brightened; pin toggle brightened.

## [2.5.1] - 2026-03-14

### Added
- **Audio Settings Bar** — a collapsible strip below the transport bar exposes the most-used audio controls inline: FluidSynth output-gain knob (Linux), mic-sensitivity knob, mic-device dropdown, and output-device dropdown (Android). A chevron icon on the left of the transport bar shows/hides the strip (and any future supplementary bars added below it) with an animated slide transition. Settings remain in sync with the Preferences screen.
- **Configurable FluidSynth gain** — the output gain for the built-in FluidSynth engine is now user-adjustable (range 0–10) and persisted across sessions. The Linux default is lowered from 5.0 to 3.0 to match typical VST output levels; the saved value is applied both at startup (via the `-g` flag) and live via FluidSynth's `gain` stdin command.
- **Global MIDI CC bindings for Looper** — five new system action codes (1009-1013) can be mapped to any hardware CC knob/button in the CC Preferences screen: Record/Stop Rec, Play/Pause, Overdub, Stop, and Clear All. When triggered, the action is dispatched to the single active MIDI Looper slot.
- **Global CC for channel mute/unmute (1014)** — a new system action code lets a single hardware CC toggle the mute state of any set of MIDI channels simultaneously. In the CC Preferences dialog, selecting the "Mute / Unmute Channels" action reveals a channel-selection checklist (Ch 1–16); the chosen channels are persisted with the mapping. This is useful for, e.g., silencing the vocoder channel while keeping a backing instrument playing without unplugging cables.
- **Single-instance enforcement for Jam Mode and MIDI Looper** — the "Add Plugin" sheet now checks for an existing Jam Mode or Looper before inserting a new one. If one is already present, the sheet closes and a SnackBar explains that only one instance is allowed. This prevents incoherent multi-looper setups and simplifies CC mapping.
- **Record-stop quantization (6.7)** — each looper track now has an individual quantize setting (off / 1/4 / 1/8 / 1/16 / 1/32). When set, all recorded event beat-offsets are snapped to the nearest grid line the moment the user presses stop. A minimum one-grid-step gap between paired note-on and note-off is enforced to prevent zero-duration notes. The setting is stored in `LoopTrack.quantize`, persisted in `.gf` project files, and defaults to `off`.
- **Quantize chip in transport strip** — a compact "Q:…" chip (amber, cycles on tap) has been added to the transport strip next to CLEAR, at the slot level. Set it before recording; the grid applies to every subsequent recording pass (first-pass and overdubs).

### Fixed
- **Jam Mode and Looper rack headers incorrectly highlighted / never highlighted** — Jam Mode and Looper slots have no MIDI channel (`midiChannel == 0`), mapping to channel index 0 — the same as any instrument on MIDI channel 1. Pressing a key on an unconnected Virtual Piano updated `channels[0].activeNotes`, causing both racks to flash blue even without a cable connection, while they never lit up for their own activity. Fixed by routing each plugin type to its own reactive listener: Looper glows when `LooperSession.isPlayingActive` is true (actively sending MIDI to connected slots), Jam Mode glows only when enabled AND the master channel is actively sending input matching the Detect setting (bass-note mode: at least one key held; chord mode: a chord recognised), and instrument slots continue to glow on `channelState.activeNotes`.
- **Pitch bend / CC not forwarded through VP → instrument cable (external MIDI)** — external MIDI pitch-bend (0xE0), control-change (0xB0), and channel-pressure (0xD0) messages received on a Virtual Piano slot's channel are now forwarded through its MIDI OUT cable to every connected downstream slot. Previously only Note On/Off were relayed; expression messages were silently dropped.
- **Pitch bend / CC not forwarded through VP → instrument cable (on-screen piano)** — sliding a finger on the Virtual Piano widget (pitch bend, vibrato, any CC gesture) now also forwards through the VP's MIDI OUT cable to connected slots. Previously these gestures called `AudioEngine` directly on the VP's own channel, bypassing cable routing entirely.
- **Pitch bend inoperative on the Vocoder** — the Vocoder carrier oscillator now responds to MIDI pitch bend. A new `VocoderPitchBend` C FFI function updates a `g_pitchBendFactor` multiplier applied in `renderOscillator()` across all four waveform modes (Saw, Square, Choral, Natural/PSOLA). Bend range is ±2 semitones (VST convention).
- **Vibrato (CC#1 / mod wheel) inoperative on the Vocoder** — added a 5.5 Hz LFO to the vocoder carrier oscillator driven by CC#1 (modulation wheel). Depth 0 = no vibrato; depth 127 = ±1 semitone modulation. A new `VocoderControlChange` C FFI function and `g_vibratoDepth` global control the depth; `g_effectivePitchFactor` now combines both pitch bend and vibrato for a single multiply in `renderOscillator`.
- **Pitch bend / CC not sent to VST3 plugins via cable** — `VstHostService` now exposes `pitchBend()` and `controlChange()` methods so that expression messages arriving via VP cable routing reach VST3 instrument plugins (effective once the native `dart_vst_host` binding is added).
- **Soundfont volume too low** — FluidSynth's built-in default gain (0.2) produced ~0.1 amplitude, far quieter than typical VST output. Raised to 5.0 on both Linux (CLI `-g 5` flag) and Android (`synth.gain` in native-lib.cpp), bringing soundfonts in line with the rest of the audio graph.
- **"Pin below transport" Jam Mode shortcut** — the pin toggle in the Jam Mode rack slot now works as intended. Pinning a Jam Mode slot inserts a compact one-liner strip (slot name · ON/OFF LED · live scale LCD) directly below the transport bar for quick control without scrolling. Pin state is persisted in `.gf` project files.
- **"Pin below transport" looper shortcut** — the pin toggle in the looper rack slot now works as intended. Pinning a looper inserts a compact one-liner control strip (slot name · LOOP · STOP · CLEAR · Q chip · state LCD) directly below the transport bar so the user can control the looper from anywhere without scrolling to its rack slot.

## [2.5.0] - 2026-03-13

### Added
- **MIDI Looper (Phase 7.1–7.4)** — new multi-track MIDI looper rack slot (`LooperPluginInstance`) with MIDI IN / MIDI OUT jacks in the patch view. Record MIDI from any connected source, loop it back to instrument slots, and overdub additional layers in parallel.
- **LooperEngine service** — beat-accurate 10 ms playback engine with bar-quantised loop lengths, smart downbeat sync, per-track mute/reverse/half-speed/double-speed modifiers, and per-bar chord detection via `ChordDetector`. State machine: idle → armed → recording → playing → overdubbing.
- **LoopTrack model** — serialisable MIDI event timeline with beat-offset timestamps, speed modifiers, reverse flag, mute state, and a per-bar chord grid (`Map<int, String?>`).
- **Looper front-panel UI** — hardware-style slot panel with REC / PLAY / OVERDUB (amber layers icon) / STOP / CLEAR transport buttons; state LCD badge; per-track chord grid (horizontally scrollable bar cells); mute (M), reverse (R), and speed (½× / 1× / 2×) per-track controls; pin-below-transport toggle.
- **Overdub** — dedicated OD button (amber, layers icon) enabled only while a loop is playing. Pressing it starts a new overdub layer; pressing again stops the overdub pass and resumes clean playback. REC button is disabled during play to prevent accidental first-pass overwrite.
- **Looper persistence** — recorded tracks and chord grids are saved in `.gf` project files under `"looperSessions"` and restored on project open/autosave reload.
- **Hardware CC assignment** — bind any CC to looper actions (toggle-record, toggle-play, stop, clear) per slot.
- **Add Plugin sheet** — "MIDI Looper" tile added (green loop icon).
- 20 new localised strings for the looper UI (EN + FR).

### Fixed
- **Linux audio silence after looper repeat** — FluidSynth stdout/stderr were never drained, causing the OS pipe buffer (~64 KB) to fill up after prolonged looper playback. Once full, FluidSynth blocked on its own output writes, stopped reading from stdin, and all note-on/note-off commands silently dropped — producing stuck held notes followed by total silence from all sources (looper, MIDI keyboard, on-screen piano). Fixed by draining both streams immediately after `Process.start` and adding the `-q` (quiet) flag to reduce FluidSynth's output volume.
- **Save As… crash** — `ProjectService` was registered as `Provider` instead of `ChangeNotifierProvider`, causing an unhandled exception when `context.read<ProjectService>()` was called from `rack_screen.dart`. Fixed by changing to `ChangeNotifierProvider`.
- **Splash screen ProjectService isolation** — splash screen now uses the shared `Provider`-registered `ProjectService` instance (via `context.read`) instead of creating a local instance, so autosave path and project state are consistent between screens.
- **Looper not recording from GFK on-screen keys** — on-screen piano key presses for `GrooveForgeKeyboardPlugin` (and other non-VP, non-VST3 slots) now also feed any looper connected via a MIDI OUT cable in the patch view. Previously only `VirtualPianoPlugin` slots dispatched through cables; GFK called FluidSynth directly and bypassed the looper entirely.
- **Looper not recording from external (hardware) MIDI on GFK channel** — `_routeMidiToVst3Plugins` in `rack_screen.dart` now also looks up GFK slots for the incoming MIDI channel and calls `_feedMidiToLoopers` as a side-effect, so a hardware controller playing on a GFK channel is captured by a connected looper. FluidSynth still plays in parallel (return value unchanged for pure GFK channels).
- **Looper chord grid not refreshing during recording** — `LooperEngine._detectBeatCrossings` now calls `notifyListeners()` when a bar-boundary chord flush occurs, so the chord grid in `LooperSlotUI` updates in real time without waiting for a state-machine transition.
- **Loops lost on app restart** — the autosave callbacks (`rack.onChanged` and `audioGraph.addListener`) are now registered **after** `loadOrInitDefault` completes in `splash_screen.dart`. Previously, `audioGraph.notifyListeners()` fired synchronously during `audioGraph.loadFromJson` — before `looperEngine.loadFromJson` was called — triggering an autosave that captured an empty looper and overwrote the persisted session data.
- **Missed playback events / skipped notes** — looper playback now uses `LooperSession.prevPlaybackBeat` (the actual transport beat at the end of the previous tick) to define the event window. Previously a hardcoded `0.01 × bpm / 60` estimate was used, which silently skipped events whenever the Dart timer fired late (GC pause, heavy UI frame).
- **Stuck notes and progressive chord decay** — notes held past the loop boundary (no note-off recorded) no longer ring indefinitely. `LoopTrack.activePlaybackNotes` tracks which notes are "on" during playback; at wrap-around the looper sends note-offs before the next iteration begins; at stop/pause/transport-stop all held notes are silenced. Eliminates the FluidSynth voice-stealing that caused a 3-note chord to lose one note per loop iteration.

## [2.4.0] - 2026-03-12

### Added
- **Audio Signal Graph** — directed graph model (`AudioGraph` service) connecting rack slots with typed ports: MIDI IN/OUT (yellow), Audio IN/OUT L/R (red/white), Send/Return (orange), and Data chord/scale ports (purple for Jam Mode). Validates port compatibility, prevents duplicate edges, and enforces cycle detection via DFS.
- **"Back of Rack" patch view** — toggle via the cable icon in the app bar. The rack flips to show each slot's back panel with coloured virtual jacks. MIDI/Audio cables are drawn as bezier curves with natural downward sag; data cables (chord/scale routing) are rendered in purple and stay in sync with the Jam Mode dropdowns.
- **Cable interactions** — long-press an output jack to start drawing a cable; compatible input jacks pulse; drop on a valid target to create the connection. Tap a cable to disconnect it via a context menu. Incompatible drops are silently ignored.
- **VirtualPianoPlugin** — a new addable slot type (addable from "Add Plugin") with a real MIDI channel, an on-screen piano keyboard, and MIDI IN / MIDI OUT / Scale IN jacks in the patch view. MIDI OUT is aligned with the same position as other slots. Touch-keyboard notes are forwarded through drawn MIDI cables to connected target slots (VST3 or FluidSynth). Jam Mode's Scale OUT can be wired to its Scale IN jack to enable scale locking for VST instruments.
- **Audio graph persistence** — all MIDI/Audio cable connections are saved and restored in `.gf` project files under the `"audioGraph"` key. Data connections continue to be stored per-plugin in `masterSlotId`/`targetSlotIds`.
- **Slot cleanup** — removing a rack slot automatically disconnects all its MIDI/Audio cables from the graph.
- 20 new localised strings for the patch view UI (EN + FR).
- **User guide "Rack & Cables" tab** — new fifth tab in the in-app user guide covering patch view toggle, jack types, cable drawing, disconnecting, data cable/Jam Mode sync, and the Virtual Piano slot.
- **Cable disconnect badge** — visible ✕ badge drawn at each cable's midpoint with a 48 dp tap zone; `HitTestBehavior.opaque` ensures the badge reliably receives taps.
- **Add Plugin sheet scrollable** — sheet now uses `isScrollControlled: true` and `SingleChildScrollView`, preventing overflow on small or crowded screens.

### Fixed
- **Scale lock on individual key taps** — `VirtualPiano._onDown` now applies `_validTarget` snapping before calling `onNotePressed`, so tapping a single invalid key redirects to the nearest valid pitch class (same behaviour as glissando). The same fix applies to glissando note transitions in `_onMove`: the snapped pitch is stored in `_pointerNote` and forwarded to the callback instead of the raw key under the finger. This matters especially for VP→VST3 cable routing which bypasses the engine's internal snapping.
- **External MIDI through Virtual Piano** — incoming MIDI on a VP's channel is now forwarded through its MIDI OUT cable connections (respecting scale lock/Jam Mode snapping), so a hardware MIDI controller can drive a VST3 instrument via the VP routing chain. Previously, external MIDI on a VP channel fell through to FluidSynth (silent/wrong sound) and never reached the downstream VST.

### Fixed
- **Scale lock on individual key taps** — `VirtualPiano._onDown` now applies `_validTarget` snapping before calling `onNotePressed`, so tapping a single invalid key redirects to the nearest valid pitch class (same behaviour as glissando). The same fix applies to glissando note transitions in `_onMove`: the snapped pitch is stored in `_pointerNote` and forwarded to the callback instead of the raw key under the finger.
- **External MIDI through Virtual Piano** — incoming MIDI on a VP's channel is now forwarded through its MIDI OUT cable connections (respecting scale lock/Jam Mode snapping), so a hardware MIDI controller can drive a VST3 instrument via the VP routing chain. Previously, external MIDI on a VP channel fell through to FluidSynth (silent/wrong sound) and never reached the downstream VST.
- **VST3 pitch off by ~1.5 semitones on Linux** — the ALSA audio state had a hardcoded default sample rate of 44100 Hz while VST3 plug-ins were resumed at 48000 Hz, causing the audio output to play back at the wrong speed. `dvh_start_alsa_thread` now reads `sr` and `maxBlock` from the host configuration so ALSA opens at the same rate the plug-ins use.

### Architecture
- `AudioPortId` enum with colour, direction, family, and compatibility helpers.
- `AudioGraphConnection` model with canonical composite ID (no UUID dependency).
- `PatchDragController` ChangeNotifier for live cable drag state.
- `RackState` now receives `AudioGraph` as a constructor parameter (`ChangeNotifierProxyProvider3`).
- `ProjectService` methods gain an `AudioGraph` parameter; autosave is also triggered on graph mutations.
- `PatchCableOverlay` uses per-midpoint `Positioned` tap zones computed via `addPostFrameCallback` after each paint; no full-screen gesture interceptor.
- `DragCableOverlay` is a `StatefulWidget` with an internal `ListenableBuilder` so it repaints on pointer-move without a parent `Consumer`.
- **Native audio graph execution** — `dart_vst_host` ALSA/CoreAudio loop gains `dvh_set_processing_order` (topological order) and `dvh_route_audio` / `dvh_clear_routes` (signal routing). When a VST3 audio cable is drawn in the patch view, the source plugin's output is fed directly into the destination plugin's audio input; the source is no longer mixed into the master bus. Plugins with no outgoing audio cable continue mixing directly to the master output. Dart-side sync via `VstHostService.syncAudioRouting` is triggered whenever the `AudioGraph` changes or a slot is added/removed.
- `GraphImpl::process()` in `dart_vst_graph` now uses Kahn's topological sort so nodes are always processed in dependency order (sources before effects), replacing the previous naïve index-order traversal.
- `dvh_graph_add_plugin` added to the `dart_vst_graph` C API — wraps an already-loaded `DVH_Plugin` as a non-owning node so external plugin managers can participate in the graph without transferring lifecycle responsibility.

## [2.3.0] - 2026-03-11

### Added
- **Global transport engine**: a new `TransportEngine` service tracks BPM (20–300), time signature, play/stop state, and swing. Changes are propagated live to all loaded VST3 plugins via `dvh_set_transport` → `ProcessContext`, so tempo-synced effects (LFOs, delays, arpeggiators) instantly lock to the app BPM.
- **Transport bar** in the `RackScreen` app bar: inline BPM field (tap to type), **`−` / `+` nudge buttons** (tap ±1 BPM; hold for rapid repeat — 400 ms initial delay then 80 ms intervals), **scroll-wheel on BPM display** (scroll up/down ±1 BPM), **Tap Tempo** button (averages the last 4 taps, rejects outliers), **▶ / ■ Play/Stop** toggle, **time signature selector**, **beat-pulse LED** (flashes amber on every beat, red on downbeat with fade animation), and **audible metronome toggle** (🎵 icon; GM percussion click via FluidSynth / flutter_midi_pro channel 9 — side-stick on downbeat, high-wood-block on other beats).
- **Transport state saved/restored** in `.gf` project files: BPM, time signature, swing, and `metronomeEnabled` are preserved per project. Missing `transport` key in older files defaults to `120 BPM / 4/4 / metronome off`.
- **Jam Mode BPM lock** — fully functional end-to-end: the `Off / 1 beat / ½ bar / 1 bar` sync setting in each Jam Mode slot now gates scale-root changes at beat-window boundaries (wall-clock based, derived from live BPM). Both the piano shading and the note snapping use the same locked pitch-class set — what you see highlighted is exactly what you hear.
- **Walking bass scale persistence**: when the master channel has no active notes (bass note released between steps), the last known bass scale is cached in `_lastBassScalePcs` so follower channels continue snapping correctly across note transitions.
- **`bpmLockBeats` wired end-to-end**: the beat-lock setting flows from the Jam Mode UI → `plugin.state` → `RackState._syncJamFollowerMapToEngine` → `GFpaJamEntry.bpmLockBeats` → `AudioEngine._shouldUpdateLockedScale()`.
- **Forward-compatibility reserved keys**: `"audioGraph": { "connections": [] }` and `"loopTracks": []` added to newly created `.gf` files (empty — prevents format churn when Phases 5 and 7 land).

### Fixed
- **Jam Mode chord scale locking**: snapping and piano shading now always use the same `_getScaleInfo(chord, scaleType)` function. Previously, Gemini-introduced code routed snapping through `GFJamModePlugin.processMidi` (which used `chord.scalePitchClasses` — the raw chord-detector output) while the shading used the chord-quality × scale-type matrix. For Jazz, Pentatonic, Blues, Classical and all non-Standard scale types, the two diverged — played notes no longer matched highlighted keys. Snapping is now always done directly via `_snapKeyToGfpaJam`, which calls `_getScaleInfo` identically to the shading logic.
- **Jam Mode MIDI input locking**: external MIDI keyboard notes on a follower channel are now correctly snapped. The broken plugin-registry routing introduced by a previous refactor is removed; all paths go through `_snapKeyToGfpaJam`.
- **Snap algorithm direction restored**: all three snapping paths (scale lock, GFPA jam, virtual piano) now use the original DOWN-first tie-breaking preference (nearest lower neighbor wins on equidistant candidates), matching the pre-regression behaviour.

### Architecture
- `TransportEngine` now runs a `Timer.periodic(10 ms)` ticker while playing; it advances `positionInBeats` / `positionInSamples` by wall-clock elapsed microseconds, fires `onBeat(isDownbeat)` on each beat boundary, increments `ValueNotifier<int> beatCount` (for UI pulse), and calls `_syncToHost()` every tick so VST3 plugins always read an accurate playhead position.
- `TransportEngine.onBeat` callback is wired by `RackState` to call `AudioEngine.playMetronomeClick(isDownbeat)` when `metronomeEnabled` is true.
- `AudioEngine.bpmProvider` / `isPlayingProvider` — lightweight function-reference callbacks injected by `RackState`; the audio engine reads live transport state without a hard import dependency on `TransportEngine`.
- `AudioEngine._bpmLockedScalePcs` — per-follower-channel cache of the currently committed locked scale pitch-class set, shared by both the piano shading propagation (`_performChordUpdate`) and the note snapper (`_snapKeyToGfpaJam`).
- `AudioEngine._lastScaleLockTime` — wall-clock timestamp per follower channel; `_shouldUpdateLockedScale()` compares elapsed time against `bpmLockBeats × 60 / bpm` ms to gate updates.

---

## [2.2.1] - 2026-03-11

### Added
- **GrooveForge Keyboard VST3 plugin**: Distributable `.vst3` bundle (Linux) that runs inside any VST3-compatible DAW (Ardour, Reaper, etc.) without requiring the GrooveForge app. MIDI in → FluidSynth → stereo audio out. Parameters: Gain, Bank, Program.
- **GrooveForge Vocoder VST3 plugin**: Distributable `.vst3` bundle (Linux) implementing the sidechain vocoder pattern standard in professional DAWs. Route any audio track as the carrier signal via the DAW's sidechain bus; play MIDI notes to control pitch. Parameters: Waveform, Noise Mix, Bandwidth, Gate Threshold, Env Release, Input Gain.
- **`vocoder_dsp.h/c`**: Context-based vocoder DSP library extracted from `audio_input.c` — no audio-backend dependencies, usable from both the GFPA plugin and the VST3 bundle.
- **Flatpak DAW compatibility**: Both bundles load correctly inside sandboxed Flatpak builds of Ardour/Reaper. Achieved by statically linking FluidSynth (built from source with all audio backends disabled), inlining math functions with `-ffast-math`, and patching all `$ORIGIN` RPATHs via `scripts/bundle_deps.sh`.
- **`scripts/bundle_deps.sh`**: Shell script that recursively bundles shared library dependencies into a `.vst3` bundle and patches all RPATHs to `$ORIGIN` for self-contained deployment.
- **VST3 build documentation**: Comprehensive `packages/flutter_vst3/vsts/README.md` covering plugin properties, build instructions, Flatpak compatibility notes, a GFPA vs VST3 comparison table, and a troubleshooting guide.

### Architecture
- Pure C++ VST3 plugins using the Steinberg VST3 SDK (MIT since v3.8) — no Dart or Flutter runtime required in the DAW.
- `grooveforge_keyboard.vst3`: single compilation unit (`factory.cpp` includes `processor.cpp` + `controller.cpp`), FluidSynth statically linked via CMake `FetchContent` (v2.4.0 built from source), Linux `ModuleEntry`/`ModuleExit` entry points via `linuxmain.cpp`.
- `grooveforge_vocoder.vst3`: same single-TU pattern, `vocoder_dsp` static library compiled with `-fPIC -ffast-math`, zero external runtime dependencies.
- `make keyboard` / `make vocoder` / `make grooveforge` targets perform a real `cp -rL` install to `~/.vst3/` (no symlinks — required for Flatpak sandbox compatibility).

---

## [2.2.0] - 2026-03-09

### Added
- **GrooveForge Plugin API (GFPA)**: A pure-Dart extensible plugin system, platform-independent (Linux, macOS, Windows, Android, iOS). Defines typed interfaces: `GFInstrumentPlugin` (MIDI in → audio out), `GFEffectPlugin` (audio in → audio out), `GFMidiFxPlugin` (MIDI in → MIDI out). Ships as a standalone `packages/grooveforge_plugin_api/` package with no Flutter dependency, enabling third-party plugins.
- **`packages/grooveforge_plugin_ui/`**: Flutter companion package exposing reusable UI helpers — `RotaryKnob`, `GFParameterKnob`, `GFParameterGrid` — for rapid plugin UI development.
- **Vocoder as a standalone GFPA slot**: The vocoder is now its own rack slot with a dedicated MIDI channel, piano, and controls. Multiple vocoders can coexist independently in the same project.
- **Jam Mode GFPA plugin**: A full `GFMidiFxPlugin` implementation with a complete UI overhaul inspired by the Roland RC-20.
  - Signal-flow row: MASTER dropdown → amber LCD (live scale name + type tag) → TARGETS chips.
  - LCD doubles as a scale-type selector; displays `[SCALE TYPE]` bracket only for families where the name is not self-describing (Standard, Jazz, Classical, Asiatic, Oriental).
  - Glowing LED enable/disable button with ON/OFF indicator.
  - **Multiple targets**: one Jam Mode slot can control any number of keyboard and vocoder slots simultaneously.
  - **Bass note detection mode**: uses the lowest active note on the master channel as the scale root — ideal for walking-bass lines.
  - **BPM sync lock** (Off / 1 beat / ½ bar / 1 bar): scale root changes only on beat boundaries (activates fully when Phase 4 transport lands).
  - Responsive layout: wide two-row panel (≥480 px); narrow stacked column (<480 px); controls strip reflows with `Wrap` on very small screens.
  - Key borders and wrong-note dimming settings moved from Preferences into the Jam Mode rack slot.
- **Default project template**: new projects start with two keyboard slots and a pre-configured Jam Mode slot (master = CH 2, target = CH 1, inactive by default).
- **`GFpaPluginInstance` model**: serializes/deserializes as `"type": "gfpa"` in `.gf` files; supports multiple `targetSlotIds` (backward-compatible with old single `targetSlotId` string).
- **GFPA plugin registry** (`GFPluginRegistry`): singleton registry for all built-in and future third-party plugins.

### Changed
- Scale name display in the Jam rack now shows the full `"C Minor Blues"` form (root note + scale name); the `[TYPE]` bracket is shown only when the scale family does not already encode the type.
- Virtual keyboard no longer exposes a vocoder option in its soundfont dropdown (vocoder is its own slot type).
- Default new project no longer sets master/slave roles on keyboard slots (role concept superseded by the Jam Mode GFPA slot).

### Removed
- **Legacy `JamSessionWidget`** and global `ScaleLockMode` preference — all jam routing is now managed by the Jam Mode GFPA plugin slot.
- **`GrooveForgeKeyboardPlugin.jamEnabled/jamMasterSlotId`** fields — dead code purge after GFPA migration.
- **`_buildMasterDropdown` / `_buildSlavesSection`** — replaced by `GFpaJamModeSlotUI`.
- **Vocoder option from the keyboard soundfont dropdown** — vocoder is a dedicated slot type.

### Fixed
- **Vocoder MIDI routing**: removed erroneous omni-mode routing that caused all MIDI input to trigger the vocoder channel regardless of which slot was targeted.
- **Startup hang**: added `_isConnecting` guard to `MidiService` to prevent concurrent `connectToDevice` calls when the 2-second polling timer raced with `_tryAutoConnect` on Linux.
- **Note labels on white keys**: note name labels (e.g. `C4`, `F#6`) now render correctly on white keys as well as black keys.
- **Scale immediately applied on change**: changing the scale type in a Jam Mode slot now propagates to all target channels without requiring a stop/restart cycle.
- **Vocoder targetable by Jam Mode**: vocoder slots can now be added as Jam Mode targets, receiving scale locking the same way keyboard slots do.
- **Rack bottom padding**: added bottom margin so the FAB no longer overlaps the last rack slot.

---

## [2.1.0] - 2026-03-08

### Added
- **External VST3 plugin hosting** (Linux, macOS, Windows): load any `.vst3` bundle into a rack slot via the "Browse VST3" tile in the Add Plugin sheet.
- **Parameter knobs**: each VST3 slot displays category chips (one per parameter group). Tapping a chip opens a modal grid of `RotaryKnob` widgets with search, sub-group filter, and pagination (24 per page).
- **Native plugin editor window** (Linux): opens the VST3 plugin's own GUI in a floating X11 window. The editor can be opened, closed, and reopened without freezing or crashing.
- **ALSA audio output thread**: `dart_vst_host_alsa.cpp` — low-latency ALSA playback thread consuming VST3 audio output in real time.
- **Single-component VST3 support**: controller is queried from the component when `getControllerPtr()` returns null (Aeolus, Guitarix).
- **Multi-output-bus support**: all audio output buses are configured dynamically on resume (Surge XT Scene B, etc.).
- **Autosave reload**: VST3 plugin instances in a `.gf` project are re-loaded into `VstHostService` on startup via the splash screen.
- **Parameter persistence**: VST3 parameter values are stored in `Vst3PluginInstance.parameters` and saved to the `.gf` project.

### Architecture
- `packages/flutter_vst3/` vendored at project root (BSD-3-Clause, compatible with MIT); nested `.git` removed so it is committed to the repo.
- `dart_vst_host` converted to a Flutter FFI plugin (`ffiPlugin: true`) with platform-specific CMakeLists for Linux (ALSA + X11), Windows (Win32), and macOS (Cocoa/CoreAudio).
- Platform-conditional import: `vst_host_service.dart` exports the desktop implementation on Linux/macOS/Windows and a no-op stub on mobile.

### Fixed
- JUCE-based plugins (Surge XT, DISTRHO): `setComponentState()` called after init to build the internal processor reference.
- Editor X-button close: `removed()` called on the event thread to avoid deadlock with JUCE's GUI thread.
- Re-open after close: `g_cleanupFutures` wait ensures `removed()` finishes before `createView()` is called again.

---

## [2.0.0] - 2026-03-08

### Added
- **Plugin Rack**: Replaced the fixed channel list with a fully dynamic, reorderable plugin rack. Each slot is an independent synthesizer lane with its own MIDI channel, soundfont/patch, and Jam Mode role.
- **GrooveForge Keyboard Plugin**: The built-in synth/vocoder is now a proper plugin instance with per-slot configuration (soundfont, bank, patch, vocoder settings) and full save/restore support.
- **Drag-and-Drop Reordering**: Rack slots can be reordered freely by dragging the handle on the left of each slot header.
- **Add / Remove Plugins**: A floating action button opens a sheet to add new GrooveForge Keyboard slots (or VST3 plugins on desktop — Phase 2). Slots can be removed with confirmation.
- **Master / Slave Roles in Slot Headers**: Each slot now has a Master/Slave chip directly in its header. Tapping toggles the role; the Jam Mode engine is updated automatically.
- **MIDI Channel Badge**: Each slot shows its MIDI channel and allows changing it via a picker, preventing conflicts with other slots.
- **Project Files (.gf format)**: Projects are now saved and loaded as JSON `.gf` files. The app bar file menu provides Open, Save As, and New Project actions.
- **Autosave**: Every rack change is automatically persisted to `autosave.gf` in the app documents directory, restoring the session on next launch.
- **First-Launch Defaults**: On first launch, the rack is pre-configured with one Slave slot on MIDI channel 1 and one Master slot on MIDI channel 2.
- **Simplified Jam Mode Widget**: The Jam Mode bar no longer shows master/slave channel dropdowns (managed per-slot in the rack); it now focuses on the JAM start/stop and scale type controls.

### Removed
- **Visible Channels Modal**: The "Filter Visible Channels" dialog has been removed. The rack is the channel list — every slot is visible.
- **SynthesizerScreen** and **ChannelCard**: Replaced by `RackScreen` and `RackSlotWidget`.

### Architecture
- New `PluginInstance` abstract model with `GrooveForgeKeyboardPlugin` and `Vst3PluginInstance` (desktop Phase 2 stub).
- New `RackState` ChangeNotifier manages the plugin list and syncs Jam master/slave to `AudioEngine`.
- New `ProjectService` handles `.gf` file I/O (JSON save/load/autosave).

## [1.7.1] - 2026-03-07
### Added
- **Vocoder Feedback Warning**: Implemented a safety modal that warns users about potential audio feedback (Larsen effect) when using the vocoder with internal microphones and speakers. The warning is shown once and can be dismissed permanently.

### Fixed
- **Android Audio Input Regression**: Fixed a critical issue where internal and external microphones were not working on Android due to missing runtime permissions and incorrect device ID handling in the native layer.

## [1.7.0] - 2026-03-07
### Added
- **Absolute Pitch Vocoder (Natural Mode)**: A complete redesign of the vocoder's high-fidelity mode using **PSOLA (Pitch Synchronous Overlap and Add)** grain synthesis. It now captures your voice cycle and triggers fixed-duration grains at the **exact MIDI frequency**. This preserves your natural vocal formants and vowel character, eliminating the "accelerated" feeling and ensuring perfect pitch locking even if you sing out of tune.
- **Audio Device Persistence Fix (Linux)**: Resolved an issue where the preferred audio input device was not correctly initialized on startup. All vocoder settings (Waveform, Noise Mix, Gain, etc.) are now correctly persistent and applied before the audio stream starts.
- **Improved Vocoder Volume**: Integrated RMS-based normalization into the PSOLA engine to ensure the Natural mode matches the perceived loudness of the other vocoder modes.
- **Vocoder Noise Gate**: Added a dedicated "GATE" control to the vocoder panel to eliminate background noise and feedback hum during quiet passages.
- **Zoomed Knob Preview**: Added a zoomed knob preview that appears on interaction (200ms hold or instant drag), providing clear visual feedback on the current value.
- **Autoscroll Toggle**: Added a user preference to enable or disable automatic channel list scrolling when MIDI notes are played (disabled by default).
- **Audio Output Device Selection**: Added an output device selector in Preferences, alongside the existing mic selector, for routing vocoder output to a specific speaker or headset.
- **AAudio Jitter Mitigation**: Integrated a background health watcher that monitors audio stream stability and triggers a silent engine restart if persistent glitches are detected.
- **DSP Inner-Loop Optimization**: Significantly reduced per-sample processing overhead by refactoring core audio synthesis logic, enhancing real-time performance on mobile devices.
- **Engine Stability & Audio Decoupling**: Massive improvement in overall app stability and sound quality by decoupling the low-level audio lifecycle from the Flutter UI thread. This eliminates the "chopped sound" and UI lag that previously occurred after extended use.

### Changed
- **Vocoder Mode Rename**: "Neutral" mode is now **"Natural"** to better reflect its high-fidelity vocal character.
- **Knob Responsiveness**: Enhanced `RotaryKnob` sizing and layout for narrow/mobile screens to improve touch accuracy and visibility.
- **Adaptive Vocoder Layout**: Optimized the vocoder row with smart icon/label switching to maintain accessibility on small screens.
- **Mic automatically restarts on device change**: Changing the input or output device in Preferences now automatically restarts the audio capture engine without requiring a manual "Refresh Mic" tap.

### Fixed
- **Absolute MIDI Locking**: Fixed the issue where the vocoder would follow the singer's pitch inaccuracies instead of the keyboard notes.
- **Optimized Vocoder Latency**: Achieved near-real-time performance by decoupling microphone capture from the main playback thread using a lock-free ring buffer. This eliminates the significant (400ms+) onset delay caused by Android's duplex clock synchronization.
- **Squelch Gate Precision**: Bypassed the noise gate when notes are active to prevent sound occlusion at the start of vocal phrases.
- **USB Audio Device Enumeration**: Switched Android audio device queries to `GET_DEVICES_ALL` with capability-based filtering, ensuring USB microphones and wired headsets are always listed even when sharing a USB-C hub.
- **Duplicate device in input list**: Bidirectional USB headsets (e.g. a USB headset with both mic and speaker) no longer appear twice in the mic selector — only the source/mic side is listed.
- **Stale device ID after reconnect**: Selecting a USB mic or headset and then unplugging/replugging the hub (which reassigns device IDs) no longer shows "Disconnected" — the selection automatically resets to the system default.
- **Auto-fallback on device disconnect**: The app now listens to Android `AudioDeviceCallback` events. When a previously selected input or output device is removed, the selection resets to the system default automatically.
- **Audio engine restart loop**: Added a re-entrancy guard (`_isRestartingCapture`) with a 500 ms cooldown on `restartCapture()` to prevent Fluidsynth's Oboe disconnect-recovery events from cascading into an infinite restart loop.

## [1.6.1] - 2026-03-06
### Added
- **Revamped User Guide**: Reorganized tabs (Features, MIDI Connectivity, Soundfonts, Musical Tips).
- **Vocoder Documentation**: Added detailed instructions on how to use the new vocoder features.
- **Musical Improvisation Tips**: Added a new section with theory bits to help beginners improvise using scales.
- **Auto-Welcome**: The user guide now appears automatically on first launch or after a major update to highlight new features.

## [1.6.0] - 2026-03-05
### Added
- **Vocoder Overhaul**: 32-band polyphonic vocoder with carrier waveform selection (including new 'Neutral' mode).
- **Native Audio Input**: High-performance audio capture via miniaudio + FFI.
- **Rotary UI Control**: New `RotaryKnob` custom widget for a more tactile experience.
- **Advanced Vocoder Controls**: Added Bandwidth and Sibilance injection parameters.
- **Audio Session Management**: Integration with `audio_session` for improved Bluetooth and routing support.
- **Enhanced Level Meters**: Real-time visual feedback for vocoder input and output levels.

### Changed
- **Performance Optimizations**: Low-latency audio profile and optimized note release tails.

## [1.5.2] - 2026-03-04
### Fixed
- **Chord Release Stabilization**: Optimized the chord release logic in Jam Mode by implementing a robust 50ms debounced stabilization window, preventing chord identity "flickering" during natural finger lift-offs.

## [1.5.1] - 2026-03-04
### Added
- **Instant Device Connection**: When a new MIDI device is plugged in while on the main synthesizer screen, an automatic prompt appears allowing instant connection.
- **Improved Auto-Reconnect**: MIDI devices now reliably auto-reconnect even if unplugged and replugged while the app is running.

## [1.5.0] - 2026-03-04
### Added
- **Internationalization (i18n)**: Added full support for application localization.
- **French Language**: Translated the entire application UI and provided a French changelog (`CHANGELOG.fr.md`).
- **Language Preferences**: Users can now dynamically switch the application language from the Preferences screen (System Default, English, French).

## [1.4.5] - 2026-03-04
### Added
- **Jam Mode Borders Toggle**: Added a user-configurable preference to toggle the visibility of the visual borders around scale-mapped key groups in Jam Mode.
- **Jam Mode Wrong Note Highlighting**: Pressing an out-of-scale physical key in Jam Mode now colors the originally pressed wrong key in red and highlights the correctly mapped target note in blue, with a user preference to optionally toggle the red coloring.

## [1.4.4] - 2026-03-03
### Added
- **Jam Mode Click Zones**: Virtual Piano keys in Jam Mode are now grouped with the valid keys they snap to, forming unified clickable zones enclosed in subtle colored borders.

## [1.4.3] - 2026-03-02
### Fixed
- **Virtual Piano Artifacts**: Fixed a bug where Virtual Piano shading did not update immediately when Jam Mode was started or stopped.
- **Scroll Interference**: Prevented the main screen from scrolling vertically when performing gestures on the Virtual Piano keys.

## [1.4.2] - 2026-03-02
### Added
- **Reactive Jam Mode Sync**: Scale tags and virtual piano visuals (grayed-out keys) now update in real-time when the jam master scale changes or when slave channel configurations are modified.

### Changed
- **Virtual Piano Scalability**: Slave channels now visually gray out keys that do not belong to the master channel's current scale.
- **Improved UI Performance**: Fixed complex widget nesting issues in `ChannelCard` to guarantee clean and reactive UI builds.

### Fixed
- **Glissando Behavior**: Notes outside the current scale continue to sound if they are part of an ongoing glissando gesture instead of being stopped abruptly.
- **Virtual Piano Artifacts**: Resolved keyboard transparency artifacts by using solid colors for disabled keys.

## [1.4.1] - 2026-02-28
### Added
- **Configurable Expressive Gestures**: Users can now independently assign actions (None, Pitch Bend, Vibrato, Glissando) to Vertical and Horizontal key gestures.
- **Unified Gesture Preferences**: High-level configuration in the Preferences screen with new axis-specific dropdown menus.
- **Android Permission Optimization**: Decoupled Bluetooth from Location for Android 12+. Location access is no longer required on modern devices.
- **Improved UI Responsiveness**: Refactored the Preferences screen with an adaptive layout to prevent text crushing on narrow mobile devices.

### Changed
- **Performance Optimization**: Chord detection in Jam mode is now asynchronous, significantly reducing UI latency during heavy performance tracking.

### Fixed
- Resolved a runtime `Provider` crash on application startup.
- Fixed a minor linting warning in the `VirtualPiano` logic.

## [1.4.0] - 2026-02-28
### Added
- **Expressive Gestures**: Introduced vertical Pitch Bend and horizontal Vibrato on the Virtual Piano.
- **Gesture-Locked Scrolling**: Automatic suppression of piano list scrolling while expressive gestures are in progress to prevent accidental movement.
- **Independent Jam Chords**: Every channel now detects and displays its own chord independently in Jam mode.
- **Dynamic Slave Visibility**: Slave channel chord names now hide automatically when they are not actively playing.

### Changed
- Refined Jam mode chord badges by removing the "JAM:" prefix for a cleaner aesthetic.
- Scale names across all channels correctly reference the Master's chord context for synchronized performance feedback.

## [1.3.6] - 2026-02-28
### Added
- New "About" section in Preferences screen.
- Integrated Changelog viewer to see the history of changes directly in the app.

## [1.3.5] - 2026-02-28
### Added
- Maximized vertical real estate for the Virtual Piano keys. Reduced padding and margins across the main screen and channel cards to improve playability on mobile/tablet devices.

## [1.3.4] - 2026-02-28
### Changed
- Virtual Piano "Glissando" (Drag to Play) is now enabled by default for new installations and preference resets.

## [1.3.3] - 2026-02-28
### Added
- Unified "boxed" styling for Jam Master, Slaves, and Scale controls in both horizontal and vertical layouts.
- Centered vertical layout for the Jam sidebar with a more compact footprint (95px width).
- New interactive icons for dropdowns to clearly signal clickability.

### Fixed
- Flutter assertion error when `itemHeight` was set too low in Jam dropdowns.
- Vertical sidebar now correctly centers vertically on the left edge.

## [1.3.2] - 2026-02-27

### Added
- **Dual-Mode Jam UI:** Overhauled the Jam Session widget with strict layout isolation. Mobile landscape now features a premium, labeled vertical sidebar, while portrait/narrow displays use an ultra-compact, correctly ordered horizontal bar.
- **Subtle Labels:** Added high-contrast, tiny labels to both horizontal and vertical Jam UI modes for improved clarity during performance.

### Fixed
- **Splash Screen Cropping:** Changed splash screen image scaling to prevent cropping on portrait displays.
- **Jam Bar Restoration:** Restored the legacy widget order (Jam, Master, Slaves, Scale) and compact container sizing in the horizontal header.
- **Label Redundancy:** Removed duplicate labels in the vertical sidebar for a cleaner aesthetic.

## [1.3.1] - 2026-02-27

### Added
- **Interactive User Guide:** A comprehensive, multi-tabbed in-app guide replacing the legacy CC help modal. It covers connectivity, soundfonts, CC mapping, and Jam Mode.
- **Exhaustive System Actions:** All 8 system-level MIDI CC actions (1001-1008) are now fully implemented and documented, including Absolute Patch/Bank sweeps.

### Changed
- **System Action Renaming:** "Toggle Scale Lock" (1007) has been renamed to "Start/Stop Jam Mode" to better reflect its primary performance role.
- **Improved Action Descriptions:** Descriptions in the CC mapping service and Guide are now more descriptive and accurate.

## [1.3.0] - 2026-02-27

### Added
- **Musical Scale Names:** Real descriptive names (e.g., Dorian, Mixolydian, Altered Scale) are now displayed in the UI instead of generic labels.
- **Smart Jam Mode:** Significant overhaul of the Jam Mode engine to support multi-channel scale locking and dynamic mode calculation based on the Master's chord.
- **Improved UI Propagation:** Descriptive scale names are now propagated to all UI components, offering better musical feedback during performance.

### Changed
- **Default Lock Mode:** "Jam Mode" is now the default scale-locking preference.

### Fixed
- **Chord Release Stabilization:** Implemented a peak-preservation logic with a 30ms grace period to prevent chord identity "flickering" during release transitions.
## [1.2.1] - 2026-02-27

### Added
- **Reset Preferences:** Added a "Reset All Preferences" feature in the Preferences screen with a confirmation dialog to restore factory settings.
- **Improved Soundfont UI:** The Default soundfont now displays as "Default soundfont", appears first in lists, and is protected from deletion.

### Fixed
- **Linux Stability:** Resolved a crash and duplicated soundfont entries caused by logic errors in the soundfont loading state.
- **macOS Audio Pipeline:** Complete refactor of the macOS audio engine to use a single shared `AVAudioEngine` with 16 mixer buses, providing better performance and fixing "no sound" issues.
- **macOS Custom Soundfonts:** Removed a redundant file-copying loop that caused `PathNotFoundException` and added an automatic bank fallback (MSB 0) to fix load error `-10851`.
- **Audio Improvements:** Boosted default audio volume on macOS by 15dB for better parity with other platforms.
- **Path Migration:** Implemented a robust migration layer to automatically move legacy soundfont paths to the new secure internal storage.


## [1.2.0] - 2026-02-26

### Added
- Implemented a custom application icon for all platforms.
- Added a native splash screen (Android, iOS) for a seamless startup experience.
- Created a dynamic, fullscreen Flutter splash screen that shows initialization progress (loading preferences, starting backends, etc.).

## [1.1.0] - 2026-02-26

### Added
- Bundled a default, lightweight General MIDI Soundfont (`TimGM6mb.sf2`) so the app produces sound out-of-the-box on all platforms without requiring a manual download.
- Added a horizontal scrollbar to the virtual piano.
- Added a preference to customize the default number of piano keys visible on screen.

### Changed
- The virtual piano now initializes centered on Middle C (C4) instead of the far left.
- Re-architected virtual piano auto-scrolling to track active notes robustly.
- Synthesizer view gracefully adapts to ultra-wide/short aspect ratios (e.g., landscape mobile phones) by displaying a single channel vertically.

## [1.0.1] - 2026-02-26

### Changed
- Replaced the channel configuration modal with interactive dropdowns for Soundfont, Patch, and Bank right on the `ChannelCard`.
- Made the dropdown layout responsive to different screen widths.

## [1.0.0] - 2026-02-26

### Added
- Initial project release.
- Core capability to parse MIDI.
- Bluetooth LE compatibility.
- Virtual piano interactable via mouse/touch.
- Real-time chord parsing and identification.
- User Preferences screen to select output MIDI devices or internal Soundfonts.
- Automatic channel parsing and UI component architecture `ChannelCard`.
- Scale-locking chord functionality to constraint the played keys.
