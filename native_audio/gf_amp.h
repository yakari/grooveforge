// gf_amp.h — Guitar amp simulator: drive pedal, preamp, tone stack, cabinet.
//
// What a guitar sounds like through an amp is mostly three things, and this
// module chains them in the order they sit on a pedalboard and in an amp:
//
//   1. **Drive pedal.** Overdrive is a Tube Screamer-style circuit: only the
//      frequencies above ~720 Hz are amplified into the soft clipper, and the
//      clean low end is added back. That is what gives it its "mid hump" and
//      why the bass stays tight under heavy drive. Distortion amplifies the
//      whole band into a hard clipper, for a rougher, fuller sound. Both are
//      followed by a Tone low-pass. (Modelled after Yeh, Abel and Smith,
//      "Simplified, Physically-Informed Models of Distortion and Overdrive
//      Guitar Effects Pedals", DAFx-07.)
//
//   2. **Preamp.** The tube stages that colour the sound even when it is
//      "clean" and break up when pushed. Modelled as an asymmetric soft
//      clipper: a tube does not clip both halves of the wave the same way, and
//      that asymmetry adds the even harmonics that make tube drive sound warm.
//
//   3. **Tone stack.** The Bass / Middle / Treble knobs of a real amp are not
//      independent EQ bands: they are one passive circuit, and turning one
//      shifts the others. This is the exact transfer function of that circuit
//      (Yeh and Smith, "Discretization of the '59 Fender Bassman Tone Stack",
//      DAFx-06), reimplemented from the paper's equations, with component
//      values for three amps.
//
//   4. **Cabinet.** A guitar speaker cuts everything above ~5 kHz and has
//      strong resonances; without it, distortion sounds like a fizzy buzz.
//      The built-in cabinets are sets of filters shaped like 1x12, 2x12 and
//      4x12 cabinets. The "IR" cabinet convolves with a measured impulse
//      response the user loads instead (gf_amp_ir_create, gf_convolver.h),
//      which is how commercial amp simulators get a real cabinet's sound.
//
// Aliasing. Clipping creates harmonics far above what the sample rate can
// hold; left alone they fold back down as inharmonic, metallic noise. Two
// remedies are combined: the nonlinear stages run at twice the sample rate
// (polyphase half-band IIR resampling, after Laurent de Soras's HIIR), and the
// clippers use first-order antiderivative antialiasing (ADAA: Parker,
// Zavalishin and Le Bivic, DAFx-16), which removes most of the folding at the
// source for a fraction of the cost of heavier oversampling.
//
// Each of the three sections (Drive, Amp = preamp + tone stack, Cab) can be
// switched off; switching crossfades over ~10 ms so it never clicks.
//
// The module is mono: a guitar is a mono source, and processing one channel
// halves the cost.
//
// Real-time safety: after gf_amp_create nothing on the hot path allocates,
// locks or logs.

#ifndef GF_AMP_H
#define GF_AMP_H

