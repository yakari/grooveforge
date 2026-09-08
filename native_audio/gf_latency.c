// gf_latency.c — Implementation of the round-trip measurement (see gf_latency.h).

#include "gf_latency.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// ─── Measurement signal ──────────────────────────────────────────────────────

int gf_lat_chirp_frames(int sample_rate) {
    return (int)((long long)GF_LAT_CHIRP_MS * sample_rate / 1000);
}

int gf_lat_run_frames(int sample_rate) {
    const int period = (int)((long long)GF_LAT_SHOT_PERIOD_MS * sample_rate / 1000);
    return period * (GF_LAT_SHOTS - 1) + gf_lat_chirp_frames(sample_rate);
}

void gf_lat_generate_chirp(float* out, int sample_rate) {
    const int n = gf_lat_chirp_frames(sample_rate);
    const double duration = (double)n / (double)sample_rate;

    // A linear sweep: frequency rises from f0 to f1 at a constant rate, so the
    // instantaneous frequency at time t is f0 + (f1-f0)*t/duration. Phase is
    // the integral of that, hence the t^2 term.
    const double f0 = GF_LAT_CHIRP_F0;
    const double rate = (GF_LAT_CHIRP_F1 - GF_LAT_CHIRP_F0) / duration;

    // Fade length: 20% of the chirp at each end. Without it, the sweep would
    // start and stop with a step discontinuity, and that step is a click —
    // broadband energy that correlates just as well as the sweep does and
    // would blur the correlation peak we are trying to sharpen.
    const int fade = n / 5;

    for (int i = 0; i < n; i++) {
        const double t = (double)i / (double)sample_rate;
        const double phase = 2.0 * M_PI * (f0 * t + 0.5 * rate * t * t);
        double s = sin(phase);

        if (i < fade) {
            // Raised cosine rising from 0 to 1.
            s *= 0.5 - 0.5 * cos(M_PI * (double)i / (double)fade);
        } else if (i >= n - fade) {
            const int j = n - 1 - i;
            s *= 0.5 - 0.5 * cos(M_PI * (double)j / (double)fade);
        }
        out[i] = (float)s;
    }
}

// ─── Audio-thread emitter ────────────────────────────────────────────────────

void gf_lat_emitter_init(gf_lat_emitter* em, const float* chirp, int sample_rate) {
    em->chirp = chirp;
    em->chirp_frames = gf_lat_chirp_frames(sample_rate);
    em->shot_period_frames =
        (int)((long long)GF_LAT_SHOT_PERIOD_MS * sample_rate / 1000);
    em->shots = GF_LAT_SHOTS;
    em->amplitude = 0.5f;
}

long long gf_lat_shot_frame(const gf_lat_emitter* em, int shot_index) {
    return (long long)shot_index * (long long)em->shot_period_frames;
}

int gf_lat_emitter_render(const gf_lat_emitter* em, float* out, int frames,
                          long long start_frame) {
    const long long end_frame = start_frame + frames;
    const long long run_end =
        gf_lat_shot_frame(em, em->shots - 1) + em->chirp_frames;

    // Only the chirps that could overlap this block are considered, so the
    // cost per callback is bounded no matter how long the run is.
    for (int s = 0; s < em->shots; s++) {
        const long long shot_start = gf_lat_shot_frame(em, s);
        const long long shot_end = shot_start + em->chirp_frames;
        if (shot_end <= start_frame || shot_start >= end_frame) continue;

        // Intersect the chirp with this block, in absolute frames.
        const long long from = shot_start > start_frame ? shot_start : start_frame;
        const long long to = shot_end < end_frame ? shot_end : end_frame;

        for (long long f = from; f < to; f++) {
            const int out_i = (int)(f - start_frame);
            const int chirp_i = (int)(f - shot_start);
            out[out_i] += em->amplitude * em->chirp[chirp_i];
        }
    }

    return end_frame < run_end ? 1 : 0;
}

// ─── Delay estimation ────────────────────────────────────────────────────────

