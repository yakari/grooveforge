/**
 * grooveforge_audio.js — GrooveForge Web Audio Bridge
 *
 * Exposes two global objects consumed by the Flutter/Dart app:
 *
 *   window.grooveForgeAudio      — GM instrument playback via soundfont-player
 *   window.grooveForgeOscillator — Raw Web Audio oscillators for
 *                                  Stylophone and Theremin
 *
 * ## Why soundfont-player instead of spessasynth_lib
 *
 * spessasynth_lib v4 uses WebAssembly + SharedArrayBuffer (for threading)
 * in both its WorkletSynthesizer and WorkerSynthesizer backends. SharedArrayBuffer
 * requires the response headers:
 *   Cross-Origin-Opener-Policy: same-origin
 *   Cross-Origin-Embedder-Policy: require-corp
 * These headers are not set by GitHub Pages or by the Flutter dev server, so
 * the synth hangs at initialisation in those environments.
 *
 * soundfont-player (Gleitz) uses plain Web Audio API + pre-rendered MP3 samples
 * hosted on GitHub Pages. No WASM, no SharedArrayBuffer, no Workers — works
 * everywhere. The trade-off is that instrument samples are General MIDI only
 * (not the app's custom SF2 files); this is acceptable for the web strip-down.
 *
 * ## Audio flow
 *   Soundfont.instrument() → AudioBufferSourceNode → _masterGain → AudioContext.destination
 *
 * This whole file is loaded as <script type="module"> in web/index.html so
 * the ES import statement is legal.
 */

import Soundfont from 'https://esm.sh/soundfont-player';

// ─────────────────────────────────────────────────────────────────────────────
// Shared AudioContext
// ─────────────────────────────────────────────────────────────────────────────

/** Single AudioContext shared by the SF2 synth and the oscillators. */
const _ctx = new AudioContext();

/**
 * Resumes the AudioContext after a user gesture.
 * Browsers suspend the context until the user has interacted with the page.
 */
async function _resumeCtx() {
  if (_ctx.state === 'suspended') await _ctx.resume();
}

// ─────────────────────────────────────────────────────────────────────────────
// Master gain node — routed between soundfont-player and the destination.
// soundfont-player accepts an AudioNode as `destination` option; we pass
// _masterGain so that setGain() can adjust master volume without per-note
// re-wiring.
// ─────────────────────────────────────────────────────────────────────────────

/** GainNode that all soundfont-player notes route through. */
const _masterGain = _ctx.createGain();
_masterGain.gain.value = 0.7;  // Slightly below full to match native default feel.
_masterGain.connect(_ctx.destination);

