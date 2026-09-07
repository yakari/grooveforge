// gf_media_import.c — Implementation (see gf_media_import.h).
//
// This file carries its own miniaudio implementation rather than borrowing
// audio_input.c's, because that one is compiled with `MA_API static` — every
// miniaudio symbol there is private to that translation unit, deliberately, so
// it cannot clash with the second vendored copy inside dart_vst_host. Linking
// against it is therefore not an option, and the same `static` is used here so
// this copy stays private too.
//
// MA_NO_DEVICE_IO strips every audio backend, which is most of miniaudio: this
// file only ever decodes files and never opens a device, so the playback and
// capture code would be dead weight in the binary.

#define MA_NO_DEVICE_IO
#define MA_API static
// `MA_API static` privatises miniaudio's *functions*, but not the handful of
// globals it declares outside that macro, so the two copies in this library
// collide on them at link time. Renaming them here keeps this copy entirely to
// itself.
#define ma_atomic_global_lock gf_import_ma_atomic_global_lock
// `ma_android_sdk_version` is declared without MA_API too, and is compiled on
// Android regardless of MA_NO_DEVICE_IO.
#define ma_android_sdk_version gf_import_ma_android_sdk_version
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include "gf_media_import.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/// Frames decoded per pass. Large enough that the loop is not the cost, small
/// enough that a four-minute master does not need a 40 MB buffer to convert.
#define GF_IMPORT_CHUNK 8192

int gf_media_can_decode(const char* path) {
    if (!path) return 0;
    ma_decoder_config cfg = ma_decoder_config_init(ma_format_s16, 1, 48000);
    ma_decoder dec;
    if (ma_decoder_init_file(path, &cfg, &dec) != MA_SUCCESS) return 0;
    ma_decoder_uninit(&dec);
    return 1;
}

/// Writes a mono 16-bit WAV header with placeholder sizes.
static FILE* wav_begin(const char* path, int sample_rate) {
    FILE* f = fopen(path, "wb");
    if (!f) return NULL;
    const uint32_t byte_rate = (uint32_t)sample_rate * 2u;
    unsigned char h[44];
    memcpy(h, "RIFF", 4);
    memset(h + 4, 0, 4);
    memcpy(h + 8, "WAVEfmt ", 8);
    h[16] = 16; h[17] = 0; h[18] = 0; h[19] = 0;
    h[20] = 1;  h[21] = 0;
    h[22] = 1;  h[23] = 0;
    h[24] = (unsigned char)(sample_rate & 0xFF);
    h[25] = (unsigned char)((sample_rate >> 8) & 0xFF);
    h[26] = (unsigned char)((sample_rate >> 16) & 0xFF);
    h[27] = (unsigned char)((sample_rate >> 24) & 0xFF);
    h[28] = (unsigned char)(byte_rate & 0xFF);
    h[29] = (unsigned char)((byte_rate >> 8) & 0xFF);
    h[30] = (unsigned char)((byte_rate >> 16) & 0xFF);
    h[31] = (unsigned char)((byte_rate >> 24) & 0xFF);
    h[32] = 2;  h[33] = 0;
    h[34] = 16; h[35] = 0;
    memcpy(h + 36, "data", 4);
    memset(h + 40, 0, 4);
    if (fwrite(h, 1, 44, f) != 44) { fclose(f); return NULL; }
    return f;
}

/// Patches the two size fields and closes.
static void wav_end(FILE* f, int64_t frames) {
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
    fclose(f);
}

int64_t gf_media_to_mono_wav(const char* src, const char* dst, int sample_rate) {
    if (!src || !dst || sample_rate <= 0) return -1;

    // The decoder is asked for the exact shape the engine streams, so
    // resampling, channel folding and format conversion all happen inside
    // miniaudio rather than in a hand-written loop here.
    ma_decoder_config cfg = ma_decoder_config_init(ma_format_s16, 1,
                                                   (ma_uint32)sample_rate);
    ma_decoder dec;
    if (ma_decoder_init_file(src, &cfg, &dec) != MA_SUCCESS) return -2;

    FILE* out = wav_begin(dst, sample_rate);
    if (!out) { ma_decoder_uninit(&dec); return -3; }

    int16_t* buf = (int16_t*)malloc(sizeof(int16_t) * GF_IMPORT_CHUNK);
    if (!buf) { fclose(out); ma_decoder_uninit(&dec); return -3; }

    int64_t total = 0;
    for (;;) {
        ma_uint64 got = 0;
        const ma_result rc =
            ma_decoder_read_pcm_frames(&dec, buf, GF_IMPORT_CHUNK, &got);
        if (got > 0) {
            if (fwrite(buf, 2, (size_t)got, out) != (size_t)got) {
                free(buf);
                fclose(out);
                ma_decoder_uninit(&dec);
                return -3;
            }
            total += (int64_t)got;
        }
        // MA_AT_END arrives with the final partial read, so the count is only
        // complete once that read has been written.
        if (rc != MA_SUCCESS || got == 0) break;
    }

    free(buf);
    wav_end(out, total);
    ma_decoder_uninit(&dec);
    return total;
}

int gf_media_waveform(const char* wav_path, float* out, int bins) {
    if (!wav_path || !out || bins <= 0) return 0;
    for (int i = 0; i < bins; i++) out[i] = 0.0f;

    FILE* f = fopen(wav_path, "rb");
    if (!f) return 0;
    fseek(f, 0, SEEK_END);
    const long size = ftell(f);
    if (size <= 44) { fclose(f); return 0; }
    const int64_t frames = (int64_t)(size - 44) / 2;
    if (frames <= 0) { fclose(f); return 0; }
    fseek(f, 44, SEEK_SET);

    const int64_t per_bin = frames / bins > 0 ? frames / bins : 1;
    static int16_t chunk[4096];
    int64_t read_so_far = 0;

    // One pass over the file, filling bins as the cursor crosses them, rather
    // than seeking per bin: a four-minute master is ten thousand seeks that
    // way, which is slow enough to be felt on a phone.
    while (read_so_far < frames) {
        const int want = (int)((frames - read_so_far) < 4096
                                   ? (frames - read_so_far)
                                   : 4096);
        const int got = (int)fread(chunk, 2, (size_t)want, f);
        if (got <= 0) break;
        for (int i = 0; i < got; i++) {
            const int64_t bin = (read_so_far + i) / per_bin;
            if (bin >= bins) break;
            float v = (float)chunk[i] / 32768.0f;
            if (v < 0) v = -v;
            if (v > out[bin]) out[bin] = v;
        }
        read_so_far += got;
    }
    fclose(f);
    return 1;
}
