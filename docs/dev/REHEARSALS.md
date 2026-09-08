# Rehearsals — merging GrooveForge Sessions into the main app

> **Status:** Plan, 2026-09-06. Supersedes `grooveforge-sessions/SPEC.md`, which
> assumed a separate closed-source app with a paid cloud tier.
> **Scope:** New main screen in GrooveForge, Android / iOS / Linux / macOS /
> Windows. No cloud, no subscription — direct peer-to-peer sharing only.
> **TL;DR:** Most of the DSP already exists in the app. The two things to change
> from the original sketch are the linking layer (drop Wi-Fi Direct) and the
> topology (drop creator-as-server). The one thing that decides whether the
> feature is loved or abandoned is latency-compensated overdub alignment —
> build that first.

---

## 1. What this is

A band, or a music-school group, rehearses one tune. One member creates a
rehearsal, optionally imports the original recording as a **master track**, and
shows a QR code. The others scan it and the rehearsal lands in their app. Each
member records their own part at home, aligned to a shared bar grid. Next time
they meet, the parts merge automatically.

Fold into GrooveForge rather than shipping a second app:

- The hard DSP is already here (§6). A separate app would re-implement it.
- One app to maintain, one F-Droid submission, one changelog, one l10n corpus.
- Free and FOSS throughout, so the sharing is direct: no server, no accounts,
  no subscription. Everything the old spec said about cloud storage, R2,
  RevenueCat and end-to-end encryption against a server is deleted.

Not a rack module — a second **main screen**, alongside the rack (§5).

---

## 2. Decisions taken

| # | Decision | Rationale |
|---|---|---|
| D1 | Second main screen, not a rack module | Different mode of use, different lifetime, different persistence |
| D2 | Rehearsals are an in-app library, not `.gf` files | Multi-megabyte audio, collaboratively owned, never opened from a file picker |
| D3 | **No Wi-Fi Direct** — ordinary IP over whatever LAN exists | §4.1 |
| D4 | **Every device is a peer**, not creator-as-server | The merge is conflict-free, so any two members who meet converge (§4.4) |
| D5 | QR decoding via `flutter_zxing` | MIT, ZXing-C++ over FFI, no proprietary blob (§4.3) |
| D6 | Takes are keyed by **part**, not by member | One phone often records a singer who also plays guitar |
| D7 | Ships on desktop too | A laptop in the rehearsal room is an excellent always-present archive node |
| D8 | **No take-length cap**; takes stream from disk | Forced by the master-track import (§7) — a 4-minute master plus five takes cannot live in RAM |
| D9 | Transposition dropped from v1 | Pitch-shifting a full band by several semitones sounds rough and is not what a rehearsal needs. Tempo change stays |
| D10 | Master track import (mp3 and friends) is a v1 feature | School groups take on famous tunes; §7 |
| D11 | Desktop scanning is **typed code + image decoding only** | No maintained camera plugin covers desktop, and a laptop webcam is not a given (§4.3) |
| D12 | Chord grid lands in **P6**, not v1 | It is a play-along aid, not a recording feature |
| D13 | Count-in defaults to **2 bars**, settable per rehearsal | Two bars is right for a standing start; the value is part of the synced manifest so the whole band counts in together |
| D14 | The mixer **scrolls**; all lanes need not fit one screen | Mute and gain are occasional actions, not performance controls |

---

## 3. Glossary

- **Rehearsal** — one tune. Title, time signature, tempo, grid, members, parts,
  optionally a master track. Identified by a UUID plus a shared **join key**.
- **Member** — a participant: display name plus instrument.
- **Part** — a slot in the arrangement, owned by exactly one member. A member
  may own several (voice *and* guitar).
- **Take** — the audio for one part. Immutable once recorded; re-recording
  produces a new take with `revision = previous + 1`.
- **Master track** — an imported reference recording (§7). Owned by the creator,
  not by a member, and never recorded over.
- **Grid** — the bar timeline. Anchored to the master track when there is one,
  otherwise seeded by the first take.

---

## 4. Linking and syncing

### 4.1 Why not Wi-Fi Direct

The original sketch had the creator start a Wi-Fi Direct group named after the
rehearsal UUID. Five objections, worst first:

1. **iOS has no Wi-Fi Direct API at all.** Apple's analogue is
   MultipeerConnectivity over AWDL — a different stack that cannot talk to a
   Wi-Fi P2P group. An iPhone in the band could never join.
2. **Permission regression.** `WifiP2pManager` requires `NEARBY_WIFI_DEVICES`
   on API 33+ and `ACCESS_FINE_LOCATION` below it. `AndroidManifest.xml`
   currently caps fine location at `maxSdkVersion="30"` precisely to avoid that
   prompt; Wi-Fi Direct would bring it back.
3. **Radio contention.** Single-radio phones time-share between the P2P group
   and the normal Wi-Fi association. Joining a group commonly drops everyone's
   internet, and group-owner negotiation behaves differently on every OEM build.
4. **Plugin risk.** No maintained cross-platform Flutter plugin exists; the
   Android-only ones are stale. A poor bet with an F-Droid submission pending.
5. **It solves nothing.** The case it addresses is "the room has no network".
   Most rooms have one; when they do not, a phone hotspot fixes it with no
   exotic API (§4.5).

### 4.2 Instead: plain TCP, and let the QR be the discovery

The insight that removes most of the complexity: **the joiner is standing next
to the host when they scan**. So the QR carries the endpoint itself, and first
contact needs no discovery protocol.

```
gf-rehearsal:v1?id=<uuid>&k=<32-byte key, base64url>&h=192.168.1.24:47821&n=Autumn%20Leaves
```

- **First join** — scan, connect straight to `h`, authenticate with `k`, pull
  the manifest. No mDNS, no timeouts, no "searching…" spinner.
- **Later meetings** — mDNS (`_gfrehearsal._tcp`) so nobody re-scans anything;
  the app simply notices the others are in the room. This is what the
  prototype's `lan_sync.dart` already does with `bonsoir`, and it is worth
  salvaging.
- **Typed fallback** — a six-character code resolved over mDNS, for when a
  camera is unavailable or the QR will not focus.

Transport is length-prefixed binary frames over `dart:io` sockets: JSON for
control messages, raw payload for audio, **pushed on change** rather than
polled. Zero per-platform networking code; all five targets are covered by
`dart:io` plus one mDNS package.

On iOS, `NSLocalNetworkUsageDescription` and `NSBonjourServices` must go in
`Info.plist` — without them mDNS silently returns nothing.

### 4.3 QR scanning, and the F-Droid constraint

F-Droid inclusion is mandatory, which rules out `mobile_scanner`: it decodes
with Google ML Kit, a proprietary blob.

Use **`flutter_zxing`** (3.0.1, MIT, wraps zxing-cpp 3.1.1 over FFI, no
proprietary dependency). Its `ReaderWidget` live scanner builds on the official
`camera` plugin, which supports **Android and iOS only**.

Per-platform scanning path:

| Platform | Live camera scan | Fallback |
|---|---|---|
| Android, iOS | `flutter_zxing` `ReaderWidget` | typed six-character code |
| Linux, macOS, Windows | none | typed code, plus decoding a QR from an image file or a pasted screenshot via `flutter_zxing`'s still-image API |

Desktop deliberately gets **no live scanner** (D11). Community desktop camera
packages exist but none is solid enough to depend on, and plenty of laptops have
no webcam at all — so on desktop the typed code is the primary path, not a
degraded one. Design the Nearby screen accordingly: give the six-character code
the same visual weight as the QR rather than setting it in small print
underneath.

The still-image path is worth having everywhere regardless: it covers "someone
messaged me a screenshot of the QR", which is a real way bands share things.

### 4.4 Topology: every device is a peer

The original sketch had the creator re-enable a server at each meeting. One
change makes the whole thing far more robust for no extra work: **every device
advertises and serves**. The creator having the flu then stops nothing, and two
members can sync at a bus stop.

This is safe because the merge cannot conflict:

- A take is owned by exactly one part and is immutable once recorded. Merging
  is *for each part, keep the highest revision*. No two devices ever write the
  same key, so it is a grow-only map, not a diff.
- Rehearsal metadata (title, tempo, chord grid) uses a last-writer-wins
  register per field with a Lamport counter and a device-id tiebreak. About
  fifty lines, and it removes the entire class of "whose tempo won" bugs.
- Time signature, bar count and master-track anchoring **freeze** once the
  first take exists. They define the grid; changing them would invalidate every
  take.

### 4.5 When there is no usable Wi-Fi

Two layers of fallback, both cheap:

- **Hotspot wizard.** A two-step QR flow: the first code is a standard
  `WIFI:S:…;T:WPA;P:…;;` payload that any phone camera joins natively, the
  second is the session code. On Android,
  `WifiManager.startLocalOnlyHotspot()` hands you the SSID and passphrase
  programmatically, so the host taps one button. Elsewhere the host enables the
  personal hotspot manually and types the password once.
- **Bundle export.** Zip the rehearsal folder into a `.gfr` file and send it by
  any means — Bluetooth share, USB, email, Nextcloud. Same merge code path,
  roughly a day of work, and it rescues every hostile network. It is also the
  backup and archive story, which we want anyway.

### 4.6 Wire format for takes

The prototype's `take_transfer.dart` sends base64 float32 PCM inside JSON and
polls every two seconds — roughly five times the bytes it needs to be.

v1 ships **mono 16-bit WAV, uncompressed**. Three minutes is about 17 MB,
roughly ten seconds over Wi-Fi, and it adds no dependency at all —
`wav_utils.dart` is already in the tree.

- *Mono* because the source is one player and one microphone; stereo doubles
  everything for nothing.
- *Uncompressed* because takes are time-stretched later by the phase vocoder,
  and lossy artefacts compound through it.

Add Opus only if transfer time turns out to actually annoy anyone.

### 4.7 Security, kept proportionate

Dropping the cloud tier deletes the entire end-to-end-encryption problem from
the old spec — there is no server to keep honest. The join key from the QR does
two jobs: it authenticates the TCP handshake, and it keys an AES-GCM channel so
nothing else on the room's Wi-Fi can read the takes.

---

## 5. Storage and the shell

### 5.1 A rehearsal library, not a file format

Rehearsals never touch `ProjectService` or the `.gf` format — different
lifetime, different ownership, orders of magnitude more bytes. A separate
`RehearsalLibrary` service with its own autosave, under the app documents
directory:

```
rehearsals/
  <rehearsalId>/
    rehearsal.json   synced manifest: title, tempo, time sig, count-in bars,
                     members, parts, chord grid, per-part revisions,
                     Lamport clock, master meta
    master/
      source.<ext>   the imported file, as imported (§7)
      master.pcm     decoded canonical audio, streamed at playback
    takes/
      <partId>-<rev>.wav
    self.json        never leaves the device: my mutes, my gains,
                     my latency nudge, which member I am
```

- `rehearsal.json` is the document that syncs. `self.json` is strictly local,
  which settles the old spec's open question about mute scope: mute and gain
  are a personal mix decision and are never broadcast.
- Old take revisions are deleted once the replacement is committed, otherwise a
  band's storage grows without bound.
- Show total size per rehearsal in the library list. Audio is the only thing
  here big enough for a user to care about, so make it visible.
- Zipping one `<rehearsalId>/` folder *is* the `.gfr` bundle from §4.5 — the
  fallback transport and the backup feature are the same code.

### 5.2 The shell

Today `SplashScreen` pushes `RackScreen`, which owns its own `Scaffold` and
`AppBar`. Add a `MainShell` above it holding an `IndexedStack`.

