/**
 * keyboard_synth.c — FluidSynth-based GF Keyboard audio engine (Linux + macOS).
 *
 * Audio architecture (Linux ALSA / macOS CoreAudio):
 *   - Up to MAX_KB_SLOTS isolated FluidSynth instances, one per GF Keyboard
 *     rack slot.  MIDI channel n maps to slot n % MAX_KB_SLOTS.
 *   - dart_vst_host registers keyboard_render_block_N() as a master-render
 *     contributor for slot N.  Because each slot has a unique C function
 *     address, dart_vst_host can attach a GFPA insert effect to slot N without
 *     that effect bleeding into slot M (N ≠ M).
 *   - Backward-compat wrappers (keyboard_init / keyboard_render_block) operate
 *     on slot 0 so existing single-keyboard code paths are unchanged.
 *
 * macOS: glib's g_slice allocator corrupts Swift/ObjC heap metadata.
 * setenv("G_SLICE","always-malloc",1) is called in AppDelegate.swift
 * (applicationWillFinishLaunching) and again inside keyboard_init_slot() as a
 * belt-and-suspenders fallback.
 *
 * Android and other platforms use flutter_midi_pro; all functions below are
 * no-op stubs on those platforms.
 */

#if defined(_WIN32)
  #define EXPORT __declspec(dllexport)
#else
  #define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

// FluidSynth is available on Linux and macOS desktop.
// Android also defines __linux__, so we explicitly exclude it.
#if (defined(__linux__) || defined(__APPLE__)) && !defined(__ANDROID__)

#include <fluidsynth.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// ── Constants ─────────────────────────────────────────────────────────────────

/** Maximum number of concurrent GF Keyboard slots (FluidSynth instances).
 *  Slot 0 = even MIDI channels (0,2,4,6,8,10,12,14) — GF Keyboard 1.
 *  Slot 1 = odd MIDI channels EXCEPT 9 (1,3,5,7,11,13,15) — GF Keyboard 2.
 *  Slot 2 = channel 9 only — GM percussion (metronome, drum generator).
 *  Isolating channel 9 prevents metronome clicks from bleeding into keyboard
 *  renders when the audio looper captures a keyboard slot.
 */
#define MAX_KB_SLOTS 3

/** Maximum number of soundfonts that can be loaded globally. */
#define MAX_LOADED_SF 16

// ── Per-slot state ────────────────────────────────────────────────────────────

typedef struct {
    fluid_settings_t* settings;
    fluid_synth_t*    synth;
    int               in_use; ///< 1 = active FluidSynth instance, 0 = free.
} KbSlot;

static KbSlot g_kb_slots[MAX_KB_SLOTS];

/**
 * Last gain value applied via keyboard_set_gain().
 * Stored so that newly created slots (slot 1 is initialised lazily when the
 * second keyboard plugin first appears in syncAudioRouting) receive the same
 * gain as slot 0, which is set up earlier during audio engine initialisation.
 * Default matches FluidSynth's factory default.
 */
static float g_current_gain = 0.2f;

/**
 * Ordered list of soundfont paths loaded so far.
 * When a new slot is created, all paths are replayed into it so that
 * sfIds stay consistent across slots (equal load order → equal sfIds).
 */
static char g_loaded_sf_paths[MAX_LOADED_SF][512];
static int  g_loaded_sf_count = 0;

// ── Internal helpers ──────────────────────────────────────────────────────────

/** Returns the slot index that owns [channel] (0-based MIDI channel 0–15).
 *  Channel 9 (GM percussion) is isolated in slot 2 so metronome clicks
 *  don't bleed into keyboard renders captured by the audio looper.
 */
static int _slot_for_channel(int channel) {
    if (channel == 9) return 2;
    return channel % 2;
}

/**
 * Aggressively disable reverb and chorus on [slot->synth].
 *
 * Three independent layers so macOS FluidSynth 2.5.3 cannot sneak reverb back:
 *   1. fluid_synth_reverb_on / fluid_synth_chorus_on with explicit fx_group=0
 *      (the group all 16 channels belong to by default).  Using -1 ("all groups")
 *      was silently ignored on Homebrew FluidSynth 2.5.3.
 *   2. fluid_synth_set_reverb_group_level / _chorus_group_level → 0.0 so even
 *      if the unit is somehow still active its output contribution is zero.
 *   3. Called again after every fluid_synth_sfload because loading a soundfont
 *      with reset_presets=1 can restore the internal reverb state.
 *
 * Must only be called when slot->synth is non-NULL.
 */
