/**
 * keyboard_synth.c — FluidSynth-based GF Keyboard audio engine.
 *
 * Replaces the external FluidSynth subprocess with an in-process library call
 * so that the audio thread in dart_vst_host can drive rendering via
 * keyboard_render_block() — the same "external render" mechanism used by the
 * Theremin and Stylophone.
 *
 * Audio architecture (Linux + macOS desktop):
 *   - FluidSynth is created with audio.driver = "none" (no built-in output).
 *   - dart_vst_host calls keyboard_render_block() each block, which calls
 *     fluid_synth_write_float() to advance the synth and fill L/R buffers.
 *   - GFPA descriptor effects (reverb, delay, …) are applied inline at the
 *     end of keyboard_render_block() via the insert chain managed by
 *     keyboard_add_insert() / keyboard_clear_inserts().  This keeps the
 *     effect processing inside libaudio_input and eliminates the race
 *     condition that arises when inserts are registered externally in
 *     dart_vst_host's master-insert API.
 *
 * Android uses flutter_midi_pro (Oboe) for MIDI playback and
 * gfpa_audio_android.cpp for effects — keyboard_render_block() is not
 * compiled on Android.
 */

#include <pthread.h>
#include <string.h>

#if defined(_WIN32)
  #define EXPORT __declspec(dllexport)
#else
  #define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

// ── GFPA insert chain — platform-agnostic types and scratch buffers ──────────
//
// Each GF Keyboard rack slot maintains its OWN insert chain so that a GFPA
// effect wired to slot A does not bleed into slot B.  The chains live inside
// KbSlot (defined in the FluidSynth block below), but the helper types and
// ping-pong scratch buffers are shared here to avoid duplication.
//
// Thread safety: each slot's insert_mutex serialises Dart-isolate writes
// against the audio-thread snapshot taken at the top of _kb_apply_chain().
// The lock is held only long enough to copy a handful of pointers.

/// GfpaInsertFn-compatible callback: process [frames] samples from
/// inL/inR into outL/outR.  Must be allocation-free (called on audio thread).
typedef void (*KbInsertFn)(const float* inL, const float* inR,
                            float*       outL, float*       outR,
                            int          frames, void* userdata);

#define MAX_KB_INSERTS  8
#define MAX_KB_BLOCK  4096

struct KbInsert { KbInsertFn fn; void* ud; };

/// Pre-allocated scratch buffers for ping-pong insert chaining.
/// Shared across all slots — only one slot renders per block, so no conflict.
static float g_kb_scratchL[MAX_KB_BLOCK];
static float g_kb_scratchR[MAX_KB_BLOCK];

/**
 * Apply an insert chain snapshot to [outL]/[outR] in-place.
 *
 * [chain] and [count] come from a mutex-protected snapshot taken by the caller.
 * Uses ping-pong between outL/outR and g_kb_scratchL/R — no heap allocation.
 */
static void _kb_apply_chain(const struct KbInsert* chain, int count,
                             float* outL, float* outR, int frames) {
    if (count == 0) return;

    // Ping-pong: first effect reads outL/outR → scratch, then alternates.
    float* curInL = outL,            *curInR = outR;
    float* curOutL = g_kb_scratchL,  *curOutR = g_kb_scratchR;

    for (int i = 0; i < count; ++i) {
        chain[i].fn(curInL, curInR, curOutL, curOutR, frames, chain[i].ud);
        // Swap input/output pointers for the next effect.
        float* tmpL = curInL; curInL = curOutL; curOutL = tmpL;
        float* tmpR = curInR; curInR = curOutR; curOutR = tmpR;
    }

    // After N effects curInL holds the final result.  Copy back if an odd
    // number of effects left it in the scratch buffers instead of outL/outR.
    if (curInL != outL) {
        memcpy(outL, curInL, (size_t)frames * sizeof(float));
        memcpy(outR, curInR, (size_t)frames * sizeof(float));
    }
}

// Forward declarations for the per-slot insert API (defined in the FluidSynth
// block below).  Exposed as EXPORT so the Dart FFI can call them directly.
EXPORT void keyboard_add_insert(void* fn, void* userdata);
EXPORT void keyboard_clear_inserts(void);
EXPORT void keyboard_add_insert_slot(int slotIdx, void* fn, void* userdata);
EXPORT void keyboard_clear_inserts_slot(int slotIdx);