> **Non-negotiable:** an `IndexedStack`, not a swapped child. `RackScreen` owns
> live audio state, per-slot FluidSynth instances and VST plugin handles.
> Disposing it on a tab switch would tear down the audio graph every time
> someone glances at the rehearsal tab.

Navigation chrome, per Rule 1:

| Form factor | Chrome |
|---|---|
| Phone portrait | `NavigationBar` at the bottom, two destinations |
| Phone landscape | Collapsed `NavigationRail`, 56 px — the rack is already vertically starved, so stealing 80 px of height hurts more than 56 px of width |
| ≥ 900 px | `NavigationRail`; labels shown from 1280 px |

### 5.3 Screens

- **Library** — the tab root. Two big friendly actions, *Start a tune* and
  *Join a tune*, then a card per rehearsal: title, instrument chips per member,
  a progress ring reading "3 of 4 parts recorded", last-synced-ago. Colour
  derived from the rehearsal id so each is recognisable at a glance; the ring
  springs when a new take arrives from a peer.
- **Create** — title, your name, your instrument, time signature, tempo, and
  the optional *play along to a recording* import (§7). Built on `RotaryKnob`
  and `GFSlider` so it feels like GrooveForge, not a Material form.
- **Nearby** — the QR, large, with the six-character code beneath it and a live
  list of who has connected, each arriving with a small pop. Doubles as the
  re-enable-at-the-next-meeting screen, reachable from a persistent *Nearby*
  button in the rehearsal app bar.
- **Join** — scanner, or type the code; then name and instrument.
- **Rehearsal** — transport, count-in selector and metronome toggle on top; the
  bar grid with chord cells in the middle; the master lane and then one lane
  per part below — name, instrument icon, level meter, mute, gain — with your
  own lane pinned first and carrying the record button. The lane list
  **scrolls** (D14): mute and gain are occasional actions, not performance
  controls, so there is no need to squeeze a seven-piece band onto one phone
  screen. What must stay pinned and always visible is the transport, the bar
  position and your own lane; everything else can scroll away.

Audio device pickers live in a bottom sheet behind a mic icon, not a settings
screen. Sync status is a quiet chip in the app bar: *2 nearby*, *receiving
Léa's part*, *up to date*.

The visual metronome must be prominent — the audience is often on headphones in
a quiet room. And the design principle from the old spec stands: playful and
encouraging, never a sterile DAW. The audience is music-school students and
high-school bands.

---

## 6. The audio engine we already have

Most of the hard DSP for this feature is already in GrooveForge, which is a
strong argument for the merge on its own.

| Capability | Where | Status |
|---|---|---|
| Bar-synced recording | `dart_vst_host/native/src/audio_looper.cpp`, `alooper_android` | Built |
| Multitrack playback, per-clip gain | same, `ALOOPER_MAX_CLIPS 8` | Built |
| Time-stretch for tempo change | `native_audio/gf_phase_vocoder.c` | Built |
| Metronome, BPM, time signature, beat callbacks | `lib/services/transport_engine.dart` | Built |
| Mic capture on every platform | `native_audio/audio_input.c` (miniaudio) | Built |
| WAV read and write | `lib/services/wav_utils.dart` plus native encoder | Built |
| MP3 / FLAC / WAV file decoding | vendored miniaudio: `MA_HAS_MP3`, `MA_HAS_FLAC`, `MA_HAS_WAV`, no `MA_NO_*` set | Built |
| Latency-compensated take alignment | — | **Missing** |
| Disk-streamed multitrack playback | — | **Missing** |
| A clip pool the rack does not own | `ALOOPER_MAX_CLIPS` is shared with the rack looper | **Conflict** |

The old spec agonised over Signalsmith versus SoundTouch versus Rubber Band for
time-stretching. We already own a phase-locked vocoder, in C, licence-clean,
tuned for transients, with a smoke test that stretches 120 BPM to 140. Use it.

### 6.1 Gap — latency compensation

**This is the whole product risk.** The looper arms recording on the next
downbeat, which is correct and matches the looper bar-sync rule. But it never
shifts the captured audio *earlier* by the round trip, and for overdubs that is
the difference between "locked in" and "everyone quietly stopped using this".

Compensation is output latency plus input latency. Output is the large,
route-dependent term — roughly 10 ms wired to 300 ms on Bluetooth — and it
changes the moment someone swaps headphones.

- Query the OS per route: AAudio timestamps on Android,
  `AVAudioSession.outputLatency` on iOS. miniaudio does not surface this well,
  so it needs a small platform channel or a direct AAudio call.
- Persist the resolved offset keyed by output route.
- Always ship a manual millisecond nudge with a tap-along check. On Bluetooth
  the OS number is frequently a polite fiction, so the nudge is not optional.
- Warn when record is armed on a **speaker** route: the mic then captures the
  other parts too and produces an unusable ghosted take. Worth being slightly
  pushy about.

### 6.2 Gap — the memory model does not survive a band

The looper pre-allocates stereo float in RAM. Five minutes of stereo float is
about 115 MB per clip; six members would be 690 MB, which no phone will give
us. Even mono float at three minutes is 35 MB a take, so six takes is 210 MB —
survivable, but not comfortable. Add a 4-minute imported master (§7) on top and
the RAM model is simply dead.

Rehearsal audio therefore lives **on disk as mono 16-bit PCM and is streamed at
playback** through a small per-track ring buffer filled by a worker thread. This
is the one genuinely new native component in the plan. It also removes any need
for a take-length cap (D8).

### 6.3 P0 status — the alignment maths is proven, on synthetic audio

`native_audio/gf_latency.{h,c}` implements the chain, and
`gf_latency_smoke_test.c` verifies it offline
(`./scripts/run_smoke_tests.sh latency`). It needs no audio device, so it runs
in CI and on any machine.

The measurement emits a train of six 40 ms linear chirps (300 Hz → 6 kHz) on
the playback timeline at known frames, then finds each one in the capture by
normalised cross-correlation. A chirp beats a click here: it spreads its energy
over time yet still correlates to one sharp peak, which survives room
reverberation and a phone speaker's ragged response where a click does not.
Normalising by the capture window's energy is what stops the estimator locking
onto whatever was loudest rather than onto the signal.

Against a simulated channel that is band-limited (180 Hz – 7 kHz), carries a
13 ms wall reflection at −7 dB, has a capture clock starting at an arbitrary
different frame, and is buried in noise down to roughly 3 dB SNR:

| Case | Result |
|---|---|
| Round trips 12 – 280 ms | recovered exactly |
| Delays landing between frame boundaries | within 1 frame (0.02 ms) |
| Rehearsal-room noise at 3 dB SNR | recovered exactly, confidence 7.1 |
| Capture containing only noise | **rejected**, 0 of 6 shots usable |
| End to end: note played in time with what was heard | lands 0.000 ms off the beat |

That last row is the P0 question, and on synthetic audio the answer is yes. The
rejection row matters just as much: the failure mode to fear is not "no
answer", it is a confident wrong answer, which would shift every take in the
session by a random amount. The correlator scores its peak against the best
competing peak and refuses to answer below a ratio of 2.0.

### 6.4 P0 on real hardware — measured, and it holds

`gf_latency_probe` runs the same measurement against real devices from the
command line, and the app carries it as a screen (Preferences → Overdub
latency) that measures through GrooveForge's *own* devices — the only
configuration whose answer is usable.

**Galaxy Z Fold, speaker to built-in microphone, three consecutive runs:**

| | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| Round trip | 27.27 ms | 28.98 ms | 28.96 ms |
| Frames | 1309 | 1391 | 1390 |
| Sweeps found | 6/6 | 6/6 | 6/6 |
| Confidence | 5.7 | 5.3 | 4.9 |
| Clock drift | — | — | 0.7 ppm |

Runs 2 and 3 agree to within one frame. Run 1 sits 82 frames low, almost
certainly the capture device still settling immediately after being opened —
worth discarding the first run of a calibration, or warming up before measuring.

**Two things this settles:**

1. **Drift is a non-issue on this hardware.** 0.7 ppm is 0 ms over a
   four-minute take. The resampling path floated in §6.5 below is therefore not
   needed for P1 — the figure stays as a health check, and the case for acting
   on it only arises if some device reports tens of ppm.
2. **The measurement is reproducible to about 2 ms**, and to a single frame
   between settled runs. That is comfortably inside the 10 ms budget, so the
   remaining error is dominated by the device settling rather than by the
   method.

**Linux laptop, speaker to built-in microphone, after a warm-up run:**
35.52 / 35.06 / 35.54 ms — a spread of 0.5 ms — with drift at 0.1 ppm.
Through the PipeWire monitor loopback instead (no room, no speaker, no mic):
26.67 ms, identical across runs, drift exactly 0.0 ppm — the expected result
for a digital loopback that shares one clock domain, and a useful control.

**Discard the first run.** On both machines the first measurement after the
devices open is an outlier — 710 frames high on the laptop, 82 frames low on
the phone — because the graph is still settling and the frame/timestamp pairs
the alignment depends on are not yet regular. `gf_latency_probe` now performs
a warm-up run and throws it away. **P1's calibration flow must do the same**;
without it every calibration will look far noisier than the hardware is.

**Verified surfaces.** Synthetic (`run_smoke_tests.sh latency`), the Linux CLI
probe against real devices, the Linux app screen, and the Android app screen —
all four green. P0 is answered: the alignment chain works, and the round trip
is measurable to well inside the budget on both an Android phone and a Linux
laptop.

### 6.4.1 What the hardware caught that the simulation could not

Three real bugs, none of which the offline test could have found:

- **Android never opens the miniaudio playback device.** `start_audio_capture`
  logs `PLAYBACK device: skipped (Android uses Oboe bus)` — output goes through
  Oboe in `libnative-lib.so`. The probe had to register itself as an ordinary
  bus source (`OBOE_BUS_SLOT_LATENCY_PROBE`) to emit anything at all.
- **The bus source must stay registered between runs.** The playback frame
  counter only advances while its render callback is being called, so removing
  the source after a run froze that clock while the capture clock kept going;
  the next run then scheduled its sweeps seconds into the future and timed out.
- **The two frame counters have different origins.** Each counts frames since
  *its own* device started, and on the phone the output bus had been running
  4.4 seconds longer than the microphone. Subtracting them raw put the search
  window past the end of the buffer, finding nothing. The fix is to project
  both to one instant using a timestamp latched in each callback, and then to
  pass **zero** as the analysis origin — the emitter counts from that instant
  and the capture buffer is indexed from it, so the two axes already share an
  origin.

That last one also corrected the desktop reading, which had been low by exactly
the counter difference (768 frames, 16 ms).

A fourth surfaced once the laptop microphone was available: the standalone
probe still read its counters bare while the in-app path had been fixed, and
one run's skew came back 768 frames off with the round trip wrong by exactly
those 768 frames — the error lands in the answer 1:1. Both now project from
per-callback timestamps.

A fifth, on Linux only: `permission_handler` has no implementation there, so
requesting the microphone threw `MissingPluginException`. It is only registered
for Android and iOS in this project — `ThereminDistanceService` works around
the same gap on macOS — and the desktop builds open the microphone directly
anyway, exactly as the Live Input module does.

### 6.5 Earlier finding — clock drift, and when a constant offset is not enough

Building the harness surfaced something the original spec missed entirely.

Compensation is a single constant, so it corrects the *start* of a take. But
the playback and capture devices have independent crystals, and two nominally
48 kHz clocks are never exactly equal. The take therefore slides against the
grid as it plays:

| Drift | A 4-minute take ends |
|---|---|
| 50 ppm | 12 ms late |
| 200 ppm | 48 ms late |

48 ms is not subtle — it is roughly a semiquaver at 120 BPM, and it lands at
the end of the song where the band is least forgiving. No constant offset can
fix it, because the error is not constant.

