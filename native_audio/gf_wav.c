// gf_wav.c — Implementation of the mono 16-bit WAV helpers.
// See gf_wav.h for the API and why the format is deliberately narrow.

#include "gf_wav.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

// ─── Little-endian field readers ────────────────────────────────────────────

static uint32_t rd_u32(const unsigned char* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static uint16_t rd_u16(const unsigned char* p) {
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

// ─── Reading ────────────────────────────────────────────────────────────────

gf_wav_reader gf_wav_open_read(const char* path) {
    gf_wav_reader r;
    r.file = NULL;
    r.frames = 0;
    r.sample_rate = 48000;
    r.data_offset = 0;
    if (!path) return r;

    FILE* f = fopen(path, "rb");
    if (!f) return r;

    unsigned char hdr[12];
    if (fread(hdr, 1, 12, f) != 12 || memcmp(hdr, "RIFF", 4) != 0 ||
        memcmp(hdr + 8, "WAVE", 4) != 0) {
        fclose(f);
        return r;
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
            r.sample_rate = (int)rd_u32(fmt + 4);
            have_fmt = 1;
            if (size > 16) fseek(f, (long)(size - 16), SEEK_CUR);
        } else if (memcmp(chunk, "data", 4) == 0) {
            if (!have_fmt) break;
            r.frames = (int64_t)size / 2;
            r.data_offset = ftell(f);
            r.file = f;
            return r;  // positioned at the first sample
        } else {
            // Chunks are word-aligned, so an odd size carries a pad byte.
            fseek(f, (long)(size + (size & 1u)), SEEK_CUR);
        }
    }
    fclose(f);
    return r;
}

int gf_wav_read(gf_wav_reader* r, float* dst, int count) {
    if (!r || !r->file || !dst || count <= 0) return 0;

    // Converted through a small stack buffer so a long read does not need a
    // matching int16 allocation of its own.
    enum { CHUNK = 1024 };
    int16_t raw[CHUNK];
    int done = 0;
    while (done < count) {
        const int want = (count - done < CHUNK) ? (count - done) : CHUNK;
        const size_t got = fread(raw, sizeof(int16_t), (size_t)want, r->file);
        if (got == 0) break;
        for (size_t i = 0; i < got; i++) {
            dst[done + (int)i] = (float)raw[i] / 32768.0f;
        }
        done += (int)got;
        if ((int)got < want) break;  // short read: end of file
    }
    return done;
}

void gf_wav_rewind(gf_wav_reader* r) {
    if (r && r->file) fseek(r->file, r->data_offset, SEEK_SET);
}

void gf_wav_seek(gf_wav_reader* r, int64_t frame) {
    if (!r || !r->file) return;
    if (frame < 0) frame = 0;
    if (frame > r->frames) frame = r->frames;
    fseek(r->file, r->data_offset + (long)(frame * 2), SEEK_SET);
}

void gf_wav_close(gf_wav_reader* r) {
    if (!r) return;
    if (r->file) fclose(r->file);
    r->file = NULL;
    r->frames = 0;
    r->data_offset = 0;
}

// ─── Writing ────────────────────────────────────────────────────────────────

FILE* gf_wav_open_write(const char* path, int sample_rate) {
    if (!path) return NULL;
    FILE* f = fopen(path, "wb");
    if (!f) return NULL;
    const uint32_t byte_rate = (uint32_t)sample_rate * 2u;
    unsigned char h[44];
    memcpy(h, "RIFF", 4);
    memset(h + 4, 0, 4);  // patched by gf_wav_finish
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

int gf_wav_write(FILE* f, const float* samples, int count) {
    if (!f || !samples) return 0;
    for (int i = 0; i < count; i++) {
        float v = samples[i];
        if (v > 1.0f) v = 1.0f;
        if (v < -1.0f) v = -1.0f;
        const int32_t s = (int32_t)lrintf(v * 32767.0f);
        const unsigned char b[2] = {(unsigned char)(s & 0xFF),
                                    (unsigned char)((s >> 8) & 0xFF)};
        if (fwrite(b, 1, 2, f) != 2) return 0;
    }
    return 1;
}

void gf_wav_finish(FILE* f, int64_t frames) {
    if (!f) return;
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