// FluidSynth is available on Linux and macOS desktop.
// Android also defines __linux__, so we explicitly exclude it here.
#if (defined(__linux__) || defined(__APPLE__)) && !defined(__ANDROID__)

#include <fluidsynth.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// ── Multi-slot FluidSynth instances ──────────────────────────────────────────
//
// Each GF Keyboard rack slot is backed by its own FluidSynth instance so that
// GFPA effects connected to slot A are fully isolated from slot B.
//
// Slot index mapping: slotIdx = midiChannel % MAX_KB_SLOTS (0-based channel).
// With four slots, MIDI channels 0-3 each get a dedicated synth.  Most racks
// use at most two keyboard slots, so two isolated synths cover all common cases.
//
// Soundfont IDs (sfIds) are kept consistent across slots by loading every font
// into ALL active slots in the same order.  Because FluidSynth assigns sfIds
// monotonically per-instance, equal load order → equal sfIds → the Dart layer
// never needs to track per-slot sfId mappings.
//
// Backward-compatible single-slot API (keyboard_init / keyboard_render_block /
// keyboard_add_insert / keyboard_clear_inserts) continues to operate on slot 0.

#define MAX_KB_SLOTS  4
#define MAX_LOADED_SF 16

/// Per-slot state: one FluidSynth engine + one isolated GFPA insert chain.
typedef struct {
    fluid_settings_t* settings;
    fluid_synth_t*    synth;

    /// GFPA effect callbacks applied at the end of this slot's render block.
    struct KbInsert   inserts[MAX_KB_INSERTS];
    int               insert_count;
    pthread_mutex_t   insert_mutex;

    int               in_use;  ///< 1 = active FluidSynth instance, 0 = free
} KbSlot;

static KbSlot g_kb_slots[MAX_KB_SLOTS];
static float  g_kb_sample_rate = 48000.0f; ///< Stored so new slots can match sr.
static int    g_kb_gslice_done = 0;        ///< setenv("G_SLICE") called once.

/// Ordered list of soundfonts loaded globally — replayed into new slots so
/// that sfIds stay consistent across all instances.
static char g_loaded_sf_paths[MAX_LOADED_SF][512];
static int  g_loaded_sf_count = 0;

// ── Internal helpers ──────────────────────────────────────────────────────────

/** Belt-and-suspenders G_SLICE fix — also set in AppDelegate.swift at launch.
 *
 *  glib's g_slice allocator bypasses the system malloc zone, corrupting
 *  Swift/ObjC heap metadata on macOS.  The authoritative fix is in
 *  AppDelegate.swift (applicationWillFinishLaunching) which runs before dyld
 *  loads libglib.  This call is a redundant safety net for the case where
 *  keyboard_init_slot is the first glib-touching code and G_SLICE was somehow
 *  not set earlier.
 */
static void _kb_ensure_gslice(void) {
    if (!g_kb_gslice_done) {
        setenv("G_SLICE", "always-malloc", /*overwrite=*/1);
        g_kb_gslice_done = 1;
    }
}

/**
 * Return the slot index for a given 0-based MIDI [channel].
 *
 * Channels 0–3 map one-to-one to slots 0–3.  Channels ≥4 wrap modulo
 * MAX_KB_SLOTS.  The common two-keyboard case (channels 0 and 1) always
 * gets two fully isolated slots.
 */
static int _kb_slot_for_channel(int channel) {
    return channel % MAX_KB_SLOTS;
}

/**
 * Apply a slot's GFPA insert chain to [outL]/[outR] in-place.
 *
 * Snapshots the chain under the slot's mutex, then processes without
 * holding it.  Delegates to _kb_apply_chain() for the actual DSP work.
 */
static void _kb_apply_slot_inserts(KbSlot* slot, float* outL, float* outR,
                                   int frames) {
    struct KbInsert snap[MAX_KB_INSERTS];
    int count;

    pthread_mutex_lock(&slot->insert_mutex);
    count = slot->insert_count;
    if (count > 0)
        memcpy(snap, slot->inserts, (size_t)count * sizeof(struct KbInsert));
    pthread_mutex_unlock(&slot->insert_mutex);

    _kb_apply_chain(snap, count, outL, outR, frames);
}

/**
 * Create and configure a FluidSynth instance for [slot] at [sampleRate].
 * Loads all soundfonts that were registered before this slot was created.
 * Returns 1 on success, 0 on failure.
 */
