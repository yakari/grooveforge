/**
 * GrooveForge Vocoder — VST3 Edit Controller
 */

#include "../include/grooveforge_vocoder_ids.h"

#include "pluginterfaces/base/ibstream.h"
#include "pluginterfaces/base/ustring.h"
#include "public.sdk/source/vst/vsteditcontroller.h"
#include "base/source/fstreamer.h"

#include <cstdio>
#include <cstring>

using namespace Steinberg;
using namespace Steinberg::Vst;

static const char* kWaveformNames[] = { "Saw", "Square", "Choral", "Natural" };

class GrooveForgeVocoderController : public EditController {
public:
    GrooveForgeVocoderController() = default;

    tresult PLUGIN_API initialize(FUnknown* context) override {
        tresult r = EditController::initialize(context);
        if (r != kResultTrue) return r;

        // Stepped parameter for waveform (4 choices)
        auto* wf = new Parameter(STR16("Waveform"), kParamWaveform,
                                 STR16(""), 0.0, 4,
                                 ParameterInfo::kIsList | ParameterInfo::kCanAutomate);
        parameters.addParameter(wf);
        parameters.addParameter(STR16("Noise Mix"),       STR16(""),  0, 0.05, ParameterInfo::kCanAutomate, kParamNoiseMix);
        parameters.addParameter(STR16("Bandwidth"),       STR16(""),  0, 0.15, ParameterInfo::kCanAutomate, kParamBandwidth);
        parameters.addParameter(STR16("Gate Threshold"),  STR16(""),  0, 0.1,  ParameterInfo::kCanAutomate, kParamGateThreshold);
        parameters.addParameter(STR16("Env Release"),     STR16(""),  0, 0.02, ParameterInfo::kCanAutomate, kParamEnvRelease);
        parameters.addParameter(STR16("Input Gain"),      STR16(""),  0, 0.5,  ParameterInfo::kCanAutomate, kParamInputGain);
        return kResultTrue;
    }

    tresult PLUGIN_API setComponentState(IBStream* stream) override {
        if (!stream) return kResultFalse;
        IBStreamer s(stream, kLittleEndian);
        float vals[kParamCount];
        for (int i = 0; i < kParamCount; ++i)
            if (!s.readFloat(vals[i])) return kResultFalse;
        for (int i = 0; i < kParamCount; ++i)
            setParamNormalized(i, vals[i]);
        return kResultOk;
    }

    tresult PLUGIN_API getParamStringByValue(ParamID id, ParamValue v, String128 str) override {
        switch (id) {
            case kParamWaveform: {
                int idx = (int)(v * 3.0 + 0.5);
                if (idx < 0) idx = 0;
                if (idx > 3) idx = 3;
                UString128(str).fromAscii(kWaveformNames[idx]);
                return kResultOk;
            }
            default: {
                char buf[16];
                snprintf(buf, sizeof(buf), "%.3f", (float)v);
                UString128(str).fromAscii(buf);
                return kResultOk;
            }
        }
    }

    IPlugView* PLUGIN_API createView(FIDString /*name*/) override { return nullptr; }

    static FUnknown* createInstance(void*) {
        return (IEditController*) new GrooveForgeVocoderController();
    }
};
