# Skill: audio-safety

Audit Dart/Flutter or C++ code for audio-thread safety violations.

## What to look for

### Hard violations (must fix — cause dropouts or crashes)

| Pattern | Why it's bad |
|---|---|
| `List.filled(..., growable: true)` or any `new`/`[]` allocation in the callback | Triggers GC pauses |
| `print(...)` or `debugPrint(...)` | Synchronous I/O, unpredictable latency |
| `await` / `async` / `Future` anywhere on the audio path | Dart event-loop hop, unbounded delay |
| `Mutex.lock()` / `synchronized(...)` | Can block indefinitely if the UI holds the lock |
| File or network I/O | Always unbounded latency |
| `throw` / exception construction | Allocates |

### Soft violations (should fix — risk of latency spikes)

| Pattern | Why it's risky |
|---|---|
| `String` interpolation or `.toString()` | May allocate |
| Growing a `Map` or `Set` | Rehash allocation |
| `List.add()` on an unfixed-capacity list | May reallocate |
| Dart isolate `send`/`receive` on the hot path | Serialization cost |

## Safe patterns

```dart
// ✅ Pre-allocate in initialize(), read in process()
final _buffer = Float64List(bufferSize); // allocated once

// ✅ Non-blocking parameter update from UI
_engine.gainProvider = () => _gainNotifier.value;

// ✅ Lock-free ring buffer for audio↔UI exchange
_ringBuffer.write(sample); // no lock needed
```

## Review workflow

1. Identify the audio callback entry point (usually `process()` or an equivalent method tagged with a comment).
2. Trace every code path reachable from that entry point.
3. Flag each violation with its category (hard / soft) and suggest the safe alternative.
4. Confirm no allocation, logging, async, or lock-acquisition can be reached transitively.

## C++ equivalents

- No `new`/`malloc`/`std::vector::push_back` in `IComponent::process()`.
- No `std::cout`, `printf`, or file I/O.
- No `std::mutex::lock()` — use `std::atomic` or a lock-free queue.
- No system calls with unbounded latency (e.g. `mmap`, `open`).