static void _disable_reverb_chorus(KbSlot* slot) {
    // Layer 1 — toggle the FX unit off for the default FX group (0).
    fluid_synth_reverb_on(slot->synth, 0, 0);
    fluid_synth_chorus_on(slot->synth, 0, 0);
    // Layer 2 — zero output level for ALL FX groups (-1 = all groups is valid
    // for the *_group_level variants even if it is not for *_on).
    fluid_synth_set_reverb_group_level(slot->synth, -1, 0.0);
    fluid_synth_set_chorus_group_level(slot->synth, -1, 0.0);
}

/**
 * Create a FluidSynth instance for [slot] at [sampleRate] Hz and replay all
 * previously loaded soundfonts into it so its sfIds match slot 0.
 *
 * The first soundfont is loaded with reset=1 to bootstrap channel assignments;
 * subsequent ones use reset=0 to preserve existing assignments.
 *
 * Returns 1 on success, 0 on failure.
 */
static int _create_synth(KbSlot* slot, float sampleRate) {
    slot->settings = new_fluid_settings();
    fluid_settings_setnum(slot->settings, "synth.sample-rate", (double)sampleRate);
    fluid_settings_setint(slot->settings, "synth.midi-channels", 16);
    fluid_settings_setstr(slot->settings, "audio.driver", "none");
    // Disable built-in reverb/chorus — these add a reverb tail that sounds like
    // a permanently-held sustain pedal.  GFPA effects are applied downstream.
    fluid_settings_setint(slot->settings, "synth.reverb.active", 0);
    fluid_settings_setint(slot->settings, "synth.chorus.active", 0);

    slot->synth = new_fluid_synth(slot->settings);
    if (!slot->synth) {
        delete_fluid_settings(slot->settings);
        slot->settings = NULL;
        return 0;
    }

    // Apply the current master gain so this slot matches existing slots.
    fluid_synth_set_gain(slot->synth, g_current_gain);

    // Replay all loaded soundfonts so sfIds match slot 0.
    for (int i = 0; i < g_loaded_sf_count; ++i) {
        // First SF gets reset=1 to bootstrap channel assignments on this fresh
        // synth; subsequent SFs use reset=0 to leave those assignments intact.
        int resetFlag = (i == 0) ? 1 : 0;
        fluid_synth_sfload(slot->synth, g_loaded_sf_paths[i], resetFlag);
    }

    // Disable reverb/chorus AFTER the sfload replay — loading a soundfont with
    // reset_presets=1 can restore FluidSynth's internal reverb state, so the
    // disable must come last to be authoritative.
    _disable_reverb_chorus(slot);

    slot->in_use = 1;
    return 1;
}

// ── Slot lifecycle API ────────────────────────────────────────────────────────

/**
 * Initialise FluidSynth slot [slotIdx] at [sampleRate] Hz.
 *
 * Safe to call multiple times — subsequent calls for an already-initialised
 * slot are no-ops.  Returns 1 on success (new or existing), 0 on failure.
 */
EXPORT int keyboard_init_slot(int slotIdx, float sampleRate) {
    if (slotIdx < 0 || slotIdx >= MAX_KB_SLOTS) return 0;
    KbSlot* slot = &g_kb_slots[slotIdx];
    if (slot->in_use) return 1; // already initialised

#ifdef __APPLE__
    // Belt-and-suspenders G_SLICE fix — AppDelegate.swift also sets this
    // before dyld loads libglib, which is the authoritative fix.
    setenv("G_SLICE", "always-malloc", 0);
#endif

    if (!_create_synth(slot, sampleRate)) {
        fprintf(stderr, "[keyboard_synth] ERROR: new_fluid_synth() failed for slot %d\n", slotIdx);
        return 0;
    }
    fprintf(stderr, "[keyboard_synth] FluidSynth slot %d initialised (sr=%.0f)\n",
            slotIdx, (double)sampleRate);
    return 1;
}

/**
 * Backward-compatible initialiser — creates slot 0 at [sampleRate] Hz.
 * Returns 1 on success, 0 on failure.
 */
EXPORT int keyboard_init(float sampleRate) {
    return keyboard_init_slot(0, sampleRate);
}

/** Destroy the FluidSynth instance for [slotIdx] and free its resources. */
EXPORT void keyboard_destroy_slot(int slotIdx) {
    if (slotIdx < 0 || slotIdx >= MAX_KB_SLOTS) return;
    KbSlot* slot = &g_kb_slots[slotIdx];
    if (!slot->in_use) return;
    if (slot->synth)    { delete_fluid_synth(slot->synth);       slot->synth    = NULL; }
    if (slot->settings) { delete_fluid_settings(slot->settings); slot->settings = NULL; }
    slot->in_use = 0;
}

