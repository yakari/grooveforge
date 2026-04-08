// gfpa_dsp.cpp — Native C++ DSP implementations for GFPA effect plugins.
//
// All six built-in descriptor effects are implemented here:
//   Reverb    — Freeverb (8 comb + 4 allpass per channel)
//   Delay     — Stereo ping-pong with optional BPM sync
//   Wah       — Chamberlin SVF bandpass + LFO
//   EQ        — 4-band (low shelf, 2× peaking, high shelf) biquad chain
//   Compressor— Feed-forward RMS compressor with attack/release
//   Chorus    — Stereo chorus/flanger with LFO and cross-feedback
//
// Audio-thread guarantees:
//   - All buffers are pre-allocated in each effect's constructor.
//   - Parameters are stored in std::atomic<float> and accessed via .load()
//     inside process(), so Dart-side writes never block the audio thread.
//   - No heap allocation, no logging, no locks inside any process() method.

#include "../include/gfpa_dsp.h"

#include <atomic>
#include <cmath>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

// ── Global BPM ───────────────────────────────────────────────────────────────

/// Global BPM shared across all GFPA effect instances.
/// Written from Dart via gfpa_set_bpm(); read atomically on the audio thread.
static std::atomic<float> g_gfpa_bpm{120.0f};

extern "C" void gfpa_set_bpm(double bpm) {
    g_gfpa_bpm.store(static_cast<float>(bpm));
}

// ── Constants ────────────────────────────────────────────────────────────────

static constexpr float kPi    = 3.14159265358979f;
static constexpr float kTwoPi = 2.0f * kPi;

/// Beat-division lookup table (same values as the Dart side).
/// Index:  0=2bars, 1=1bar, 2=1/2, 3=1/4, 4=1/8, 5=1/16.
/// Value: number of quarter-note beats per one LFO/delay cycle.
static constexpr float kBeatDivs[6] = {8.0f, 4.0f, 2.0f, 1.0f, 0.5f, 0.25f};

/// Clamp an integer beat-division index to the valid range [0,5].
static inline int clampBeatDiv(float v) {
    int i = static_cast<int>(v + 0.5f);
    return i < 0 ? 0 : (i > 5 ? 5 : i);
}

// ── Wet/Dry blend helper ─────────────────────────────────────────────────────

/// Mix dry and wet signals: out = dry*(1-mix) + wet*mix.
/// [mix] is in [0,1] where 0 = all dry, 1 = all wet.
static void blendWetDry(
    const float* dryL, const float* dryR,
    const float* wetL, const float* wetR,
    float* outL, float* outR,
    float mix, int32_t n)
{
    const float w = mix, d = 1.0f - mix;
    for (int32_t i = 0; i < n; ++i) {
        outL[i] = dryL[i] * d + wetL[i] * w;
        outR[i] = dryR[i] * d + wetR[i] * w;
    }
}

// ── Freeverb ─────────────────────────────────────────────────────────────────
//
// Classic Schroeder–Freeverb topology:
//   8 parallel comb filters → 4 series all-pass filters (per channel).
// L and R channels use slightly different delay line lengths (+23 samples)
// to decorrelate the reverb tail for a stereo spread effect.

/// One comb filter in the Freeverb network.
/// Implements a feedback comb with a one-pole low-pass in the feedback loop
/// (the "damping" characteristic that makes reverb sound more natural).
struct CombFilter {
    std::vector<float> buf; ///< Circular delay-line buffer.
    int   pos{0};           ///< Current write position.
    float feedback{0.5f};   ///< Feedback gain (controls reverb tail length).
    float damp1{0.5f};      ///< Low-pass coefficient (damp1 = damping * 0.4).
    float damp2{0.5f};      ///< Complementary: 1 - damp1.
    float state{0.0f};      ///< One-pole filter memory.

    explicit CombFilter(int len) : buf(len, 0.0f) {}

    /// Process one sample through this comb filter.
    float process(float in) {
        float out    = buf[pos];
        // One-pole low-pass on the feedback signal — attenuates high frequencies
        // on each recirculation, simulating acoustic absorption.
        state        = out * damp2 + state * damp1;
        buf[pos]     = in + state * feedback;
        if (++pos >= static_cast<int>(buf.size())) pos = 0;
        return out;
    }
};

/// All-pass filter used in the Freeverb diffusion stage.
/// Spreads transient energy across time to smooth the reverb onset.
struct AllpassFilter {
    std::vector<float> buf; ///< Circular delay-line buffer.
    int pos{0};             ///< Current write position.

    explicit AllpassFilter(int len) : buf(len, 0.0f) {}

    /// Process one sample through this all-pass section.
    float process(float in) {
        float out = buf[pos] - in;
        buf[pos]  = in + buf[pos] * 0.5f; // fixed 0.5 coefficient (Freeverb default)
        if (++pos >= static_cast<int>(buf.size())) pos = 0;
        return out;
    }
};

