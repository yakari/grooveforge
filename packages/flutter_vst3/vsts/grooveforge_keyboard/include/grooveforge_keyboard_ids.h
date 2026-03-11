#pragma once

#include "pluginterfaces/base/funknown.h"
#include "pluginterfaces/vst/vsttypes.h"

// {C7B3E1A0-F5D2-4B8C-9E1F-3A762D584C0E}
static const Steinberg::FUID kGrooveForgeKeyboardProcessorUID(
    0xC7B3E1A0, 0xF5D24B8C, 0x9E1F3A76, 0x2D584C0E);

// {D8C4F2B1-G6E3-5C9D-AF20-4B873E695D1F}
static const Steinberg::FUID kGrooveForgeKeyboardControllerUID(
    0xD8C4F2B1, 0x06E35C9D, 0xAF204B87, 0x3E695D1F);

/* Parameter IDs */
enum GrooveForgeKeyboardParams : Steinberg::Vst::ParamID {
    kParamGain    = 0,  /* 0..1, output gain           */
    kParamBank    = 1,  /* 0..1 (maps to 0-127)        */
    kParamProgram = 2,  /* 0..1 (maps to 0-127)        */
    kParamCount   = 3,
};