`gf_lat_result` now reports `drift_ppm` from a least-squares fit across the six
shots (the sub-frame refined peaks, since one run's drift is a fraction of a
frame per shot). The test confirms ±50 and ±200 ppm are recovered with the
correct sign — the sign being the one thing that must not be wrong, since
resampling the wrong way would double the error instead of removing it.

**Measured outcome (§6.4): 0.7 ppm on the test phone, 0 ms over a four-minute
take.** So this does not need handling in P1. It stays measured and reported as
a health signal, and the resampling path — the phase vocoder already does the
resampling, so it is a routing question rather than new DSP — is only worth
building if some device turns out to report tens of ppm.

### 6.6 Gap — the clock

`TransportEngine` ticks from a Dart `Timer.periodic(10ms)`. Fine for a
metronome LED and a beat counter, but rehearsal alignment must be sample-counted
in C. The pattern exists — `alooper_android_set_transport` pushes transport
state to the native side — so the rule is: **the rehearsal grid position is
derived from the audio callback's frame counter, never from the Dart clock.**

---

## 7. Master track import

School groups take on famous tunes, so a rehearsal must be able to start from an
existing recording rather than from a blank grid.

At creation (and only at creation, before any take exists) the creator can
import an audio or video file. Its audio becomes the **master track**: a lane
that everyone plays along to, mixable and mutable like any other lane, but owned
by the rehearsal rather than by a member and never recorded over.

### 7.1 Formats, without adding a proprietary dependency

The vendored miniaudio already decodes **WAV, FLAC and MP3** on all five
platforms with no new dependency (`MA_HAS_WAV` / `MA_HAS_FLAC` / `MA_HAS_MP3`,
and no `MA_NO_*` is set anywhere in our sources). That is the universal
baseline.

Beyond it, use the **OS extractors** rather than bundling a codec pack:

| Source | Android | iOS / macOS | Linux / Windows |
|---|---|---|---|
| WAV, FLAC, MP3 | miniaudio | miniaudio | miniaudio |
| Ogg Vorbis | miniaudio + `stb_vorbis` (public domain, drop-in) | same | same |
| AAC / M4A | `MediaExtractor` + `MediaCodec` | `AVAssetReader` | system `ffmpeg` if on `PATH`, else unsupported |
| Video containers (mp4, mkv, screencasts) — audio track only | `MediaExtractor` + `MediaCodec` | `AVAssetReader` | system `ffmpeg` if on `PATH`, else unsupported |

Avoid `ffmpeg_kit_flutter`: the project was archived in 2025 and it ships
prebuilt binaries, which is exactly what F-Droid will not take. OS extractors
are system APIs, so they bundle nothing.

Decode **once, at import**, to the canonical on-disk PCM (`master/master.pcm`).
Playback then goes through the same streaming path as takes (§6.2), so the
master costs nothing extra at runtime.

Video is imported for its **audio only** in v1. Playing the picture back in sync
is a separate feature and a much larger one; say so in the import sheet rather
than silently dropping the video.

### 7.2 The master anchors the grid

With a master present, the grid must be anchored to *it*, not to the first take.
That needs two numbers: the tempo, and where bar 1 starts inside the file.

v1 does this manually, and deliberately so:

1. Play the master. The user taps along for a few beats — tap tempo gives the
   BPM.
2. A drag handle on the waveform sets `masterOffsetMs`, the position of the
   first downbeat. Nudge buttons at ±10 ms for fine work.
3. Loop a two-bar window with the click over the master so the user can hear
   whether it lines up, and adjust until it does.

No automatic beat detection in v1. Manual tap-and-nudge is reliable,
understandable, and takes a student about twenty seconds; a beat tracker that is
wrong 15% of the time is worse than useless because the user cannot tell which
15%.

Both values freeze once the first take is recorded (§4.4), and both are part of
the synced manifest so every member gets the same grid.

**Consequence worth designing around:** when a master is present it *is* the
timing reference, not the click. Members hear the real recording and lock to it
naturally, so the metronome should default to **off** in master-backed
rehearsals. Real recordings also drift — few commercial tracks are metronomic —
and that is fine precisely because everyone follows the master rather than a
grid.

### 7.3 Syncing the master

The master is one more entry in the manifest with `role: master`, immutable,
owned by the creator, and merged by the same highest-revision rule.

Transfer the **original imported file**, not the decoded PCM — a 4-minute MP3 is
5–8 MB against roughly 40 MB of PCM. Exception: if the file needed an OS
extractor to decode (AAC, video container), a Linux or Windows peer may not be
able to read it, so in that case export decoded 16-bit WAV instead. The rule is
simply: *ship the source file when it is WAV, FLAC, MP3 or Ogg; otherwise ship
decoded WAV.*

### 7.4 Copyright posture

Importing a commercial recording to rehearse against is ordinary private use,
and the feature is strictly peer-to-peer: no server, no hosting, no
distribution by us — the same posture as any DAW that opens an MP3. It is also
a standing reason never to add a cloud tier for masters, which would change that
posture completely.

---

## 8. Phasing

| Phase | Content |
|---|---|
| **P0** | **Latency spike.** Record a take over a playing reference on one device, wired then Bluetooth, and measure alignment error. Target well under 10 ms. No UI, no networking, no library. If this does not come out right the rest of the plan is moot — which is why it goes first. |
| **P1** | **Single-device rehearsal — done.** Library, create, grid, disk-streaming player, metronome, count-in, record and replace your own take, playback mix, mute and gain, persistence. See §11. |
| **P2** | **Master track import — done.** Decoders, tap-tempo and offset alignment, master lane. See §12. |
| **P3** | **Shell and tab — done, during P1.** `MainShell`, responsive nav, l10n pass, `flutter analyze` clean. It had to come early: without the tab there was no way to reach anything P1 built. |
| **P4** | **Pairing and sync — done.** QR, scanner, authenticated TCP handshake, manifest merge, take and master transfer, mDNS re-discovery, Nearby screen. See §13, §14 and §15. |
| **P5** | **Hostile networks — done, differently.** The hotspot wizard became a page in the user guide: Android gives a normal app no way to switch the real hotspot on or read its credentials, so the honest version is instructions. `.gfr` bundle export was **dropped** — it carries the join key, so it works as an introduction, but it cannot sync back, which makes it an archive rather than a way into a live group. Backup is the only case it would still serve. |
| **P6** | **Musical extras — part done.** Tempo change through the phase vocoder is built (§25), for both the tune's tempo and a local practice speed. The shared score vault is built (§28). The chord grid is built (§30). Count-in refinements are still open. |
| **P7** | **Polish.** Onboarding, playful motion pass, store and F-Droid assets, changelogs in both languages. |

---

## 9. What to salvage from grooveforge-sessions

| File | Verdict |
|---|---|
| `ui/bar_grid.dart`, `model/{bar,time_signature,instrument,session}.dart` | **Port** — directly reusable, minor renames |
| `ui/create_session_screen.dart`, `ui/join_session_screen.dart` | **Port** as UI reference; rebuild the controls on GrooveForge widgets |
| `lan/lan_sync.dart` | **Rework** — good mDNS and TCP skeleton; add the QR endpoint path and the key handshake |
| `lan/take_transfer.dart` | **Rewrite** — base64 PCM in JSON, polled every two seconds |
| `audio/audio_engine.dart` and the `gf_audio_core` submodule | **Drop** — the main app's native stack replaces it wholesale |
| `ui/widgets/gf_slider.dart` | **Drop** — already in GrooveForge |

Roughly 700 of the 1 800 prototype lines survive the move. The audio layer does
not, and that is fine: it was written against `gf_audio_core` precisely because
it had no GrooveForge to lean on. Now it does.

---

## 10. Deferred, deliberately

Nothing in this plan is blocked on an unanswered question. These are the things
consciously pushed out of v1, recorded so they are not rediscovered as
oversights:

| Deferred | Where it went | Why |
|---|---|---|
| Chord grid editing | P6 | A play-along aid, not a recording feature (D12) |
| Transposition | Dropped | Pitch-shifting a full band by several semitones sounds rough (D9) |
| Video playback for imported screencasts | Unscheduled | Audio-only import is a small feature; picture-in-sync is a large one (§7.1) |
| Automatic beat detection for the master | Unscheduled | A tracker that is wrong 15% of the time is worse than useless, because the user cannot tell which 15% (§7.2) |
| Live camera scanning on desktop | Unscheduled | No dependable plugin, and laptops often have no webcam (D11) |
| Opus for take transfer | Unscheduled | Only worth it if uncompressed WAV transfer turns out to actually annoy anyone (§4.6) |
| Multiple takes per part with a picker | Unscheduled | v1 keeps the latest; the data model already carries `revision`, so this is additive |

The instrument list is confirmed as-is: the prototype's twelve-entry
`Instrument` enum — vocals, guitar, electric guitar, bass, drums, keyboard,
synth, violin, saxophone, trumpet, percussion — with `other` as the escape
hatch, localized through `instrumentLabel()` so the enum stays
presentation-free.

---

## 11. P1 as built

Shipped and verified on a Galaxy Z Fold and on Linux.

### 11.1 What exists

| Piece | Where |
|---|---|
| Multitrack engine — grid, streaming playback, aligned recording, metronome | `native_audio/gf_rehearsal.{h,c}` |
| Offline verification (7 checks, no audio device) | `gf_rehearsal_smoke_test.c`, `./scripts/run_smoke_tests.sh rehearsal` |
| Audio routing — desktop playback callback, Android Oboe bus slot 105 | `native_audio/audio_input.c` |
| Data model and on-disk format | `lib/models/rehearsal.dart` |
| Library — create, load, commit takes, delete, local state | `lib/services/rehearsal_library.dart` (17 tests) |
| Engine service — transport, mix, take commit | `lib/services/rehearsal_engine.dart` |
| Shell with the second tab | `lib/screens/main_shell.dart` |
| Library and rehearsal screens | `lib/screens/rehearsals_screen.dart`, `rehearsal_screen.dart` |

The smoke test checks the things that would be invisible from Dart: two takes
with transients at known grid frames land on exactly those frames, a count-in
plays nothing until it crosses the downbeat, and a recording is written shifted
earlier by exactly the latency compensation.

### 11.2 The calibration loop is closed

The latency probe stores its measurement under `gf.rehearsal.compensationFrames`,
and a rehearsal with no calibration of its own adopts it on open. Measured
28.62 ms on the test phone, matching P0's ~29 ms. Until a measurement exists the
rehearsal screen says so, because recording without one produces a take that
drags by the device's whole round trip.

### 11.3 Known gaps, for P2 onwards

- **Recording length is unbounded.** The transport runs until stopped; there is
  no take-length cap by design (D8), but nothing warns about disk use yet.
- **No warm-up on the in-app probe.** P0 found the first measurement after the
  devices open is an outlier; the CLI probe discards one, the app screen does
  not. Tap it twice, or fix it when the calibration flow gets its own screen.
- **The input tap reads the transport position from the render thread**, so the
  frame at which a recording begins can be up to one output block stale. It is
  inside the block error the compensation already absorbs, but a future
  calibration pass could remove it by relating the input and output frame
  counters directly, the way `gf_latency_probe` does.
- **No waveform display.** A lane shows a duration, not a shape.

---

## 12. P2 as built

### 12.1 What exists