/// Complete Freeverb stereo reverberator.
struct FreeverbEffect {
    /// 8 comb filters per channel — primary reverb tail.
    CombFilter  combL[8];
    CombFilter  combR[8];
    /// 4 all-pass sections per channel — diffusion / smoothing.
    AllpassFilter apL[4];
    AllpassFilter apR[4];

    /// Pre-allocated wet signal buffers (no heap alloc in process()).
    std::vector<float> tmpL, tmpR;

    /// Reverb parameters (atomic for thread-safe Dart→audio updates).
    std::atomic<float> roomSize{0.5f};  ///< 0=small, 1=large.
    std::atomic<float> damping{0.5f};   ///< 0=bright tail, 1=dull tail.
    std::atomic<float> width{1.0f};     ///< 0=mono, 1=full stereo.
    std::atomic<float> mix{0.33f};      ///< Wet ratio 0–1 (stored as fraction).

    explicit FreeverbEffect(int32_t blockSize)
        : combL{CombFilter(1116),CombFilter(1188),CombFilter(1277),CombFilter(1356),
                CombFilter(1422),CombFilter(1491),CombFilter(1557),CombFilter(1617)}
        , combR{CombFilter(1139),CombFilter(1211),CombFilter(1300),CombFilter(1379),
                CombFilter(1445),CombFilter(1514),CombFilter(1580),CombFilter(1640)}
        , apL{AllpassFilter(556),AllpassFilter(441),AllpassFilter(341),AllpassFilter(225)}
        , apR{AllpassFilter(579),AllpassFilter(464),AllpassFilter(364),AllpassFilter(248)}
        , tmpL(blockSize, 0.0f), tmpR(blockSize, 0.0f)
    {
        _updateCombParams(0.5f, 0.5f);
    }

    /// Apply a parameter change. [id] is the string key from the .gfpd file.
    /// [v] is the physical (denormalized) value.
    void setParam(const char* id, float v) {
        if      (strcmp(id, "room_size") == 0) { roomSize.store(v); _updateCombParams(v, damping.load()); }
        else if (strcmp(id, "damping")   == 0) { damping.store(v);  _updateCombParams(roomSize.load(), v); }
        else if (strcmp(id, "width")     == 0)   width.store(v);
        else if (strcmp(id, "mix")       == 0)   mix.store(v / 100.0f);
    }

    /// Recalculate comb filter feedback and damping coefficients.
    /// Called whenever room_size or damping changes.
    void _updateCombParams(float r, float d) {
        // Map room_size [0,1] → feedback gain [0.84, 1.12].
        // Higher feedback = longer reverb tail.
        float fb = r * 0.28f + 0.84f;
        float d1 = d * 0.4f;          // damping coefficient
        float d2 = 1.0f - d1;         // complementary (pass-through portion)
        for (int i = 0; i < 8; ++i) {
            combL[i].feedback = combR[i].feedback = fb;
            combL[i].damp1    = combR[i].damp1    = d1;
            combL[i].damp2    = combR[i].damp2    = d2;
        }
    }

    /// Process one block of stereo audio. Allocation-free.
    void process(const float* inL, const float* inR,
                 float* outL, float* outR, int32_t n)
    {
        const float w  = width.load();
        // Width controls the side-to-side spread of the reverb:
        //   w1 = weight of same-channel reverb output
        //   w2 = weight of cross-channel reverb output (stereo spread)
        const float w1 = w / 2.0f + 0.5f;
        const float w2 = (1.0f - w) / 2.0f;

        for (int32_t i = 0; i < n; ++i) {
            // Sum both input channels to a mono feed for the reverb network.
            // Scale by 0.015 to keep levels in line with the input amplitude.
            float mono = (inL[i] + inR[i]) * 0.015f;

            // Run all 8 parallel comb filters and accumulate their outputs.
            float accL = 0.0f, accR = 0.0f;
            for (int j = 0; j < 8; ++j) {
                accL += combL[j].process(mono);
                accR += combR[j].process(mono);
            }
            // Diffuse with 4 all-pass filters in series.
            for (int j = 0; j < 4; ++j) {
                accL = apL[j].process(accL);
                accR = apR[j].process(accR);
            }
            // Apply stereo width matrix.
            tmpL[i] = accL * w1 + accR * w2;
            tmpR[i] = accR * w1 + accL * w2;
        }
        blendWetDry(inL, inR, tmpL.data(), tmpR.data(), outL, outR, mix.load(), n);
    }
};

// ── Biquad filter (Audio EQ Cookbook) ────────────────────────────────────────
//
// Transposed Direct Form II state (lower round-off error than DF1).
// Separate state variables per channel (sXL for left, sXR for right).
// Reference: R.Bristow-Johnson, "Cookbook formulae for audio EQ biquad filters".

/// General biquad filter with pre-computed coefficients.
/// Supports low-shelf, high-shelf, and peaking shapes.
struct BiquadFilter {
    /// Filter state (TDF2) — left channel.
    float s1L{0}, s2L{0};
    /// Filter state (TDF2) — right channel.
    float s1R{0}, s2R{0};
    /// Coefficients (normalised: a0=1).
    float b0{1}, b1{0}, b2{0}, a1{0}, a2{0};

