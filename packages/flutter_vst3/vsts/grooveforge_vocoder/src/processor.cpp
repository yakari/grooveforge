/**
 * GrooveForge Vocoder — VST3 Processor
 *
 * Audio buses:
 *   Input  bus 0 — "Voice In"   (mono sidechain, the singer's microphone)
 *   Output bus 0 — "Stereo Out" (processed vocoder output)
 *
 * Event bus:
 *   Input  0 — "MIDI In" (notes drive the carrier oscillator)
 *
 * The actual DSP is fully contained in vocoder_dsp.c/h so there is no
 * miniaudio dependency here.
 */

#include "../include/grooveforge_vocoder_ids.h"

// vocoder_dsp lives in native_audio/ — path resolved by CMake include dirs
#include "vocoder_dsp.h"

#include "pluginterfaces/base/ibstream.h"
#include "pluginterfaces/vst/ivstevents.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "public.sdk/source/vst/vstaudioeffect.h"
#include "base/source/fstreamer.h"

#include <cstring>
#include <vector>

using namespace Steinberg;
using namespace Steinberg::Vst;

class GrooveForgeVocoderProcessor : public AudioEffect {
public:
    GrooveForgeVocoderProcessor();
    ~GrooveForgeVocoderProcessor() override;

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
        return (IAudioProcessor*) new GrooveForgeVocoderProcessor();
    }

private:
    void applyParams();

    VocoderContext* mCtx        = nullptr;
    double          mSampleRate = 44100.0;

    /* Normalised (0..1) parameter cache */
    float mWaveform      = 0.0f;
    float mNoiseMix      = 0.05f;
    float mBandwidth     = 0.15f;
    float mGateThreshold = 0.1f;   /* 0..1 → mapped to 0..0.1 in applyParams */
    float mEnvRelease    = 0.02f;
    float mInputGain     = 0.5f;   /* 0..1 → mapped to 0..2 in applyParams   */

    /* Mono voice scratch buffer (avoids per-block allocation) */
    std::vector<float> mMonoIn;
};

GrooveForgeVocoderProcessor::GrooveForgeVocoderProcessor() {
    setControllerClass(kGrooveForgeVocoderControllerUID);
}

GrooveForgeVocoderProcessor::~GrooveForgeVocoderProcessor() {
    if (mCtx) { vocoder_dsp_destroy(mCtx); mCtx = nullptr; }
}

tresult GrooveForgeVocoderProcessor::initialize(FUnknown* context) {
    tresult r = AudioEffect::initialize(context);
    if (r != kResultTrue) return r;

    /* Mono sidechain for the voice signal */
    addAudioInput(STR16("Voice In"), SpeakerArr::kMono);
    addAudioOutput(STR16("Stereo Out"), SpeakerArr::kStereo);
    addEventInput(STR16("MIDI In"), 1);
    return kResultTrue;
}

tresult GrooveForgeVocoderProcessor::terminate() {
    if (mCtx) { vocoder_dsp_destroy(mCtx); mCtx = nullptr; }
    return AudioEffect::terminate();
}

tresult GrooveForgeVocoderProcessor::setupProcessing(ProcessSetup& setup) {
    mSampleRate = setup.sampleRate;
    return AudioEffect::setupProcessing(setup);
}

tresult GrooveForgeVocoderProcessor::setActive(TBool state) {
    if (state && !mCtx) {
        mCtx = vocoder_dsp_create((float)mSampleRate);
        applyParams();
    } else if (!state && mCtx) {
        vocoder_dsp_destroy(mCtx);
        mCtx = nullptr;
    }
    return AudioEffect::setActive(state);
}

void GrooveForgeVocoderProcessor::applyParams() {
    if (!mCtx) return;
    vocoder_dsp_set_waveform(mCtx,       (int)(mWaveform * 3.0f + 0.5f));
    vocoder_dsp_set_noise_mix(mCtx,      mNoiseMix);
    vocoder_dsp_set_bandwidth(mCtx,      mBandwidth);
    vocoder_dsp_set_gate_threshold(mCtx, mGateThreshold * 0.1f);
    vocoder_dsp_set_env_release(mCtx,    mEnvRelease);
    vocoder_dsp_set_input_gain(mCtx,     mInputGain * 2.0f);
}

