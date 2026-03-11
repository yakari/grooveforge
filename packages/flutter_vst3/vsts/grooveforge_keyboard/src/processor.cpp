/**
 * GrooveForge Keyboard — VST3 Instrument Processor
 *
 * MIDI in → FluidSynth → stereo audio out.
 * No sidechain / audio input bus.
 */

#include "../include/grooveforge_keyboard_ids.h"

#include "pluginterfaces/base/ibstream.h"
#include "pluginterfaces/vst/ivstevents.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "pluginterfaces/vst/ivstprocesscontext.h"
#include "public.sdk/source/vst/vstaudioeffect.h"
#include "base/source/fstreamer.h"

#include <fluidsynth.h>
#include <cstring>
#include <cstdlib>
#include <algorithm>
#include <filesystem>

using namespace Steinberg;
using namespace Steinberg::Vst;

/* ── Helpers ──────────────────────────────────────────────────────────────── */

static std::string find_default_soundfont() {
    /* Search relative to this shared library first (VST3 bundle Resources/) */
    const char* candidates[] = {
        /* Common system paths on Linux */
        "/usr/share/sounds/sf2/FluidR3_GM.sf2",
        "/usr/share/soundfonts/FluidR3_GM.sf2",
        "/usr/share/sounds/sf2/default_soundfont.sf2",
    };
    for (const char* p : candidates) {
        if (std::filesystem::exists(p)) return p;
    }
    return {};
}

/* ── Processor ────────────────────────────────────────────────────────────── */

class GrooveForgeKeyboardProcessor : public AudioEffect {
public:
    GrooveForgeKeyboardProcessor();
    ~GrooveForgeKeyboardProcessor() override;

    tresult PLUGIN_API initialize(FUnknown* context) override;
    tresult PLUGIN_API terminate() override;
    tresult PLUGIN_API setActive(TBool state) override;
    tresult PLUGIN_API process(ProcessData& data) override;
    tresult PLUGIN_API setupProcessing(ProcessSetup& setup) override;
    tresult PLUGIN_API setBusArrangements(SpeakerArrangement* in, int32 nIn,
                                         SpeakerArrangement* out, int32 nOut) override;
    tresult PLUGIN_API setState(IBStream* state) override;
    tresult PLUGIN_API getState(IBStream* state) override;
    tresult PLUGIN_API getControllerClassId(TUID classId) override;

    static FUnknown* createInstance(void*) {
        return (IAudioProcessor*) new GrooveForgeKeyboardProcessor();
    }

private:
    void loadSoundfont(const std::string& path);

    fluid_settings_t* mSettings = nullptr;
    fluid_synth_t*    mSynth    = nullptr;

    double      mSampleRate = 44100.0;
    float       mGain       = 1.0f;
    int         mBank       = 0;
    int         mProgram    = 0;
    std::string mSoundfontPath;
    int         mSfId       = -1;
};

GrooveForgeKeyboardProcessor::GrooveForgeKeyboardProcessor() {
    setControllerClass(kGrooveForgeKeyboardControllerUID);
}

GrooveForgeKeyboardProcessor::~GrooveForgeKeyboardProcessor() {
    if (mSynth)    { delete_fluid_synth(mSynth);       mSynth    = nullptr; }
    if (mSettings) { delete_fluid_settings(mSettings); mSettings = nullptr; }
}

tresult GrooveForgeKeyboardProcessor::initialize(FUnknown* context) {
    tresult r = AudioEffect::initialize(context);
    if (r != kResultTrue) return r;

    addAudioOutput(STR16("Stereo Out"), SpeakerArr::kStereo);
    addEventInput(STR16("MIDI In"), 1);
    return kResultTrue;
}

tresult GrooveForgeKeyboardProcessor::terminate() {
    if (mSynth)    { delete_fluid_synth(mSynth);       mSynth    = nullptr; }
    if (mSettings) { delete_fluid_settings(mSettings); mSettings = nullptr; }
    return AudioEffect::terminate();
}

tresult GrooveForgeKeyboardProcessor::setupProcessing(ProcessSetup& setup) {
    mSampleRate = setup.sampleRate;
    return AudioEffect::setupProcessing(setup);
}

tresult GrooveForgeKeyboardProcessor::setActive(TBool state) {
    if (state && !mSynth) {
        mSettings = new_fluid_settings();
        fluid_settings_setnum(mSettings, "synth.sample-rate", mSampleRate);
        fluid_settings_setint(mSettings, "synth.midi-channels", 16);
        fluid_settings_setint(mSettings, "audio.period-size", 64);
        mSynth = new_fluid_synth(mSettings);

        mSoundfontPath = find_default_soundfont();
        if (!mSoundfontPath.empty()) loadSoundfont(mSoundfontPath);
    }
    return AudioEffect::setActive(state);
}