    /// Compute low-shelf coefficients.
    /// [freq] = shelf corner Hz, [gainDb] = boost/cut in dB, [sr] = sample rate.
    void computeLowShelf(float freq, float gainDb, float sr) {
        float A    = powf(10.0f, gainDb / 40.0f);
        float w0   = kTwoPi * freq / sr;
        float cosw = cosf(w0);
        float sinw = sinf(w0);
        // Shelf slope S=1: alpha = sin(w0)/2 * sqrt(2).
        float alpha = sinw / 2.0f * sqrtf(2.0f);
        float sqA  = sqrtf(A);
        float a0   = (A+1) + (A-1)*cosw + 2*sqA*alpha;
        b0 = A * ((A+1) - (A-1)*cosw + 2*sqA*alpha) / a0;
        b1 = 2 * A * ((A-1) - (A+1)*cosw) / a0;
        b2 = A * ((A+1) - (A-1)*cosw - 2*sqA*alpha) / a0;
        a1 = -2 * ((A-1) + (A+1)*cosw) / a0;
        a2 = ((A+1) + (A-1)*cosw - 2*sqA*alpha) / a0;
    }

    /// Compute high-shelf coefficients.
    void computeHighShelf(float freq, float gainDb, float sr) {
        float A    = powf(10.0f, gainDb / 40.0f);
        float w0   = kTwoPi * freq / sr;
        float cosw = cosf(w0);
        float sinw = sinf(w0);
        float alpha = sinw / 2.0f * sqrtf(2.0f);
        float sqA  = sqrtf(A);
        float a0   = (A+1) - (A-1)*cosw + 2*sqA*alpha;
        b0 = A * ((A+1) + (A-1)*cosw + 2*sqA*alpha) / a0;
        b1 = -2 * A * ((A-1) + (A+1)*cosw) / a0;
        b2 = A * ((A+1) + (A-1)*cosw - 2*sqA*alpha) / a0;
        a1 = 2 * ((A-1) - (A+1)*cosw) / a0;
        a2 = ((A+1) - (A-1)*cosw - 2*sqA*alpha) / a0;
    }

    /// Compute peaking EQ band coefficients.
    /// [q] controls the bandwidth: higher Q = narrower band.
    void computePeaking(float freq, float q, float gainDb, float sr) {
        float A     = powf(10.0f, gainDb / 40.0f);
        float w0    = kTwoPi * freq / sr;
        float alpha = sinf(w0) / (2.0f * q);
        float cosw  = cosf(w0);
        float a0    = 1.0f + alpha / A;
        b0 = (1.0f + alpha * A) / a0;
        b1 = -2.0f * cosw / a0;
        b2 = (1.0f - alpha * A) / a0;
        a1 = b1;
        a2 = (1.0f - alpha / A) / a0;
    }

    /// Process one sample through the TDF2 structure.
    /// [s1], [s2] are the channel's state variables (passed by reference).
    inline float tick(float x, float& s1, float& s2) {
        float y = b0 * x + s1;
        s1      = b1 * x - a1 * y + s2;
        s2      = b2 * x - a2 * y;
        return y;
    }

    /// Process one block of stereo audio in-place.
    void processBlock(const float* inL, const float* inR,
                      float* outL, float* outR, int32_t n) {
        for (int32_t i = 0; i < n; ++i) {
            outL[i] = tick(inL[i], s1L, s2L);
            outR[i] = tick(inR[i], s1R, s2R);
        }
    }
};

// ── 4-Band Parametric EQ ─────────────────────────────────────────────────────

/// Four-band parametric EQ: low-shelf → low-mid peaking → hi-mid peaking → hi-shelf.
/// All bands are chained in series on the output buffers.
struct EqEffect {
    BiquadFilter eq1; ///< Band 1: low-shelf.
    BiquadFilter eq2; ///< Band 2: low-mid peaking.
    BiquadFilter eq3; ///< Band 3: high-mid peaking.
    BiquadFilter eq4; ///< Band 4: high-shelf.

    // Physical parameters (atomic for thread safety).
    std::atomic<float> lowFreq{100.0f},  lowGain{0.0f};
    std::atomic<float> lmidFreq{500.0f}, lmidQ{1.0f},   lmidGain{0.0f};
    std::atomic<float> hmidFreq{2500.f}, hmidQ{1.0f},   hmidGain{0.0f};
    std::atomic<float> highFreq{8000.f}, highGain{0.0f};

    float sampleRate; ///< Stored for coefficient re-computation.

    explicit EqEffect(float sr) : sampleRate(sr) {
        _rebuildEq1(); _rebuildEq2(); _rebuildEq3(); _rebuildEq4();
    }

