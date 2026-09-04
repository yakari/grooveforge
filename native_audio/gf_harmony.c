// gf_harmony.c — Implementation of the shared harmony engine.
// See gf_harmony.h for the API and the rationale behind each stage.

#include "gf_harmony.h"

#include "gf_phase_vocoder.h"

#include <stdlib.h>
#include <string.h>

// ── Vocoder settings ─────────────────────────────────────────────────────────

/// FFT window and analysis hop for every voice.
///
/// 2048 at 48 kHz gives 23 Hz bins — fine enough to resolve the partials of
/// a low male voice or a bass guitar, which is what the vocoder's peak-based
/// phase locking needs to track a pitch at all. It also fixes the engine's
/// latency at roughly half a window, so this is the number to revisit if
/// latency ever has to come down.
#define GF_HARMONY_FFT 2048
#define GF_HARMONY_HOP 512

/// Production quanta a voice banks before it starts contributing.
///
/// One quantum covers the obvious case — a block during which no synthesis
/// frame happened to land. Two is needed because the analysis hop is
/// fractional, so frames drift against the block grid and occasionally two
/// blocks in a row come up empty.
#define GF_HARMONY_BANK_QUANTA 2

/// Below this a voice counts as silent and its vocoder is not run at all.
#define GF_HARMONY_SILENT 0.0001f

// ── Voice ────────────────────────────────────────────────────────────────────

typedef struct {
    gf_pv_context* pv;

    /// Pitch offset and level, written by the caller, read once per block.
    float semitones;
    float mix;

    /// False while the voice is filling its bank, during which it
    /// contributes silence.
    int primed;

    /// Whether the voice was audible last block. A voice coming back from
    /// silence restarts from a clean vocoder rather than replaying the
    /// overlap-add tail left over from whenever it last played.
    int running;
} gf_harmony_voice;

struct gf_harmony {
    gf_harmony_voice voice[GF_HARMONY_MAX_VOICES];
    int   voice_count;
    int   max_block;

    /// One block of vocoder output, reused across voices.
    float* scratch;
};

// ── Lifecycle ────────────────────────────────────────────────────────────────

gf_harmony* gf_harmony_create(int max_block) {
    if (max_block <= 0) return NULL;

    gf_harmony* h = (gf_harmony*)calloc(1, sizeof(gf_harmony));
    if (!h) return NULL;

    h->max_block   = max_block;
    h->voice_count = GF_HARMONY_MAX_VOICES;
    h->scratch     = (float*)calloc((size_t)max_block, sizeof(float));
    if (!h->scratch) { gf_harmony_destroy(h); return NULL; }

    for (int v = 0; v < GF_HARMONY_MAX_VOICES; v++) {
        h->voice[v].pv = gf_pv_create(GF_HARMONY_FFT, GF_HARMONY_HOP, 1);
        if (!h->voice[v].pv) { gf_harmony_destroy(h); return NULL; }
        h->voice[v].mix = 0.0f;
    }
    return h;
}

void gf_harmony_destroy(gf_harmony* h) {
    if (!h) return;
    for (int v = 0; v < GF_HARMONY_MAX_VOICES; v++) gf_pv_destroy(h->voice[v].pv);
    free(h->scratch);
    free(h);
}

void gf_harmony_reset(gf_harmony* h) {
    if (!h) return;
    for (int v = 0; v < GF_HARMONY_MAX_VOICES; v++) {
        gf_pv_reset(h->voice[v].pv);
        h->voice[v].primed  = 0;
        h->voice[v].running = 0;
    }
}

// ── Parameters ───────────────────────────────────────────────────────────────

void gf_harmony_set_voice(gf_harmony* h, int index, float semitones, float mix) {
    if (!h || index < 0 || index >= GF_HARMONY_MAX_VOICES) return;
    if (semitones < -24.0f) semitones = -24.0f;
    if (semitones >  24.0f) semitones =  24.0f;
    if (mix < 0.0f) mix = 0.0f;
    h->voice[index].semitones = semitones;
    h->voice[index].mix       = mix;
}