static int _kb_create_synth(KbSlot* slot, float sampleRate) {
    slot->settings = new_fluid_settings();
    fluid_settings_setnum(slot->settings, "synth.sample-rate", (double)sampleRate);
    fluid_settings_setint(slot->settings, "synth.midi-channels", 16);
    fluid_settings_setstr(slot->settings, "audio.driver", "none");

    slot->synth = new_fluid_synth(slot->settings);
    if (!slot->synth) {
        delete_fluid_settings(slot->settings);
        slot->settings = NULL;
        return 0;
    }

    // Replay all previously loaded soundfonts so this slot's sfIds match slot 0.
    //
    // reset strategy mirrors keyboard_load_sf(): the FIRST soundfont gets
    // reset=1 so that every MIDI channel in the freshly created synth has a
    // valid default assignment (otherwise channels produce silence until an
    // explicit keyboard_program_select() call is made for each one).
    // Subsequent soundfonts use reset=0 so they don't wipe those assignments.
    //
    // After this function returns, the caller (keyboard_init_slot) will invoke
    // the onNewSlot / reapplySlotPrograms callback which re-applies the correct
    // per-channel instrument selections, overriding the reset=1 default where
    // needed.
    for (int i = 0; i < g_loaded_sf_count; ++i) {
        int resetFlag = (i == 0) ? 1 : 0;
        fluid_synth_sfload(slot->synth, g_loaded_sf_paths[i], /*reset=*/resetFlag);
    }
    pthread_mutex_init(&slot->insert_mutex, NULL);
    slot->in_use = 1;
    return 1;
}

// ── Internal per-slot render ──────────────────────────────────────────────────

/** Render one block from [slot]'s FluidSynth and apply its insert chain. */
static void _kb_render_slot(KbSlot* slot, float* outL, float* outR, int frames) {
    if (!slot->synth || !slot->in_use) {
        memset(outL, 0, (size_t)frames * sizeof(float));
        memset(outR, 0, (size_t)frames * sizeof(float));
        return;
    }
    // fluid_synth_write_float: non-interleaved, stride 1.
    fluid_synth_write_float(slot->synth, frames, outL, 0, 1, outR, 0, 1);
    _kb_apply_slot_inserts(slot, outL, outR, frames);
}

// ── Static render trampolines (one per slot) ──────────────────────────────────
//
// dart_vst_host's addMasterRender() stores a raw C function pointer, so we
// need a unique address per slot.  Static trampolines provide that without
// heap allocation or closures.

/** Render trampoline for GF Keyboard slot 0. */
EXPORT void keyboard_render_block_0(float* l, float* r, int n) {
    _kb_render_slot(&g_kb_slots[0], l, r, n);
}
/** Render trampoline for GF Keyboard slot 1. */
EXPORT void keyboard_render_block_1(float* l, float* r, int n) {
    _kb_render_slot(&g_kb_slots[1], l, r, n);
}
/** Render trampoline for GF Keyboard slot 2. */
EXPORT void keyboard_render_block_2(float* l, float* r, int n) {
    _kb_render_slot(&g_kb_slots[2], l, r, n);
}
/** Render trampoline for GF Keyboard slot 3. */
EXPORT void keyboard_render_block_3(float* l, float* r, int n) {
    _kb_render_slot(&g_kb_slots[3], l, r, n);
}

/**
 * Return the static render-block function pointer for the given [slotIdx].
 *
 * Pass the returned pointer to dart_vst_host's addMasterRender() or
 * setExternalRender() so that each keyboard slot has a unique render
 * function that only advances its own FluidSynth instance.
 *
 * Returns NULL for out-of-range indices.
 */
EXPORT void* keyboard_render_fn_for_slot(int slotIdx) {
    typedef void (*RenderFn)(float*, float*, int);
    static const RenderFn ptrs[MAX_KB_SLOTS] = {
        keyboard_render_block_0,
        keyboard_render_block_1,
        keyboard_render_block_2,
        keyboard_render_block_3,
    };
    if (slotIdx < 0 || slotIdx >= MAX_KB_SLOTS) return NULL;
    return (void*)ptrs[slotIdx];
}

// ── Lifecycle ─────────────────────────────────────────────────────────────────

/**
 * Initialise the FluidSynth engine for [slotIdx] at [sampleRate] Hz.
 *
 * [slotIdx] must be in [0, MAX_KB_SLOTS).  Idempotent: safe to call again if
 * already initialised.  All soundfonts loaded before this call are
 * automatically loaded into the new instance.
 *
 * Returns 1 on success, 0 on failure.
 */