    /// Update a parameter. [id] is the .gfpd string key; [v] is physical value.
    void setParam(const char* id, float v) {
        if      (strcmp(id,"low_freq")  ==0) { lowFreq.store(v);  _rebuildEq1(); }
        else if (strcmp(id,"low_gain")  ==0) { lowGain.store(v);  _rebuildEq1(); }
        else if (strcmp(id,"lmid_freq") ==0) { lmidFreq.store(v); _rebuildEq2(); }
        else if (strcmp(id,"lmid_q")    ==0) { lmidQ.store(v);    _rebuildEq2(); }
        else if (strcmp(id,"lmid_gain") ==0) { lmidGain.store(v); _rebuildEq2(); }
        else if (strcmp(id,"hmid_freq") ==0) { hmidFreq.store(v); _rebuildEq3(); }
        else if (strcmp(id,"hmid_q")    ==0) { hmidQ.store(v);    _rebuildEq3(); }
        else if (strcmp(id,"hmid_gain") ==0) { hmidGain.store(v); _rebuildEq3(); }
        else if (strcmp(id,"high_freq") ==0) { highFreq.store(v); _rebuildEq4(); }
        else if (strcmp(id,"high_gain") ==0) { highGain.store(v); _rebuildEq4(); }
    }

    /// Process one block: chain all four bands in series.
    void process(const float* inL, const float* inR,
                 float* outL, float* outR, int32_t n)
    {
        eq1.processBlock(inL,   inR,   outL, outR, n);
        eq2.processBlock(outL,  outR,  outL, outR, n);
        eq3.processBlock(outL,  outR,  outL, outR, n);
        eq4.processBlock(outL,  outR,  outL, outR, n);
    }

private:
    void _rebuildEq1() { eq1.computeLowShelf (lowFreq.load(),  lowGain.load(),  sampleRate); }
    void _rebuildEq2() { eq2.computePeaking  (lmidFreq.load(), lmidQ.load(),   lmidGain.load(), sampleRate); }
    void _rebuildEq3() { eq3.computePeaking  (hmidFreq.load(), hmidQ.load(),   hmidGain.load(), sampleRate); }
    void _rebuildEq4() { eq4.computeHighShelf(highFreq.load(), highGain.load(), sampleRate); }
};

// ── Ping-Pong Delay ──────────────────────────────────────────────────────────
//
// Stereo ping-pong: the left feedback feeds the right delay line and vice versa.
// This causes the repeated echoes to alternate between the left and right channels,
// creating a bouncing spatial effect.

/// Stereo ping-pong delay with optional BPM synchronisation.
struct DelayEffect {
    // NOTE: maxDelaySamples and sampleRate MUST be declared before bufL/bufR
    // — C++ initializes members in declaration order.
    int32_t maxDelaySamples;         ///< Pre-allocated buffer length.
    float   sampleRate;
    std::vector<float> bufL, bufR;  ///< Left and right delay lines.
    int32_t writePos{0};             ///< Current write head.

    // Physical parameters.
    std::atomic<float> timeMs{375.0f};    ///< Delay time in ms [1, 2000].
    std::atomic<float> feedback{0.40f};   ///< Feedback ratio [0, 1].
    std::atomic<float> bpmSync{0.0f};     ///< 0=time, 1=BPM.
    std::atomic<float> beatDiv{2.0f};     ///< Beat-division index [0, 5].
    std::atomic<float> mix{0.40f};        ///< Wet ratio [0, 1].

    std::vector<float> tmpL, tmpR; ///< Wet output before blend.

    DelayEffect(float sr, int32_t block)
        : maxDelaySamples(static_cast<int32_t>(sr * 2.0f) + 1)
        , sampleRate(sr)
        , bufL(maxDelaySamples, 0.0f)
        , bufR(maxDelaySamples, 0.0f)
        , tmpL(block, 0.0f), tmpR(block, 0.0f)
    {}

    /// Compute delay in samples, accounting for BPM-sync mode.
    int32_t _delaySamples() const {
        if (bpmSync.load() > 0.5f) {
            // BPM sync: delay period = one beat-division at current tempo.
            float rateHz = (g_gfpa_bpm.load() / 60.0f)
                         / kBeatDivs[clampBeatDiv(beatDiv.load())];
            float ms = 1000.0f / rateHz;
            return static_cast<int32_t>(ms * sampleRate / 1000.0f);
        }
        return static_cast<int32_t>(timeMs.load() * sampleRate / 1000.0f);
    }

    void setParam(const char* id, float v) {
        if      (strcmp(id,"time")     ==0) timeMs.store(v);
        else if (strcmp(id,"feedback") ==0) feedback.store(v / 100.0f);
        else if (strcmp(id,"bpm_sync") ==0) bpmSync.store(v);
        else if (strcmp(id,"beat_div") ==0) beatDiv.store(v);
        else if (strcmp(id,"mix")      ==0) mix.store(v / 100.0f);
    }