/** Backward-compatible destructor — destroys slot 0. */
EXPORT void keyboard_destroy(void) {
    keyboard_destroy_slot(0);
}

// ── SoundFont management ──────────────────────────────────────────────────────

/**
 * Load a SoundFont into ALL active slots and record its path for future slots.
 *
 * Because every slot loads soundfonts in the same order, FluidSynth assigns
 * identical sfIds across all instances.  Dart needs only one path→sfId map.
 *
 * The first soundfont ever loaded uses reset=1 to bootstrap channel assignments;
 * subsequent ones use reset=0 so existing assignments are not wiped.
 *
 * Returns the sfId assigned by slot 0 on success, -1 on failure.
 */
EXPORT int keyboard_load_sf(const char* path) {
    if (!g_kb_slots[0].synth) return -1;

    // Record for future slot creation.
    if (g_loaded_sf_count < MAX_LOADED_SF) {
        strncpy(g_loaded_sf_paths[g_loaded_sf_count], path,
                sizeof(g_loaded_sf_paths[0]) - 1);
        g_loaded_sf_paths[g_loaded_sf_count][sizeof(g_loaded_sf_paths[0]) - 1] = '\0';
        ++g_loaded_sf_count;
    }

    // reset=1 only for the very first SF — bootstraps channel assignments on a
    // fresh synth.  Subsequent SFs use reset=0 to preserve existing assignments.
    int isFirst = (g_loaded_sf_count == 1);
    int sfId = (int)fluid_synth_sfload(g_kb_slots[0].synth, path, isFirst);
    fprintf(stderr, "[keyboard_synth] load_sf '%s' → sfId=%d (reset=%d)\n",
            path, sfId, isFirst);
    // sfload with reset=1 can restore FluidSynth's reverb state — re-disable.
    _disable_reverb_chorus(&g_kb_slots[0]);

    // Mirror into all other active slots.
    for (int i = 1; i < MAX_KB_SLOTS; ++i) {
        if (g_kb_slots[i].in_use && g_kb_slots[i].synth) {
            fluid_synth_sfload(g_kb_slots[i].synth, path, /*reset=*/0);
            _disable_reverb_chorus(&g_kb_slots[i]);
        }
    }
    return sfId;
}

/** Unload a SoundFont by [sfId] from ALL active slots. */
EXPORT void keyboard_unload_sf(int sfId) {
    for (int i = 0; i < MAX_KB_SLOTS; ++i) {
        if (g_kb_slots[i].in_use && g_kb_slots[i].synth) {
            fluid_synth_sfunload(g_kb_slots[i].synth, (unsigned int)sfId, /*reset=*/1);
        }
    }
}

// ── MIDI dispatch — routed to the correct slot via channel % MAX_KB_SLOTS ─────

/** Assign an instrument patch to MIDI [channel]. Routes to the owning slot. */
EXPORT void keyboard_program_select(int channel, int sfId, int bank, int program) {
    KbSlot* slot = &g_kb_slots[_slot_for_channel(channel)];
    if (slot->synth) {
        fluid_synth_program_select(slot->synth, channel,
                                   (unsigned int)sfId,
                                   (unsigned int)bank,
                                   (unsigned int)program);
    }
}

/** Send note-on to [channel]'s owning slot. */
EXPORT void keyboard_note_on(int channel, int key, int velocity) {
    KbSlot* slot = &g_kb_slots[_slot_for_channel(channel)];
    if (slot->synth) fluid_synth_noteon(slot->synth, channel, key, velocity);
}

/** Send note-off to [channel]'s owning slot. */
EXPORT void keyboard_note_off(int channel, int key) {
    KbSlot* slot = &g_kb_slots[_slot_for_channel(channel)];
    if (slot->synth) fluid_synth_noteoff(slot->synth, channel, key);
}

/** Send pitch-bend to [channel]'s owning slot. */
EXPORT void keyboard_pitch_bend(int channel, int value) {
    KbSlot* slot = &g_kb_slots[_slot_for_channel(channel)];
    if (slot->synth) fluid_synth_pitch_bend(slot->synth, channel, value);
}

/** Send control-change to [channel]'s owning slot. */
EXPORT void keyboard_control_change(int channel, int cc, int value) {
    KbSlot* slot = &g_kb_slots[_slot_for_channel(channel)];
    if (slot->synth) fluid_synth_cc(slot->synth, channel, cc, value);
}

/** Set the output gain on ALL active slots and remember it for future slots. */
EXPORT void keyboard_set_gain(float gain) {
    g_current_gain = gain;
    for (int i = 0; i < MAX_KB_SLOTS; ++i) {
        if (g_kb_slots[i].in_use && g_kb_slots[i].synth) {
            fluid_synth_set_gain(g_kb_slots[i].synth, gain);
        }
    }
}

