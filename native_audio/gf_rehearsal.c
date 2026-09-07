// gf_rehearsal.c — Implementation of the rehearsal engine (see gf_rehearsal.h).

#include "gf_rehearsal.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
  #include <windows.h>
#else
  #include <pthread.h>
  #include <time.h>
#endif

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// ─── A very small thread abstraction ─────────────────────────────────────────
//
// One worker thread and one mutex is all this needs, so pulling in a threading
// library would cost more than it saves. Windows gets the Win32 primitives,
// everything else pthreads.

#if defined(_WIN32)
typedef HANDLE gf_thread;
typedef CRITICAL_SECTION gf_mutex;
static void gf_mutex_init(gf_mutex* m)   { InitializeCriticalSection(m); }
static void gf_mutex_free(gf_mutex* m)   { DeleteCriticalSection(m); }
static void gf_mutex_lock(gf_mutex* m)   { EnterCriticalSection(m); }
static void gf_mutex_unlock(gf_mutex* m) { LeaveCriticalSection(m); }
static void gf_sleep_ms(int ms)          { Sleep((DWORD)ms); }
#else
typedef pthread_t gf_thread;
typedef pthread_mutex_t gf_mutex;
static void gf_mutex_init(gf_mutex* m)   { pthread_mutex_init(m, NULL); }
static void gf_mutex_free(gf_mutex* m)   { pthread_mutex_destroy(m); }
static void gf_mutex_lock(gf_mutex* m)   { pthread_mutex_lock(m); }
static void gf_mutex_unlock(gf_mutex* m) { pthread_mutex_unlock(m); }
static void gf_sleep_ms(int ms) {
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (long)(ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}
#endif

// ─── Minimal WAV I/O ─────────────────────────────────────────────────────────
//
// Only mono 16-bit PCM is handled, which is the one format takes are stored in
// (see REHEARSALS.md §4.6 — mono because the source is one player and one
// microphone, 16-bit because a phone cannot hold six five-minute takes as
// float).

/// Reads a little-endian 32-bit value.
static uint32_t rd_u32(const unsigned char* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static uint16_t rd_u16(const unsigned char* p) {
    return (uint16_t)((uint32_t)p[0] | ((uint32_t)p[1] << 8));
}

/// Opens [path] and locates its audio.
///
/// Walks the RIFF chunk list rather than assuming a 44-byte header: real files
/// carry LIST/fact chunks before `data` often enough that a fixed offset reads
/// metadata as audio, which comes out as a burst of noise.
///
/// On success fills [data_offset] (bytes) and [frames], and returns the open
/// file. Returns NULL if the file cannot be read or is not mono 16-bit PCM.
static FILE* wav_open_read(const char* path, long* data_offset, int64_t* frames,
                           int* sample_rate) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;

    unsigned char hdr[12];
    if (fread(hdr, 1, 12, f) != 12 ||
        memcmp(hdr, "RIFF", 4) != 0 || memcmp(hdr + 8, "WAVE", 4) != 0) {
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
            const uint16_t format = rd_u16(fmt);
            const uint16_t channels = rd_u16(fmt + 2);
            const uint16_t bits = rd_u16(fmt + 14);
            if (format != 1 || channels != 1 || bits != 16) break;
            if (sample_rate) *sample_rate = (int)rd_u32(fmt + 4);
            have_fmt = 1;
            // Skip any remainder of an over-long fmt chunk.
            if (size > 16) fseek(f, (long)(size - 16), SEEK_CUR);
        } else if (memcmp(chunk, "data", 4) == 0) {
            if (!have_fmt) break;
            *data_offset = ftell(f);
            *frames = (int64_t)size / 2;   // 2 bytes per mono frame
            return f;
        } else {
            // Chunks are word-aligned, so an odd size is followed by a pad byte.
            fseek(f, (long)(size + (size & 1u)), SEEK_CUR);
        }
    }
    fclose(f);
    return NULL;
}