    /// Process one block. Allocation-free.
    void process(const float* inL, const float* inR,
                 float* outL, float* outR, int32_t n)
    {
        int32_t delay = _delaySamples();
        // Clamp delay to valid range to prevent buffer over-reads.
        if (delay <= 0)                  delay = 1;
        if (delay >= maxDelaySamples)    delay = maxDelaySamples - 1;

        const float fb = feedback.load();
        for (int32_t i = 0; i < n; ++i) {
            int32_t readPos = (writePos - delay + maxDelaySamples) % maxDelaySamples;
            float delL = bufL[readPos];
            float delR = bufR[readPos];
            // Cross-feed: each channel feeds the opposite channel's delay line.
            bufL[writePos] = inL[i] + delR * fb;
            bufR[writePos] = inR[i] + delL * fb;
            tmpL[i] = delL;
            tmpR[i] = delR;
            if (++writePos >= maxDelaySamples) writePos = 0;
        }
        blendWetDry(inL, inR, tmpL.data(), tmpR.data(), outL, outR, mix.load(), n);
    }
};

// ── Wah filter (Chamberlin SVF bandpass + LFO) ───────────────────────────────
//
// The Chamberlin State Variable Filter (SVF) exposes three simultaneous
// outputs (low, band, high pass) per call. We use the bandpass output, which
// creates the characteristic "wah" tone sweep.
// The LFO modulates the filter's cutoff frequency exponentially so the sweep
// sounds perceptually uniform across the audible range.

/// Wah auto-filter: LFO-swept SVF bandpass with optional BPM sync.
struct WahEffect {
    // SVF state variables (per channel).
    float lowL{0}, bandL{0};
    float lowR{0}, bandR{0};
    float lfoPhase{0.0f}; ///< LFO phase in [0,1).

    float sampleRate;

    // Physical parameters.
    std::atomic<float> center{1200.0f};   ///< Center frequency Hz [200, 4000].
    std::atomic<float> resonance{5.0f};   ///< Q / resonance [0.5, 20].
    std::atomic<float> rate{1.0f};        ///< LFO rate Hz [0.1, 10].
    std::atomic<float> depth{0.8f};       ///< LFO modulation depth [0, 1].
    std::atomic<float> waveform{0.0f};    ///< 0=sine, 1=triangle, 2=saw.
    std::atomic<float> bpmSync{0.0f};
    std::atomic<float> beatDiv{2.0f};
    std::atomic<float> mix{1.0f};         ///< Wet ratio [0, 1].

    std::vector<float> tmpL, tmpR;

    WahEffect(float sr, int32_t block)
        : sampleRate(sr), tmpL(block, 0.0f), tmpR(block, 0.0f)
    {}

    void setParam(const char* id, float v) {
        if      (strcmp(id,"center")    ==0) center.store(v);
        else if (strcmp(id,"resonance") ==0) resonance.store(v);
        else if (strcmp(id,"rate")      ==0) rate.store(v);
        else if (strcmp(id,"depth")     ==0) depth.store(v);
        else if (strcmp(id,"waveform")  ==0) waveform.store(v);
        else if (strcmp(id,"bpm_sync")  ==0) bpmSync.store(v);
        else if (strcmp(id,"beat_div")  ==0) beatDiv.store(v);
        else if (strcmp(id,"mix")       ==0) mix.store(v / 100.0f);
    }

    /// Evaluate the LFO for the current phase.
    /// [wf]: 0=sine (smooth), 1=triangle (linear), 2=sawtooth (rising ramp).
    float _lfo(float phase, int wf) {
        switch (wf) {
            case 1:  return phase < 0.5f ? 4.0f*phase - 1.0f : 3.0f - 4.0f*phase; // triangle
            case 2:  return phase * 2.0f - 1.0f;                                    // saw
            default: return sinf(kTwoPi * phase);                                   // sine
        }
    }

    /// Return the LFO rate in Hz, accounting for BPM sync.
    float _rateHz() const {
        return (bpmSync.load() > 0.5f)
            ? (g_gfpa_bpm.load() / 60.0f) / kBeatDivs[clampBeatDiv(beatDiv.load())]
            : rate.load();
    }

    /// Process one block. Allocation-free.
    void process(const float* inL, const float* inR,
                 float* outL, float* outR, int32_t n)
    {
        const float c        = center.load();
        const float q        = resonance.load();
        const float d        = depth.load();
        const float rHz      = _rateHz();
        const int   wf       = static_cast<int>(waveform.load() + 0.5f);
        const float phaseInc = rHz / sampleRate;
        const float qInv     = 1.0f / q;

        for (int32_t i = 0; i < n; ++i) {
            // LFO modulates center frequency exponentially:
            //   fc = center * 2^(lfo * depth * 2)
            // This maps the LFO linearly to musical pitch intervals (octaves).
            float lfoVal = _lfo(lfoPhase, wf);
            float fc = c * powf(2.0f, lfoVal * d * 2.0f);
            if (fc < 20.0f)    fc = 20.0f;
            if (fc > 20000.0f) fc = 20000.0f;
            // Chamberlin SVF frequency coefficient.
            float f = 2.0f * sinf(kPi * fc / sampleRate);

            // Left channel — bandpass output selected.
            float hpL = inL[i] - qInv * bandL - lowL;
            bandL = f * hpL + bandL;
            lowL  = f * bandL + lowL;
            tmpL[i] = bandL;

            // Right channel.
            float hpR = inR[i] - qInv * bandR - lowR;
            bandR = f * hpR + bandR;
            lowR  = f * bandR + lowR;
            tmpR[i] = bandR;

            lfoPhase += phaseInc;
            if (lfoPhase >= 1.0f) lfoPhase -= 1.0f;
        }
        blendWetDry(inL, inR, tmpL.data(), tmpR.data(), outL, outR, mix.load(), n);
    }
};

