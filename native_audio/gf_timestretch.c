#include "gf_timestretch.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gf_phase_vocoder.h"

// ─── WAV I/O ────────────────────────────────────────────────────────────────
//
// Mono 16-bit only, which is what every take and every decoded master is
// stored as. A general reader would be dead weight: nothing else ever reaches
// this file.

static uint32_t rd_u32(const unsigned char* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static uint16_t rd_u16(const unsigned char* p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

static FILE* wav_open_read(const char* path, int64_t* frames, int* sample_rate) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;

    unsigned char hdr[12];
    if (fread(hdr, 1, 12, f) != 12 || memcmp(hdr, "RIFF", 4) != 0 ||
        memcmp(hdr + 8, "WAVE", 4) != 0) {
        fclose(f);
        return NULL;
    }

    int have_fmt = 0;
    unsigned char chunk[8];
    while (fread(chunk, 1, 8, f) == 8) {
        const uint32_t size = rd_u32(chunk + 4);
        if (memcmp(chunk, "fmt ", 4) == 0) {
            unsigned char fmt[16];
            if (size < 16 || fread(fmt, 1, 16, f) != 16) break;
            if (rd_u16(fmt) != 1 || rd_u16(fmt + 2) != 1 ||
                rd_u16(fmt + 14) != 16) {
                break;  // not mono 16-bit PCM
            }
            if (sample_rate) *sample_rate = (int)rd_u32(fmt + 4);
            have_fmt = 1;
            if (size > 16) fseek(f, (long)(size - 16), SEEK_CUR);
        } else if (memcmp(chunk, "data", 4) == 0) {
            if (!have_fmt) break;
            *frames = (int64_t)size / 2;
            return f;  // positioned at the first sample
        } else {
            // Chunks are word-aligned, so an odd size carries a pad byte.
            fseek(f, (long)(size + (size & 1u)), SEEK_CUR);
        }
    }
    fclose(f);
    return NULL;
}

static FILE* wav_open_write(const char* path, int sample_rate) {
    FILE* f = fopen(path, "wb");
    if (!f) return NULL;
    const uint32_t byte_rate = (uint32_t)sample_rate * 2u;
    unsigned char h[44];
    memcpy(h, "RIFF", 4);
    memset(h + 4, 0, 4);  // patched by wav_finish
    memcpy(h + 8, "WAVEfmt ", 8);
    h[16] = 16; h[17] = 0; h[18] = 0; h[19] = 0;
    h[20] = 1;  h[21] = 0;   // PCM
    h[22] = 1;  h[23] = 0;   // mono
    h[24] = (unsigned char)(sample_rate & 0xFF);
    h[25] = (unsigned char)((sample_rate >> 8) & 0xFF);
    h[26] = (unsigned char)((sample_rate >> 16) & 0xFF);
    h[27] = (unsigned char)((sample_rate >> 24) & 0xFF);
    h[28] = (unsigned char)(byte_rate & 0xFF);
    h[29] = (unsigned char)((byte_rate >> 8) & 0xFF);
    h[30] = (unsigned char)((byte_rate >> 16) & 0xFF);
    h[31] = (unsigned char)((byte_rate >> 24) & 0xFF);
    h[32] = 2;  h[33] = 0;   // block align
    h[34] = 16; h[35] = 0;   // bits per sample
    memcpy(h + 36, "data", 4);
    memset(h + 40, 0, 4);
    if (fwrite(h, 1, 44, f) != 44) { fclose(f); return NULL; }
    return f;
}

static void wav_patch_sizes(FILE* f, int64_t frames) {
    const uint32_t data_bytes = (uint32_t)(frames * 2);
    const uint32_t riff_bytes = data_bytes + 36u;
    unsigned char b[4];
    b[0] = (unsigned char)(riff_bytes & 0xFF);
    b[1] = (unsigned char)((riff_bytes >> 8) & 0xFF);
    b[2] = (unsigned char)((riff_bytes >> 16) & 0xFF);
    b[3] = (unsigned char)((riff_bytes >> 24) & 0xFF);
    fseek(f, 4, SEEK_SET);
    fwrite(b, 1, 4, f);
    b[0] = (unsigned char)(data_bytes & 0xFF);
    b[1] = (unsigned char)((data_bytes >> 8) & 0xFF);
    b[2] = (unsigned char)((data_bytes >> 16) & 0xFF);
    b[3] = (unsigned char)((data_bytes >> 24) & 0xFF);
    fseek(f, 40, SEEK_SET);
    fwrite(b, 1, 4, f);
}

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

/// Writes [count] floats as mono 16-bit, clipping rather than wrapping.
///
/// The vocoder's overlap-add can overshoot slightly on transients even when
/// the input never did, and a wrapped sample is a loud click in the middle of
/// someone's take.
static int write_samples(FILE* out, const float* samples, int count) {
    for (int i = 0; i < count; i++) {
        float v = samples[i];
        if (v > 1.0f) v = 1.0f;
        if (v < -1.0f) v = -1.0f;
        const int32_t s = (int32_t)lrintf(v * 32767.0f);
        const unsigned char b[2] = {(unsigned char)(s & 0xFF),
                                    (unsigned char)((s >> 8) & 0xFF)};
        if (fwrite(b, 1, 2, out) != 2) return 0;
    }
    return 1;
}

int gf_ts_render_file(const char* in_path, const char* out_path, float ratio) {
    if (!in_path || !out_path) return GF_TS_ERR_OPEN_INPUT;
    if (!(ratio >= GF_TS_MIN_RATIO) || !(ratio <= GF_TS_MAX_RATIO)) {
        return GF_TS_ERR_RATIO;
    }

    int64_t in_frames = 0;
    int sample_rate = 48000;
    FILE* in = wav_open_read(in_path, &in_frames, &sample_rate);
    if (!in) return GF_TS_ERR_OPEN_INPUT;

    FILE* out = wav_open_write(out_path, sample_rate);
    if (!out) { fclose(in); return GF_TS_ERR_OPEN_OUTPUT; }

    gf_pv_context* pv = gf_pv_create(TS_FFT, TS_HOP, 1);
    // Worst case per pass, as the vocoder's contract states.
    const int out_cap = (int)(TS_CHUNK * GF_TS_MAX_RATIO) + TS_FFT;
    int16_t* raw = (int16_t*)malloc(sizeof(int16_t) * TS_CHUNK);
    float* in_buf = (float*)malloc(sizeof(float) * TS_CHUNK);
    float* out_buf = (float*)malloc(sizeof(float) * (size_t)out_cap);

    if (!pv || !raw || !in_buf || !out_buf) {
        if (pv) gf_pv_destroy(pv);
        free(raw); free(in_buf); free(out_buf);
        fclose(in); fclose(out); remove(out_path);
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
        const size_t got = fread(raw, sizeof(int16_t), (size_t)n, in);
        if (got == 0) break;
        for (size_t i = 0; i < got; i++) in_buf[i] = (float)raw[i] / 32768.0f;
        remaining -= (int64_t)got;

        const int produced =
            gf_pv_process_block(pv, in_buf, (int)got, out_buf, out_cap);
        int usable = produced;
        if (written + usable > want) usable = (int)(want - written);
        if (usable > 0) {
            ok = write_samples(out, out_buf, usable);
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
            ok = write_samples(out, out_buf, usable);
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
            ok = write_samples(out, zero, n);
            written += n;
        }
    }

    gf_pv_destroy(pv);
    free(raw); free(in_buf); free(out_buf);
    fclose(in);

    if (!ok) { fclose(out); remove(out_path); return GF_TS_ERR_WRITE; }
    wav_patch_sizes(out, written);
    fclose(out);
    return GF_TS_OK;
}