/// Opens [path] for writing and lays down a header with placeholder sizes,
/// patched by [wav_finish] once the length is known.
static FILE* wav_open_write(const char* path, int sample_rate) {
    FILE* f = fopen(path, "wb");
    if (!f) return NULL;
    const uint32_t byte_rate = (uint32_t)sample_rate * 2u;
    unsigned char h[44];
    memcpy(h, "RIFF", 4);
    memset(h + 4, 0, 4);                    // patched later
    memcpy(h + 8, "WAVEfmt ", 8);
    h[16] = 16; h[17] = 0; h[18] = 0; h[19] = 0;   // fmt chunk size
    h[20] = 1;  h[21] = 0;                          // PCM
    h[22] = 1;  h[23] = 0;                          // mono
    h[24] = (unsigned char)(sample_rate & 0xFF);
    h[25] = (unsigned char)((sample_rate >> 8) & 0xFF);
    h[26] = (unsigned char)((sample_rate >> 16) & 0xFF);
    h[27] = (unsigned char)((sample_rate >> 24) & 0xFF);
    h[28] = (unsigned char)(byte_rate & 0xFF);
    h[29] = (unsigned char)((byte_rate >> 8) & 0xFF);
    h[30] = (unsigned char)((byte_rate >> 16) & 0xFF);
    h[31] = (unsigned char)((byte_rate >> 24) & 0xFF);
    h[32] = 2;  h[33] = 0;                          // block align
    h[34] = 16; h[35] = 0;                          // bits per sample
    memcpy(h + 36, "data", 4);
    memset(h + 40, 0, 4);                   // patched later
    if (fwrite(h, 1, 44, f) != 44) { fclose(f); return NULL; }
    return f;
}

/// Patches the two size fields and closes the file.
static void wav_finish(FILE* f, int64_t frames) {
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
    fclose(f);
}

// ─── Track state ─────────────────────────────────────────────────────────────

/// One streamed take.
///
/// Every take is aligned to grid frame 0 by construction, so a track's file
/// frame index *is* the grid position — there is no per-track offset to carry.
typedef struct {
    int    active;
    FILE*  file;
    long   data_offset;      ///< Byte offset of the first audio frame.
    int64_t frames;          ///< Length of the take.

    float  ring[GF_REH_RING_FRAMES];
    /// Grid frame the worker has filled up to (exclusive). Only the worker
    /// writes this; the audio thread only reads it.
    volatile int64_t fill_pos;

    volatile float gain;
    volatile int   muted;
    volatile float peak;
} Track;

/// Frames of microphone input held between the audio thread and the worker.
/// About 1.4 s at 48 kHz — far more than any scheduling gap, and the cost is
/// one buffer rather than one per track.
#define GF_REH_REC_RING_FRAMES 65536

typedef struct {
    int sample_rate;
    int created;

    // Grid.
    double bpm;
    int beats_per_bar;
    int beat_unit;

    Track tracks[GF_REH_MAX_TRACKS];

    // Transport. `position` is signed: negative is the count-in.
    volatile int64_t position;
    volatile int state;

    // Metronome.
    volatile int metronome_on;
    volatile float metronome_gain;
    float* click_hi;         ///< Downbeat click.
    float* click_lo;         ///< Other beats.
    int click_frames;

    // Recording.
    FILE* rec_file;
    volatile int rec_armed;          ///< Set until the transport reaches 0.
    volatile int compensation;
    volatile int64_t rec_frames;     ///< Frames committed to the take.
    /// Input frames seen since the transport crossed grid 0, used to drop the
    /// first `compensation` of them.
    volatile int64_t rec_input_seen;
    float rec_ring[GF_REH_REC_RING_FRAMES];
    volatile int64_t rec_write;      ///< Audio thread writes here.
    volatile int64_t rec_read;       ///< Worker drains from here.
    volatile float input_peak;

    // Worker.
    gf_thread worker;
    gf_mutex lock;                   ///< Guards track add/remove against fills.
    volatile int worker_run;
    int worker_started;
} Engine;

static Engine g_e;

// ─── Grid helpers ────────────────────────────────────────────────────────────

int gf_reh_frames_per_beat(void) {
    if (g_e.bpm <= 0.0) return 0;
    return (int)((60.0 / g_e.bpm) * (double)g_e.sample_rate + 0.5);
}

int gf_reh_frames_per_bar(void) {
    return gf_reh_frames_per_beat() * g_e.beats_per_bar;
}

void gf_reh_set_grid(double bpm, int beats_per_bar, int beat_unit) {
    // Refused while running: every existing take is already aligned to the
    // current grid, and moving it underneath them would put every part in the
    // wrong place with no way to tell from the audio which grid it was cut to.
    if (g_e.state != GF_REH_STOPPED) return;
    if (bpm < 20.0 || bpm > 400.0) return;
    if (beats_per_bar < 1 || beats_per_bar > 32) return;
    g_e.bpm = bpm;
    g_e.beats_per_bar = beats_per_bar;
    g_e.beat_unit = beat_unit;
}

