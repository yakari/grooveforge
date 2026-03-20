#include <jni.h>
#include <fluidsynth.h>
#include <unistd.h>
#include <map>
#include "gfpa_audio_android.h"

std::map<int, fluid_synth_t*> synths = {};
std::map<int, fluid_audio_driver_t*> drivers = {};
std::map<int, fluid_settings_t*> settings = {};
std::map<int, int> soundfonts = {};
int nextSfId = 1;

/// Current output gain applied to all synths. Default matches the original
/// hardcoded value so existing behaviour is preserved until the user changes it.
static float g_gain = 5.0f;

extern "C" JNIEXPORT int JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_loadSoundfont(JNIEnv* env, jclass clazz, jstring path, jint bank, jint program) {
    settings[nextSfId] = new_fluid_settings();
    // Apply the current user-set gain (default 5.0) so that newly-loaded
    // synths match any gain adjustment already applied via setGain().
    fluid_settings_setnum(settings[nextSfId], "synth.gain", g_gain);
    // Real-time priority for the Oboe audio thread (99 = max SCHED_FIFO).
    fluid_settings_setint(settings[nextSfId], "audio.realtime-prio", 99);
    fluid_settings_setnum(settings[nextSfId], "synth.sample-rate", 48000.0);
    fluid_settings_setint(settings[nextSfId], "synth.polyphony", 32);
    // Select the Oboe backend explicitly — required for new_fluid_audio_driver2
    // to route audio through Oboe instead of an unavailable default driver.
    fluid_settings_setstr(settings[nextSfId], "audio.driver", "oboe");
    fluid_settings_setstr(settings[nextSfId], "audio.oboe.performance-mode", "LowLatency");
    fluid_settings_setstr(settings[nextSfId], "audio.oboe.sharing-mode", "Exclusive");

    const char *nativePath = env->GetStringUTFChars(path, nullptr);
    synths[nextSfId] = new_fluid_synth(settings[nextSfId]);
    int sfId = fluid_synth_sfload(synths[nextSfId], nativePath, 0);
    for (int i = 0; i < 16; i++) {
        fluid_synth_program_select(synths[nextSfId], i, sfId, bank, program);
    }
    env->ReleaseStringUTFChars(path, nativePath);
    // Use the standard audio driver (not new_fluid_audio_driver2) because the
    // bundled FluidSynth Oboe driver does not implement new_fluid_oboe_audio_driver2
    // and new_fluid_audio_driver2 would return NULL, silencing all audio.
    // GFPA insert effects on the keyboard audio path are not supported on Android
    // with this FluidSynth build; they would require a custom FluidSynth with the
    // Oboe func2 variant.
    drivers[nextSfId] = new_fluid_audio_driver(settings[nextSfId], synths[nextSfId]);
    soundfonts[nextSfId] = sfId;
    nextSfId++;
    return nextSfId - 1;
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_selectInstrument(JNIEnv* env, jclass clazz, jint sfId, jint channel, jint bank, jint program) {
    fluid_synth_program_select(synths[sfId], channel, soundfonts[sfId], bank, program);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_playNote(JNIEnv* env, jclass clazz, jint channel, jint key, jint velocity, jint sfId) {
    fluid_synth_noteon(synths[sfId], channel, key, velocity);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_stopNote(JNIEnv* env, jclass clazz, jint channel, jint key, jint sfId) {
    fluid_synth_noteoff(synths[sfId], channel, key);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_stopAllNotes(JNIEnv* env, jclass clazz, jint sfId) {
    if (synths.find(sfId) == synths.end()) return;
    // Sustain'i kapat ve tüm kanallar için All Sound Off gönder
    for (int ch = 0; ch < 16; ++ch) {
        fluid_synth_cc(synths[sfId], ch, 64, 0); // Sustain off
        fluid_synth_all_sounds_off(synths[sfId], ch); // Instant cut
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_controlChange(JNIEnv* env, jclass clazz, jint sfId, jint channel, jint controller, jint value) {
    if (synths.find(sfId) == synths.end()) return;
    fluid_synth_cc(synths[sfId], channel, controller, value);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_pitchBend(JNIEnv* env, jclass clazz, jint sfId, jint channel, jint value) {
    if (synths.find(sfId) == synths.end()) return;
    fluid_synth_pitch_bend(synths[sfId], channel, value);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_unloadSoundfont(JNIEnv* env, jclass clazz, jint sfId) {
    delete_fluid_audio_driver(drivers[sfId]);
    delete_fluid_synth(synths[sfId]);
    synths.erase(sfId);
    drivers.erase(sfId);
    soundfonts.erase(sfId);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_setGain(JNIEnv* env, jclass clazz, jdouble gain) {
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
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_dispose(JNIEnv* env, jclass clazz) {
    for (auto const& x : synths) {
        delete_fluid_audio_driver(drivers[x.first]);
        delete_fluid_synth(synths[x.first]);
        delete_fluid_settings(settings[x.first]);
    }
    synths.clear();
    drivers.clear();
    soundfonts.clear();
}