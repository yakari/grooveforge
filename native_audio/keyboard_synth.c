/**
 * keyboard_synth.c — FluidSynth-based GF Keyboard audio engine (Linux only).
 *
 * Replaces the external FluidSynth subprocess with an in-process library call
 * so that the ALSA audio thread in dart_vst_host can drive rendering via
 * keyboard_render_block() — the same "external render" mechanism used by the
 * Theremin and Stylophone.
 *
 * Audio architecture:
 *   - FluidSynth is created with audio.driver = "none" (no built-in output).
 *   - dart_vst_host calls keyboard_render_block() each ALSA block, which
 *     calls fluid_synth_write_float() to advance the synth and fill L/R buffers.
 *   - When a GF Keyboard slot is NOT routed into a VST3 effect, dart_vst_host
 *     adds keyboard_render_block to its master-mix render list, mixing the
 *     keyboard audio directly into the ALSA output.
 *   - When the slot IS routed into a VST3 effect, dart_vst_host uses
 *     keyboard_render_block as the effect's external-render source instead.
 *
 * Non-Linux platforms continue using flutter_midi_pro; all functions below
 * are no-op stubs on those platforms.
 */

#if defined(_WIN32)
  #define EXPORT __declspec(dllexport)
#else
  #define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __linux__

#include <fluidsynth.h>
#include <string.h>
#include <stdio.h>

/** Global FluidSynth settings and synth instances — shared across all GF
 *  Keyboard rack slots (which simply use different MIDI channels). */
static fluid_settings_t* g_settings = NULL;
static fluid_synth_t*    g_synth    = NULL;

/**
 * Initialise the FluidSynth engine at [sampleRate] Hz.
 *
 * Must be called once before any other keyboard_* function. The synth is
 * created with no audio driver so that audio output is fully manual via
 * keyboard_render_block(). Safe to call multiple times — subsequent calls
 * are no-ops if already initialised.
 *
 * Returns 1 on success, 0 on failure.
 */
EXPORT int keyboard_init(float sampleRate) {
    if (g_synth) return 1; // already initialised

    g_settings = new_fluid_settings();
    fluid_settings_setnum(g_settings, "synth.sample-rate", (double)sampleRate);
    fluid_settings_setint(g_settings, "synth.midi-channels", 16);
    // "none" disables the built-in audio output; we drive rendering manually.
    fluid_settings_setstr(g_settings, "audio.driver", "none");

    g_synth = new_fluid_synth(g_settings);
    if (!g_synth) {
        delete_fluid_settings(g_settings);
        g_settings = NULL;
        fprintf(stderr, "[keyboard_synth] ERROR: new_fluid_synth() failed\n");
        return 0;
    }

    fprintf(stderr, "[keyboard_synth] FluidSynth initialised (sr=%.0f, no audio driver)\n",
            (double)sampleRate);
    return 1;
}

/**
 * Destroy the FluidSynth engine and free all resources.
 *
 * Any loaded soundfonts are automatically freed. After this call, all other
 * keyboard_* functions are no-ops until keyboard_init() is called again.
 */
EXPORT void keyboard_destroy(void) {
    if (g_synth)    { delete_fluid_synth(g_synth);       g_synth    = NULL; }
    if (g_settings) { delete_fluid_settings(g_settings); g_settings = NULL; }
}

/**
 * Load a SoundFont (.sf2) file and return its FluidSynth soundfont ID.
 *
 * [path] must be an absolute path to a valid .sf2 file.
 * Returns a positive sfId on success, -1 on failure.
 * Passing reset=1 resets all channel presets to the new soundfont.
 */
EXPORT int keyboard_load_sf(const char* path) {
    if (!g_synth) return -1;
    int sfId = (int)fluid_synth_sfload(g_synth, path, /*reset_presets=*/1);
    fprintf(stderr, "[keyboard_synth] load_sf '%s' → sfId=%d\n", path, sfId);
    return sfId;
}

/**
 * Unload a previously loaded SoundFont by its FluidSynth ID.
 *
 * Passing reset=1 clears any channel assignments that referenced this font.
 */
EXPORT void keyboard_unload_sf(int sfId) {
    if (g_synth) fluid_synth_sfunload(g_synth, (unsigned int)sfId, /*reset_presets=*/1);
}