// ── Per-slot render functions ─────────────────────────────────────────────────
//
// Each slot gets its own static C function so that dart_vst_host can attach
// a GFPA insert effect to exactly one slot without it bleeding into others.
// A unique C function address is required because the insert chain is keyed
// on the render function pointer.

/** Render one block from slot 0 into [outL]/[outR]. */
EXPORT void keyboard_render_block_0(float* outL, float* outR, int frames) {
    KbSlot* slot = &g_kb_slots[0];
    if (!slot->synth) {
        memset(outL, 0, (size_t)frames * sizeof(float));
        memset(outR, 0, (size_t)frames * sizeof(float));
        return;
    }
    fluid_synth_write_float(slot->synth, frames, outL, 0, 1, outR, 0, 1);
}

/** Render one block from slot 1 into [outL]/[outR]. */
EXPORT void keyboard_render_block_1(float* outL, float* outR, int frames) {
    KbSlot* slot = &g_kb_slots[1];
    if (!slot->synth) {
        memset(outL, 0, (size_t)frames * sizeof(float));
        memset(outR, 0, (size_t)frames * sizeof(float));
        return;
    }
    fluid_synth_write_float(slot->synth, frames, outL, 0, 1, outR, 0, 1);
}

/** Render one block from slot 2 (GM percussion / metronome). */
EXPORT void keyboard_render_block_2(float* outL, float* outR, int frames) {
    KbSlot* slot = &g_kb_slots[2];
    if (!slot->synth) {
        memset(outL, 0, (size_t)frames * sizeof(float));
        memset(outR, 0, (size_t)frames * sizeof(float));
        return;
    }
    fluid_synth_write_float(slot->synth, frames, outL, 0, 1, outR, 0, 1);
}

/**
 * Return the render function pointer for [slotIdx].
 *
 * Dart stores this as the key for dart_vst_host insert-chain registration,
 * ensuring effects are scoped to one keyboard slot only.
 */
EXPORT void* keyboard_render_fn_for_slot(int slotIdx) {
    switch (slotIdx) {
        case 0: return (void*)keyboard_render_block_0;
        case 1: return (void*)keyboard_render_block_1;
        case 2: return (void*)keyboard_render_block_2;
        default: return NULL;
    }
}

/**
 * Backward-compatible render — renders slot 0 only.
 * Kept so existing code that holds a pointer to keyboard_render_block continues
 * to work; new code should use keyboard_render_fn_for_slot(slotIdx).
 */
EXPORT void keyboard_render_block(float* outL, float* outR, int frames) {
    keyboard_render_block_0(outL, outR, frames);
}

#else // ── Stub implementations for Android / other platforms ─────────────────

#include <string.h>

EXPORT int   keyboard_init_slot(int i, float sr)                       { (void)i;(void)sr; return 0; }
EXPORT int   keyboard_init(float sr)                                   { (void)sr; return 0; }
EXPORT void  keyboard_destroy_slot(int i)                              { (void)i; }
EXPORT void  keyboard_destroy(void)                                    {}
EXPORT int   keyboard_load_sf(const char* p)                          { (void)p; return -1; }
EXPORT void  keyboard_unload_sf(int id)                                { (void)id; }
EXPORT void  keyboard_program_select(int c, int s, int b, int p)       { (void)c;(void)s;(void)b;(void)p; }
EXPORT void  keyboard_note_on(int c, int k, int v)                    { (void)c;(void)k;(void)v; }
EXPORT void  keyboard_note_off(int c, int k)                          { (void)c;(void)k; }
EXPORT void  keyboard_pitch_bend(int c, int v)                        { (void)c;(void)v; }
EXPORT void  keyboard_control_change(int c, int cc, int v)            { (void)c;(void)cc;(void)v; }
EXPORT void  keyboard_set_gain(float g)                               { (void)g; }
EXPORT void* keyboard_render_fn_for_slot(int i)                       { (void)i; return NULL; }
EXPORT void  keyboard_render_block_0(float* l, float* r, int f)       { memset(l,0,(size_t)f*4); memset(r,0,(size_t)f*4); }
EXPORT void  keyboard_render_block_1(float* l, float* r, int f)       { memset(l,0,(size_t)f*4); memset(r,0,(size_t)f*4); }
EXPORT void  keyboard_render_block_2(float* l, float* r, int f)       { memset(l,0,(size_t)f*4); memset(r,0,(size_t)f*4); }
EXPORT void  keyboard_render_block(float* l, float* r, int f)         { memset(l,0,(size_t)f*4); memset(r,0,(size_t)f*4); }

#endif
