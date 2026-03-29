---
name: gf-audio-safety
description: Audit Dart/Flutter or C++ code for audio-thread safety violations — hard violations that cause dropouts or crashes, and soft violations that risk latency spikes.
argument-hint: "[file-or-class]  e.g. lib/audio/synth_engine.dart | (no args = full audio path audit)"
allowed-tools: Read, Grep
context: fork
---

## Scope

If a file or class name is provided as an argument, audit only that file or class. If no argument is provided, audit the full audio callback path starting from the entry point (usually `process()` or an equivalent method) and trace every code path reachable from it transitively.

**If the scope is ambiguous** (e.g. the user says "check the looper" but multiple files are involved), list the candidate files and ask which to audit:
> I found these files related to the looper audio path:
> - `lib/audio/looper_engine.dart` (LooperEngine.process)
> - `lib/audio/loop_track.dart` (LoopTrack playback logic)
> - `native_audio/looper_dsp.c` (C++ DSP)
>
> Audit all of them, or a specific one?

---

## What to look for

### Hard violations (must fix — cause dropouts or crashes)

| Pattern | Why it's bad |
|---|---|
| `List.filled(..., growable: true)` or any `new`/`[]` allocation in the callback | Triggers GC pauses |
| `print(...)` or `debugPrint(...)` | Synchronous I/O, unpredictable latency |
| `await` / `async` / `Future` anywhere on the audio path | Dart event-loop hop, unbounded delay |
| `Mutex.lock()` / `synchronized(...)` | Can block indefinitely if the UI holds the lock |
| File or network I/O | Always unbounded latency |
| `throw` / exception construction | Allocates a stack trace |

### Soft violations (should fix — risk of latency spikes)

| Pattern | Why it's risky |
|---|---|
| `String` interpolation or `.toString()` | May allocate |
| Growing a `Map` or `Set` | Rehash allocation |
| `List.add()` on an unfixed-capacity list | May trigger reallocation |
| Dart isolate `send`/`receive` on the hot path | Serialization cost |

---

## Output format

For each violation found, report using this structure:

```
[HARD|SOFT] <file>:<line> — <violation description>
  → Fix: <concrete safe alternative>
```

Example output:

```
[HARD] lib/audio/synth_engine.dart:142 — List allocation in process() callback
  → Fix: pre-allocate `_noteBuffer` in initialize(); reuse across callbacks

[HARD] lib/audio/synth_engine.dart:198 — `await _presetLoader.load()` on audio path
  → Fix: load presets on the UI isolate and push results via a lock-free ring buffer

[SOFT] lib/audio/synth_engine.dart:201 — String interpolation in hot path
  → Fix: use a pre-allocated diagnostic buffer or remove entirely
```

After listing all violations, add a one-line summary: `X hard violation(s), Y soft violation(s) found.`

---

## Safe patterns reference

### Pre-allocation (Dart)

```dart
// ✅ Allocate once in initialize(), reuse every callback
late final Float64List _buffer;
late final List<Note> _notePool;

void initialize(int bufferSize, int maxPolyphony) {
  _buffer = Float64List(bufferSize);       // fixed-size, no GC pressure
  _notePool = List.filled(maxPolyphony, Note.empty(), growable: false);
}

void process(AudioBuffer out) {
  // No allocations here — read/write _buffer and _notePool in place
}
```

### Non-blocking parameter propagation (Dart)

```dart
// ✅ ValueNotifier — UI writes, audio thread reads atomically
final _gainNotifier = ValueNotifier<double>(1.0);
_engine.gainProvider = () => _gainNotifier.value;   // closure read, no await

// ❌ Never do this on the audio path
await _engine.setGain(value);   // event-loop hop, unbounded latency
```

### Lock-free ring buffer (Dart)

```dart
// ✅ Single-producer / single-consumer ring buffer
// Write from UI isolate, read from audio callback — no mutex needed
_ringBuffer.write(noteOnEvent);   // producer side, UI thread
final event = _ringBuffer.read(); // consumer side, audio thread
```

---

## Review workflow

1. Identify the audio callback entry point (usually `process()` or a method tagged with a `// AUDIO THREAD` comment).
2. Trace every code path reachable from that entry point, including called methods and closures.
3. Flag each violation with its category (`[HARD]` or `[SOFT]`) using the output format above.
4. Confirm no allocation, logging, async, or lock-acquisition can be reached transitively.

---

## C++ equivalents (VST3)

The same rules apply to `IComponent::process()` and any function it calls:

| Dart violation | C++ equivalent |
|---|---|
| `new List` | `new`, `malloc`, `std::vector::push_back` |
| `print(...)` | `std::cout`, `printf`, file I/O |
| `Mutex.lock()` | `std::mutex::lock()` — use `std::atomic` or a lock-free queue |
| Any `await` | Any blocking syscall (`mmap`, `open`, `sleep`) |

```cpp
// ✅ Pre-allocate in constructor or initialize(), use in processAudio()
void MyPlugin::initialize(int maxBlockSize) {
    _buffer.resize(maxBlockSize);  // one-time allocation, OK here
}

void MyPlugin::process(Vst::ProcessData& data) {
    // NO new, NO malloc, NO std::mutex::lock, NO I/O here
    for (int i = 0; i < data.numSamples; ++i) {
        _buffer[i] = computeSample();  // reads pre-allocated buffer
    }
}
```
