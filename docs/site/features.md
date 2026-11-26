# All features

Everything GrooveForge does, one line each. For step-by-step help, see the [Getting started guide](../guide/).

Limits are marked in the line they apply to: *Desktop only*, *Android only*, *Not in the web demo*.

---

## Play

### Keyboards and scales

- **GrooveForge Keyboard** plays a soundfont (.sf2) on its own MIDI channel. Each keyboard picks its own soundfont, bank and patch.
- Set its soundfont to **None (MIDI only)** and the keyboard makes no sound: it only sends notes to other modules. [How](../guide/#guitar)
- The tune icon next to the MIDI CH badge sets, for one keyboard: how many keys show, key height (Small to Extra Large), what a vertical or horizontal swipe does (pitch bend, vibrato, glissando) and which CC aftertouch sends.
- The keyboard names the chord you hold (Cmaj7, F#m11). Tap that name to lock the keyboard to the chord's scale.
- Load your own soundfonts in Preferences, with **Load Soundfont (.sf2)**.

### Xen: play in a scale

- Hold a key and tap a scale: the key becomes the root and every note you play lands in that scale. [How](../guide/#scale)
- 92 scales in 11 families: Western, Maqam, Persian, Raga, Far East, SE Asia, Gamelan, Africa, Europe, Temperaments and Experimental (equal divisions from 13 to 31 notes, Bohlen-Pierce, Wendy Carlos's alpha, beta and gamma).
- Scales with notes between the piano keys retune the keys they use. Every note of a chord keeps its own tuning.
- Grey keys are outside the scale; retuned keys get a teal band and their offset in cents.
- **SNAP** (move wrong notes into the scale) and **TUNE** (apply the scale's tuning) switch on and off separately, and each has its own socket.
- The **Scale editor** builds your own scales, saved under **My Scales**. It imports and exports Scala (.scl) files and GrooveForge .json files.
- A project keeps a copy of the custom scales it uses, so it plays correctly on another device.
- New projects start with a keyboard and a Xen module, switched off until you pick a scale.

### Jam Mode: follow another player

- One keyboard (the leader) plays chords or a bass line; the keyboards you add as targets stay in the scale that fits. One Jam Mode per project.
- **DETECT** chooses what sets the scale: the chord the leader holds, or its lowest note.
- 14 scale types, from Standard, Blues and Pentatonic to Dorian, Harmonic Minor and Whole Tone.
- **SYNC** makes the scale change only on the beat, on half a bar or on the bar.
- Optional key borders and wrong-note highlights show what fits.
- **Pin below transport** keeps a one-line Jam Mode strip under the transport bar.

### Instruments

- **Riff** is an electric guitar modelled string by string. It has no keys: a keyboard or a controller sends it notes. [How](../guide/#guitar)
- Riff's palm mute, pick position, pickups, tone and sustain change strings that are already ringing. Legato plays hammer-ons and pull-offs; Feedback makes held notes bloom into a harmonic. *Not in the web demo.*
- **Vocoder**: sing into the mic and play keys; your voice takes the pitch of the notes. Four modes: Saw, Square, Choral and Harmony (your own voice, pitch-shifted to each key). *Not in the web demo.*
- **Stylophone**: a 25-key strip played with one finger, one note at a time. Four waveforms, octave shift, vibrato (VIB), and chiptune controls (pulse width, noise, bit crusher, sub-octave, a fast chord arpeggio).
- **Theremin**: a touch pad, up and down for pitch, left and right for volume. Base note, range, vibrato and pad height are adjustable.
- Theremin **CAM** mode plays pitch from how close your hand is to the camera. *Android and macOS.*
- Stylophone and Theremin have a MIDI OUT socket, and a MUTE button that silences their own sound so they can play another instrument.
- **Live Input** brings a microphone or line input into the rack, so you can send it through effects or into a looper. *Not in the web demo.*
- On a phone, Live Input mutes itself when the phone's speaker would feed back into its mic. **Unmute anyway** overrides it. *Android only.*
- **VST3 instruments**: load any installed VST3 instrument, or browse to a .vst3 file. Its settings show as knobs. *Desktop only.*
- The plugin's own window opens from its slot. *Linux and macOS; on Windows, use the knobs.*

---

## Shape the sound

To put an effect after an instrument, cable them in Patch view: [Add an effect](../guide/#effect). One effect module processes one instrument; add a second module for a second instrument.

### Audio effects

*Not in the web demo.*

- **Amp**: a drive pedal (Overdrive or Distortion), three amp models (US, Brit, AC) and three speaker cabinets. Each section switches on and off. [How](../guide/#amp)
- Amp can load a cabinet impulse response (IR) from a .wav file instead of its own cabinets. The IR is saved with the project.
- **Plate Reverb**: stereo reverb.
- **Ping-Pong Delay**: stereo echo that can follow the tempo.
- **Wah**: Auto mode sweeps by itself, in time with the tempo; Manual mode follows a pedal or a knob on your controller.
- **4-Band EQ**: bass, two middle bands and treble.
- **Compressor**: evens out loud and quiet playing.
- **Chorus / Flanger**: stereo chorus that can follow the tempo.
- **Audio Harmonizer**: adds up to 4 harmony voices to any sound. With **Scale Lock** on, the voices follow the scale from Xen or Jam Mode.
- **Autotune**: pulls a voice onto the notes of a key and scale, from a light touch to a robot voice. It shows the note you sing and how many cents off it is.
- **VST3 effects** go after any instrument or effect. *Desktop only.*

### MIDI FX: change the notes

MIDI FX change the notes before an instrument plays them. More on the [MIDI FX page](../midi-fx/).

- **Harmonizer**: adds up to 4 notes above each note you play. Plug a keyboard's CHORD OUT into it and the chord you hold sets the intervals.
- **Chord Expand**: turns each note into a full chord (11 chord types, close, open or wide).
- **Arpeggiator**: plays held notes one after another, in 6 patterns and 12 speeds, over 1 to 3 octaves.
- **Transposer**: moves every note up or down, up to 24 semitones.
- **Velocity Curve**: changes how hard or soft your playing sounds.
- **Gate**: lets through only the notes inside a velocity or pitch range.
- **Microtone**: plays the notes you hold together as one note between them, using pitch bend.
- Every MIDI FX has an on/off button that can be mapped to a controller.
- **Load .gfpd from file…** adds a module written as a plugin descriptor. See [Plugin descriptors](../gfpd/).

### Patch view

- The cable icon at the top shows the back of every module. Long-press a socket and drag to another to connect them. [How sound moves](../guide/)
- Socket colours: yellow for notes (MIDI), red and white for sound, orange for effect loops, purple for chord and scale, teal for tuning. [Socket colours](../guide/#sockets)
- Tap the ✕ on a cable to remove it. [How](../guide/#remove)

---

## Rhythm and loops

- The transport bar sets the tempo (20 to 300 BPM, typed, nudged with − and +, or tapped with **Tap**), the time signature, play and stop, and the metronome.
- Drums, loopers, tempo-synced effects and VST3 plugins all follow that one tempo.

### Drum Generator

- Plays a drum pattern in time with the transport. [How](../guide/#drums)
- 35 bundled patterns: rock, funk, disco, jazz, Latin, Brazilian, Celtic, marches, techno, dub, R&B, metal, and Arabic, Turkish, Persian, Indian, Japanese and Chinese rhythms.
- **Swing** and **Human feel** change the groove, from a strict grid to a live drummer.
- **Count-in**, **Fill every** (a fill every few bars), crash after a fill, and a dynamic build.
- **Load .gfdrum…** plays your own patterns. See [Rhythmic patterns](../gfdrum/).

### MIDI Looper

- Records the notes you play, loops them back to an instrument, and records new layers on top. One per project.
- Each track has mute, reverse, half or double speed, volume and its own quantize setting (off to 1/32).
- Shows the chord of each bar.
- **Pin below transport** keeps its controls under the transport bar.

### Audio Looper

*Not in the web demo.*

- Records the sound of any module cabled into it, effects included, and loops it. [How](../guide/#loop)
- With bar sync on, recording starts on the next bar and the loop is rounded to whole bars.
- Overdub, reverse, and a **Source** menu to pick what it records without opening Patch view.
- Change the tempo and loops follow it without changing pitch.
- Loops are saved as WAV files next to the project. The slot warns you when loops use more than 256 MB of memory.

---

## Play together: Rehearsals

The **Rehearse** tab. Each player records their own part of a tune on their own device. Full walkthrough on the [Rehearsals page](../rehearsals/).

- **Start a tune** with a tempo, time signature and count-in, or **Join a tune** from another device. [How](../guide/#rehearsal)
- Each player adds a part for their instrument and records it over a shared click. You can record again or delete your own parts, never someone else's.
- Takes land on the beat: **Calibrate** measures how late your device plays and records, and each take is shifted back by that delay. The speaker, a wired headset and each Bluetooth headset are measured separately.
- **Record from the rack**: a part can record a rack instrument directly instead of the microphone.
- Import a recording to play along to (MP3, FLAC, WAV; on Android also M4A, AAC and the sound of a video). Tap the tempo and drag a marker onto the first downbeat to line up the grid.
- **Practice speed** slows the tune down to 50% without lowering the pitch. It changes only your device.
- **Chords**: write the chord grid bar by bar, up to four chords a bar. The bar being played lights up.
- **Scores**: add a PDF, a chart or a photo of a page, and every player gets a copy.
- Parts travel between devices over the local Wi-Fi, encrypted, with no server, no account and no internet. Join once with a QR code or a link; after that the devices find each other.
- A dot on each part shows whether its player is connected. A warning tells you when a take has not reached everyone yet.
- **Remove the speaker bleed** takes the click out of a take recorded with the phone's speaker on. The original is kept. *Android only.*
- Scanning a QR code needs a phone camera. On a computer, paste the link instead.

---

## Controllers

- Connect a USB MIDI keyboard or pad controller (an OTG adapter on a phone), or a Bluetooth one on Android, from **Preferences** > **Connect MIDI Device**. [How](../guide/#controller)
- Your controller plays the module whose MIDI CH badge matches its channel (1 to 16).
- Pitch bend, mod wheel, CCs and aftertouch reach the instruments, through cables and MIDI FX.
- Map a knob, fader or pad to any control of a module: the sliders icon on the module, then **Learn**. [How](../guide/#learn)
- **CC Mapping Preferences** maps a CC to: standard MIDI controls (volume, pan, expression, sustain, reverb send...), pitch bend, any module control, the loopers, play/stop, tap tempo, the metronome, or the system volume.
- One knob can drive several targets at once.
- System actions: next or previous soundfont and patch, a patch sweep, start or stop Jam Mode, cycle the scale type, and mute or unmute a set of channels with one button.
- A pad can call up one exact soundfont patch (**Select Patch**) or one Xen scale. Several pads, several patches or scales.
- **Channel Swap**: one button swaps two instruments' MIDI channels, with their cables and effects if you want.
- **Neutral value on release**, for ribbons and touch strips that drop to 0 when you lift your finger.
- System volume control works on Android, Linux and macOS.
- Mappings are saved in the project.

---

## Projects and settings

- A project (.gf file) keeps your modules, cables, settings, tempo, mappings, MIDI loops and custom scales. [How](../guide/#projects)
- The folder icon has **New Project**, **Open Project** and **Save As…**.
- The app keeps your current session between launches. *Not in the web demo: use* **Save As…** *to download a .gf file.*
- Audio loops are saved as WAV files beside the project; the Amp's IR is saved inside it.
- **Preferences**: default keyboard settings, soundfonts, MIDI devices, mic and output choice, language (English or French).
- The audio bar under the transport sets keyboard gain, mic sensitivity and mic. On Android it also picks the output device.
- The question-mark icon opens the in-app guide, including what changed in the latest version.

---

## Platforms

- **Android**: everything except VST3. On [Google Play](https://play.google.com/store/apps/details?id=com.grooveforge.grooveforge), [F-Droid](https://f-droid.org/packages/com.grooveforge.grooveforge/) and the GitHub releases page.
- **Linux**: everything, including VST3. Packages: .deb, .rpm, Arch, Flatpak and .zip. Audio goes through PipeWire or JACK, so you can route it to and from other audio apps.
- **macOS**: everything, including VST3 and their own windows.
- **Windows**: everything, including VST3, but VST3 plugin windows do not open yet: use GrooveForge's knobs.
- **Web demo**: try it in a browser, no install. Vocoder, Riff, Audio Looper, Live Input and the audio effects are greyed out with an **Apps only** badge, and VST3 is not offered. Your session is not kept.
- **iOS**: not supported. The build has never been tested.

### Android only

- **Direct USB output** (Preferences > Audio Output) plays through a USB audio interface that Android would drop when a USB microphone is plugged in too.
- When the output falls back to a slow path, a warning shows with a **Restore low latency** button.
- Sound can go to a chosen USB audio device; if it is unplugged, sound returns to the default output.

---

*Last updated: 2026-11-25*