int gf_lat_estimate_delay(const float* ref, int ref_frames,
                          const float* cap, int cap_frames,
                          int search_start, int search_frames,
                          gf_lat_shot* out) {
    if (ref_frames <= 0 || cap_frames <= 0 || search_frames <= 0) return 0;
    if (search_start < 0) search_start = 0;

    // The last lag at which a full reference window still fits in the capture.
    int last_lag = cap_frames - ref_frames;
    if (last_lag < search_start) return 0;
    int search_end = search_start + search_frames;
    if (search_end > last_lag + 1) search_end = last_lag + 1;
    if (search_end <= search_start) return 0;

    // Energy of the reference, computed once — it does not move.
    double ref_energy = 0.0;
    for (int i = 0; i < ref_frames; i++) ref_energy += (double)ref[i] * ref[i];
    if (ref_energy <= 0.0) return 0;
    const double ref_norm = sqrt(ref_energy);

    // Running energy of the capture window, so each lag costs one add and one
    // subtract instead of a fresh sum over the whole window.
    double cap_energy = 0.0;
    for (int i = search_start; i < search_start + ref_frames; i++) {
        cap_energy += (double)cap[i] * cap[i];
    }

    // Correlation is scored for every lag; the peak and the best competing
    // peak are tracked together so confidence comes out of the same pass.
    float* scores = (float*)malloc(sizeof(float) * (size_t)(search_end - search_start));
    if (!scores) return 0;

    int best_lag = search_start;
    double best_score = -1.0;

    for (int lag = search_start; lag < search_end; lag++) {
        double dot = 0.0;
        const float* c = cap + lag;
        for (int i = 0; i < ref_frames; i++) dot += (double)ref[i] * c[i];

        // Normalising by the capture window's own energy is what makes this
        // robust: without it the estimator scores "loud" rather than "similar"
        // and locks onto the loudest moment in the room.
        double score = 0.0;
        if (cap_energy > 1e-12) {
            score = dot / (ref_norm * sqrt(cap_energy));
            if (score < 0.0) score = -score;  // polarity may be inverted
        }
        scores[lag - search_start] = (float)score;

        if (score > best_score) {
            best_score = score;
            best_lag = lag;
        }

        // Slide the energy window by one frame.
        if (lag + ref_frames < cap_frames) {
            cap_energy -= (double)cap[lag] * cap[lag];
            cap_energy += (double)cap[lag + ref_frames] * cap[lag + ref_frames];
            if (cap_energy < 0.0) cap_energy = 0.0;  // guard rounding drift
        }
    }

    // Confidence: how far the winner stands above the best peak outside a
    // guard band around it. A genuine match towers over everything else; noise
    // produces a field of near-equal peaks and a ratio close to 1.
    const int guard = ref_frames / 2;
    double runner_up = 0.0;
    for (int lag = search_start; lag < search_end; lag++) {
        if (lag > best_lag - guard && lag < best_lag + guard) continue;
        const double s = scores[lag - search_start];
        if (s > runner_up) runner_up = s;
    }

    // Sub-frame refinement: fit a parabola through the peak and its two
    // neighbours and take its vertex. The true arrival almost never falls
    // exactly on a frame boundary, and this recovers the fraction.
    float frac = (float)best_lag;
    const int bi = best_lag - search_start;
    if (bi > 0 && bi < (search_end - search_start) - 1) {
        const double y0 = scores[bi - 1], y1 = scores[bi], y2 = scores[bi + 1];
        const double denom = y0 - 2.0 * y1 + y2;
        if (fabs(denom) > 1e-12) {
            const double delta = 0.5 * (y0 - y2) / denom;
            if (delta > -1.0 && delta < 1.0) frac = (float)(best_lag + delta);
        }
    }

    free(scores);

    out->delay_frames = best_lag;
    out->delay_frames_frac = frac;
    out->peak = (float)best_score;
    out->confidence = runner_up > 1e-9 ? (float)(best_score / runner_up) : 999.0f;
    return 1;
}

/// Ascending comparison for the median.
static int compare_int(const void* a, const void* b) {
    const int ia = *(const int*)a, ib = *(const int*)b;
    return (ia > ib) - (ia < ib);
}

/// Below this, the correlator did not find anything it could tell apart from
/// the room, and the shot is discarded rather than averaged in.
#define GF_LAT_MIN_CONFIDENCE 2.0f