/**
 * Assign an instrument patch to a MIDI channel.
 *
 * [channel] 0–15, [sfId] from keyboard_load_sf(), [bank] and [program]
 * are standard General MIDI bank/program numbers.
 */
EXPORT void keyboard_program_select(int channel, int sfId, int bank, int program) {
    if (g_synth) {
        fluid_synth_program_select(g_synth, channel,
                                   (unsigned int)sfId,
                                   (unsigned int)bank,
                                   (unsigned int)program);
    }
}

/** Send a MIDI note-on event: [channel] 0–15, [key] 0–127, [velocity] 1–127. */
EXPORT void keyboard_note_on(int channel, int key, int velocity) {
    if (g_synth) fluid_synth_noteon(g_synth, channel, key, velocity);
}

/** Send a MIDI note-off event: [channel] 0–15, [key] 0–127. */
EXPORT void keyboard_note_off(int channel, int key) {
    if (g_synth) fluid_synth_noteoff(g_synth, channel, key);
}

/**
 * Send a MIDI pitch-bend value.
 *
 * [value] is the 14-bit MIDI pitch-bend word (0–16383, centre 8192),
 * which matches the raw value forwarded by AudioEngine.
 */
EXPORT void keyboard_pitch_bend(int channel, int value) {
    if (g_synth) fluid_synth_pitch_bend(g_synth, channel, value);
}

/** Send a MIDI Control Change: [cc] 0–127, [value] 0–127. */
EXPORT void keyboard_control_change(int channel, int cc, int value) {
    if (g_synth) fluid_synth_cc(g_synth, channel, cc, value);
}

/**
 * Set the master output gain of the FluidSynth engine.
 *
 * [gain] is a linear scalar (FluidSynth default is 0.2; GrooveForge default
 * is 3.0 on Linux to match VST3 output levels).
 */
EXPORT void keyboard_set_gain(float gain) {
    if (g_synth) fluid_synth_set_gain(g_synth, gain);
}

/**
 * Render one block of stereo audio into [outL] and [outR].
 *
 * Called by the dart_vst_host ALSA thread every block — either as a
 * master-mix contributor (keyboard not routed into a VST3 effect) or as an
 * external-render source for a downstream VST3 effect. [frames] matches the
 * ALSA block size (typically 256 samples at 48 kHz).
 *
 * Uses non-interleaved output: fluid_synth_write_float() strides are 1,
 * writing directly into the provided float arrays.
 */
EXPORT void keyboard_render_block(float* outL, float* outR, int frames) {
    if (!g_synth) {
        // Synth not ready — output silence to avoid noise.
        memset(outL, 0, (size_t)frames * sizeof(float));
        memset(outR, 0, (size_t)frames * sizeof(float));
        return;
    }
    // fluid_synth_write_float(synth, len, lbuf, loff, lstride, rbuf, roff, rstride)
    fluid_synth_write_float(g_synth, frames, outL, 0, 1, outR, 0, 1);
}

#else // !__linux__ ─────────────────────────────────────────────────────────

// Non-Linux stubs — keyboard audio is handled by flutter_midi_pro on those
// platforms and never flows through the dart_vst_host ALSA loop.

#include <string.h>

EXPORT int  keyboard_init(float sr)                                    { return 0; }
EXPORT void keyboard_destroy(void)                                     {}
EXPORT int  keyboard_load_sf(const char* p)                           { (void)p; return -1; }
EXPORT void keyboard_unload_sf(int id)                                 { (void)id; }
EXPORT void keyboard_program_select(int c, int s, int b, int p)        { (void)c;(void)s;(void)b;(void)p; }
EXPORT void keyboard_note_on(int c, int k, int v)                     { (void)c;(void)k;(void)v; }
EXPORT void keyboard_note_off(int c, int k)                           { (void)c;(void)k; }
EXPORT void keyboard_pitch_bend(int c, int v)                         { (void)c;(void)v; }
EXPORT void keyboard_control_change(int c, int cc, int v)             { (void)c;(void)cc;(void)v; }
EXPORT void keyboard_set_gain(float g)                                { (void)g; }
EXPORT void keyboard_render_block(float* l, float* r, int f) {
    memset(l, 0, (size_t)f * sizeof(float));
    memset(r, 0, (size_t)f * sizeof(float));
}

#endif // __linux__