// ── Feed-forward RMS Compressor ───────────────────────────────────────────────
//
// Detects signal level using a simple absolute-value envelope follower
// (approximates RMS without sqrt for efficiency). Applies gain reduction
// when the level exceeds [threshold]. Attack/release determine how fast the
// gain reduction engages and recovers.

/// Dynamics compressor with configurable threshold, ratio, attack and release.
struct CompressorEffect {
    float envL{0}, envR{0}; ///< Per-channel envelope state.
    float sampleRate;

    std::atomic<float> threshold{-18.0f}; ///< dB [-60, 0].
    std::atomic<float> ratio{4.0f};        ///< [1, 20].
    std::atomic<float> attackMs{10.0f};    ///< ms [0.1, 200].
    std::atomic<float> releaseMs{100.0f};  ///< ms [10, 2000].
    std::atomic<float> makeupDb{0.0f};     ///< Makeup gain dB [0, 24].

    explicit CompressorEffect(float sr) : sampleRate(sr) {}

    void setParam(const char* id, float v) {
        if      (strcmp(id,"threshold") ==0) threshold.store(v);
        else if (strcmp(id,"ratio")     ==0) ratio.store(v);
        else if (strcmp(id,"attack")    ==0) attackMs.store(v);
        else if (strcmp(id,"release")   ==0) releaseMs.store(v);
        else if (strcmp(id,"makeup")    ==0) makeupDb.store(v);
    }

    /// Process one block. Allocation-free; computes gain sample-by-sample.
    void process(const float* inL, const float* inR,
                 float* outL, float* outR, int32_t n)
    {
        // Pre-compute per-block constants to avoid repeated atomic loads.
        const float attCoeff = expf(-1.0f / (sampleRate * attackMs.load() / 1000.0f));
        const float relCoeff = expf(-1.0f / (sampleRate * releaseMs.load() / 1000.0f));
        const float thrLin   = powf(10.0f, threshold.load() / 20.0f);
        const float rat      = ratio.load();
        const float makeup   = powf(10.0f, makeupDb.load() / 20.0f);

        for (int32_t i = 0; i < n; ++i) {
            // Absolute-value envelope follower — attack on rising edges, release on falling.
            float rmsL = fabsf(inL[i]);
            float rmsR = fabsf(inR[i]);
            envL = (rmsL > envL) ? attCoeff * envL + (1.0f-attCoeff)*rmsL : relCoeff * envL;
            envR = (rmsR > envR) ? attCoeff * envR + (1.0f-attCoeff)*rmsR : relCoeff * envR;

            // Gain computer: reduce by (1 - 1/ratio) for each dB above threshold.
            auto computeGain = [&](float env) -> float {
                if (env <= thrLin || env <= 1e-6f) return 1.0f;
                float dBover = 20.0f * log10f(env / thrLin);
                float dBred  = dBover * (1.0f - 1.0f / rat);
                return powf(10.0f, -dBred / 20.0f);
            };

            outL[i] = inL[i] * computeGain(envL) * makeup;
            outR[i] = inR[i] * computeGain(envR) * makeup;
        }
    }
};

// ── Stereo Chorus / Flanger ───────────────────────────────────────────────────
//
// Modulated delay lines with cross-feedback create chorus (longer delay) or
// flanger (very short delay) effects. L and R channels use LFOs that start
// 180° apart for a natural stereo widening feel.

/// Stereo chorus with optional BPM synchronisation.
struct ChorusEffect {
    // NOTE: maxDelaySamples and sampleRate MUST be declared before bufL/bufR
    // because C++ initializes members in declaration order, and the buffers
    // depend on maxDelaySamples in the constructor initializer list.
    int32_t maxDelaySamples;
    float sampleRate;
    std::vector<float> bufL, bufR;  ///< Per-channel modulated delay lines.
    int32_t writePos{0};
    float lfoPhaseL{0.0f};  ///< LFO phase for L (starts at 0°).
    float lfoPhaseR{0.5f};  ///< LFO phase for R (starts at 180° — stereo spread).

    std::atomic<float> rate{0.5f};       ///< LFO rate Hz [0.1, 10].
    std::atomic<float> depth{0.5f};      ///< Modulation depth [0, 1].
    std::atomic<float> delayMs{20.0f};   ///< Base delay ms [5, 50].
    std::atomic<float> feedback{0.0f};   ///< Cross-feedback ratio [0, 1].
    std::atomic<float> bpmSync{0.0f};
    std::atomic<float> beatDiv{3.0f};
    std::atomic<float> mix{0.5f};        ///< Wet ratio [0, 1].