// ─────────────────────────────────────────────────────────────────────────────
// General MIDI program-number → instrument-name map (128 entries)
// Used to translate the Dart-side bank/program into soundfont-player names.
// ─────────────────────────────────────────────────────────────────────────────
const _GM_PROGRAMS = [
  'acoustic_grand_piano','bright_acoustic_piano','electric_grand_piano',
  'honkytonk_piano','electric_piano_1','electric_piano_2','harpsichord',
  'clavinet','celesta','glockenspiel','music_box','vibraphone','marimba',
  'xylophone','tubular_bells','dulcimer','drawbar_organ','percussive_organ',
  'rock_organ','church_organ','reed_organ','accordion','harmonica',
  'tango_accordion','acoustic_guitar_nylon','acoustic_guitar_steel',
  'electric_guitar_jazz','electric_guitar_clean','electric_guitar_muted',
  'overdriven_guitar','distortion_guitar','guitar_harmonics','acoustic_bass',
  'electric_bass_finger','electric_bass_pick','fretless_bass','slap_bass_1',
  'slap_bass_2','synth_bass_1','synth_bass_2','violin','viola','cello',
  'contrabass','tremolo_strings','pizzicato_strings','orchestral_harp',
  'timpani','string_ensemble_1','string_ensemble_2','synth_strings_1',
  'synth_strings_2','choir_aahs','voice_oohs','synth_voice','orchestra_hit',
  'trumpet','trombone','tuba','muted_trumpet','french_horn','brass_section',
  'synth_brass_1','synth_brass_2','soprano_sax','alto_sax','tenor_sax',
  'baritone_sax','oboe','english_horn','bassoon','clarinet','piccolo',
  'flute','recorder','pan_flute','blown_bottle','shakuhachi','whistle',
  'ocarina','lead_1_square','lead_2_sawtooth','lead_3_calliope','lead_4_chiff',
  'lead_5_charang','lead_6_voice','lead_7_fifths','lead_8_bass_lead',
  'pad_1_new_age','pad_2_warm','pad_3_polysynth','pad_4_choir','pad_5_bowed',
  'pad_6_metallic','pad_7_halo','pad_8_sweep','fx_1_rain','fx_2_soundtrack',
  'fx_3_crystal','fx_4_atmosphere','fx_5_brightness','fx_6_goblins',
  'fx_7_echoes','fx_8_sci-fi','sitar','banjo','shamisen','koto','kalimba',
  'bag_pipe','fiddle','shanai','tinkle_bell','agogo','steel_drums',
  'woodblock','taiko_drum','melodic_tom','synth_drum','reverse_cymbal',
  'guitar_fret_noise','breath_noise','seashore','bird_tweet','telephone_ring',
  'helicopter','applause','gunshot',
];

/**
 * Resolves a MIDI program number to a soundfont instrument name.
 * Falls back to acoustic_grand_piano for out-of-range values (e.g. drums).
 *
 * @param {number} program - MIDI program number 0-127
 * @returns {string} soundfont-player instrument name
 */
function _programName(program) {
  return _GM_PROGRAMS[program % 128] ?? 'acoustic_grand_piano';
}

// ─────────────────────────────────────────────────────────────────────────────
// Instrument player cache  (name → Promise<SoundfontPlayer>)
// Instruments are loaded lazily and shared across all sfIds that use them.
// ─────────────────────────────────────────────────────────────────────────────

/** @type {Object.<string, Promise<any>>} */
const _playerCache = {};

/**
 * Returns a soundfont-player instrument routed through _masterGain,
 * loading it from CDN on first use. Results are cached so the same
 * instrument is only fetched once.
 *
 * @param {number} program - MIDI program number
 * @returns {Promise<any>} soundfont-player instrument instance
 */
function _loadPlayer(program) {
  const name = _programName(program);
  if (!_playerCache[name]) {
    _playerCache[name] = Soundfont.instrument(_ctx, name, {
      soundfont: 'MusyngKite',
      format: 'mp3',
      destination: _masterGain,
      // Host: Gleitz's GitHub Pages mirror of the MIDI.js soundfonts.
      nameToUrl: (n, sf, fmt) =>
        `https://gleitz.github.io/midi-js-soundfonts/${sf}/${n}-${fmt}.js`,
    });
  }
  return _playerCache[name];
}

// ─────────────────────────────────────────────────────────────────────────────
// SF2 Synthesizer  (window.grooveForgeAudio)
// ─────────────────────────────────────────────────────────────────────────────

/** Auto-incrementing ID counter for loaded soundfonts. Starts at 1. */
let _sfIdCounter = 1;

/**
 * Per-sfId state: which instrument player is active, and which notes are
 * currently sounding (so they can be stopped individually).
 *
 * @type {Object.<number, {player: any|null, notes: Object.<string, any>, program: number}>}
 */
const _synths = {};

/**
 * SF2 synthesis bridge.
 *
 * API mirrors flutter_midi_pro's FlutterMidiProPlatform so the Dart web
 * platform implementation can delegate directly to these functions.
 *
 * Note: on web the "soundfont URL" passed by Dart is ignored; instruments
 * are loaded as pre-rendered GM samples from Gleitz's MIDI.js CDN instead.
 */