void GrooveForgeKeyboardProcessor::loadSoundfont(const std::string& path) {
    if (!mSynth || path.empty()) return;
    if (mSfId != -1) { fluid_synth_sfunload(mSynth, mSfId, 1); mSfId = -1; }
    mSfId = fluid_synth_sfload(mSynth, path.c_str(), 1);
    if (mSfId != -1) fluid_synth_program_select(mSynth, 0, mSfId, mBank, mProgram);
}

tresult GrooveForgeKeyboardProcessor::setBusArrangements(SpeakerArrangement* /*in*/,
                                                         int32 nIn,
                                                         SpeakerArrangement* out,
                                                         int32 nOut) {
    if (nIn == 0 && nOut == 1 && out[0] == SpeakerArr::kStereo)
        return AudioEffect::setBusArrangements(nullptr, 0, out, nOut);
    return kResultFalse;
}

tresult GrooveForgeKeyboardProcessor::process(ProcessData& data) {
    /* ── Parameters ── */
    if (data.inputParameterChanges) {
        int32 n = data.inputParameterChanges->getParameterCount();
        for (int32 i = 0; i < n; ++i) {
            IParamValueQueue* q = data.inputParameterChanges->getParameterData(i);
            if (!q) continue;
            ParamValue v; int32 off;
            if (q->getPoint(q->getPointCount() - 1, off, v) != kResultTrue) continue;
            switch (q->getParameterId()) {
                case kParamGain:    mGain    = (float)v; break;
                case kParamBank:    mBank    = (int)(v * 127.0 + 0.5);
                    if (mSynth && mSfId != -1)
                        fluid_synth_program_select(mSynth, 0, mSfId, mBank, mProgram);
                    break;
                case kParamProgram: mProgram = (int)(v * 127.0 + 0.5);
                    if (mSynth && mSfId != -1)
                        fluid_synth_program_select(mSynth, 0, mSfId, mBank, mProgram);
                    break;
            }
        }
    }

    /* ── MIDI events ── */
    if (mSynth && data.inputEvents) {
        int32 n = data.inputEvents->getEventCount();
        for (int32 i = 0; i < n; ++i) {
            Event e{};
            data.inputEvents->getEvent(i, e);
            switch (e.type) {
                case Event::kNoteOnEvent:
                    fluid_synth_noteon(mSynth, e.noteOn.channel,
                                       e.noteOn.pitch,
                                       (int)(e.noteOn.velocity * 127.0f));
                    break;
                case Event::kNoteOffEvent:
                    fluid_synth_noteoff(mSynth, e.noteOff.channel, e.noteOff.pitch);
                    break;
            }
        }
    }

    /* ── Render ── */
    if (!mSynth || data.numOutputs == 0) return kResultOk;
    int32 nFrames = data.numSamples;
    if (nFrames <= 0) return kResultOk;

    AudioBusBuffers& out = data.outputs[0];
    float* L = out.channelBuffers32[0];
    float* R = out.channelBuffers32[1];

    fluid_synth_write_float(mSynth, nFrames, L, 0, 1, R, 0, 1);

    if (mGain != 1.0f) {
        for (int32 i = 0; i < nFrames; ++i) { L[i] *= mGain; R[i] *= mGain; }
    }
    return kResultOk;
}

tresult GrooveForgeKeyboardProcessor::setState(IBStream* stream) {
    if (!stream) return kResultFalse;
    IBStreamer s(stream, kLittleEndian);
    float gain; int32 bank, prog;
    if (!s.readFloat(gain) || !s.readInt32(bank) || !s.readInt32(prog)) return kResultFalse;
    mGain = gain; mBank = (int)bank; mProgram = (int)prog;

    int32 sfLen = 0;
    if (s.readInt32(sfLen) && sfLen > 0) {
        std::string sf(sfLen, '\0');
        int32 nr = 0;
        stream->read(sf.data(), sfLen, &nr);
        if (nr == sfLen && sf != mSoundfontPath) {
            mSoundfontPath = sf;
            if (mSynth) loadSoundfont(mSoundfontPath);
        }
    }
    return kResultOk;
}

tresult GrooveForgeKeyboardProcessor::getState(IBStream* stream) {
    if (!stream) return kResultFalse;
    IBStreamer s(stream, kLittleEndian);
    s.writeFloat(mGain);
    s.writeInt32(mBank);
    s.writeInt32(mProgram);
    s.writeInt32((int32)mSoundfontPath.size());
    if (!mSoundfontPath.empty()) {
        int32 nw = 0;
        stream->write(const_cast<char*>(mSoundfontPath.data()),
                      (int32)mSoundfontPath.size(), &nw);
    }
    return kResultOk;
}

tresult GrooveForgeKeyboardProcessor::getControllerClassId(TUID classId) {
    memcpy(classId, kGrooveForgeKeyboardControllerUID, sizeof(TUID));
    return kResultTrue;
}
