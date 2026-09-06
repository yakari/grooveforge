#include <jni.h>
#include <fluidsynth.h>
#include <unistd.h>
#include <cstdio>
#include <map>
#include <android/log.h>
#include "oboe_stream_android.h"

// ── Per-soundfont state ───────────────────────────────────────────────────────
//
// Each loadSoundfont() call creates one FluidSynth instance (synth + settings).
// Audio is NOT driven by a FluidSynth audio driver; instead all synths are
// registered with the shared AAudio stream in oboe_stream_android.cpp, which
// calls fluid_synth_process() on each of them every block and applies the
// GFPA insert chain (WAH, reverb, delay, EQ, compressor, chorus) before
// handing the mixed audio to the device.

/// Maps the integer soundfont-ID (returned to Dart) to the FluidSynth synth.
static std::map<int, fluid_synth_t*>    synths;

/// Maps soundfont-ID to FluidSynth settings.  Kept alive alongside the synth
/// (FluidSynth documentation: settings must outlive the synth).
static std::map<int, fluid_settings_t*> settings;

/// Maps soundfont-ID to the soundfont's internal FluidSynth ID (for program_select).
static std::map<int, int> soundfonts;

/// Counter for assigning unique soundfont IDs.
static int nextSfId = 1;

/// Current output gain applied to all synths.  Persisted so that synths loaded
/// after a setGain() call start at the correct level.
static float g_gain = 5.0f;

// ── JNI entry points ──────────────────────────────────────────────────────────