/**
 * Initialise the FluidSynth engine for [slotIdx] at [sampleRate] Hz.
 *
 * Return values:
 *   0 — failure (bad index or synth creation failed)
 *   1 — slot was already initialised; this call is a no-op
 *   2 — slot was newly created; the caller MUST re-apply keyboard_program_select()
 *       for all channels that map to this slot (ch % MAX_KB_SLOTS == slotIdx),
 *       because earlier program_select calls for an uninitialised slot are NOPs.
 *
 * All soundfonts that were loaded before this call are automatically replayed
 * into the new instance so that sfIds stay consistent across slots.
 */
EXPORT int keyboard_init_slot(int slotIdx, float sampleRate) {
    if (slotIdx < 0 || slotIdx >= MAX_KB_SLOTS) return 0;
    KbSlot* slot = &g_kb_slots[slotIdx];
    if (slot->in_use) return 1; // already initialised — no program_select re-apply needed

    _kb_ensure_gslice();
    g_kb_sample_rate = sampleRate;

    if (!_kb_create_synth(slot, sampleRate)) {
        fprintf(stderr, "[keyboard_synth] ERROR: new_fluid_synth() failed for slot %d\n",
                slotIdx);
        return 0;
    }
    fprintf(stderr, "[keyboard_synth] FluidSynth slot %d initialised (sr=%.0f) — "
            "caller must re-apply program_select for channels mapping to this slot\n",
            slotIdx, (double)sampleRate);
    return 2; // newly created — Dart must re-apply channel programs
}

/**
 * Destroy the FluidSynth engine for [slotIdx] and free its resources.
 *
 * Clears the insert chain first so no use-after-free can occur.
 * Idempotent: safe to call on a slot that is already destroyed.
 */
EXPORT void keyboard_destroy_slot(int slotIdx) {
    if (slotIdx < 0 || slotIdx >= MAX_KB_SLOTS) return;
    KbSlot* slot = &g_kb_slots[slotIdx];
    if (!slot->in_use) return;

    pthread_mutex_lock(&slot->insert_mutex);
    slot->insert_count = 0;
    pthread_mutex_unlock(&slot->insert_mutex);

    if (slot->synth)    { delete_fluid_synth(slot->synth);       slot->synth    = NULL; }
    if (slot->settings) { delete_fluid_settings(slot->settings); slot->settings = NULL; }
    pthread_mutex_destroy(&slot->insert_mutex);
    slot->in_use = 0;
}

/**
 * Backward-compatible initialiser — creates slot 0 at [sampleRate] Hz.
 *
 * Equivalent to keyboard_init_slot(0, sampleRate).  All single-keyboard
 * setups use this path.
 */
EXPORT int keyboard_init(float sampleRate) {
    return keyboard_init_slot(0, sampleRate);
}

/** Backward-compatible destructor — destroys slot 0. */
EXPORT void keyboard_destroy(void) {
    keyboard_destroy_slot(0);
}

// ── SoundFont management ──────────────────────────────────────────────────────

/**
 * Load a SoundFont (.sf2) into ALL active slots and record it for future slots.
 *
 * Because every slot loads soundfonts in the same order, FluidSynth assigns
 * identical sfIds across all instances — the Dart layer can keep a single
 * path→sfId map and use it for any slot.
 *
 * Returns the sfId assigned by slot 0 on success, -1 on failure.
 */