| Piece | Where |
|---|---|
| Decode any bundled-codec file to mono 16-bit WAV, plus a peak envelope for the alignment screen | `native_audio/gf_media_import.{h,c}` |
| Per-track grid offset — anchors bar 1 anywhere inside a recording | `gf_reh_set_track_offset` |
| Master in the document, with its offset | `lib/models/rehearsal.dart` |
| Import, re-anchor, remove | `lib/services/rehearsal_library.dart` |
| Master lane, gain and mute | `lib/screens/rehearsal_screen.dart` |
| Tap tempo, waveform, draggable downbeat, listen-back | `lib/screens/master_align_screen.dart` |

Verified: a 44.1 kHz stereo WAV folds to exactly 96 000 frames at 48 kHz mono
in the smoke test, and a real 20-second MP3 decodes to exactly 20.00 s with the
waveform placing the first downbeat in the 1.30-1.40 s bin, against a true
1.35 s. The engine plays a master offset by 72 000 frames with its downbeat on
grid frame 0 and the next bar exactly one bar later.

### 12.2 Two linker traps worth remembering

`audio_input.c` compiles miniaudio with **`MA_API static`**, deliberately, so
its symbols cannot clash with the second vendored copy inside `dart_vst_host`.
That makes them private to that translation unit, so the importer cannot link
against them and carries its own copy — with `MA_NO_DEVICE_IO`, since it only
ever decodes files.

Two miniaudio globals are declared *outside* `MA_API` and so collide anyway:
`ma_atomic_global_lock` everywhere, and `ma_android_sdk_version` on Android
(compiled regardless of `MA_NO_DEVICE_IO`). Both are renamed in the importer's
copy. Anything that ever adds a third miniaudio will hit the same two.

### 12.3 Formats

| | Everywhere | Android also |
|---|---|---|
| Decoder | bundled dr_libs, via miniaudio | `MediaExtractor` + `MediaCodec` |
| Formats | MP3, FLAC, WAV | M4A, AAC, Ogg, Opus, and the audio track of MP4/MKV/WebM |

Two decoders, one path: the bundled one handles its three formats directly;
anything else goes through the platform's codecs into an intermediate WAV that
the bundled one then folds to mono and resamples. Writing a resampler in Kotlin
to avoid that intermediate would have meant maintaining two, so the intermediate
stays — and is deleted as soon as it has been consumed.

`ffmpeg_kit_flutter` is deliberately not used: archived in 2025, ships prebuilt
binaries, unacceptable for F-Droid. `MediaExtractor` and `MediaCodec` are system
APIs and bundle nothing.

The picker offers exactly what the running platform can decode, so a file that
cannot be imported cannot be selected in the first place.

**iOS is the gap.** `AVAssetReader` is the equivalent and would slot into the
same `PlatformMediaDecoder` seam; until then iOS has the bundled three.