window.grooveForgeAudio = {
  /**
   * "Loads" a soundfont — on web this pre-fetches the instrument samples for
   * the requested program from CDN and returns a numeric sfId.
   *
   * @param {string} _url    - Dart-side asset path (ignored on web)
   * @param {number} _bank   - MIDI bank (ignored on web; GM only)
   * @param {number} program - MIDI program number 0-127
   * @returns {Promise<number>} sfId
   */
  loadSoundfont: async (_url, _bank, program) => {
    // Do NOT call _resumeCtx() here: AudioContext.resume() is only allowed
    // inside a user gesture handler. Calling it during app startup (before
    // any gesture) would cause the Promise to reject or hang in Chrome,
    // blocking this CDN fetch forever. Context resume happens in playNote
    // which IS called from within a gesture handler chain.
    console.log(`grooveForgeAudio: loadSoundfont program=${program}`);
    const player = await _loadPlayer(program);
    const id = _sfIdCounter++;
    _synths[id] = { player, notes: {}, program };
    console.log(`grooveForgeAudio: soundfont ready (sfId=${id}, instrument=${_programName(program)})`);
    return id;
  },

  /**
   * Sends MIDI Note On to the instrument for the given sfId.
   *
   * Resumes the AudioContext here (fire-and-forget) because this call
   * originates from a Flutter gesture handler, which satisfies the browser's
   * user-gesture requirement for AudioContext.resume().
   */
  playNote: (channel, key, velocity, sfId) => {
    // Resume audio context on first user interaction (autoplay policy).
    _ctx.resume().catch(() => {});
    const s = _synths[sfId];
    if (!s?.player) return;
    const gain = Math.max(0.01, velocity / 127);
    const node = s.player.play(key.toString(), _ctx.currentTime, { gain });
    s.notes[`${channel}_${key}`] = node;
  },

  /** Sends MIDI Note Off (short release to avoid clicks). */
  stopNote: (channel, key, sfId) => {
    const s = _synths[sfId];
    if (!s) return;
    const k = `${channel}_${key}`;
    try { s.notes[k]?.stop(_ctx.currentTime + 0.05); } catch (_) {}
    delete s.notes[k];
  },

  /** Silences all sounding notes for the given sfId. */
  stopAllNotes: (sfId) => {
    const s = _synths[sfId];
    if (!s) return;
    for (const node of Object.values(s.notes)) {
      try { node?.stop(_ctx.currentTime + 0.05); } catch (_) {}
    }
    s.notes = {};
  },

  /**
   * Changes the GM instrument for the given sfId / channel.
   *
   * The new player is loaded in the background. Notes fired before the load
   * completes will use the previous player; subsequent notes use the new one.
   *
   * @param {number} sfId    - Soundfont ID returned by loadSoundfont
   * @param {number} _channel - MIDI channel (0-15); unused on web (GM is global)
   * @param {number} _bank   - MIDI bank (ignored; GM only)
   * @param {number} program - MIDI program number 0-127
   */
  selectInstrument: async (sfId, _channel, _bank, program) => {
    const s = _synths[sfId];
    if (!s) return;
    // Stop active notes before switching to avoid orphaned AudioNodes.
    window.grooveForgeAudio.stopAllNotes(sfId);
    s.player = null;  // marks as loading
    s.player = await _loadPlayer(program);
    s.program = program;
  },

  /** Forwards a MIDI Control Change message — no-op for the GM player. */
  controlChange: () => {},

  /** Applies MIDI pitch bend — no-op for the GM player. */
  pitchBend: () => {},

  /**
   * Sets master volume by adjusting the _masterGain node.
   *
   * @param {number} gain - Dart-side gain in [0, 10]; mapped to [0, 1].
   */
  setGain: (gain) => {
    const vol = Math.min(1.0, gain / 10.0);
    _masterGain.gain.setTargetAtTime(vol, _ctx.currentTime, 0.05);
  },

  /** Stops and removes the soundfont entry for the given sfId. */
  unloadSoundfont: (sfId) => {
    const s = _synths[sfId];
    if (s) {
      window.grooveForgeAudio.stopAllNotes(sfId);
      delete _synths[sfId];
    }
  },
};