    std::vector<float> tmpL, tmpR;

    ChorusEffect(float sr, int32_t block)
        : maxDelaySamples(static_cast<int32_t>(sr * 0.1f) + 1) // max 100 ms
        , sampleRate(sr)
        , bufL(maxDelaySamples, 0.0f)
        , bufR(maxDelaySamples, 0.0f)
        , tmpL(block, 0.0f), tmpR(block, 0.0f)
    {}

    void setParam(const char* id, float v) {
        if      (strcmp(id,"rate")     ==0) rate.store(v);
        else if (strcmp(id,"depth")    ==0) depth.store(v);
        else if (strcmp(id,"delay")    ==0) delayMs.store(v);
        else if (strcmp(id,"feedback") ==0) feedback.store(v / 100.0f);
        else if (strcmp(id,"bpm_sync") ==0) bpmSync.store(v);
        else if (strcmp(id,"beat_div") ==0) beatDiv.store(v);
        else if (strcmp(id,"mix")      ==0) mix.store(v / 100.0f);
    }

    float _rateHz() const {
        return (bpmSync.load() > 0.5f)
            ? (g_gfpa_bpm.load() / 60.0f) / kBeatDivs[clampBeatDiv(beatDiv.load())]
            : rate.load();
    }

    /// Linearly interpolate into the circular buffer at a fractional read position.
    float _readInterp(const std::vector<float>& buf, float delaySamples) {
        float fpos = static_cast<float>(writePos) - delaySamples;
        while (fpos < 0.0f) fpos += static_cast<float>(maxDelaySamples);
        int   i0   = static_cast<int>(fpos) % maxDelaySamples;
        int   i1   = (i0 + 1) % maxDelaySamples;
        float frac = fpos - static_cast<int>(fpos);
        return buf[i0] * (1.0f - frac) + buf[i1] * frac;
    }

    /// Process one block. Allocation-free.
    void process(const float* inL, const float* inR,
                 float* outL, float* outR, int32_t n)
    {
        const float rHz      = _rateHz();
        const float phaseInc = rHz / sampleRate;
        const float baseDelay = delayMs.load() * sampleRate / 1000.0f;
        const float modDepth  = depth.load() * baseDelay * 0.5f;
        const float fb        = feedback.load();

        for (int32_t i = 0; i < n; ++i) {
            // Sinusoidal LFO — modulates the delay time to create pitch variation.
            float modL = sinf(kTwoPi * lfoPhaseL);
            float modR = sinf(kTwoPi * lfoPhaseR);
            float delL = baseDelay + modL * modDepth;
            float delR = baseDelay + modR * modDepth;

            float wetL = _readInterp(bufL, delL);
            float wetR = _readInterp(bufR, delR);

            // Cross-feedback: L feeds back through R delay and vice versa,
            // enhancing stereo widening.
            bufL[writePos] = inL[i] + wetR * fb;
            bufR[writePos] = inR[i] + wetL * fb;

            tmpL[i] = wetL;
            tmpR[i] = wetR;

            lfoPhaseL += phaseInc;
            lfoPhaseR += phaseInc;
            if (lfoPhaseL >= 1.0f) lfoPhaseL -= 1.0f;
            if (lfoPhaseR >= 1.0f) lfoPhaseR -= 1.0f;

            if (++writePos >= maxDelaySamples) writePos = 0;
        }
        blendWetDry(inL, inR, tmpL.data(), tmpR.data(), outL, outR, mix.load(), n);
    }
};

// ── Plugin instance wrapper ───────────────────────────────────────────────────

/// Discriminator for the union inside GfpaDspInstance.
enum class GfpaEffectType { Reverb, Delay, Wah, Eq, Compressor, Chorus };

/// Opaque wrapper that holds one GFPA effect instance and its type tag.
///
/// The [insertCb] static method is used as the [GfpaInsertFn] callback;
/// it dispatches to the correct effect using the instance pointer as userdata.
struct GfpaDspInstance {
    GfpaEffectType type;

    /// When true, the insert callback copies input to output unchanged
    /// (the effect is bypassed).  Written from the Dart isolate via
    /// gfpa_dsp_set_bypass(); read on the audio thread in insertCb().
    std::atomic<bool> bypassed{false};

    /// Untagged union — only the field matching [type] is valid.
    union {
        FreeverbEffect*   reverb;
        DelayEffect*      delay;
        WahEffect*        wah;
        EqEffect*         eq;
        CompressorEffect* compressor;
        ChorusEffect*     chorus;
    };