Verified on device: an M4A decodes as `audio/mp4a-latm -> 882688 frames,
44100 Hz, 2 ch` and lands as 960 749 frames at 48 kHz mono (20.016 s — AAC
encoder padding, so slightly over the source's 20.000 s). An MP4 carrying both
video and AAC audio yields the same, with `MediaExtractor` selecting the audio
track rather than handing the decoder pictures.

### 12.4 Known gaps

- **Audio before the downbeat is not played.** The grid starts at bar 1, so an
  intro is skipped. Fine for playing along to a chorus; wrong for a tune whose
  intro the band plays. Needs either a negative-bar region or an explicit
  "intro bars" count.
- **Import blocks the UI thread** behind a progress bar. A four-minute file is
  a second or two on a phone; long enough to want an isolate eventually.
- **Video is imported for its audio only.** Playing the picture back in sync is
  a separate, much larger feature; the import sheet should say so.

On-device verification (Galaxy Z Fold): MP3, M4A and MP4-with-video all import,
the waveform draws, and dragging plus thirteen 10 ms nudges placed the downbeat
at 0:01.35 against a true 1.35 s, stored as `offset 64883` frames.

---

## 13. P4 as built

### 13.1 What exists

| Piece | Where |
|---|---|
| Conflict-free merge, per-field Lamport clocks | `lib/services/rehearsal_merge.dart` (17 tests) |
| Wire format, join ticket, handshake, AES-GCM channel | `lib/services/rehearsal_protocol.dart` |
| The session both sides run | `lib/services/rehearsal_sync.dart` (18 tests, over real sockets) |
| Hosting, joining, device identity, filesystem adapter | `lib/services/rehearsal_sync_service.dart` (6 tests, two real libraries) |
| Nearby (QR + code + peers) and Join screens | `lib/screens/nearby_screen.dart` |

Dependencies added, all pure Dart or MIT-licensed FFI, nothing F-Droid will
object to: `crypto` and `cryptography` for the handshake and channel,
`qr_flutter` for rendering the code, `flutter_zxing` for scanning it.

### 13.2 Why there is no host

Both devices run the *same* exchange and differ only in who speaks first. That
falls out of the merge being symmetric: for each part keep the highest take
revision, for each metadata field keep the later Lamport stamp with the device
id breaking ties. Two devices merging from their own point of view reach the
same document, which the tests assert directly.

The consequence is the one that matters in a rehearsal room: **any two members
who meet can sync**, whether or not the person who created the rehearsal is
there. It also removes a whole class of "works when A hosts, fails when B does"
bugs, because there is no difference between the two roles to get wrong.

### 13.3 Verified cross-device

Phone hosting, laptop joining, over real Wi-Fi:

- the laptop pulled the phone's manifest — title, tempo, members, parts;
- the laptop then created a bass part with a 64 000-byte take and synced again;
- the phone received it: `c0iv3a62rfgws9nz-1.wav`, 64 000 bytes, and a matching
  manifest entry at revision 1.

The QR itself was decoded from a screenshot with `zbarimg` and came back as a
well-formed ticket, so what is on screen is what the protocol expects.

### 13.4 The metadata never synced at all

The first build shipped `touch()` — the thing that stamps a field so the merge
can compare it — and **never called it anywhere**. Every field on every
rehearsal therefore carried a zero clock, `beats()` was always false, and no
metadata moved between devices: not the master, not the tempo, not the metre,
not the count-in.

It looked like it worked, which is why it survived a live cross-device test.
Parts and members are unioned without consulting clocks, so those transferred
fine; and the title appeared correct only because a joiner copies it out of the
ticket rather than from the merge. The reported symptom was the master, but the
master was one instance of the whole class.

Two fixes, both needed:

- **Stamp on write.** `create` stamps every mergeable field — otherwise a
  creator's 100 BPM and a joiner's default 120 both carry a zero clock and the
  joiner keeps 120 forever. Importing, re-anchoring or removing a master stamps
  `master`; changing the tempo goes through `updateField`, which stamps.
- **Migrate on read.** Everything written before the stamps existed has no
  clocks and would stay unsyncable for good, so `load` stamps such a rehearsal
  once and writes it back. A joiner's empty placeholder is deliberately *not*
  stamped: it has no members and no parts, and stamping it would let its
  default tempo beat the real one it is about to be sent.

A second, quieter half of the same report: even once the audio arrived, the
rehearsal screen went on showing the old document. A sync reloads the library
and builds fresh `Rehearsal` objects, so the screen's reference was stale. It
now re-resolves by id after returning from Nearby.

Verified on device afterwards: `master=true`, `tune_video.mp4` at 960 749
frames with its 1 921 542-byte file on disk, and the tempo arriving as
100.14 BPM rather than the placeholder's 120.

### 13.5 Two bugs only real conditions found

- **A VPN wins the address race.** `_localAddress` took the first private-range
  IPv4 it found, and the test phone had a VPN up: the QR advertised
  `10.5.0.2`, a tunnel endpoint nobody in the room can reach. Interfaces are
  now *ranked* — Wi-Fi, then wired, then anything else, with tunnels and
  cellular excluded outright — rather than filtered.
- **`load()` was not reentrant.** It cleared the list then appended, so a sync
  finishing while the UI reloaded left every rehearsal in the library twice. It
  now builds a local list and swaps it in.

### 13.6 What is left

- **mDNS re-discovery is not built.** First contact does not need it — the QR
  carries the endpoint — but a second meeting currently means showing the link
  again rather than the app simply noticing the others are in the room.
  `_gfrehearsal._tcp` with `bonsoir` or `nsd`, as the prototype had it.

- **There is no short typed code, and there cannot be one yet.** The first
  build displayed a six-character code and a field labelled "type the code",
  and typing it did nothing — the code was a *hash* of the key, so it carried
  neither the key nor the address and could not be turned back into either.
  Anyone without a camera was stuck.

  It now shows the whole link with a copy button, and Join accepts that. A
  short code only becomes possible once discovery exists: the code identifies
  which advertised host to connect to, and the key has to be derived from the
  code itself rather than hashed into it — which also means deciding whether
  30-odd bits of shared secret is enough for a rehearsal room. Until that is
  settled, the link is what travels, and a field that is handed something
  code-shaped says so specifically instead of "that did not work".
- **The live scanner is built but has not been pointed at a code yet.** Join
  offers *Scan a code* on Android and iOS, opening `flutter_zxing`'s reader
  restricted to QR, with `tryHarder`, rotation and inversion on because a code
  on a dim screen at an angle is the normal case. Codes that are not ours are
  ignored rather than reported, so the scanner keeps looking instead of
  complaining about whatever else is on the table. Desktop stays typed-only
  (D11).

  What is verified: it builds, `libflutter_zxing.so` ships for arm64, the parse
  path the scanner feeds is unit-tested, and joining by ticket works live. What
  is not: actually holding a camera over a code — the test phone locked itself
  before that could be tried.
- **One rehearsal is shared at a time**, and hosting stops when the Nearby
  screen closes. Fine for a rehearsal room, wrong for a laptop left running as
  an archive node.
- **The security model is LAN-shaped**: the join key authenticates and encrypts,
  there is no forward secrecy, and anyone with the code is in. Appropriate for
  people in one room; not a substitute for TLS if this ever leaves the LAN.

---

## 14. Identity, ownership and staying in step

Four things the first multi-user build got wrong or left out, all reported from
real use.

### 14.1 A joiner had no identity of its own

Joining creates an empty placeholder and the merge fills it with the *host's*
members and parts. None of those are the person holding the phone, and nothing
ever created one — so `selfMemberId` stayed null, the rehearsal screen fell
back to `members.first`, and every part a joiner added was attributed to
whoever shared the tune. Every lane carried that person's name.

Joining now asks for a name and instrument once per rehearsal, creates a member
and a part for them, and pushes both straight back so the others see the new
player without waiting for the next meeting.

### 14.2 You record your part, nobody else's

The record button only appears on parts you own, and a small badge marks them,
so a missing button reads as ownership rather than a control that failed to
appear.

This is not only tidiness. Takes merge by keeping the highest revision, so
recording over someone else's part would not merely overwrite it locally — it
would win on *their* device too, and destroy work they had not finished
listening to.

### 14.3 Deleting a take

A take can be deleted, which needs more care than it looks:

- **The revision is not rolled back.** A peer that already holds revision 3
  must never be sent a different revision 3 later, or two recordings share a
  number and the merge keeps whichever it happened to see first. `nextRevision`
  counts on from the higher of the current and the last deleted.
- **A deletion is a fact, not an absence.** It travels as a high-water mark
  (`deletedRevision`) and merges by taking the larger, and any take at or below
  it is dropped. Without that, a peer still holding the recording hands it back
  on the next sync and it can never be got rid of.

### 14.4 Staying in step while everyone is together

A sync where nothing changed costs a connect, a handshake and two manifests —
a few kilobytes, and the tests assert it moves no audio. That makes polling
cheap enough to be the whole mechanism, so there is no second protocol for live
updates: a joined device re-syncs every six seconds, and pushes immediately the
moment a take is committed rather than making the room wait.

Three details that matter:

- **Hosting outlives the Nearby screen.** The host closes it to watch the lanes
  fill in, and stopping the socket there would end the session exactly when it
  becomes useful. The rehearsal screen ends both halves on the way out.
- **A background tick reloads the library only when something arrived.**
  Reloading regardless would rebuild every `Rehearsal` object every six seconds
  and invalidate the references the open screen holds.
- **A live session gives up after five consecutive failures.** Someone who has
  walked out of the room would otherwise have every device in the band retrying
  them forever.

The stored ticket goes stale as soon as the host restarts sharing — new port,
new key — so resuming is best-effort. That is the gap discovery closes, and the
reason mDNS is still the next thing rather than an optional extra.

---

## 15. Discovery

The QR introduces two devices. Discovery is what lets them find each other
*again*, which is the case the whole feature is built around: meet, sync, go
home and record, meet again.

### 15.1 The key had to move first

Discovery on its own would not have helped. Hosting used to mint a fresh key
every time it started, so a device that rediscovered a peer tomorrow still
could not say anything to it — it held last week's secret.

The key is now a property of the **rehearsal**, generated at creation, carried
in the manifest and merged like any other field. That is not circular: everyone
holding the document is already a member. The consequence worth stating is that
anyone who ever joins keeps access, because there is no re-keying — a leaked
link cannot be revoked, only the rehearsal abandoned.

### 15.2 What is advertised, and what is not

`_gfrehearsal._tcp`, with two TXT records: the rehearsal id and the advertising
device's id. The port comes from the service record.

**The key is never advertised.** Anyone on the network can see that a
GrooveForge rehearsal is being shared and which id it has; nobody can join
without having been introduced once. Discovery answers "where are they now",
never "may I come in".

### 15.3 Following a rehearsal, not an address

A live session tracks a rehearsal id and a key. The address is resolved afresh
on every tick, preferring a discovered peer and falling back to the remembered
ticket — because a remembered address goes stale the moment the host restarts
sharing, while a discovered one is current by definition.

Two details from how mDNS behaves in practice:

- **Peers are aged out after 45 seconds as well as removed on goodbye.** A
  phone that goes into a pocket or leaves the room usually just stops
  answering; waiting for a farewell that never comes would leave the band
  syncing with a ghost.
- **A live session only gives up when nothing is discoverable either.** A peer
  that is still advertising but refusing connections is probably mid-sync with
  someone else, and is worth retrying.

Discovery failing is a normal condition, not an error: a locked-down guest
network, or a desktop with no Avahi. It is caught and logged, and the QR still
works — which is the whole reason it carries the endpoint rather than a name to
look up.

### 15.4 A permission that was missing all along

The Android manifest never declared `INTERNET`. Syncing worked anyway because
Flutter's *debug* manifest adds it for the tooling's own use — so a **release
build would have had no network at all**, and the failure would have appeared
only after shipping. It is now declared properly, along with
`ACCESS_NETWORK_STATE` and `CHANGE_WIFI_MULTICAST_STATE` for mDNS.

iOS gained `NSLocalNetworkUsageDescription` and `NSBonjourServices`. Both are
mandatory from iOS 14: without the service list, the type is silently invisible
rather than refused.

### 15.5 Not yet verified on hardware

The code builds for Linux and Android, the tests pass, and discovery failing is
handled — but two devices have not yet been watched finding each other. The
test phone locked itself before that could be tried.

The check is: open a rehearsal on the phone, tap share, then on a Linux machine
run `avahi-browse -rt _gfrehearsal._tcp`. The service should appear with the
tune's name, and its TXT records should carry the rehearsal and device ids.

---

## 16. Two things a working sync still got wrong

### 16.1 A part arrived and played silence

Takes transferred, the manifest merged, the lane appeared — and nothing came
out of the speaker. Merging a *document* and opening an *audio track* are
separate things, and only the first was happening: the engine plays tracks it
has been told to open, and after a background sync nobody told it.

`RehearsalSyncService` now calls `onAudioReceived` when a sync actually brought
audio in, and the rehearsal screen reloads the engine's tracks in response.
Two details:

- **Reloading waits if the transport is running.** Clearing and reopening every
  native track mid-playback is a dropout; a take that arrives while the band is
  listening is picked up when they stop, a moment later.
- **Syncing no longer reloads the library afterwards.** The merge mutates the
  library's live document in place and the session saves it, so memory and disk
  are already correct — and reloading swapped in fresh objects underneath the
  open screen, leaving it holding a stale one. There is a test asserting the
  caller's reference still points at the merged document.

### 16.2 A part could be emptied but never removed

Deleting a take drops the recording and keeps the lane, which is right when
someone wants another go. It is wrong for a part that should not exist at all —
added by mistake, or for an instrument nobody ended up playing — and there was
no way to get rid of one.

Removing a part needs a tombstone, for the same reason deleting a take does:
parts merge by union, so simply dropping one locally means the next sync with
anyone who still has it puts it straight back. `deletedPartIds` is a grow-only
set, merged by union and applied before the parts themselves so a removed part
is never added and then removed again.

The lane's two destructive actions are now a named menu rather than two similar
icons — *Delete this recording* keeps the lane, *Remove this part* does not,
and that difference is not something an icon conveys.

---

## 17. Three bugs from the first real two-device session

### 17.1 Everybody listening, nobody speaking

Opening a rehearsal started *browsing* but never *advertising* — that only
happened when someone tapped share. So two people opening the same tune both
looked for each other and neither answered, and they sat there indefinitely.

The model was wrong, not the code. **Being in a rehearsal is what makes you
reachable**, so opening one now binds a socket, advertises, browses and starts
the live session together (`goLive`). Share exists only to introduce someone
who has never had the tune before; it is not what puts you in the room.

### 17.2 A re-recording reused the deleted revision — and cost the peer its copy

`commitTake` computed the new revision from the take that was there. After a
deletion there *is* none, so the next recording came out as revision 1 again —
the same number as the one just deleted.

That is silent data loss, and worse than a missing update:

1. The peer holds revision 1 and receives revision 1. Equal revisions mean "the
   same take", so it declines to fetch the new audio.
2. The deletion tombstone for revision 1 then arrives and clears the copy it
   already had.

The part ends up empty on the peer and the re-recording never lands — exactly
the reported "never deleted, nor changed". `part.nextRevision` counts on from
the higher of the current take and the last deleted one, and both the file name
and the take itself now use it. It had been added for the file name and missed
here, which is why the two disagreed.

### 17.3 Nine connected devices in a room with two

The peer list was a `List` appended to on every incoming connection, and a live
session reconnects every six seconds. After a minute with one peer it read as
nine, and each device showed a different number because each had made a
different number of connections.

Peers are now keyed by address, and the count shown comes from **discovery**
rather than from connection history — it answers "who is in the room", which is
what a count of connected devices is asked to mean.

---

## 18. What making both sides reachable broke

Once opening a rehearsal made a device *reachable* as well as watchful (§17.1),
every pair in the room began hosting and polling each other. That changed which
code paths overlap, and two things that had been theoretically racy became
routine.

### 18.1 Two saves, one temporary file

`save` wrote through a fixed `rehearsal.json.tmp`. With an incoming sync and an
outgoing one both merging the same document, two saves overlap: the first
rename succeeds, the second fails with ENOENT, and whatever the second was
writing is gone. `ProjectService` carries a comment about exactly this failure;
this code repeated it.

Saves are now queued per library, and each uses a unique temporary name so
nothing outside the queue can collide either.

### 18.2 Serialising sessions deadlocked the room

The first attempt at fixing 18.1 was to run one session at a time. That is
worse: both devices can start a sync in the same instant, and each then makes
the other's incoming connection wait for its own outgoing one to finish.
Neither can answer, both wait for the ten-second frame timeout, and nothing
syncs.

Only *outgoing* sessions queue now. Incoming ones answer immediately, which is
safe because the two things sessions share are handled elsewhere: the document
is merged synchronously and the merge is order-independent, and the manifest's
writes are queued.

The test that found this is worth keeping in mind when touching any of it — it
builds the real topology, both sides hosting *and* syncing at once, which none
of the earlier tests did. It failed at eleven seconds with the deadlock and
passes in one without.

### 18.3 An immediate push no longer skips itself

`syncNow` returned early when a sync was already in flight. That is right for a
periodic poll and wrong for this: it carries a take the player has just
finished, and dropping it because a routine poll happened to be running left
the room waiting for the next one — or indefinitely, if that poll found
nothing. It queues instead.

---

## 19. Playback ends with the audio

The transport ran on indefinitely after the last track finished. It now stops
when the content does, decided in the engine rather than in Dart — the engine
owns the transport, and a UI timer noticing a moment later would let it drift
past the end audibly.

Three cases the naive version would get wrong, all covered by the smoke test:

- **Recording is exempt.** A player laying down a part longer than anything
  already there is how a rehearsal grows past its first take; cutting them off
  at the old end would be wrong.
- **An offset master ends where its *audio* does**, not where its file does.
  Anchoring the grid partway into a recording means the last bar arrives that
  much earlier.
- **With nothing loaded the transport is a metronome**, which has no end to
  reach, so it keeps running.

The stop lands within one block of the exact end rather than on the frame: the
check runs once per callback, and stopping mid-buffer would tear it.

One Dart-side consequence: a reload deferred because audio arrived mid-playback
used to be applied in `stop()`. The engine can now stop without anyone calling
that, so the poll applies it too — otherwise a part that arrived during a
play-through would stay silent until the transport was started and stopped by
hand.

---

## 20. Why the room went quiet

Two devices stopped seeing each other within a minute or two. Three defects
stacked, and each alone was enough:

**The advertised name collided.** Everyone in a rehearsal advertised under the
tune's title, but DNS-SD instance names have to be unique on the link. The
daemon resolved the collision by renaming: `test2`, `test2 (2)`, `test2 (3)`.
The name now carries a slice of the device id.

**Each rename read as a departure.** A rename withdraws the old name, and the
stack emits a goodbye for it while the device is still in the room. Peers were
keyed by service name, so a rename also filed the same device twice. Peers are
now keyed by device and rehearsal — what a peer *is*, not what it is currently
called — and a goodbye starts a 20-second grace period instead of deleting on
the spot. That matters because nothing would have re-added the peer: mDNS has
no reason to re-announce a registration it still considers live.

**Ageing killed live peers.** A sighting was only refreshed by an mDNS event,
and browsers re-query at around 80% of a two-minute TTL — so a perfectly alive
peer routinely went 90 seconds without producing one, against a 45-second
timeout. The timeout is now three minutes, and the real liveness signal is that
we actually exchanged data: a successful sync, or an incoming connection,
refreshes the sighting. A peer that just answered is in the room by definition,
whatever the daemon last said about it.

Unrelated, found in the same log: the shell keeps the rack and rehearsals
screens alive side by side, so their two floating action buttons shared the
default hero tag and any route animation threw. Both now name their tag.

---

## 21. Goodbyes are checked, and pushes go to everyone

**A departure took a minute to show.** The grace period from §20 protects
against goodbyes that mean nothing, but it made real ones slow: the room went
on showing a device that had already packed up. Rather than pick a timeout that
is wrong in one direction or the other, the peer is now asked directly —
discovery calls a probe that knocks on the sync port. Nobody listening means
they left, and they go at once; an answer means the goodbye was noise, and they
stay. The grace period remains as the fallback when no probe is set.

The probe lives in the sync service, which owns the sockets, and is injected
into discovery. It re-checks the peer table after the probe returns, because a
sighting can arrive while the knock is in flight and a fresh sighting outranks
a stale goodbye.

Worth knowing when reading a log: the stack emits *two* goodbyes for one
departure, and the first carries no TXT attributes at all (`{"lib":"bonsoir"}`),
so it cannot be attributed to a device and is ignored. Only the resolved one
does anything.

**A tick synced with one peer.** With two devices that is the whole room. With
three or more, a take reached the far end only by being relayed through
whichever peer discovery happened to list first — several ticks later, and
looking exactly like a bug. Both the periodic tick and the immediate push after
a recording now sync with every discovered peer, sequentially: the sessions are
cheap when there is nothing to exchange, the merge is order-independent, and
three simultaneous sessions would only make one phone's radio and manifest
contend with themselves.

---

## 22. Who is here

Lanes are owned by members; discovery speaks in devices. Nothing joined the
two, so the screen could count the devices in the room but could not say *which
lane* belonged to any of them.

`RehearsalMember.deviceId` is that link, written once by that member's own
device. It is the single exception to the members merge rule ("a member already
known keeps the local copy"): a device id may go from unknown to known, because
otherwise a member who synced before the field existed could never acquire one
and would read as away permanently. Never overwritten — a peer claiming a
different id for someone is stale news, not an update. Rehearsals from before
the field are handled on load, where each device stamps its own member and
nobody else's.

Two smaller things this needed:

- The sync service now forwards discovery's notifications. The screens watch
  the service, not discovery, so an arrival or departure repainted only when
  something unrelated happened to notify. That was already true of the device
  count in the live bar.
- Your own lane is present by definition rather than by lookup — this device
  does not discover itself.

The badge is a dot, filled and green when present, hollow and outlined when
not: the two states differ in shape as well as hue, so it still reads without
colour vision, and the tooltip and semantics label carry the meaning for screen
readers, to whom a coloured circle says nothing.

---

## 23. Knowing the room has everything

Someone re-records a part and walks out before it transfers, and the take exists
on exactly one device. Nothing said so.

The protocol already knew enough to say it. A session ends with both sides
merged from the same pair of manifests, so the local document *is* what both
converged on. A part the peer never asked for is one they already held at that
revision or better — their own merge decided that. A part they did ask for is
theirs only if the audio actually went, which is why `_sendWanted` now returns
the set of parts it sent rather than a count: a part we advertised but could not
read is skipped silently, and counting it as delivered would report the room
complete while a take sat on one phone.

`SyncReport` carries the peer's device id (already exchanged in the handshake,
just never captured) and what they now hold. The service keeps that as a
ledger — rehearsal, device, part, revision.

**In memory, deliberately.** It is knowledge about right now: it only means
anything while the peer is visible, and the warning it feeds asks people to stay
connected a moment longer. A restart loses it and the next session rebuilds it
in seconds.

Three rules the UI depends on:

- Only *visible* peers count. Someone who went home cannot be waited for, and
  warning about them would make the indicator permanent and so ignored.
- A peer we have not finished a session with counts as **not** having it. Until
  manifests are exchanged we genuinely do not know, and a restart therefore
  shows the warning for one tick — honest, and self-clearing.
- The ledger entry is replaced, not merged. Someone who deletes and re-records
  moves *backwards* in our view of them until the new take lands, and keeping
  the old higher number would hide exactly the case this exists for.

The live bar becomes the warning rather than growing a second one beside it —
it is already the "who is here" strip, and "does everyone have everything" is
the same question. Lanes carry a red tag individually.

### A test seam this forced

`RehearsalLibrary` gained `deviceIdOverride`. The identity lives in shared
preferences, which are per *process*, so two libraries in one test were the same
device — and a peer whose id matches your own is filtered out of discovery as
yourself, quietly turning every two-device test into a one-device one. Every
stamp in the library now goes through `deviceId()`, and the sync service asks
the library rather than the free function, so a device's member stamps, its
field clocks and the id it announces on the network cannot disagree.

---

## 24. The stranded take

Reported from a real session: a re-recorded trumpet part reached the phone but
not the tablet. The tablet showed the *new* take's duration, showed no warning,
and played the old audio.

The manifest merges and saves before a single byte of audio moves, and
`partsToFetch` was decided purely on revision numbers. So once a device wrote
down revision 2, every later sync compared 2 against 2, asked for nothing, and
the take was stranded permanently — right duration on screen, wrong recording
underneath, and no way back.

Two ways in, and the reported one is the second:

1. A session dies between saving the manifest and receiving the blob.
2. **Relay.** A hands B the manifest for a take whose audio B does not have
   yet; B skips the blob silently (`_sendWanted` cannot send what it cannot
   read); C, syncing with B, writes down the revision. Exactly the "the tune
   was already open on the phone and the tablet joined after" shape.

The fix is that presence of the audio, not the revision alone, decides a fetch.
`SyncStore` gained `hasTake` / `hasMaster`, and the want list is the merge's
answer plus every part whose take has no audio on disk. Zero bytes counts as
absent — an interrupted write leaves a file that exists and plays nothing, and
"the file is there" would strand it just as surely.

Asking again costs a part id in a list. Not asking costs the take.

The lane now also says **Waiting for audio** when this device holds the record
of a take without the recording. It reads that state off what the engine
actually loaded rather than re-checking the filesystem: a part with a take and
no entry in `_trackOf` is one whose file would not open. That is the tag that
would have made this visible immediately, instead of leaving it to be noticed
by ear.

### A test that could not see the bug

`_MemoryStore` keyed audio by part id, so "holds the old take but not the new
one" was unrepresentable — the exact state at the heart of this. It now keys by
file name, as the real store does on disk, and both new tests fail without the
fix.

---

## 25. Practising slowly

Two speeds, answering two different questions:

- **The tune's tempo** is a property of the arrangement. It syncs, like metre
  and count-in already did, and changing it changes the tune for the band.
- **Practice speed** is local, sitting beside gain and mute because it is the
  same kind of thing. One person working a hard bar at half speed should not
  drag the others down with them, nor make every device re-render.

The effective tempo is their product, and it is the only number the grid and
the renderer ever see.

### Stretching, not resampling

Reading a recording at 70% of its rate drops it about six semitones, which
makes it useless to play along to. The duration has to change while the pitch
stays put. `gf_phase_vocoder` was already in the tree for the harmonizer and
the vocoder's natural mode, and already exposed `gf_pv_set_stretch` — so this
needed no new dependency, and dodged the licence problem the good third-party
options would have brought (Rubber Band is GPL, SoundTouch LGPL, against an MIT
app that has to pass F-Droid).

### Rendered once, not in the callback

`gf_timestretch` writes a whole file. Stretching live would mean an FFT per
block per track on the audio thread, and the device most likely to be in a
school rehearsal is the one least able to afford it — a dropout mid-take is a
far worse outcome than waiting two seconds after moving a slider. Rendering
offline also lifts the real-time constraint, so the analysis window is 4096
rather than the harmonizer's live size, which holds sustained notes together
much better.

The engine then streams a rendered file through the ordinary disk path,
knowing nothing about tempo at all.

Three details that decide whether it stays in time:

- **The output length is decided up front**, from the input length and the
  ratio, not accepted from the vocoder. Its output arrives in whole synthesis
  frames, so the last one overshoots — and a track one frame longer than the
  grid expects drifts against every other track in the tune. Short renders are
  padded with silence for the same reason.
- **The master's downbeat offset scales by the same ratio** as its audio. The
  downbeat is at the same musical place, which is a different frame number once
  the recording has been stretched.
- **Always render from the original.** Rendering from an earlier render
  compounds the vocoder's artefacts, and a few tempo nudges are enough to hear
  it.

### Takes carry their own tempo

`RehearsalTake.recordedBpm` and `RehearsalMaster.nativeBpm` say what a
recording was played at, so the stretch ratio is `recordedBpm / effective`.
This is what lets someone record a part *while slowed down* and have it land
correctly when the band returns to tempo — the take is stored as played and
stamped, never pre-stretched.

Documents written before these fields carry zero, and the library fills them in
from the tune's own tempo on load. That is exactly right: the fields did not
exist, so nobody can have changed the tempo, so everything on disk was recorded
at the one the tune still has.

### What is no longer frozen

`isGridFrozen` used to stop the tempo changing once anything was recorded.
It now guards only the metre: 4/4 to 3/4 re-bars everything that was played,
and there is no honest way to reinterpret a recording phrased in fours.

### The cache

`tempo/` inside the rehearsal, named by ratio so a stale render can never be
mistaken for a current one — that failure would be a track playing at the wrong
length against a correct grid, which sounds like a broken app rather than a
stale cache. Swept *after* a render, never before: the files being replaced may
still be open in the engine.

---

## 26. Calibrating from where it matters

The latency warning told the player to go to Settings and find the probe. That
is most of the reason latency stays unmeasured: leaving the tune, opening
preferences and scrolling to an item you have never seen is a lot to ask of
someone who just wanted to record a part.

The ribbon now carries the fix next to the complaint. The dialog in between is
not padding: the probe listens for its own sweeps through the microphone, so on
headphones it hears nothing and reports — correctly — that it found nothing.
Meeting a feature that way is confusing, and one paragraph beforehand avoids
it. The dialog says to use the speaker, turn it up, keep the room quiet, and
re-measure after switching to Bluetooth.

Two things this needed:

- **The transport is stopped first.** The probe rides on a different bus slot
  from the rehearsal engine, so the engine does not have to be torn down — but
  anything else coming out of the speaker is interference for a measurement
  that works by cross-correlation.
- **The engine is told to look again.** The probe writes to shared
  preferences, which the rehearsal read once when it opened. Without
  `adoptMeasuredCompensation`, calibrating from inside a tune would appear to
  do nothing and the warning would still be sitting there.

---

## 27. Removing a stale player

Reported after clearing app data on a tablet to test something: the device
re-joined as a new member, and the old one stayed in the band with no way out.
Members merge by union, so dropping one locally lasts exactly until the next
sync with anyone who still has them.

### Why not a vote

The suggestion was to require everyone connected and put a ballot on each
screen. It was rejected, for three reasons:

1. It would be the **only synchronous, everybody-present operation** in a
   design that is otherwise entirely asynchronous. It fails precisely in the
   normal case — a band between rehearsals is almost never all online — and the
   thing being removed is by definition a device that will never appear.
2. **"All the other users" is not knowable.** A member who has never opened the
   tune on a device we have met has no device id at all, so "absent" and "not a
   device" are indistinguishable. The precondition could be permanently
   unsatisfiable with nothing to show the user why.
3. **The document already solves this.** Parts are removed with a tombstone —
   a grow-only set, which is the conflict-free way to take something out of
   another grow-only set. `deletedMemberIds` is the same mechanism, and it needs
   no agreement: it wins on merge in either direction and in any order, so a
   device that was offline reaches the same answer whenever it next syncs.
   Tested from both directions.

### What the vote was really protecting

Not agreement — presence. The genuine risk is removing someone who is still
around, and that is a local check costing nothing: the action is offered only
for a member who is **not you** and **not currently visible**. Someone who is
connected can remove themselves. The dialog says as much rather than simply
greying the item out.

### Consequences handled

- **Their parts go with them**, each with its own tombstone. A part belongs to
  exactly one member (D6), and leaving them would attribute recordings to
  nobody. The merge applies this too, because the tombstone can arrive from a
  peer long before — or long after — the parts do.
- **Their audio is deleted** from disk, not just unlinked from the manifest.
- **A device removed while it was away** clears its own `selfMemberId` on the
  next open, so it becomes a fresh joiner rather than a ghost that owns
  nothing, matches no lane and cannot record. Re-adding the old id would not
  survive a sync anyway — that is what the tombstone means.
- The confirmation names how many recordings are about to go.

### What happens when the removed device comes back

It syncs like any other peer, and the tombstone travels *to* it: its own member
and parts are dropped from its copy, and `RehearsalEngine.open` notices that
`selfMemberId` is tombstoned and clears it. Their old part is not merged back
anywhere, in either direction — that is what the tombstone is for.

They are **not banned**. The join key is unchanged, so the device still
connects and syncs; tapping to add a part asks who is playing and creates a
*new* member with a new id, which merges in normally because no tombstone names
it. What does not come back is the old identity and its recordings: those have
to be recorded again.

Revoking access would mean rotating the join key, and that has the same defect
as the vote — every device that was offline during the rotation would be locked
out too, not just the one being removed. Removal tidies the roster; it is not
access control.

This is also why the identity dialog moved to `lib/widgets/`. It was reachable
only from the join screen, so a removed device that already had the tune was
never asked who it was again: it could sync forever while the add-part button
silently did nothing. A removal that cannot be undone by rejoining is a ban by
accident.

One loose end: on the removed device the old take's WAV stays on disk,
unreferenced by any manifest. It is never played and never sent — `readTake`
resolves through the part, which is gone — but it is not cleaned up either.

### The menu that was never shown

First attempt put the action inside the lane's overflow menu, which is wrapped
in `if (isMine)` — so a `!isMine` item inside it could never render. It compiled,
analysed clean and was unreachable.

The menu now renders when there is something to put in it, and the items are
chosen per lane: your own gives *delete recording* and *remove part*; someone
else's gives *remove player*, and only when they are not visible. A lane that
offers nothing shows no button rather than an empty menu.

Worth noting for tests: a member with no `deviceId` at all — one written before
members carried one — counts as not present, so they are removable. That is the
intended case, since a stale identity from before the field is exactly what
this is for.

---

## 28. The shared score vault

A band learning a tune needs the chart as much as the click. Documents —
PDFs, scans, photos of a page, a chord sheet someone typed — are added on one
device and reach the others the next time they meet.

This is the simplest structure in the whole document, and deliberately so: a
document **never changes**. There is no revision to compare, no conflict to
resolve, no editing. Adding is a union by id, removing is a tombstone, and
replacing a score means adding the new one and removing the old. That is the
same shape as members, minus everything that made members interesting.

### What it reuses

- The blob path already chunks, seals and reassembles. Documents ride it with
  `kind: 'doc'`, next to takes and the master.
- The want list gained `docs`, and `_alsoMissingFiles` mirrors
  `_alsoMissingAudio`: a document whose file never arrived is asked for again.
  That guard matters *more* here than for takes — a take at least has a
  revision that could eventually differ, whereas a document has nothing to
  compare, so without it a listed-but-absent score would be stranded for good.
- `_documentFile` resolves through the manifest rather than from the id alone,
  so a peer cannot name a path this device never agreed to hold.

### Choices worth recording

- **The file is copied into the tune, not referenced.** The picked file may sit
  in a cache the system clears, on a card that gets removed, or behind a
  content URI that stops resolving the moment the picker closes. A score the
  band relies on has to be the tune's own.
- **The name on disk comes from the id.** Two people each adding `score.pdf`
  must not land on top of each other; the original name is kept alongside,
  because that is what people recognise it by.
- **Images are drawn in the app**, zoomable — a photographed page is usually
  taken at an angle and read at arm's length. Everything else goes to whatever
  the device already uses for it (`open_filex`, MIT, plain platform channels,
  no bundled blobs). A PDF viewer of our own would be worse than the one
  already installed, and on Android the hand-off supplies a content URI, which
  is the only kind another app may open.
- **A listed document whose file has not arrived says so** and is not tappable.
  The manifest merges before the bytes move, so that is a real state rather
  than an error.
- **No extension filter on the picker.** A band shares whatever it has.

---

## 29. Reclaiming the tune screen

Measured on a Z Fold cover screen, which is the narrowest thing this has to
work on, and the tightest constraint before a chord grid can go above the lanes.

**The connection strip was permanently on.** Being *in* a rehearsal makes you
live (§?), so `isLive || isHosting` was always true and a full-width strip
announced "connected" for the whole session — two wrapped lines saying nothing
is wrong. It now appears only for the one message worth interrupting for: a
take that has not reached everyone. The quiet states moved to a chip in the app
bar, which is what the design called for in the first place, and which
disappears entirely when nobody else is about.

**The tempo could not be found.** It was plain grey text with a 14 px icon
after it, which reads as a caption, not a control. It is now a bordered chip
with a speed icon and a dropdown arrow. Nothing about the behaviour changed —
only whether anyone could tell it was there.

**Lanes lost half their height.** The level slider had a row to itself on every
lane, so five players filled a cover screen before the chord grid had anywhere
to go. It now appears when a lane is tapped — level is an occasional
adjustment, which is the same reasoning as D14.

**Mute is pinned last.** The other buttons on a lane come and go with whose it
is and what is on it, so mute used to sit at a different x-position on almost
every row. It is the one control people reach for *while* the band is playing,
so it is now always rightmost and always present, disabled rather than absent
when there is nothing to mute.

Denser lanes immediately overflowed: a lane that was both yours and awaiting
delivery carried two badges beside the name and ran 84 px off the side. The
status tags moved to the second line, where the instrument and duration
ellipsize and the tag keeps its full width.

---

## 30. The chord grid

### A real parser, not a validator

`ChordSymbol` reads a symbol into a root pitch class, a triad, a seventh and a
full interval set. Storing the text and merely checking its shape would have
been a third of the work — and would have had to be thrown away the moment
anything wanted to *draw* the chord on a keyboard or a fretboard. Building for
that now was the deliberate choice.

Four cases decided the design, each one where a plausible parser is quietly
wrong:

- **`CM` is C major, not CM7.** A major marker with no `7` after it must not
  conjure a seventh. Same for `Cmaj`.
- **`CmM7` needs both letters** to mean different things: minor triad, major
  seventh. `Cm(M7)` and `Cminmaj7` are the same chord.
- **`C6/9` is two added tones, not a slash bass.** A `/` starts a bass only
  when what follows parses as a note *and* consumes the rest of the symbol —
  which is also what keeps `Am(M7)/B` working.
- **Accidentals are only accidentals in some places.** `Gm7b5` displays as
  `Gm7♭5`, but `Csus4` must not become `su♭4`, so a `b` is only a flat where it
  follows a note letter or sits against a degree.

The root's *spelling* is kept rather than normalised: whether someone wrote
`Ab` or `G#` says something about the key they are thinking in.

A symbol may name its triad only once. `C+-` used to parse, with the second
token quietly winning; it is now refused, because a typo becoming a plausible
chord is worse than a rejection. The rule is one triad, not triad-first —
`C7sus4` still works, because charts write it constantly.

### Bars are slots, not positions

A bar is a fixed-size list of nullable chords. Four slots with the second empty
means the first chord holds through beat two — which is how a chart reads.
Positions would let a chord land between beats, which nothing notates and
nobody could play. Re-dividing keeps chords where they were *played*, not where
they were indexed: going from four slots to two puts the chord from beat three
in the second half.

Divisions offered are the divisors of the beat count, so every slot lands on a
beat.

### The form merges as one value

`RehearsalField.chords` is a last-writer-wins register like tempo and metre,
not a per-bar CRDT. Editing a form is a deliberate act on the shape of a tune,
and half of one chart merged with half of another is not a tune anybody wrote.
The bars are copied on merge — the remote document is discarded afterwards, and
sharing its objects would leave the local one holding bars a later edit could
mutate underneath it.

### A written form has length

`gf_reh_set_min_end` puts a floor under `gf_reh_content_end`. Type out
thirty-two bars, press play, and the click runs through them instead of the
transport stopping at once because no track is loaded. A track longer than the
form still decides the end.

### Collapsed and expanded

Collapsed is one line that scrolls itself, with two bars of lead-in rather than
centring the current bar — a player reads ahead, and centring shows the past as
prominently as the future. It stops following the moment the player scrolls by
hand, and starts again when the transport does. Expanded wraps the whole chart
at as many bars per row as the width allows, capped in height so a long form
cannot push the lanes off the screen.

### What the first version on a real phone got wrong

Five things, all found by using it rather than by reading it:

- **A bar of four was unreadable.** Every cell had the same width and each slot
  scaled its own text to fit, so `Em7♯5 B69 GmM7 C6/9` came out at four
  different sizes, none of them legible. Cell width now grows with the number
  of chords, every chord in a bar is set at one size, and a hairline separates
  the beats.
- **The editor overflowed.** Four chord fields plus a software keyboard is
  taller than a phone, and the dialog lost its own buttons behind the warning
  stripes. Its content scrolls and is capped at a share of the screen height.
- **There was no way to add a bar without unfolding the chart**, which is the
  state it spends least of its life in. The collapsed strip ends with a `+`,
  and the toolbar's `+` is no longer conditional.
- **The keyboard forced upper case on every character**, which makes
  `Abm7sus4` all but untypable. A chord is upper case exactly where it names a
  note — the root, and the bass after a slash — so a formatter raises those two
  positions and leaves everything else as typed. `C/G` needs no shift key
  either.
- **A bar of four in the expanded chart could be wider than the row.** Bar
  width is clamped to the available width, so it takes a line to itself rather
  than overflowing.

---

## 31. Bluetooth latency

Reported from a real session: plugging in Bluetooth headphones — the right
instinct, to stop the microphone hearing the other tracks — puts every take
roughly a fifth of a second behind the beat.

### Why the video players' trick does not transfer

Netflix, YouTube and VLC do A/V sync: they delay the *picture* to match the
audio. They own both streams, only have to shift a visual, and there is no
microphone anywhere in the loop. Their tolerance is also enormous — lip-sync
passes at roughly 45 ms early to 125 ms late, against about 10 ms for an
overdub. They are allowed ten times our error and only have to move the thing
they draw.

They are not really measuring it either. Android's NDK guide states plainly
that *"there is currently no API to determine audio latency over any path on an
Android device at runtime"*; the platform offers two feature flags describing
the built-in path and nothing about a headset. `AAudioStream_getTimestamp`
reports when a frame reached the audio device, but for A2DP the sink-side delay
— codec, radio, the earbud's own buffer, which is most of the two hundred
milliseconds — is generally not in that number.

### What does work

The acoustic probe already measures Bluetooth correctly if the player **holds
an earcup against the phone's microphone** while it runs. The chirp goes out
through the headset, the mic hears it through the cup, and the existing
cross-correlation returns the true round trip including every part of the
Bluetooth path. No new API, no vendor cooperation, no estimate — and once per
headset. Only the instructions changed.

Both places that explain the measurement now check the route first, because
telling somebody wearing Bluetooth headphones to "use the speaker" is worse
than unhelpful: following it measures the speaker, files the answer against the
headset, and leaves every take late.

### The gap that made all of this unusable

`compensationFrames` was one number per device. Measuring with headphones on
overwrote the speaker's figure and vice versa, so whichever route was measured
last was the only one that was right. It is now a table keyed by route —
`speaker`, `wired`, and each Bluetooth headset by name, since somebody may own
several and each has its own delay.

An unmeasured route falls back to the last figure rather than to zero: a
wrong-but-close number beats no compensation, which is a whole round trip of
error. Falling back is deliberately *not* the same as having been measured, and
that difference is what the warning reads.

`AudioRoutePlugin` reports identity, not latency — which device is connected is
enough to look up a measurement already taken, and to notice when none exists.
The active route is inferred by precedence (Bluetooth over wire, wire over
speaker) because Android exposes which devices are available, not which one is
in use.

### It had to be device-wide

First version put the table in `RehearsalLocalState`, which lives inside each
rehearsal — so calibrating a headset in one tune left the next tune reporting
that same headset as unknown. The document above says why that was wrong three
times over: the delay belongs to the gear, not the tune, and the same headset
has the same delay whichever chart is open.

`LatencyCalibration` now owns the table in shared preferences, and is the only
source of truth. Two details it needed:

- **It reloads.** The probe runs on its own screen and saves there, so the
  engine has to look again afterwards rather than trust what it read when the
  tune opened — otherwise calibrating from inside a rehearsal appears to do
  nothing until the tune is closed and reopened.
- **It adopts what was stranded.** Anything filed per-tune by the earlier
  version is taken up when that tune next opens, so a measurement already made
  is not lost. The device table wins on conflict: it is the newer, better
  source, and a stale per-tune figure must not overwrite it.

The old single-figure preference keeps its name, so a calibration from before
any of this survives as the fallback.

### Still open

A manual trim on a finished take: nudge it against the others while it loops.
Not a substitute for measuring, but Bluetooth latency drifts with codec
negotiation and battery level, so a by-ear backstop is worth having.

---

## 32. Count-in, after the fact

It could only be set when a tune was created, which is the one moment nobody
knows what they want: two bars is only obviously too short or too long once you
have tried recording against it. It now sits in the tempo sheet, beside the two
speeds, because it is the same kind of decision.

It is part of the tune rather than of a device, so it goes through
`updateField` and syncs — a band that agrees on four bars in should not have to
agree again on every phone.

---

## 33. Aligning a recording by eye

Tapping the tempo and dragging a marker got the grid roughly right, and roughly
was all it could be: at a phone's width a three-minute track puts a whole bar
inside two pixels. Everything below exists to make the last tenth of a beat
visible.

**Beat lines.** Red verticals drawn from the downbeat at the current tempo, bar
lines full height and beats short. This is what makes a tempo error legible: a
tenth of a beat out is inaudible over two bars and unmistakable after thirty,
because the lines walk off the sound. Suppressed below four pixels apart, where
they would be a wash rather than a reading.

**Zoom, up to ×400, about the marker** — not about the centre of the screen,
which would walk the downbeat off the edge after two presses when it is the
only reason anyone is zooming. Waveform resolution follows the zoom, capped at
24 000 bins; magnifying a 600-bin drawing would enlarge the bins rather than
the sound. Only the bins inside the window are drawn, so zooming costs no more
than the whole file did.

Tap and drag now map through the visible window. Without that, every tap while
zoomed in would land near the start of the recording.

**Fine tempo**, a tenth of a beat per press, with the value between its two
buttons. The tap tempo lands within a beat or so; the last tenth decides
whether the lines still sit on the sound thirty bars later, and it is not
something anybody can tap.

**Skip the silence.** Commercial tracks and screen recordings open with
anything from digital black to two seconds of room tone, and the first thing
anyone does is drag past it. `MasterSilence` reads only the first thirty
seconds — the answer is always near the front — and requires about two
milliseconds of sound above roughly -46 dBFS before it will call it an entry,
so a decoder click cannot be mistaken for the music. It reports the start of
the run rather than its end, because that is where the note began.

Nothing is cut. The grid may legitimately start before the first note — an
upbeat, or a count-in on the recording itself — and a trim would throw that
away irreversibly, so the button offers the position and the file stays whole.
It appears only once the scan has found something and the marker is not already
there.

---

## 34. Measuring a recording without moving it

Reported while using the new beat lines: nudging the tempo to line them up with
the music made the music speed up or slow down, so the two could never meet.
Chase the tempo and it runs away from you.

The mistake was mine and it was conceptual. A recording is a fixed thing.
Changing the tempo while calibrating means *"I now think it was played at
142"*, not *"play it at 142"* — so `master.nativeBpm` has to move with the
tune's tempo, which leaves the stretch ratio at exactly 1 and nothing is
re-rendered. `setMasterTempo` does both together; the align screen uses it
instead of `setBpm`.

Slowing down for practice is the other case entirely, and there the recording
*should* stretch — that is `setPracticeSpeed`, and it leaves the pair alone.

Which makes the tune-tempo slider wrong to offer once a recording exists: its
tempo is not ours to choose, it is whatever was played. The slider is disabled
with a line saying where the tempo comes from and pointing at the practice
speed for slowing down.

## 35. Count-in on play, and the lead-in

Two things, and the second is the interesting one.

**Play now counts in**, like recording already did. You are rehearsing either
way, and coming in cold on bar one is the harder of the two. Setting the
count-in to none in the tempo panel restores the old behaviour exactly.

**A recording that starts before the tune's first downbeat is now heard during
the count-in.** This closes the "audio before the downbeat is not played" gap
from §12.4, and the count-in turns out to be exactly the right place for it: an
intro or a pick-up plays while the click counts, and the music's first downbeat
lands on the grid's.

The engine change was one guard — `p < 0` was suppressing every track before
the downbeat, where checking `p + offset` alone is both sufficient and correct.
A take has no offset, so it stays silent there, which is right: nobody played
anything before bar one. But removing the guard exposed two latent bugs, both
of which would have read out of bounds or gone silent:

- **`p % GF_REH_RING_FRAMES` is negative for negative `p`.** C's `%` keeps the
  sign of the dividend, so the ring was indexed backwards out of its buffer.
  `ring_index` now normalises it, in both the fill and the read.
- **`fill_pos = -1` meant "empty", and -1 is a real grid position.** It read as
  "already filled up to just before the downbeat", so the count-in region was
  never fetched and the lead-in stayed silent even after the guard was gone.
  The sentinel is `INT64_MIN`.

`service_all` also stopped clamping the playhead to zero, for the same reason:
during a count-in the playhead is *before* the downbeat and there is audio
there to fill.

The smoke test covers all three cases — a lead-in heard, silence before the
recording actually starts, and a take still silent before bar one.

---

## 36. The master went silent at practice speed

Two faults, one of mine and one that only the first made visible.

**The render ran in an isolate that built the app's entire FFI surface.**
`AudioInputFFI`'s constructor opens a *second* library — `libnative-lib.so` —
and resolves scores of symbols belonging to the synth, the looper, the vocoder
and the theremin. None of that has anything to do with stretching a file, and
any one of them failing to resolve in a background isolate takes the render
down with it. The isolate now binds `gf_ts_render` and nothing else.

**A missing render meant silence rather than a wrong speed.** The path helper
returned the cache location whether or not anything was there, so a failed
render loaded no track at all — which reads as the recording having vanished.
It now falls back to the original file: audibly at the wrong speed, which is
wrong in a way anyone can see, rather than absent. Rendering failures are also
caught rather than propagated, because one file that will not stretch should
not take the whole rehearsal's audio with it.

## 37. Recording through the count-in

A player following a recording's intro comes in *before* bar one. Capture used
to begin at the downbeat, so those bars were thrown away and the take started
late against the very thing it was following.

Capture now begins with the count-in, and the take carries its own
`offsetFrames` — the same convention the master already used, where file
position equals grid position plus the offset. So:

- **With a count-in**, the take's file starts that many bars before the grid
  does, and it plays during the count-in exactly as an imported intro does.
- **Without one**, the offset is zero and the downbeat is the start of the
  file, which is what every take did before this and what every existing take
  still says.

The offset scales with the tempo like the audio it belongs to, so the downbeat
stays at the same musical place when the practice speed moves.

Compensation needs no special handling: it still drops the first frames of the
physical input, which shifts the whole capture earlier by the round trip and
therefore lands the downbeat at exactly `offsetFrames` into the file.

### The first beat is the anchor, for everything

Everything on the grid — every take and the imported recording alike — is
aligned on **its own first beat**, which is grid frame 0 and the first click of
the metronome. A file may begin before that; the offset says by how much, and
the engine reads `file position = grid position + offset`. Nothing else lines
tracks up.

The arithmetic for a take recorded through a count-in, since it is easy to get
off by the compensation:

- Capture starts at grid `-countIn`.
- The first `compensation` frames of physical input are dropped, because what
  was played at a given moment arrives that many frames later.
- So file frame *j* is what was performed at grid `-countIn + j`, and grid 0 —
  the first beat of the click — sits at file frame `countIn`.
- Which is exactly what `gf_reh_take_offset` reports and what the take stores.

**A slot kept the previous track's offset.** `gf_reh_add_track` sets seven
fields of a slot and left `grid_offset` alone, and neither `remove_track` nor
`clear_tracks` cleared it either. Nothing set it for takes, so a take dropped
into the slot the imported recording had been using inherited that recording's
offset — and played a second or two ahead of everything else *and* ended early,
because `content_end` subtracts the offset. Both reported symptoms, one cause.
It is now reset where `fill_pos` is, for the reason already written there: a
slot must not trust what its last occupant left behind.

### A headset connected before the app was

Reported after a redeploy: with the headset paired and on throughout the
restart, latency was badly wrong until it was switched off and on again.

`AudioDeviceCallback` fires on devices being *added or removed*. A headset that
was already connected when the app started generates neither, so a route read
taken before the audio system had listed it was never corrected — the tune then
recorded against the speaker's compensation with a headset on, which is exactly
the two hundred milliseconds this whole mechanism exists to remove. Toggling
the headset produced a remove and an add, and everything snapped into place.

Two changes:

- **The engine follows the route itself**, through the provider, instead of
  being handed it from `RehearsalScreen.build`. Writing to a notifier while
  another widget is building is not something to rely on, and the compensation
  has to be right when record is pressed whatever happens to be on screen.
- **The route is re-read on opening a tune and again on arming a recording.**
  One method-channel round trip against the act of starting a recording is
  nothing, and it is the last moment the answer can still be made right.

Worth noting for the next report: if this recurs, the remaining suspect is not
bookkeeping but the output stream itself — a stream opened before A2DP became
the active route may genuinely buffer differently until it is reopened, which
toggling the headset also forces. That would need the engine's audio restarted
on a route change, which is a larger and more disruptive change than either of
the above.

### The web build, broken by the isolate fix

Binding `gf_ts_render` directly in the isolate (§36) put `import 'dart:ffi'` in
`rehearsal_tempo_cache.dart` — a library `main.dart` reaches through the
rehearsal library. `dart:ffi` does not exist on web, so dart2js refused the
whole compile. Nothing local caught it: `flutter analyze` and `flutter test`
never compile for web.

The renderer now sits behind a conditional export, the same shape
`audio_input_ffi.dart` has used all along — `rehearsal_stretch_io.dart` for
native targets, `rehearsal_stretch_stub.dart` for web. `StretchJob` lives in a
file of its own so neither implementation has to import the other, and so
nothing on the web side can reach a library that imports `dart:ffi`.

Before this, everything reached the native library through `AudioInputFFI`,
which already had that stub — which is why the web build had never noticed the
rehearsal engine existed.

**Verify a change like this with `flutter build web --release --wasm`**, the
same command CI runs. It is the only thing that compiles the web target.

### Two permissions the score viewer brought with it

Play flagged `READ_MEDIA_IMAGES` and `READ_MEDIA_VIDEO` and asked for a
justification. Neither is declared by this app: `open_filex`, added for the
shared score folder, declares all three media permissions plus
`READ_EXTERNAL_STORAGE` so that it can open *any* file in shared storage.

GrooveForge only ever hands it a file from the rehearsal's own `docs/` folder,
through a FileProvider content URI — which needs no permission at all. So they
are removed with `tools:node="remove"`, following the precedent already in the
manifest for `CHECK_LICENSE`, rather than justified.

That nothing depends on them is checkable rather than assumed: importing an
MP3, an M4A or a video's soundtrack worked before `open_filex` existed, when
these permissions were not in the manifest at all.

Verified against the built APK with `aapt2 dump permissions`, not just the
merged manifest — the two Play named, and `READ_MEDIA_AUDIO` with them, are
gone.