// ─────────────────────────────────────────────────────────────────────────────
// Web Audio Oscillators  (window.grooveForgeOscillator)
// Stylophone and Theremin use the same AudioContext as the SF2 synth.
// ─────────────────────────────────────────────────────────────────────────────

/** Maps waveform index (0-3) to the corresponding OscillatorNode type. */
const _waveformTypes = ['square', 'sawtooth', 'sine', 'triangle'];

// ── Stylophone state ─────────────────────────────────────────────────────────
let _styloGain        = null;  // GainNode  (master volume + envelope)
let _styloOsc         = null;  // OscillatorNode (current note)
let _styloVibratoOsc  = null;  // OscillatorNode (6.5 Hz LFO source)
let _styloVibratoGain = null;  // GainNode  (LFO depth → frequency modulation)
let _styloWaveform    = 'square';

// ── Theremin state ───────────────────────────────────────────────────────────
let _thereminGain        = null;
let _thereminOsc         = null;
let _thereminVibratoOsc  = null;
let _thereminVibratoGain = null;

window.grooveForgeOscillator = {
  // ── Stylophone ─────────────────────────────────────────────────────────────

  /** Initialises the stylophone Web Audio graph. Idempotent. */
  styloStart: () => {
    if (_styloGain) return;  // already running
    _resumeCtx();
    // Master gain node — envelope is applied to its gain AudioParam.
    _styloGain = _ctx.createGain();
    _styloGain.gain.value = 0;
    _styloGain.connect(_ctx.destination);
    // 6.5 Hz vibrato LFO — same frequency as the native C implementation.
    _styloVibratoOsc = _ctx.createOscillator();
    _styloVibratoOsc.frequency.value = 6.5;
    _styloVibratoGain = _ctx.createGain();
    _styloVibratoGain.gain.value = 0;  // silent until depth is set
    _styloVibratoOsc.connect(_styloVibratoGain);
    _styloVibratoOsc.start();
  },

  /** Tears down the stylophone audio graph and resets all state. */
  styloStop: () => {
    try { _styloOsc?.stop(); }        catch (_) {}
    try { _styloVibratoOsc?.stop(); } catch (_) {}
    _styloGain?.disconnect();
    _styloGain = _styloOsc = _styloVibratoOsc = _styloVibratoGain = null;
  },

  /**
   * Starts a note at the given frequency.
   *
   * A new OscillatorNode is created each time to support seamless slides
   * (Web Audio does not allow changing type mid-note without a click).
   * A 10 ms attack ramp prevents the transient click on note onset.
   *
   * @param {number} hz - Target frequency in Hz
   */
  styloNoteOn: (hz) => {
    if (!_styloGain) return;
    // Tear down any previous oscillator cleanly.
    if (_styloOsc) {
      try { _styloOsc.disconnect(); _styloOsc.stop(); } catch (_) {}
    }
    _styloOsc = _ctx.createOscillator();
    _styloOsc.type = _styloWaveform;
    _styloOsc.frequency.value = hz;
    // Route vibrato LFO into the oscillator's frequency AudioParam.
    _styloVibratoGain.connect(_styloOsc.frequency);
    _styloOsc.connect(_styloGain);
    _styloOsc.start();
    // Short attack ramp to remove onset click.
    const now = _ctx.currentTime;
    _styloGain.gain.cancelScheduledValues(now);
    _styloGain.gain.setValueAtTime(0, now);
    _styloGain.gain.linearRampToValueAtTime(0.6, now + 0.01);
  },

  /**
   * Releases the current note with a ~150 ms exponential decay,
   * matching the release envelope of the native C stylophone engine.
   */
  styloNoteOff: () => {
    if (!_styloGain) return;
    const now = _ctx.currentTime;
    _styloGain.gain.cancelScheduledValues(now);
    _styloGain.gain.setValueAtTime(_styloGain.gain.value, now);
    _styloGain.gain.exponentialRampToValueAtTime(0.0001, now + 0.15);
    // Stop the oscillator node after the decay to free resources.
    const osc = _styloOsc;
    if (osc) {
      setTimeout(() => {
        try { osc.stop(); } catch (_) {}
        if (_styloOsc === osc) _styloOsc = null;
      }, 200);
    }
  },

  /**
   * Changes the oscillator waveform.
   *
   * @param {number} waveform - 0 = square, 1 = sawtooth, 2 = sine, 3 = triangle
   */
  styloSetWaveform: (waveform) => {
    _styloWaveform = _waveformTypes[waveform] ?? 'square';
    if (_styloOsc) _styloOsc.type = _styloWaveform;
  },

  /**
   * Sets the vibrato LFO depth.
   *
   * @param {number} depth - Normalised [0, 1]; 1 modulates frequency by ±15 Hz.
   */
  styloSetVibrato: (depth) => {
    if (_styloVibratoGain) _styloVibratoGain.gain.value = depth * 15;
  },

  // ── Theremin ───────────────────────────────────────────────────────────────

  /** Initialises the theremin Web Audio graph. Idempotent. */
  thereminStart: () => {
    if (_thereminGain) return;  // already running
    _resumeCtx();
    _thereminGain = _ctx.createGain();
    _thereminGain.gain.value = 0;
    _thereminGain.connect(_ctx.destination);
    // Sine oscillator — matches the native theremin timbre.
    _thereminOsc = _ctx.createOscillator();
    _thereminOsc.type = 'sine';
    _thereminOsc.frequency.value = 440;
    // 6.5 Hz vibrato LFO — same as native.
    _thereminVibratoOsc = _ctx.createOscillator();
    _thereminVibratoOsc.frequency.value = 6.5;
    _thereminVibratoGain = _ctx.createGain();
    _thereminVibratoGain.gain.value = 0;
    _thereminVibratoOsc.connect(_thereminVibratoGain);
    _thereminVibratoGain.connect(_thereminOsc.frequency);
    _thereminVibratoOsc.start();
    _thereminOsc.connect(_thereminGain);
    _thereminOsc.start();
  },

  /** Tears down the theremin audio graph and resets all state. */
  thereminStop: () => {
    try { _thereminOsc?.stop(); }        catch (_) {}
    try { _thereminVibratoOsc?.stop(); } catch (_) {}
    _thereminGain?.disconnect();
    _thereminGain = _thereminOsc = _thereminVibratoOsc = _thereminVibratoGain = null;
  },

  /**
   * Smoothly glides to a new pitch frequency (15 ms time constant ≈ 42 ms native).
   *
   * @param {number} hz - Target frequency in Hz
   */
  thereminSetPitchHz: (hz) => {
    if (!_thereminOsc) return;
    _thereminOsc.frequency.setTargetAtTime(hz, _ctx.currentTime, 0.015);
  },

  /**
   * Sets the theremin amplitude (3 ms time constant, 0.85 peak).
   *
   * @param {number} volume - Normalised [0, 1]
   */
  thereminSetVolume: (volume) => {
    if (!_thereminGain) return;
    _thereminGain.gain.setTargetAtTime(volume * 0.85, _ctx.currentTime, 0.003);
  },

  /**
   * Sets the vibrato LFO depth.
   *
   * @param {number} depth - Normalised [0, 1]; 1 modulates frequency by ±15 Hz.
   */
  thereminSetVibrato: (depth) => {
    if (_thereminVibratoGain) _thereminVibratoGain.gain.value = depth * 15;
  },
};