    /// Static C-callable insert callback dispatched to the correct effect.
    ///
    /// If the instance is bypassed, the input is copied directly to the output
    /// with no DSP processing — zero latency, zero CPU cost.
    static void insertCb(const float* inL, const float* inR,
                         float* outL, float* outR,
                         int32_t frames, void* ud)
    {
        auto* inst = static_cast<GfpaDspInstance*>(ud);

        // Bypass: pass-through input unchanged.
        if (inst->bypassed.load(std::memory_order_relaxed)) {
            std::memcpy(outL, inL, sizeof(float) * static_cast<size_t>(frames));
            std::memcpy(outR, inR, sizeof(float) * static_cast<size_t>(frames));
            return;
        }

        switch (inst->type) {
            case GfpaEffectType::Reverb:
                inst->reverb->process(inL, inR, outL, outR, frames); break;
            case GfpaEffectType::Delay:
                inst->delay->process(inL, inR, outL, outR, frames);  break;
            case GfpaEffectType::Wah:
                inst->wah->process(inL, inR, outL, outR, frames);    break;
            case GfpaEffectType::Eq:
                inst->eq->process(inL, inR, outL, outR, frames);     break;
            case GfpaEffectType::Compressor:
                inst->compressor->process(inL, inR, outL, outR, frames); break;
            case GfpaEffectType::Chorus:
                inst->chorus->process(inL, inR, outL, outR, frames); break;
        }
    }
};

// ── C API implementation ──────────────────────────────────────────────────────

extern "C" {

/// Create a native DSP instance for [pluginId].
/// Returns NULL if [pluginId] is not a recognised built-in effect.
GfpaDspHandle gfpa_dsp_create(const char* pluginId, int32_t sr, int32_t block) {
    auto* inst = new GfpaDspInstance();
    std::string id(pluginId);

    if (id == "com.grooveforge.reverb") {
        inst->type   = GfpaEffectType::Reverb;
        inst->reverb = new FreeverbEffect(block);
    } else if (id == "com.grooveforge.delay") {
        inst->type  = GfpaEffectType::Delay;
        inst->delay = new DelayEffect(static_cast<float>(sr), block);
    } else if (id == "com.grooveforge.wah") {
        inst->type = GfpaEffectType::Wah;
        inst->wah  = new WahEffect(static_cast<float>(sr), block);
    } else if (id == "com.grooveforge.eq") {
        inst->type = GfpaEffectType::Eq;
        inst->eq   = new EqEffect(static_cast<float>(sr));
    } else if (id == "com.grooveforge.compressor") {
        inst->type       = GfpaEffectType::Compressor;
        inst->compressor = new CompressorEffect(static_cast<float>(sr));
    } else if (id == "com.grooveforge.chorus") {
        inst->type   = GfpaEffectType::Chorus;
        inst->chorus = new ChorusEffect(static_cast<float>(sr), block);
    } else {
        delete inst;
        return nullptr;
    }
    return static_cast<GfpaDspHandle>(inst);
}

/// Set a physical parameter value on a live DSP instance.
void gfpa_dsp_set_param(GfpaDspHandle handle, const char* paramId, double v) {
    auto* inst = static_cast<GfpaDspInstance*>(handle);
    float fv   = static_cast<float>(v);
    switch (inst->type) {
        case GfpaEffectType::Reverb:     inst->reverb->setParam(paramId, fv);     break;
        case GfpaEffectType::Delay:      inst->delay->setParam(paramId, fv);      break;
        case GfpaEffectType::Wah:        inst->wah->setParam(paramId, fv);        break;
        case GfpaEffectType::Eq:         inst->eq->setParam(paramId, fv);         break;
        case GfpaEffectType::Compressor: inst->compressor->setParam(paramId, fv); break;
        case GfpaEffectType::Chorus:     inst->chorus->setParam(paramId, fv);     break;
    }
}

/// Set the bypass state of a DSP instance.
///
/// When [bypassed] is true, the insert callback copies input to output
/// unchanged (zero CPU cost, zero latency).  Thread-safe: may be called
/// from the Dart isolate while the audio thread runs.
void gfpa_dsp_set_bypass(GfpaDspHandle handle, bool bypassed) {
    auto* inst = static_cast<GfpaDspInstance*>(handle);
    inst->bypassed.store(bypassed, std::memory_order_relaxed);
}

/// Return the static insert callback (shared by all instances — dispatch via userdata).
GfpaInsertFn gfpa_dsp_insert_fn(GfpaDspHandle /*handle*/) {
    return GfpaDspInstance::insertCb;
}

/// Return the userdata pointer (the instance itself).
void* gfpa_dsp_userdata(GfpaDspHandle handle) {
    return handle;
}

/// Free all resources associated with a DSP instance.
void gfpa_dsp_destroy(GfpaDspHandle handle) {
    auto* inst = static_cast<GfpaDspInstance*>(handle);
    switch (inst->type) {
        case GfpaEffectType::Reverb:     delete inst->reverb;     break;
        case GfpaEffectType::Delay:      delete inst->delay;      break;
        case GfpaEffectType::Wah:        delete inst->wah;        break;
        case GfpaEffectType::Eq:         delete inst->eq;         break;
        case GfpaEffectType::Compressor: delete inst->compressor; break;
        case GfpaEffectType::Chorus:     delete inst->chorus;     break;
    }
    delete inst;
}

} // extern "C"