extern "C" JNIEXPORT int JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_loadSoundfont(
        JNIEnv* env, jclass /*clazz*/, jstring path, jint bank, jint program)
{
    // Start the shared AAudio stream BEFORE creating the synth.
    //
    // The stream is what decides the real render rate: 48000 is a request, and
    // a device whose native rate is 44100 will hand back 44100 instead. Opening
    // first lets us build the synth at exactly the granted rate, so nothing in
    // the chain resamples. Subsequent loads are no-ops (oboe_stream_start
    // returns early once the stream exists) and simply re-read the same rate.
    oboe_stream_start(48000);
    const double streamRate = static_cast<double>(oboe_stream_get_sample_rate());

    fluid_settings_t* s = new_fluid_settings();
    settings[nextSfId]  = s;

    // Apply the current gain so this synth starts at the same level as any
    // already-loaded synth.
    fluid_settings_setnum(s, "synth.gain", g_gain);

    // Render at the AAudio stream's actual rate so FluidSynth never resamples
    // and the mixed bus never needs AudioFlinger to resample either.
    fluid_settings_setnum(s, "synth.sample-rate", streamRate);
    fluid_settings_setint(s, "synth.polyphony", 32);

    // Disable FluidSynth's built-in reverb and chorus — both are applied via
    // the GFPA insert chain at the mixer level, so having them active here
    // would double-process the signal.
    fluid_settings_setint(s, "synth.reverb.active", 0);
    fluid_settings_setint(s, "synth.chorus.active", 0);

    // Create the synth (no audio driver — we drive it via fluid_synth_process).
    fluid_synth_t* synth = new_fluid_synth(s);

    // Definitively disable reverb/chorus at runtime too.  Some FluidSynth
    // builds ignore the settings-only path; the runtime call is authoritative.
    fluid_synth_reverb_on(synth, -1, 0);
    fluid_synth_chorus_on(synth, -1, 0);

    synths[nextSfId] = synth;

    // Load the soundfont and select it on all 16 MIDI channels.
    const char* nativePath = env->GetStringUTFChars(path, nullptr);
    int sfId = fluid_synth_sfload(synth, nativePath, 0);
    for (int i = 0; i < 16; i++) {
        fluid_synth_program_select(synth, i, sfId, bank, program);
    }
    env->ReleaseStringUTFChars(path, nativePath);
    soundfonts[nextSfId] = sfId;

    // Register this synth for rendering.  The AAudio callback will mix it
    // alongside any other active synth each block.
    // Pass nextSfId so the AAudio callback can route this keyboard's audio
    // through its own GFPA insert chain before summing into the master mix.
    oboe_stream_add_synth(synth, nextSfId);

    return nextSfId++;
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_selectInstrument(
        JNIEnv* /*env*/, jclass /*clazz*/, jint sfId, jint channel, jint bank, jint program)
{
    fluid_synth_program_select(synths[sfId], channel, soundfonts[sfId], bank, program);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_playNote(
        JNIEnv* /*env*/, jclass /*clazz*/, jint channel, jint key, jint velocity, jint sfId)
{
    fluid_synth_noteon(synths[sfId], channel, key, velocity);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_stopNote(
        JNIEnv* /*env*/, jclass /*clazz*/, jint channel, jint key, jint sfId)
{
    fluid_synth_noteoff(synths[sfId], channel, key);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_stopAllNotes(
        JNIEnv* /*env*/, jclass /*clazz*/, jint sfId)
{
    if (synths.find(sfId) == synths.end()) return;

    // Release sustain and send All Sound Off on every MIDI channel.
    for (int ch = 0; ch < 16; ++ch) {
        fluid_synth_cc(synths[sfId], ch, 64, 0);          // Sustain off
        fluid_synth_all_sounds_off(synths[sfId], ch);      // Instant cut
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_controlChange(
        JNIEnv* /*env*/, jclass /*clazz*/, jint sfId, jint channel, jint controller, jint value)
{
    if (synths.find(sfId) == synths.end()) return;
    fluid_synth_cc(synths[sfId], channel, controller, value);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_pitchBend(
        JNIEnv* /*env*/, jclass /*clazz*/, jint sfId, jint channel, jint value)
{
    if (synths.find(sfId) == synths.end()) return;
    fluid_synth_pitch_bend(synths[sfId], channel, value);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_unloadSoundfont(
        JNIEnv* /*env*/, jclass /*clazz*/, jint sfId)
{
    auto it = synths.find(sfId);
    if (it == synths.end()) return;

    fluid_synth_t* synth = it->second;

    // Unregister from the AAudio stream.  This call blocks until any
    // in-progress callback that captured a snapshot of this synth has
    // fully completed — safe to delete immediately after.
    oboe_stream_remove_synth(synth);

    delete_fluid_synth(synth);
    delete_fluid_settings(settings[sfId]);

    synths.erase(sfId);
    settings.erase(sfId);
    soundfonts.erase(sfId);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_setGain(
        JNIEnv* /*env*/, jclass /*clazz*/, jdouble gain)
{
    // Persist so future soundfont loads also start at this gain level.
    g_gain = static_cast<float>(gain);

    // Apply gain to every currently-loaded synth instance.
    // fluid_synth_set_gain() updates the live output level without requiring
    // a restart; range is 0.0–10.0 (FluidSynth internal limit).
    for (auto const& entry : synths) {
        fluid_synth_set_gain(entry.second, g_gain);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_setOutputDevice(
        JNIEnv* /*env*/, jclass /*clazz*/, jint deviceId)
{
    oboe_stream_set_output_device(static_cast<int>(deviceId));
}

/// Releases the shared AAudio output stream without touching the synths.
///
/// Called when the Flutter engine detaches, which is the last point this
/// process reliably gets before it is killed — swiping the app off the recents
/// list lands here.
///
/// Letting the process die with the stream still open is not free. The
/// platform then tears the route down on our behalf, and creating the audio
/// patch for a low-latency (MMAP) playback thread is exactly what trips this
/// vendor's sound-dose lock-order assertion:
///
///     Abort message: 'pre_lock: invalid mutex order
///                     (previous) 18 MelReporter_Mutex> (new) 13 ThreadBase_Mutex'
///       MelReporter::onCreateAudioPatch
///         -> MelReporter::startMelComputationForActivePatch_l
///            -> MmapPlaybackThread::startMelComputation_l
///
/// audioserver aborts, and the *next* launch opens into a restarting audio
/// server: the stream is disconnected within half a second, the fast path is
/// denied on the strike rule, and the session runs at mixer latency. The lag
/// the user then reports is a consequence of how the previous run ended.
///
/// Closing the stream ourselves, while we are still alive, makes the teardown
/// an ordinary close instead of a route change over a live MMAP endpoint.
/// This cannot help a `force-stop`, which SIGKILLs without callbacks — but
/// that is not how anyone leaves an app mid-set.
extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_stopOutputStream(
        JNIEnv* /*env*/, jclass /*clazz*/)
{
    oboe_stream_stop();
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_dispose(
        JNIEnv* /*env*/, jclass /*clazz*/)
{
    // Stop the shared AAudio stream first so no callbacks fire while we
    // free the synths it was rendering.
    oboe_stream_stop();

    for (auto const& x : synths) {
        delete_fluid_synth(x.second);
        delete_fluid_settings(settings[x.first]);
    }
    synths.clear();
    settings.clear();
    soundfonts.clear();
}

// ── Direct FFI entry points (latency hot path) ───────────────────────────────
//
// These symbols are plain `extern "C"` — NOT JNI wrappers — so Dart can reach
// them directly via `DynamicLibrary.lookupFunction` without going through the
// Flutter method channel → Kotlin audioExecutor → JNI chain that the
// `Java_com_melihhakanpektas_*` entry points above use.
//
// The method-channel path adds ~1–3ms of serialisation per call (three
// round-trips for a single note-on: pitch bend reset, CC reset, note-on),
// which turns a 3-note chord into a 9–27ms staggered burst on Android. These
// FFI exports let the hot-path MIDI events bypass that entirely and get the
// same ~0.3ms latency we already have on Linux through libaudio_input.so.
//
// Lifecycle (load / unload / soundfont select) still goes through the
// method-channel JNI entry points — they write `synths`, `settings`,
// `soundfonts`, and fire the `oboe_stream_*` calls. This keeps
// flutter_midi_pro as the single owner of the synth lifetime, and the FFI
// path is a pure READ of `synths[sfId]` plus a direct `fluid_synth_*` call.
//
// Thread safety: these functions are called from the Dart isolate thread,
// while `fluid_synth_process()` runs on the AAudio audio thread. FluidSynth
// is documented as thread-safe between note events and process calls (the
// voice list is guarded internally). The `synths.find` lookup on a
// `std::map` is NOT mutex-guarded, but:
//   - Soundfont unload is rare and goes through the method-channel path,
//   - `oboe_stream_remove_synth` in the unload path blocks until any
//     in-flight audio-thread snapshot drains,
//   - The window between `find` and the `fluid_synth_*` call is a handful
//     of nanoseconds.
// The existing JNI entry points above follow the same lock-free pattern
// and have been stable for months; these FFI exports are modelled identically.
//
// All functions are no-ops when `sfId` is not in the map — mirrors the
// defensive `find() == end()` guards on the existing JNI side.

extern "C" __attribute__((visibility("default")))
void gf_native_note_on(int sfId, int channel, int key, int velocity) {
    auto it = synths.find(sfId);
    if (it == synths.end()) return;
    fluid_synth_noteon(it->second, channel, key, velocity);
}

extern "C" __attribute__((visibility("default")))
void gf_native_note_off(int sfId, int channel, int key) {
    auto it = synths.find(sfId);
    if (it == synths.end()) return;
    fluid_synth_noteoff(it->second, channel, key);
}

extern "C" __attribute__((visibility("default")))
void gf_native_cc(int sfId, int channel, int controller, int value) {
    auto it = synths.find(sfId);
    if (it == synths.end()) return;
    fluid_synth_cc(it->second, channel, controller, value);
}

extern "C" __attribute__((visibility("default")))
void gf_native_pitch_bend(int sfId, int channel, int value) {
    auto it = synths.find(sfId);
    if (it == synths.end()) return;
    fluid_synth_pitch_bend(it->second, channel, value);
}

// ── Microtonal tuning (MIDI Tuning Standard) ─────────────────────────────────
//
// Android counterpart of `keyboard_set_key_tuning` in native_audio/
// keyboard_synth.c — see the comment block there for what a tuning table is
// and why the Xen module needs one instead of pitch bend.  The only
// difference on this side is that the synth is looked up by soundfont id
// rather than by keyboard slot, matching the note dispatch above.

extern "C" __attribute__((visibility("default")))
void gf_native_set_key_tuning(int sfId, int channel, const double* cents_offsets) {
    if (channel < 0 || channel >= 16 || cents_offsets == nullptr) return;
    auto it = synths.find(sfId);
    if (it == synths.end()) return;

    // Deviations from equal temperament → absolute cents, as the MIDI Tuning
    // Standard expects.
    double pitch[128];
    for (int k = 0; k < 128; ++k) {
        pitch[k] = static_cast<double>(k) * 100.0 + cents_offsets[k];
    }

    char name[32];
    snprintf(name, sizeof(name), "GF Xen ch%d", channel);

    // Bank 0, one tuning program per channel — sixteen independent scales.
    fluid_synth_activate_key_tuning(it->second, 0, channel, name, pitch, 1);
    fluid_synth_activate_tuning(it->second, channel, 0, channel, 1);
}

extern "C" __attribute__((visibility("default")))
void gf_native_clear_tuning(int sfId, int channel) {
    if (channel < 0 || channel >= 16) return;
    auto it = synths.find(sfId);
    if (it == synths.end()) return;
    fluid_synth_deactivate_tuning(it->second, channel, 1);
}
