#include <jni.h>
#include <fluidsynth.h>
#include <unistd.h>
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
    fluid_settings_t* s = new_fluid_settings();
    settings[nextSfId]  = s;

    // Apply the current gain so this synth starts at the same level as any
    // already-loaded synth.
    fluid_settings_setnum(s, "synth.gain", g_gain);

    // Match the sample rate to the AAudio stream (see oboe_stream_start call
    // below) to avoid FluidSynth resampling on every block.
    fluid_settings_setnum(s, "synth.sample-rate", 48000.0);
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

    // Start the shared AAudio stream on the first load; subsequent loads are
    // no-ops in oboe_stream_start (it checks g_stream != nullptr).
    oboe_stream_start(48000);

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