void gf_harmony_set_voice_count(gf_harmony* h, int count) {
    if (!h) return;
    if (count < 1) count = 1;
    if (count > GF_HARMONY_MAX_VOICES) count = GF_HARMONY_MAX_VOICES;
    h->voice_count = count;
}

// ── Processing ───────────────────────────────────────────────────────────────

/// Attenuation that keeps the summed voices at or below unity.
///
/// Only ever attenuates: voices that already sum to less than full scale are
/// left alone, so a single quiet harmony stays quiet rather than being
/// normalised up to full.
static float gf_harmony_headroom(const gf_harmony* h) {
    float total = 0.0f;
    for (int v = 0; v < h->voice_count; v++) {
        if (h->voice[v].mix > GF_HARMONY_SILENT) total += h->voice[v].mix;
    }
    return (total > 1.0f) ? (1.0f / total) : 1.0f;
}

/// Drains [pv] down to [target] available frames, discarding the surplus.
///
/// The bank is only checked between blocks, so a large block can push it well
/// past the target in one step — and whatever a voice holds when it starts
/// playing is latency it keeps for as long as it runs. Discarding the surplus
/// is a one-off cut into audio nobody has heard yet, and it pins the latency
/// to the target no matter how big the audio device's blocks are.
static void gf_harmony_trim(gf_harmony* h, gf_pv_context* pv, int target) {
    int surplus = gf_pv_available(pv) - target;
    while (surplus > 0) {
        const int take = (surplus < h->max_block) ? surplus : h->max_block;
        // Zero input frames makes this a pure drain.
        const int got = gf_pv_process_block(pv, NULL, 0, h->scratch, take);
        if (got <= 0) break;      // nothing more to give; stop rather than spin
        surplus -= got;
    }
}

/// Runs one voice and sums it into [out] at [gain].
static void gf_harmony_mix_voice(gf_harmony* h, int index, float gain,
                                 const float* in, float* out, int n) {
    gf_harmony_voice* voice = &h->voice[index];
    gf_pv_set_pitch_semitones(voice->pv, voice->semitones);

    // While banking, push input and take nothing: a capacity of zero leaves
    // every produced sample inside the vocoder.
    if (!voice->primed) {
        gf_pv_process_block(voice->pv, in, n, h->scratch, 0);
        // The quantum shrinks as a voice is transposed up, so a voice an
        // octave above needs half the bank of one at unison.
        const int needed = GF_HARMONY_BANK_QUANTA * gf_pv_output_quantum(voice->pv);
        if (gf_pv_available(voice->pv) >= needed) {
            gf_harmony_trim(h, voice->pv, needed);
            voice->primed = 1;
        }
        return;                   // voice stays silent for this block
    }

    const int got = gf_pv_process_block(voice->pv, in, n, h->scratch, n);
    for (int i = 0; i < got; i++) out[i] += h->scratch[i] * gain;

    // A short block means the bank ran dry — possible only right after a
    // large pitch jump, which briefly changes the vocoder's internal rates.
    // Rebuilding the bank costs this voice a few silent blocks and is far
    // less audible than serving partial blocks forever.
    if (got < n) voice->primed = 0;
}

void gf_harmony_process(gf_harmony* h, const float* in, float* out, int n) {
    if (!h || n <= 0) return;
    if (n > h->max_block) n = h->max_block;

    memset(out, 0, sizeof(float) * (size_t)n);

    const float headroom = gf_harmony_headroom(h);

    for (int v = 0; v < GF_HARMONY_MAX_VOICES; v++) {
        gf_harmony_voice* voice = &h->voice[v];

        // A voice past the count, or turned down to silence, is skipped
        // outright — an idle vocoder is an FFT per hop that nobody hears.
        const int wanted = (v < h->voice_count) && (voice->mix > GF_HARMONY_SILENT);
        if (!wanted) { voice->running = 0; continue; }

        // Coming back from silence: start from a clean vocoder so the first
        // block cannot replay a stale tail.
        if (!voice->running) {
            gf_pv_reset(voice->pv);
            voice->primed  = 0;
            voice->running = 1;
        }

        gf_harmony_mix_voice(h, v, voice->mix * headroom, in, out, n);
    }
}
