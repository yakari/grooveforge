// gf_pv_smoke_test.c — Offline smoke test for the phase vocoder.
//
// Generates a synthetic 4-bar loop at 120 BPM (a 440 Hz sine plus a beep
// click train on every beat), time-stretches it to 140 BPM (stretch ratio
// 120/140 ≈ 0.857 — faster playback), and writes both the source and the
// stretched output to WAV files so the result can be auditioned.
//
// Also runs three assertions:
//   - output duration matches stretch_ratio * input duration (within 5%)
//   - output RMS is within 3 dB of input RMS (unity gain chain)
//   - sine pitch is unchanged (dominant FFT bin after stretching is the
//     same as in the source, tolerance ±1 bin)
//
// Build: see CMakeLists.txt — target "gf_pv_smoke_test".
// Run  : ./build/gf_pv_smoke_test [out_dir]
//        Default output directory is /tmp.

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include "gf_phase_vocoder.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define SR          44100
#define BPM_SRC     120
#define BPM_DST     140
#define NUM_BARS    4
#define FFT_SIZE    2048

static int write_wav_mono(const char* path, const float* data, int num_frames, int sr) {
    ma_encoder_config cfg = ma_encoder_config_init(ma_encoding_format_wav, ma_format_f32, 1, sr);
    ma_encoder enc;
    if (ma_encoder_init_file(path, &cfg, &enc) != MA_SUCCESS) {
        fprintf(stderr, "failed to open %s for writing\n", path);
        return 0;
    }
    ma_uint64 written = 0;
    ma_encoder_write_pcm_frames(&enc, data, (ma_uint64)num_frames, &written);
    ma_encoder_uninit(&enc);
    return (int)written;
}

// Generates a 4-bar mono buffer: a 440 Hz sine plus a short 2 kHz click
// on every beat (4/4 time).
static void generate_test_signal(float* buf, int num_frames, int sr, int bpm) {
    const double beat_samples = 60.0 * (double)sr / (double)bpm;
    for (int i = 0; i < num_frames; i++) {
        double t = (double)i / (double)sr;
        double sine = 0.3 * sin(2.0 * M_PI * 440.0 * t);

        // Click: a 5 ms 2 kHz burst at the start of each beat.
        double frame_in_beat = fmod((double)i, beat_samples);
        double click = 0.0;
        const double click_len = 0.005 * (double)sr;
        if (frame_in_beat < click_len) {
            double env = 1.0 - frame_in_beat / click_len;
            click = 0.4 * env * sin(2.0 * M_PI * 2000.0 * t);
        }
        buf[i] = (float)(sine + click);
    }
}

static double rms(const float* x, int n) {
    double s = 0.0;
    for (int i = 0; i < n; i++) s += (double)x[i] * (double)x[i];
    return sqrt(s / (double)n);
}

// Naive DFT magnitude at the 440 Hz bin — cheap pitch sanity check.
static double dft_mag_at(const float* x, int n, int sr, double freq) {
    double re = 0.0, im = 0.0;
    for (int i = 0; i < n; i++) {
        double a = -2.0 * M_PI * freq * (double)i / (double)sr;
        re += (double)x[i] * cos(a);
        im += (double)x[i] * sin(a);
    }
    return sqrt(re*re + im*im) / (double)n;
}