tresult GrooveForgeVocoderProcessor::setBusArrangements(SpeakerArrangement* in, int32 nIn,
                                                        SpeakerArrangement* out, int32 nOut) {
    /* Accept mono voice input → stereo output */
    if (nIn == 1 && nOut == 1 &&
        (in[0] == SpeakerArr::kMono || in[0] == SpeakerArr::kStereo) &&
        out[0] == SpeakerArr::kStereo)
        return AudioEffect::setBusArrangements(in, nIn, out, nOut);
    return kResultFalse;
}

tresult GrooveForgeVocoderProcessor::process(ProcessData& data) {
    /* ── Parameters ── */
    if (data.inputParameterChanges) {
        int32 n = data.inputParameterChanges->getParameterCount();
        bool changed = false;
        for (int32 i = 0; i < n; ++i) {
            IParamValueQueue* q = data.inputParameterChanges->getParameterData(i);
            if (!q) continue;
            ParamValue v; int32 off;
            if (q->getPoint(q->getPointCount() - 1, off, v) != kResultTrue) continue;
            changed = true;
            switch (q->getParameterId()) {
                case kParamWaveform:      mWaveform      = (float)v; break;
                case kParamNoiseMix:      mNoiseMix      = (float)v; break;
                case kParamBandwidth:     mBandwidth     = (float)v; break;
                case kParamGateThreshold: mGateThreshold = (float)v; break;
                case kParamEnvRelease:    mEnvRelease    = (float)v; break;
                case kParamInputGain:     mInputGain     = (float)v; break;
            }
        }
        if (changed) applyParams();
    }

    /* ── MIDI events ── */
    if (mCtx && data.inputEvents) {
        int32 n = data.inputEvents->getEventCount();
        for (int32 i = 0; i < n; ++i) {
            Event e{};
            data.inputEvents->getEvent(i, e);
            switch (e.type) {
                case Event::kNoteOnEvent:
                    vocoder_dsp_note_on(mCtx, e.noteOn.pitch,
                                        (int)(e.noteOn.velocity * 127.0f));
                    break;
                case Event::kNoteOffEvent:
                    vocoder_dsp_note_off(mCtx, e.noteOff.pitch);
                    break;
            }
        }
    }

    /* ── Audio ── */
    if (!mCtx || data.numInputs == 0 || data.numOutputs == 0) return kResultOk;
    int32 nFrames = data.numSamples;
    if (nFrames <= 0) return kResultOk;

    AudioBusBuffers& vIn  = data.inputs[0];
    AudioBusBuffers& sOut = data.outputs[0];

    /* Build a mono input: first input channel, or mix if stereo source */
    mMonoIn.resize(nFrames, 0.0f);
    if (vIn.numChannels == 1) {
        memcpy(mMonoIn.data(), vIn.channelBuffers32[0], nFrames * sizeof(float));
    } else if (vIn.numChannels >= 2) {
        const float* L = vIn.channelBuffers32[0];
        const float* R = vIn.channelBuffers32[1];
        for (int32 i = 0; i < nFrames; ++i) mMonoIn[i] = (L[i] + R[i]) * 0.5f;
    }

    vocoder_dsp_process(mCtx,
                        mMonoIn.data(),
                        sOut.channelBuffers32[0],
                        sOut.channelBuffers32[1],
                        nFrames);
    return kResultOk;
}

tresult GrooveForgeVocoderProcessor::setState(IBStream* stream) {
    if (!stream) return kResultFalse;
    IBStreamer s(stream, kLittleEndian);
    if (!s.readFloat(mWaveform)      || !s.readFloat(mNoiseMix)  ||
        !s.readFloat(mBandwidth)     || !s.readFloat(mGateThreshold) ||
        !s.readFloat(mEnvRelease)    || !s.readFloat(mInputGain))
        return kResultFalse;
    applyParams();
    return kResultOk;
}

tresult GrooveForgeVocoderProcessor::getState(IBStream* stream) {
    if (!stream) return kResultFalse;
    IBStreamer s(stream, kLittleEndian);
    s.writeFloat(mWaveform);
    s.writeFloat(mNoiseMix);
    s.writeFloat(mBandwidth);
    s.writeFloat(mGateThreshold);
    s.writeFloat(mEnvRelease);
    s.writeFloat(mInputGain);
    return kResultOk;
}

tresult GrooveForgeVocoderProcessor::getControllerClassId(TUID classId) {
    memcpy(classId, kGrooveForgeVocoderControllerUID, sizeof(TUID));
    return kResultTrue;
}