#ifdef __cplusplus
extern "C" {
#endif

/// Drive pedal circuits, in the order the descriptor's `drive_mode` lists them.
typedef enum {
    GF_AMP_DRIVE_OVERDRIVE = 0,
    GF_AMP_DRIVE_DISTORTION,
    GF_AMP_DRIVE_COUNT
} gf_amp_drive_mode;

/// Tone stack circuits, in the order the descriptor's `amp_model` lists them.
typedef enum {
    GF_AMP_MODEL_FENDER = 0,   ///< '59 Bassman (5F6-A).
    GF_AMP_MODEL_MARSHALL,     ///< JCM800.
    GF_AMP_MODEL_VOX,          ///< AC30-style values on the same topology.
    GF_AMP_MODEL_COUNT
} gf_amp_model;

/// Cabinet shapes, in the order the descriptor's `cab_type` lists them.
typedef enum {
    GF_AMP_CAB_1X12 = 0,       ///< Open-back combo: lighter low end.
    GF_AMP_CAB_2X12,
    GF_AMP_CAB_4X12,           ///< Closed-back stack: deep low resonance.
    GF_AMP_CAB_IR,             ///< The loaded impulse response (2x12 if none).
    GF_AMP_CAB_COUNT
} gf_amp_cab;

/// Everything the caller controls, set together once per block.
///
/// Knob values are 0..1 unless noted; out-of-range values are clamped and
/// out-of-range enums fall back to the first entry.
typedef struct {
    int   drive_on;
    int   drive_mode;   ///< gf_amp_drive_mode.
    float drive;        ///< Amount of gain into the clipper.
    float drive_tone;   ///< Dark (0) to bright (1).

    int   amp_on;       ///< Preamp and tone stack together.
    int   amp_model;    ///< gf_amp_model.
    float gain;         ///< Preamp gain: clean (0) to crunch (1).
    float bass;
    float middle;
    float treble;

    int   cab_on;
    int   cab_type;     ///< gf_amp_cab.

    float level_db;     ///< Output level in dB.
} gf_amp_params;

/// Opaque handle. All state is owned by this struct.
typedef struct gf_amp gf_amp;

/// A cabinet impulse response, prepared for use by an amp. Opaque.
typedef struct gf_amp_ir gf_amp_ir;

/// Fills [out] with the defaults the descriptor declares.
void gf_amp_default_params(gf_amp_params* out);

/// Creates an amp for [sample_rate] Hz audio. Returns NULL on bad input or
/// out-of-memory.
gf_amp* gf_amp_create(float sample_rate);

/// Destroys an amp, and the IRs it owns. Safe to pass NULL.
void gf_amp_destroy(gf_amp* a);

/// Re-targets the amp at a new [sample_rate] after the audio device changed
/// rate. Allocation-free; safe from the audio thread. Clears the filter
/// state. Out-of-range rates are ignored.
void gf_amp_set_sample_rate(gf_amp* a, float sample_rate);

/// Clears all filter state. Allocation-free; safe from the audio thread.
void gf_amp_reset(gf_amp* a);

/// Applies [params]. Cheap; call once per block from the audio thread.
/// Gains and knob changes are smoothed, so calling it with a new value
/// never produces a step in the output.
void gf_amp_set_params(gf_amp* a, const gf_amp_params* params);

/// Processes [n] mono frames. [in] and [out] may be the same buffer. Any
/// block size is accepted.
void gf_amp_process(gf_amp* a, const float* in, float* out, int n);

// ── Cabinet impulse responses ───────────────────────────────────────────────
//
// Handing an IR to the amp is split in two so that nothing heavy happens on
// the audio thread: gf_amp_ir_create does all the work (trimming, resampling,
// FFTs) on the caller's thread, and gf_amp_set_ir only swaps a pointer.
//
// The IR is prepared at once for 44.1, 48, 88.2 and 96 kHz, plus
// [also_rate] when it is none of those, so that an audio device changing rate
// later finds a ready-made version instead of needing a new one built on the
// audio thread. A stream at any other rate uses the nearest prepared one,
// which shifts the cabinet's response by the ratio of the two rates.

/// Prepares the [n]-sample mono impulse response [samples], recorded at
/// [rate] Hz, for an amp. Pass the audio stream's current rate as
/// [also_rate], or 0 if unknown.
///
/// The IR is cleaned up first: silence before the attack and after the decay
/// is dropped (silence before the attack would delay the sound), it is cut
/// to GF_AMP_IR_MAX_SEC with a short fade, and its level is matched to the
/// built-in 2x12 cabinet's, so that switching between them does not jump in
/// volume. IR files vary in level by 20 dB or more.
///
/// Allocates: never call it from the audio thread. Returns NULL on bad input
/// (no samples, a silent IR, a rate out of range) or out-of-memory.
gf_amp_ir* gf_amp_ir_create(const float* samples, int n, double rate,
                            double also_rate);

/// Frees an IR. Safe to pass NULL. Never call it on an IR an amp still owns.
void gf_amp_ir_destroy(gf_amp_ir* ir);

/// Taps of the IR as prepared for [rate] Hz (the nearest prepared rate).
/// For tests.
int gf_amp_ir_length(const gf_amp_ir* ir, double rate);

/// The longest IR kept, in seconds. Cabinet IRs are often sold 200-500 ms
/// long, but past the first few tens of milliseconds they hold only the
/// room's reverberation, which costs convolution time and muddies a guitar.
#define GF_AMP_IR_MAX_SEC 0.1

/// Hands [ir] to the amp, which takes ownership. Allocation-free; call it
/// from the audio thread, between two gf_amp_process calls.
///
/// When an IR is already playing, the amp crossfades from the old one to the
/// new one over ~10 ms, then releases the old one through
/// gf_amp_take_retired_ir. Returns 0 if the amp is still busy with a previous
/// swap (gf_amp_ir_busy): it does not take [ir] then, and the caller keeps it
/// and tries again on a later block.
int gf_amp_set_ir(gf_amp* a, gf_amp_ir* ir);

/// Non-zero while a previous IR is still fading out or waiting to be taken
/// back with gf_amp_take_retired_ir.
int gf_amp_ir_busy(const gf_amp* a);

/// Returns an IR the amp no longer uses, handing its ownership back so it can
/// be freed off the audio thread, or NULL when there is none. Allocation-free.
gf_amp_ir* gf_amp_take_retired_ir(gf_amp* a);

/// Non-zero once an IR has been handed over: "IR" in the cabinet selector
/// then uses it instead of the 2x12.
int gf_amp_has_ir(const gf_amp* a);

/// Removes the IR: "IR" in the cabinet selector goes back to the 2x12.
/// Allocation-free; call it from the audio thread, between two
/// gf_amp_process calls.
///
/// An IR being heard first fades out over ~10 ms, then is released through
/// gf_amp_take_retired_ir; gf_amp_has_ir stays non-zero until then. A
/// gf_amp_set_ir before the fade ends cancels the removal.
void gf_amp_clear_ir(gf_amp* a);

// ── Inspection (smoke test and future panel graphics) ───────────────────────

/// Magnitude in dB of the tone stack as an analog circuit, at [freq_hz],
/// computed from the closed-form transfer function. Knobs are 0..1.
double gf_amp_tonestack_analog_db(int model, double bass, double middle,
                                  double treble, double freq_hz);

/// Magnitude in dB of the digital tone stack filter actually run at
/// [sample_rate], at [freq_hz]. Same knob convention.
double gf_amp_tonestack_digital_db(int model, double bass, double middle,
                                   double treble, double sample_rate,
                                   double freq_hz);

/// Component values of a tone stack, in ohms and farads:
/// out[0..6] = C1, C2, C3, R1 (treble pot), R2 (bass pot), R3 (mid pot),
/// R4 (slope resistor). Returns 0 on success, -1 for an unknown model.
int gf_amp_tonestack_parts(int model, double out[7]);

/// The pot positions the circuit sees for knob settings: the bass pot has an
/// audio (logarithmic) taper, treble and middle are linear. Writes the
/// fractions of each pot's resistance in circuit.
void gf_amp_tonestack_tapers(double bass, double middle, double treble,
                             double* l, double* m, double* t);

/// Test hook. Passes [n] frames through the 2x upsampler and downsampler
/// alone, with nothing in between, so the resampler's own response can be
/// measured. Allocates; never call it from the audio thread. Returns 0 on
/// success, -1 on out-of-memory.
int gf_amp_debug_resample_roundtrip(const float* in, float* out, int n);

/// Test hook. Upsamples [n] frames to 2n in [up], so a test can measure the
/// images the half-band filter must remove (at 48 kHz - f for a 48 kHz
/// input). Allocates; never call it from the audio thread. Returns 0 on
/// success, -1 on out-of-memory.
int gf_amp_debug_upsample(const float* in, float* up, int n);

/// Test hook. With [enabled] = 0 the amp skips both antialiasing measures —
/// the half-band filters become sample-and-hold upsampling and plain
/// decimation, and the clippers run without ADAA — so a test can measure what
/// they remove on otherwise identical processing.
void gf_amp_debug_set_antialias(gf_amp* a, int enabled);

#ifdef __cplusplus
}
#endif

#endif // GF_AMP_H