// ─── Metronome clicks ────────────────────────────────────────────────────────

/// Renders one click: a short sine burst with a fast decay.
///
/// Two pitches rather than one, because on headphones in a quiet room the
/// downbeat is the only cue a player has for where the bar starts.
static void render_click(float* out, int frames, int sample_rate, float hz) {
    for (int i = 0; i < frames; i++) {
        const double t = (double)i / (double)sample_rate;
        // 40 ms exponential decay: audible, over before the next sixteenth.
        const double env = exp(-t * 25.0);
        out[i] = (float)(sin(2.0 * M_PI * (double)hz * t) * env * 0.7);
    }
}

// ─── Track streaming ─────────────────────────────────────────────────────────

/// Reads [count] frames from [t] starting at file frame [from] into the ring.
/// Converts 16-bit to float once, here, so the audio thread never has to.
static void fill_track_range(Track* t, int64_t from, int count) {
    if (count <= 0) return;
    static int16_t scratch[4096];

    while (count > 0) {
        const int chunk = count > 4096 ? 4096 : count;
        int got = 0;
        if (from < t->frames && t->file) {
            if (fseek(t->file, t->data_offset + (long)(from * 2), SEEK_SET) == 0) {
                got = (int)fread(scratch, 2, (size_t)chunk, t->file);
            }
        }
        for (int i = 0; i < chunk; i++) {
            const int64_t idx = (from + i) % GF_REH_RING_FRAMES;
            // Past the end of the take, or a short read: silence rather than
            // stale ring content, which would loop the last block forever.
            t->ring[idx] = (i < got) ? (float)scratch[i] / 32768.0f : 0.0f;
        }
        from += chunk;
        count -= chunk;
    }
}

/// Brings one track's ring up to [target] frames ahead of the playhead.
static void service_track(Track* t, int64_t pos) {
    if (!t->active) return;
    const int64_t want = pos + GF_REH_RING_FRAMES;
    if (t->fill_pos >= want) return;

    // A seek (or a fresh start) leaves fill_pos far from the playhead; refill
    // from the playhead rather than reading everything in between.
    if (t->fill_pos < pos || t->fill_pos > want) t->fill_pos = pos;

    const int64_t need = want - t->fill_pos;
    fill_track_range(t, t->fill_pos, (int)need);
    t->fill_pos = want;
}

/// Fills every track's ring and drains the record ring to disk.
static void service_all(void) {
    const int64_t pos = g_e.position > 0 ? g_e.position : 0;

    gf_mutex_lock(&g_e.lock);
    for (int i = 0; i < GF_REH_MAX_TRACKS; i++) service_track(&g_e.tracks[i], pos);

    // Drain captured audio. Converting to 16-bit here keeps the audio thread
    // free of it, and writing in whatever size has accumulated keeps the file
    // pointer moving forwards.
    if (g_e.rec_file) {
        static int16_t out[4096];
        while (g_e.rec_read < g_e.rec_write) {
            int64_t avail = g_e.rec_write - g_e.rec_read;
            if (avail > 4096) avail = 4096;
            for (int64_t i = 0; i < avail; i++) {
                float v = g_e.rec_ring[(g_e.rec_read + i) % GF_REH_REC_RING_FRAMES];
                if (v > 1.0f) v = 1.0f;
                if (v < -1.0f) v = -1.0f;
                out[i] = (int16_t)(v * 32767.0f);
            }
            fwrite(out, 2, (size_t)avail, g_e.rec_file);
            g_e.rec_read += avail;
        }
    }
    gf_mutex_unlock(&g_e.lock);
}