int gf_lat_analyse_run(const gf_lat_emitter* em,
                       const float* cap, int cap_frames,
                       long long cap_start_frame,
                       int sample_rate,
                       gf_lat_result* out) {
    memset(out, 0, sizeof(*out));

    const int max_rt = gf_lat_ms_to_frames(GF_LAT_MAX_ROUND_TRIP_MS, sample_rate);
    int found[GF_LAT_SHOTS];
    // Kept alongside the deltas so the drift fit has an x axis: where on the
    // playback timeline each measurement was taken.
    double shot_x[GF_LAT_SHOTS];
    double shot_y[GF_LAT_SHOTS];
    int n = 0;
    float min_conf = 1e9f;

    for (int s = 0; s < em->shots; s++) {
        // Where this chirp left the playback device, expressed on the capture
        // device's frame axis. The round trip is whatever we must add to this
        // to find the chirp in the recording — including the offset between the
        // two device clocks, which is precisely the term the OS cannot report.
        const long long emitted = gf_lat_shot_frame(em, s) - cap_start_frame;

        // Search from the chirp's own emission point forward by one maximum
        // round trip. Bounding it this tightly is what stops chirp s being
        // mistaken for chirp s-1 arriving very late.
        long long from = emitted;
        if (from < 0) from = 0;
        if (from >= cap_frames) break;

        gf_lat_shot shot;
        if (!gf_lat_estimate_delay(em->chirp, em->chirp_frames,
                                   cap, cap_frames,
                                   (int)from, max_rt, &shot)) {
            continue;
        }
        if (shot.confidence < GF_LAT_MIN_CONFIDENCE) continue;

        // The fractional peak is used for the drift fit: drift over one run is
        // a fraction of a frame per shot, so quantising each point to a whole
        // frame would bury the very slope we are trying to measure.
        shot_x[n] = (double)gf_lat_shot_frame(em, s);
        shot_y[n] = (double)shot.delay_frames_frac - (double)from;
        found[n++] = shot.delay_frames - (int)from;
        if (shot.confidence < min_conf) min_conf = shot.confidence;
    }

    out->shots_found = n;
    out->min_confidence = n > 0 ? min_conf : 0.0f;
    // Fewer than three usable shots leaves no majority to take a median of,
    // so the run is reported as failed rather than guessed at.
    if (n < 3) return 0;

    qsort(found, (size_t)n, sizeof(int), compare_int);
    out->median_frames = found[n / 2];
    out->min_frames = found[0];
    out->max_frames = found[n - 1];
    out->median_ms = 1000.0f * (float)out->median_frames / (float)sample_rate;
    out->jitter_ms =
        1000.0f * (float)(out->max_frames - out->min_frames) / (float)sample_rate;

    // Least-squares slope of measured delay against playback position. The
    // slope is dimensionless — frames of drift per frame elapsed — which is
    // parts per million once scaled.
    double sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
    for (int i = 0; i < n; i++) {
        sx += shot_x[i]; sy += shot_y[i];
        sxx += shot_x[i] * shot_x[i];
        sxy += shot_x[i] * shot_y[i];
    }
    const double denom = (double)n * sxx - sx * sx;
    if (fabs(denom) > 1e-9) {
        const double slope = ((double)n * sxy - sx * sy) / denom;
        out->drift_ppm = (float)(slope * 1e6);
        out->drift_frames_per_minute = (float)(slope * 60.0 * (double)sample_rate);
    }
    return 1;
}

// ─── Applying the compensation ───────────────────────────────────────────────

int gf_lat_ms_to_frames(float ms, int sample_rate) {
    return (int)(ms * (float)sample_rate / 1000.0f + 0.5f);
}

int gf_lat_align_take(const float* in, int in_frames, int comp_frames,
                      float* out, int out_capacity) {
    if (comp_frames < 0) comp_frames = 0;
    if (comp_frames >= in_frames) return 0;

    const int kept = in_frames - comp_frames;
    const int n = kept < out_capacity ? kept : out_capacity;
    memcpy(out, in + comp_frames, sizeof(float) * (size_t)n);

    // Zero-pad so the take still spans the grid region it was recorded over;
    // a shorter buffer would leave the mixer reading whatever was there before.
    if (n < out_capacity) {
        memset(out + n, 0, sizeof(float) * (size_t)(out_capacity - n));
    }
    return n;
}