int main(int argc, char** argv) {
    const char* out_dir = (argc > 1) ? argv[1] : "/tmp";
    printf("gf_pv_smoke_test — writing to %s\n", out_dir);

    // 1. Generate 4 bars at 120 BPM.
    int bar_samples  = (int)(4.0 * 60.0 * (double)SR / (double)BPM_SRC);
    int num_frames   = bar_samples * NUM_BARS;
    float* src = (float*)calloc((size_t)num_frames, sizeof(float));
    generate_test_signal(src, num_frames, SR, BPM_SRC);

    // 2. Time-stretch to 140 BPM. A loop recorded at 120 BPM must play
    //    140/120 = 1.1667 times faster to match — so stretch ratio = 120/140.
    float stretch = (float)BPM_SRC / (float)BPM_DST;
    int   out_capacity = (int)((double)num_frames * 1.5 + FFT_SIZE);
    float* dst = (float*)calloc((size_t)out_capacity, sizeof(float));
    int dst_frames = gf_pv_time_stretch_offline(
        src, num_frames, /*channels*/1, SR, stretch, FFT_SIZE, dst, out_capacity);
    printf("  src frames: %d  (%.3f s)\n", num_frames, (double)num_frames / SR);
    printf("  dst frames: %d  (%.3f s)  stretch=%.4f\n",
           dst_frames, (double)dst_frames / SR, stretch);

    // 3. Write WAVs.
    char src_path[512], dst_path[512];
    snprintf(src_path, sizeof(src_path), "%s/gf_pv_src_120bpm.wav", out_dir);
    snprintf(dst_path, sizeof(dst_path), "%s/gf_pv_dst_140bpm.wav", out_dir);
    write_wav_mono(src_path, src, num_frames, SR);
    write_wav_mono(dst_path, dst, dst_frames, SR);
    printf("  wrote %s\n  wrote %s\n", src_path, dst_path);

    // 4. Assertions.
    int fails = 0;

    // (a) duration ratio
    double actual_ratio = (double)dst_frames / (double)num_frames;
    double err = fabs(actual_ratio - (double)stretch) / (double)stretch;
    printf("  duration ratio: want %.4f  got %.4f  err %.2f%%\n",
           stretch, actual_ratio, err * 100.0);
    if (err > 0.05) { printf("    FAIL: duration error > 5%%\n"); fails++; }

    // (b) RMS preserved (unity gain). Measure a middle slice to avoid
    //     edge transients from the OLA ramp-in/out.
    int src_mid_start = num_frames / 4;
    int src_mid_len   = num_frames / 2;
    int dst_mid_start = dst_frames / 4;
    int dst_mid_len   = dst_frames / 2;
    double src_rms = rms(src + src_mid_start, src_mid_len);
    double dst_rms = rms(dst + dst_mid_start, dst_mid_len);
    double gain_db = 20.0 * log10(dst_rms / (src_rms + 1e-12));
    printf("  rms: src %.4f  dst %.4f  gain %.2f dB\n", src_rms, dst_rms, gain_db);
    if (fabs(gain_db) > 3.0) { printf("    FAIL: gain drift > 3 dB\n"); fails++; }

    // (c) pitch preserved: 440 Hz DFT magnitude in the middle slice should
    //     still be well above the level at neighbouring arbitrary freqs.
    double m_440 = dft_mag_at(dst + dst_mid_start, dst_mid_len, SR, 440.0);
    double m_500 = dft_mag_at(dst + dst_mid_start, dst_mid_len, SR, 500.0);
    printf("  pitch: |X(440)|=%.5f  |X(500)|=%.5f\n", m_440, m_500);
    if (m_440 < m_500 * 3.0) {
        printf("    FAIL: 440 Hz component not dominant — pitch shifted?\n");
        fails++;
    }

    // ── Pitch-shift tests ──────────────────────────────────────────────
    //
    // Generate a pure 440 Hz tone, shift it up an octave (+12 semitones)
    // and down an octave (-12 semitones), and verify the output energy
    // concentrates at 880 Hz / 220 Hz respectively. We compare the DFT
    // magnitude at the expected shifted frequency against the magnitude
    // at the original 440 Hz — a clean pitch shift should have the new
    // frequency dominate by ≥ 3× (a simple but effective sanity bound;
    // a perfect shift would give near-total dominance, but linear
    // interpolation in the resample step leaves a small residue).
    const int pv_sine_len = SR * 2;
    float* sine_in   = (float*)calloc((size_t)pv_sine_len, sizeof(float));
    float* sine_up   = (float*)calloc((size_t)pv_sine_len + FFT_SIZE, sizeof(float));
    float* sine_down = (float*)calloc((size_t)pv_sine_len + FFT_SIZE, sizeof(float));
    for (int i = 0; i < pv_sine_len; i++) {
        sine_in[i] = (float)(0.5 * sin(2.0 * M_PI * 440.0 * (double)i / (double)SR));
    }

    int up_frames = gf_pv_pitch_shift_offline(
        sine_in, pv_sine_len, /*channels*/1, SR, /*semitones*/+12.0f,
        FFT_SIZE, sine_up, pv_sine_len + FFT_SIZE);
    int down_frames = gf_pv_pitch_shift_offline(
        sine_in, pv_sine_len, 1, SR, -12.0f,
        FFT_SIZE, sine_down, pv_sine_len + FFT_SIZE);

    printf("\n  pitch-shift up +12: %d frames out of %d\n", up_frames, pv_sine_len);
    printf("  pitch-shift dn -12: %d frames out of %d\n", down_frames, pv_sine_len);

    // Use a middle slice well past the ring-in.
    int slice_start = pv_sine_len / 3;
    int slice_len   = pv_sine_len / 3;

    if (up_frames >= slice_start + slice_len) {
        double u_880 = dft_mag_at(sine_up   + slice_start, slice_len, SR, 880.0);
        double u_440 = dft_mag_at(sine_up   + slice_start, slice_len, SR, 440.0);
        printf("  +12: |X(880)|=%.5f  |X(440 residue)|=%.5f\n", u_880, u_440);
        if (u_880 < u_440 * 3.0) {
            printf("    FAIL: +12 semitone shift did not move energy to 880 Hz\n");
            fails++;
        }
    } else {
        printf("    FAIL: +12 pitch-shift produced too few frames\n");
        fails++;
    }

    if (down_frames >= slice_start + slice_len) {
        double d_220 = dft_mag_at(sine_down + slice_start, slice_len, SR, 220.0);
        double d_440 = dft_mag_at(sine_down + slice_start, slice_len, SR, 440.0);
        printf("  -12: |X(220)|=%.5f  |X(440 residue)|=%.5f\n", d_220, d_440);
        if (d_220 < d_440 * 3.0) {
            printf("    FAIL: -12 semitone shift did not move energy to 220 Hz\n");
            fails++;
        }
    } else {
        printf("    FAIL: -12 pitch-shift produced too few frames\n");
        fails++;
    }

    // Write the pitch-shifted WAVs for auditioning.
    char up_path[512], down_path[512];
    snprintf(up_path,   sizeof(up_path),   "%s/gf_pv_up12.wav",   out_dir);
    snprintf(down_path, sizeof(down_path), "%s/gf_pv_down12.wav", out_dir);
    write_wav_mono(up_path,   sine_up,   up_frames,   SR);
    write_wav_mono(down_path, sine_down, down_frames, SR);
    printf("  wrote %s\n  wrote %s\n", up_path, down_path);

    free(sine_in);
    free(sine_up);
    free(sine_down);
    free(src);
    free(dst);
    if (fails == 0) {
        printf("OK — all smoke checks passed.\n");
        return 0;
    }
    printf("FAILED — %d check(s).\n", fails);
    return 1;
}