EXPORT int keyboard_load_sf(const char* path) {
    if (!g_kb_slots[0].synth) return -1;

    // Record path for future slot initialisation.
    if (g_loaded_sf_count < MAX_LOADED_SF) {
        strncpy(g_loaded_sf_paths[g_loaded_sf_count], path,
                sizeof(g_loaded_sf_paths[0]) - 1);
        g_loaded_sf_paths[g_loaded_sf_count][sizeof(g_loaded_sf_paths[0]) - 1] = '\0';
        ++g_loaded_sf_count;
    }

    // Load into slot 0 to obtain the authoritative sfId.
    //
    // reset strategy: use reset=1 ONLY for the very first soundfont loaded into
    // a fresh synth instance (g_loaded_sf_count was 0 before this call, i.e.
    // this is the first entry in g_loaded_sf_paths).  reset=1 assigns every
    // MIDI channel in the synth to the new soundfont's bank 0 / program 0,
    // which bootstraps the audio pipeline so channels produce sound even before
    // Dart calls keyboard_program_select() for them.
    //
    // For every subsequent soundfont (g_loaded_sf_count already > 1 after the
    // increment above), use reset=0 to preserve existing channel program
    // assignments.  With reset=1, FluidSynth would reset ALL 16 channels to
    // the newly loaded soundfont's defaults, wiping the instrument selection
    // already made for channels belonging to other keyboards — those channels
    // would silently play the wrong soundfont until the Dart layer explicitly
    // re-applied their programs (which it does not do automatically when loading
    // a soundfont for a *different* keyboard).
    int isFirst = (g_loaded_sf_count == 1); // incremented above; ==1 means this is the first SF
    int sfId = (int)fluid_synth_sfload(g_kb_slots[0].synth, path, /*reset=*/isFirst);
    fprintf(stderr, "[keyboard_synth] load_sf '%s' → sfId=%d (reset=%d)\n", path, sfId, isFirst);

    // Mirror into all other active slots (sfId will match slot 0 since load
    // order is identical across instances).  Same reset strategy: first SF in
    // each fresh synth gets reset=1 so channels have a default assignment; any
    // subsequent SF uses reset=0 to leave existing assignments intact.
    for (int i = 1; i < MAX_KB_SLOTS; ++i) {
        if (g_kb_slots[i].in_use && g_kb_slots[i].synth) {
            // The slot was created AFTER some SFs were already loaded (otherwise
            // _kb_create_synth replayed them).  At this point the slot already
            // has at least one SF, so never reset here.
            fluid_synth_sfload(g_kb_slots[i].synth, path, /*reset=*/0);
        }
    }
    return sfId;
}

/**
 * Unload a SoundFont by [sfId] from ALL active slots.
 *
 * [sfId] is the value returned by keyboard_load_sf().  Assumes equal sfIds
 * across slots (guaranteed by equal load order — see keyboard_load_sf()).
 */
EXPORT void keyboard_unload_sf(int sfId) {
    for (int i = 0; i < MAX_KB_SLOTS; ++i) {
        if (g_kb_slots[i].in_use && g_kb_slots[i].synth) {
            fluid_synth_sfunload(g_kb_slots[i].synth, (unsigned int)sfId, /*reset=*/1);
        }
    }
    // Remove from the load-list so new slots don't load the unloaded font.
    // Find and compact the array.
    // (A simple linear search is fine — MAX_LOADED_SF is small.)
    // We don't know the path from sfId here; leave the list as-is.
    // In practice unloadSoundfont is rare and the Dart layer reloads anyway.
}

/**
 * Assign an instrument patch to a MIDI channel across the correct slot.
 *
 * [channel] 0–15 determines which slot via _kb_slot_for_channel().
 * [sfId] must be a value returned by keyboard_load_sf().
 */
EXPORT void keyboard_program_select(int channel, int sfId, int bank, int program) {
    int idx = _kb_slot_for_channel(channel);
    KbSlot* slot = &g_kb_slots[idx];
    if (slot->synth) {
        fluid_synth_program_select(slot->synth, channel,
                                   (unsigned int)sfId,
                                   (unsigned int)bank,
                                   (unsigned int)program);
    }
}

// ── MIDI event dispatch ───────────────────────────────────────────────────────
//
// Each MIDI function routes to the slot that owns the given channel.

/** Send a MIDI note-on event: [channel] 0–15, [key] 0–127, [velocity] 1–127. */
EXPORT void keyboard_note_on(int channel, int key, int velocity) {
    KbSlot* slot = &g_kb_slots[_kb_slot_for_channel(channel)];
    if (slot->synth) fluid_synth_noteon(slot->synth, channel, key, velocity);
}

/** Send a MIDI note-off event: [channel] 0–15, [key] 0–127. */
EXPORT void keyboard_note_off(int channel, int key) {
    KbSlot* slot = &g_kb_slots[_kb_slot_for_channel(channel)];
    if (slot->synth) fluid_synth_noteoff(slot->synth, channel, key);
}

/**
 * Send a MIDI pitch-bend value.
 *
 * [value] is the 14-bit MIDI pitch-bend word (0–16383, centre 8192),
 * which matches the raw value forwarded by AudioEngine.
 */
