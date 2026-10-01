#include "gf_timestretch.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gf_phase_vocoder.h"
#include "gf_wav.h"

// ─── Rendering ──────────────────────────────────────────────────────────────

// Larger than the harmonizer's live window. Nothing here has to finish inside
// an audio callback, and a longer analysis frame holds sustained notes —
// which is most of what a rehearsal take contains — together far better.
#define TS_FFT 4096
#define TS_HOP (TS_FFT / 4)

// Input frames per pass. Small enough that the output buffer stays modest at
// the maximum stretch, large enough that the file is not read in dribbles.
#define TS_CHUNK 8192

int64_t gf_ts_output_frames(int64_t in_frames, float ratio) {
    if (in_frames <= 0) return 0;
    if (!(ratio > 0.0f)) return 0;
    return (int64_t)llround((double)in_frames * (double)ratio);
}

int gf_ts_render_file(const char* in_path, const char* out_path, float ratio) {
    if (!in_path || !out_path) return GF_TS_ERR_OPEN_INPUT;
    if (!(ratio >= GF_TS_MIN_RATIO) || !(ratio <= GF_TS_MAX_RATIO)) {
        return GF_TS_ERR_RATIO;
    }

    gf_wav_reader in = gf_wav_open_read(in_path);
    if (!in.file) return GF_TS_ERR_OPEN_INPUT;
    const int64_t in_frames = in.frames;
    const int sample_rate = in.sample_rate;

    FILE* out = gf_wav_open_write(out_path, sample_rate);
    if (!out) { gf_wav_close(&in); return GF_TS_ERR_OPEN_OUTPUT; }

    gf_pv_context* pv = gf_pv_create(TS_FFT, TS_HOP, 1);
    // Worst case per pass, as the vocoder's contract states.
    const int out_cap = (int)(TS_CHUNK * GF_TS_MAX_RATIO) + TS_FFT;
    float* in_buf = (float*)malloc(sizeof(float) * TS_CHUNK);
    float* out_buf = (float*)malloc(sizeof(float) * (size_t)out_cap);

    if (!pv || !in_buf || !out_buf) {
        if (pv) gf_pv_destroy(pv);
        free(in_buf); free(out_buf);
        gf_wav_close(&in); fclose(out); remove(out_path);
        return GF_TS_ERR_MEMORY;
    }
    gf_pv_set_stretch(pv, ratio);

    // The target length is decided up front rather than accepted from the
    // vocoder. Its output arrives in whole synthesis frames, so the last one
    // overshoots; and a track one frame longer than the grid expects would
    // drift against every other track in the tune.
    const int64_t want = gf_ts_output_frames(in_frames, ratio);
    int64_t written = 0;
    int ok = 1;

    int64_t remaining = in_frames;
    while (remaining > 0 && written < want && ok) {
        const int n = (int)(remaining < TS_CHUNK ? remaining : TS_CHUNK);
        const int got = gf_wav_read(&in, in_buf, n);
        if (got == 0) break;
        remaining -= (int64_t)got;

        const int produced =
            gf_pv_process_block(pv, in_buf, got, out_buf, out_cap);
        int usable = produced;
        if (written + usable > want) usable = (int)(want - written);
        if (usable > 0) {
            ok = gf_wav_write(out, out_buf, usable);
            written += usable;
        }
    }

    // Flush the vocoder's tail: the last analysis frames are still inside it,
    // and stopping at the end of the input would clip the final note.
    if (ok && written < want) {
        memset(in_buf, 0, sizeof(float) * TS_CHUNK);
        int guard = 0;
        while (written < want && ok && guard++ < 64) {
            const int produced =
                gf_pv_process_block(pv, in_buf, TS_CHUNK, out_buf, out_cap);
            if (produced <= 0) break;
            int usable = produced;
            if (written + usable > want) usable = (int)(want - written);
            ok = gf_wav_write(out, out_buf, usable);
            written += usable;
        }
    }

    // Silence rather than a short file if the vocoder ran dry early. A track
    // that ends where the grid says it ends keeps the tune aligned; one that
    // stops early would pull the transport's end marker in with it.
    if (ok && written < want) {
        const float zero[256] = {0};
        while (written < want && ok) {
            const int64_t left = want - written;
            const int n = (int)(left < 256 ? left : 256);
            ok = gf_wav_write(out, zero, n);
            written += n;
        }
    }

    gf_pv_destroy(pv);
    free(in_buf); free(out_buf);
    gf_wav_close(&in);

    if (!ok) { fclose(out); remove(out_path); return GF_TS_ERR_WRITE; }
    gf_wav_finish(out, written);
    fclose(out);
    return GF_TS_OK;
}
