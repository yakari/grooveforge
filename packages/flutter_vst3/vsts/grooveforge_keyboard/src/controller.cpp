/**
 * GrooveForge Keyboard — VST3 Edit Controller
 * Exposes Gain, Bank, and Program as automatable parameters.
 */

#include "../include/grooveforge_keyboard_ids.h"

#include "pluginterfaces/base/ibstream.h"
#include "pluginterfaces/base/ustring.h"
#include "public.sdk/source/vst/vsteditcontroller.h"
#include "base/source/fstreamer.h"

#include <cstdio>
#include <cstring>

using namespace Steinberg;
using namespace Steinberg::Vst;

class GrooveForgeKeyboardController : public EditController {
public:
    GrooveForgeKeyboardController() = default;

    tresult PLUGIN_API initialize(FUnknown* context) override {
        tresult r = EditController::initialize(context);
        if (r != kResultTrue) return r;

        parameters.addParameter(STR16("Gain"),    STR16(""),  0, 1.0, ParameterInfo::kCanAutomate, kParamGain);
        parameters.addParameter(STR16("Bank"),    STR16(""),  0, 0.0, ParameterInfo::kCanAutomate, kParamBank);
        parameters.addParameter(STR16("Program"), STR16(""),  0, 0.0, ParameterInfo::kCanAutomate, kParamProgram);
        return kResultTrue;
    }

    tresult PLUGIN_API setComponentState(IBStream* stream) override {
        if (!stream) return kResultFalse;
        IBStreamer s(stream, kLittleEndian);
        float gain; int32 bank, prog;
        if (!s.readFloat(gain) || !s.readInt32(bank) || !s.readInt32(prog)) return kResultFalse;
        setParamNormalized(kParamGain,    gain);
        setParamNormalized(kParamBank,    (double)bank / 127.0);
        setParamNormalized(kParamProgram, (double)prog / 127.0);
        return kResultOk;
    }

    tresult PLUGIN_API getParamStringByValue(ParamID id, ParamValue v, String128 str) override {
        switch (id) {
            case kParamGain:
                UString128(str).printFloat(v);
                return kResultOk;
            case kParamBank:
            case kParamProgram: {
                char buf[16];
                snprintf(buf, sizeof(buf), "%d", (int)(v * 127.0 + 0.5));
                UString128(str).fromAscii(buf);
                return kResultOk;
            }
        }
        return EditController::getParamStringByValue(id, v, str);
    }

    IPlugView* PLUGIN_API createView(FIDString /*name*/) override { return nullptr; }

    static FUnknown* createInstance(void*) {
        return (IEditController*) new GrooveForgeKeyboardController();
    }
};
