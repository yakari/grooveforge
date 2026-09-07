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

Desktop, through the PipeWire monitor loopback (no room, no speaker, no mic):
26.67 ms, identical across runs, drift exactly 0.0 ppm — the expected result
for a digital loopback that shares one clock domain, and a useful control.

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
| **P1** | **Single-device rehearsal.** Library, create, grid, disk-streaming player, metronome, count-in, record and replace your own take, playback mix, mute and gain, persistence. Genuinely useful alone: one person layering a demo. |
| **P2** | **Master track import.** Decoders, tap-tempo and offset alignment, master lane. Can precede P3 — it is what makes the feature usable for a school group even before anyone else joins. |
| **P3** | **Shell and tab.** `MainShell`, responsive nav, l10n pass, `flutter analyze` clean. Small; can slot in earlier if you want the tab visible while P1 is still rough. |
| **P4** | **Pairing and sync.** QR and short code, authenticated TCP handshake, manifest merge, take and master transfer, mDNS re-discovery, Nearby screen. The moment it becomes a band feature. |
| **P5** | **Hostile networks.** Hotspot wizard, `.gfr` bundle export and import. |
| **P6** | **Musical extras.** Tempo change through the phase vocoder, chord-grid editing, count-in refinements. |
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