EXPORT void keyboard_pitch_bend(int channel, int value) {
    KbSlot* slot = &g_kb_slots[_kb_slot_for_channel(channel)];
    if (slot->synth) fluid_synth_pitch_bend(slot->synth, channel, value);
}

/** Send a MIDI Control Change: [cc] 0–127, [value] 0–127. */
EXPORT void keyboard_control_change(int channel, int cc, int value) {
    KbSlot* slot = &g_kb_slots[_kb_slot_for_channel(channel)];
    if (slot->synth) fluid_synth_cc(slot->synth, channel, cc, value);
}

/**
 * Set the master output gain on ALL active slots.
 *
 * [gain] is a linear scalar (FluidSynth default 0.2; GrooveForge uses 3.0).
 * Applied to every slot so relative levels are consistent when multiple
 * keyboards are active.
 */
EXPORT void keyboard_set_gain(float gain) {
    for (int i = 0; i < MAX_KB_SLOTS; ++i) {
        if (g_kb_slots[i].in_use && g_kb_slots[i].synth) {
            fluid_synth_set_gain(g_kb_slots[i].synth, gain);
        }
    }
}

// ── GFPA insert chain management ─────────────────────────────────────────────

/**
 * Register a GFPA DSP insert on [slotIdx]'s audio path.
 *
 * [fn]       — GfpaInsertFn-compatible function pointer, cast to void*.
 *              Obtain from gfpa_dsp_insert_fn(handle) in libdart_vst_host.
 * [userdata] — GfpaDspHandle returned by gfpa_dsp_create(), cast to void*.
 *
 * Inserts on each slot are independent — an effect registered for slot 0
 * does NOT affect slot 1 and vice versa.  At most MAX_KB_INSERTS per slot.
 *
 * Always call keyboard_clear_inserts_slot() before destroying a GfpaDspHandle.
 */
EXPORT void keyboard_add_insert_slot(int slotIdx, void* fn, void* userdata) {
    if (slotIdx < 0 || slotIdx >= MAX_KB_SLOTS) return;
    KbSlot* slot = &g_kb_slots[slotIdx];
    if (!slot->in_use) return;

    pthread_mutex_lock(&slot->insert_mutex);
    if (slot->insert_count < MAX_KB_INSERTS) {
        slot->inserts[slot->insert_count].fn = (KbInsertFn)fn;
        slot->inserts[slot->insert_count].ud = userdata;
        ++slot->insert_count;
    }
    pthread_mutex_unlock(&slot->insert_mutex);
}

/**
 * Remove all GFPA inserts from [slotIdx]'s audio path.
 *
 * The next render block for that slot will output dry audio.
 * Must be called before destroying any GfpaDspHandle linked to this slot.
 */
EXPORT void keyboard_clear_inserts_slot(int slotIdx) {
    if (slotIdx < 0 || slotIdx >= MAX_KB_SLOTS) return;
    KbSlot* slot = &g_kb_slots[slotIdx];
    if (!slot->in_use) return;

    pthread_mutex_lock(&slot->insert_mutex);
    slot->insert_count = 0;
    pthread_mutex_unlock(&slot->insert_mutex);
}

/**
 * Backward-compatible add-insert — operates on slot 0.
 *
 * Equivalent to keyboard_add_insert_slot(0, fn, userdata).
 */
EXPORT void keyboard_add_insert(void* fn, void* userdata) {
    keyboard_add_insert_slot(0, fn, userdata);
}

/**
 * Backward-compatible clear-inserts — operates on slot 0.
 *
 * Equivalent to keyboard_clear_inserts_slot(0).
 */
EXPORT void keyboard_clear_inserts(void) {
    keyboard_clear_inserts_slot(0);
}

// ── Render (backward-compatible single-slot path) ─────────────────────────────

/**
 * Render one block of stereo audio from slot 0 into [outL] and [outR].
 *
 * Backward-compatible entry point — equivalent to keyboard_render_block_0().
 * New code should prefer the per-slot trampolines (keyboard_render_fn_for_slot).
 *
 * Called by the dart_vst_host ALSA/CoreAudio thread every block.
 * [frames] matches the block size (typically 256 samples at 48 kHz).
 */
EXPORT void keyboard_render_block(float* outL, float* outR, int frames) {
    _kb_render_slot(&g_kb_slots[0], outL, outR, frames);
}

#endif // (defined(__linux__) || defined(__APPLE__)) && !defined(__ANDROID__)