#if defined(_WIN32)
static DWORD WINAPI worker_main(LPVOID arg) {
#else
static void* worker_main(void* arg) {
#endif
    (void)arg;
    while (g_e.worker_run) {
        service_all();
        // 5 ms is far tighter than the ~680 ms the rings hold, so a late wake
        // never starves playback, and the thread stays close to idle.
        gf_sleep_ms(5);
    }
#if defined(_WIN32)
    return 0;
#else
    return NULL;
#endif
}

// ─── Lifecycle ───────────────────────────────────────────────────────────────

int gf_reh_create(int sample_rate) {
    if (g_e.created) return 0;
    memset(&g_e, 0, sizeof(g_e));
    g_e.sample_rate = sample_rate > 0 ? sample_rate : 48000;
    g_e.bpm = 120.0;
    g_e.beats_per_bar = 4;
    g_e.beat_unit = 4;
    g_e.metronome_on = 1;
    g_e.metronome_gain = 0.6f;
    g_e.state = GF_REH_STOPPED;

    // Clicks are rendered once, at create, so the audio thread only ever mixes
    // a pre-computed buffer.
    g_e.click_frames = g_e.sample_rate / 10;   // 100 ms of decay tail
    g_e.click_hi = (float*)calloc((size_t)g_e.click_frames, sizeof(float));
    g_e.click_lo = (float*)calloc((size_t)g_e.click_frames, sizeof(float));
    if (!g_e.click_hi || !g_e.click_lo) {
        free(g_e.click_hi); free(g_e.click_lo);
        return -1;
    }
    render_click(g_e.click_hi, g_e.click_frames, g_e.sample_rate, 1600.0f);
    render_click(g_e.click_lo, g_e.click_frames, g_e.sample_rate, 900.0f);

    gf_mutex_init(&g_e.lock);
    g_e.worker_run = 1;
#if defined(_WIN32)
    g_e.worker = CreateThread(NULL, 0, worker_main, NULL, 0, NULL);
    g_e.worker_started = g_e.worker != NULL;
#else
    g_e.worker_started = pthread_create(&g_e.worker, NULL, worker_main, NULL) == 0;
#endif
    g_e.created = 1;
    return 0;
}

void gf_reh_destroy(void) {
    if (!g_e.created) return;
    gf_reh_stop();
    g_e.worker_run = 0;
    if (g_e.worker_started) {
#if defined(_WIN32)
        WaitForSingleObject(g_e.worker, 2000);
        CloseHandle(g_e.worker);
#else
        pthread_join(g_e.worker, NULL);
#endif
    }
    gf_reh_clear_tracks();
    free(g_e.click_hi);
    free(g_e.click_lo);
    gf_mutex_free(&g_e.lock);
    memset(&g_e, 0, sizeof(g_e));
}

// ─── Tracks ──────────────────────────────────────────────────────────────────

int gf_reh_add_track(const char* wav_path) {
    if (!g_e.created || !wav_path) return -2;

    long offset = 0;
    int64_t frames = 0;
    int rate = 0;
    FILE* f = wav_open_read(wav_path, &offset, &frames, &rate);
    if (!f) return -3;

    gf_mutex_lock(&g_e.lock);
    int slot = -1;
    for (int i = 0; i < GF_REH_MAX_TRACKS; i++) {
        if (!g_e.tracks[i].active) { slot = i; break; }
    }
    if (slot < 0) {
        gf_mutex_unlock(&g_e.lock);
        fclose(f);
        return -1;
    }
    Track* t = &g_e.tracks[slot];
    memset(t, 0, sizeof(*t));
    t->file = f;
    t->data_offset = offset;
    t->frames = frames;
    t->gain = 1.0f;
    t->muted = 0;
    // Forces the first service pass to fill from the playhead rather than
    // trusting a fill_pos left behind by a previous occupant of the slot.
    t->fill_pos = -1;
    t->active = 1;
    gf_mutex_unlock(&g_e.lock);
    return slot;
}

void gf_reh_remove_track(int idx) {
    if (idx < 0 || idx >= GF_REH_MAX_TRACKS) return;
    gf_mutex_lock(&g_e.lock);
    Track* t = &g_e.tracks[idx];
    if (t->active) {
        t->active = 0;
        if (t->file) fclose(t->file);
        t->file = NULL;
    }
    gf_mutex_unlock(&g_e.lock);
}

void gf_reh_clear_tracks(void) {
    for (int i = 0; i < GF_REH_MAX_TRACKS; i++) gf_reh_remove_track(i);
}

void gf_reh_set_track_gain(int idx, float gain) {
    if (idx < 0 || idx >= GF_REH_MAX_TRACKS) return;
    if (gain < 0.0f) gain = 0.0f;
    if (gain > 2.0f) gain = 2.0f;
    g_e.tracks[idx].gain = gain;
}

void gf_reh_set_track_mute(int idx, int muted) {
    if (idx < 0 || idx >= GF_REH_MAX_TRACKS) return;
    g_e.tracks[idx].muted = muted ? 1 : 0;
}

int64_t gf_reh_track_frames(int idx) {
    if (idx < 0 || idx >= GF_REH_MAX_TRACKS || !g_e.tracks[idx].active) return 0;
    return g_e.tracks[idx].frames;
}

float gf_reh_track_peak(int idx) {
    if (idx < 0 || idx >= GF_REH_MAX_TRACKS) return 0.0f;
    const float p = g_e.tracks[idx].peak;
    g_e.tracks[idx].peak = 0.0f;
    return p;
}

void gf_reh_set_metronome(int enabled, float gain) {
    g_e.metronome_on = enabled ? 1 : 0;
    if (gain < 0.0f) gain = 0.0f;
    if (gain > 1.0f) gain = 1.0f;
    g_e.metronome_gain = gain;
}

// ─── Transport ───────────────────────────────────────────────────────────────

int gf_reh_play(int64_t start_frame) {
    if (!g_e.created) return -1;
    gf_reh_stop();
    g_e.position = start_frame;
    // Every ring is stale after a seek; -1 makes the next service pass refill
    // from the new playhead instead of trusting what is there.
    for (int i = 0; i < GF_REH_MAX_TRACKS; i++) g_e.tracks[i].fill_pos = -1;
    g_e.state = GF_REH_PLAYING;
    return 0;
}

int gf_reh_record(const char* wav_path, int compensation_frames,
                  int count_in_bars) {
    if (!g_e.created || !wav_path) return -1;
    gf_reh_stop();

    FILE* f = wav_open_write(wav_path, g_e.sample_rate);
    if (!f) return -2;

    gf_mutex_lock(&g_e.lock);
    g_e.rec_file = f;
    g_e.rec_frames = 0;
    g_e.rec_input_seen = 0;
    g_e.rec_read = 0;
    g_e.rec_write = 0;
    g_e.compensation = compensation_frames > 0 ? compensation_frames : 0;
    gf_mutex_unlock(&g_e.lock);

    if (count_in_bars < 0) count_in_bars = 0;
    // Start the transport that many bars *before* the downbeat, so a single
    // signed position covers "click for two bars, then play".
    g_e.position = -(int64_t)count_in_bars * gf_reh_frames_per_bar();
    for (int i = 0; i < GF_REH_MAX_TRACKS; i++) g_e.tracks[i].fill_pos = -1;
    g_e.rec_armed = 1;
    g_e.state = (g_e.position < 0) ? GF_REH_COUNT_IN : GF_REH_RECORDING;
    return 0;
}

void gf_reh_stop(void) {
    if (!g_e.created) return;
    const int was = g_e.state;
    g_e.state = GF_REH_STOPPED;
    g_e.rec_armed = 0;
    if (was == GF_REH_STOPPED && !g_e.rec_file) return;

    // Let the worker flush whatever the audio thread left in the record ring
    // before the header is patched, or the take loses its tail.
    for (int spins = 0; spins < 200; spins++) {
        gf_mutex_lock(&g_e.lock);
        const int drained = (g_e.rec_read >= g_e.rec_write);
        gf_mutex_unlock(&g_e.lock);
        if (drained) break;
        gf_sleep_ms(5);
    }

    gf_mutex_lock(&g_e.lock);
    if (g_e.rec_file) {
        wav_finish(g_e.rec_file, g_e.rec_frames);
        g_e.rec_file = NULL;
    }
    gf_mutex_unlock(&g_e.lock);
}

int64_t gf_reh_position(void)        { return g_e.position; }
int     gf_reh_state(void)           { return g_e.state; }
int64_t gf_reh_recorded_frames(void) { return g_e.rec_frames; }

float gf_reh_input_peak(void) {
    const float p = g_e.input_peak;
    g_e.input_peak = 0.0f;
    return p;
}

// ─── Rendering ───────────────────────────────────────────────────────────────

/// Mixes the metronome for the block starting at [pos].
///
/// The click that belongs to a beat may have started in an earlier block and
/// still be decaying, so this walks back one click length rather than only
/// looking at beats that begin inside this block — otherwise every click would
/// be truncated at the block boundary.
static void mix_metronome(float* out, int frames, int64_t pos) {
    if (!g_e.metronome_on) return;
    const int fpb = gf_reh_frames_per_beat();
    if (fpb <= 0) return;

    const int64_t first = pos - g_e.click_frames;
    int64_t beat = first >= 0 ? (first / fpb) : ((first - fpb + 1) / fpb);

    for (; beat * fpb < pos + frames; beat++) {
        const int64_t start = beat * fpb;
        // Which beat of the bar this is, for negative positions too — C
        // truncates towards zero, so a plain % gives 0, -1, -2 during a
        // count-in and the downbeat click would land on the wrong beat.
        int64_t in_bar = beat % g_e.beats_per_bar;
        if (in_bar < 0) in_bar += g_e.beats_per_bar;
        const float* click = (in_bar == 0) ? g_e.click_hi : g_e.click_lo;

        for (int i = 0; i < frames; i++) {
            const int64_t rel = (pos + i) - start;
            if (rel < 0 || rel >= g_e.click_frames) continue;
            out[i] += click[rel] * g_e.metronome_gain;
        }
    }
}

/// Shared body of the real-time and offline render paths.
static void render_common(float* outL, float* outR, int frames, int offline) {
    if (!outL || frames <= 0) return;
    memset(outL, 0, sizeof(float) * (size_t)frames);

    const int64_t pos = g_e.position;
    const int running = (g_e.state != GF_REH_STOPPED);

    if (running) {
        for (int ti = 0; ti < GF_REH_MAX_TRACKS; ti++) {
            Track* t = &g_e.tracks[ti];
            if (!t->active) continue;

            // Offline runs faster than real time, so the worker can never fill
            // ahead; the reads happen here instead.
            if (offline) service_track(t, pos > 0 ? pos : 0);
            if (t->muted) continue;

            const float g = t->gain;
            float peak = t->peak;
            for (int i = 0; i < frames; i++) {
                const int64_t p = pos + i;
                if (p < 0 || p >= t->frames) continue;
                // Nothing filled this far yet: an underrun. Silence for this
                // frame, and the transport keeps its timing rather than
                // stalling, which would desynchronise every other track.
                if (p >= t->fill_pos) continue;
                const float s = t->ring[p % GF_REH_RING_FRAMES] * g;
                outL[i] += s;
                const float a = s < 0 ? -s : s;
                if (a > peak) peak = a;
            }
            t->peak = peak;
        }

        mix_metronome(outL, frames, pos);
        g_e.position = pos + frames;

        // Crossing zero ends the count-in and begins committing the take.
        if (g_e.state == GF_REH_COUNT_IN && g_e.position >= 0) {
            g_e.state = GF_REH_RECORDING;
        }
    }

    // Mono engine, stereo bus: the same signal to both ears.
    if (outR) memcpy(outR, outL, sizeof(float) * (size_t)frames);
}

void gf_reh_render(float* outL, float* outR, int frames) {
    render_common(outL, outR, frames, 0);
}

void gf_reh_render_offline(float* outL, float* outR, int frames) {
    render_common(outL, outR, frames, 1);
}

void gf_reh_feed_input(const float* in, int frames) {
    if (!in || frames <= 0 || !g_e.created) return;

    float peak = g_e.input_peak;
    for (int i = 0; i < frames; i++) {
        const float a = in[i] < 0 ? -in[i] : in[i];
        if (a > peak) peak = a;
    }
    g_e.input_peak = peak;

    if (g_e.state != GF_REH_RECORDING || !g_e.rec_armed) return;

    for (int i = 0; i < frames; i++) {
        const int64_t seen = g_e.rec_input_seen + i;
        // Drop the first `compensation` frames. What the player performed on
        // the downbeat arrives that many frames after it, so dropping them is
        // what puts the downbeat at frame 0 of the take.
        if (seen < g_e.compensation) continue;

        const int64_t at = g_e.rec_write;
        // A full ring means the worker has stalled. Dropping the newest frame
        // keeps what has already been written intact; overwriting would
        // corrupt audio that is on its way to disk.
        if (at - g_e.rec_read >= GF_REH_REC_RING_FRAMES) break;
        g_e.rec_ring[at % GF_REH_REC_RING_FRAMES] = in[i];
        g_e.rec_write = at + 1;
        g_e.rec_frames++;
    }
    g_e.rec_input_seen += frames;
}
