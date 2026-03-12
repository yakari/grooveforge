#pragma once

#include "pluginterfaces/base/funknown.h"
#include "pluginterfaces/vst/vsttypes.h"

// {A1E2D3C4-B5F6-7890-ABCD-EF1234567890}
static const Steinberg::FUID kGrooveForgeVocoderProcessorUID(
    0xA1E2D3C4, 0xB5F67890, 0xABCDEF12, 0x34567890);

// {B2F3E4D5-C6A7-8901-BCDE-F01234567891}
static const Steinberg::FUID kGrooveForgeVocoderControllerUID(
    0xB2F3E4D5, 0xC6A78901, 0xBCDEF012, 0x34567891);

/** Parameter IDs */
enum GrooveForgeVocoderParams : Steinberg::Vst::ParamID {
    kParamWaveform       = 0,  /* 0..1 → maps to int 0-3  */
    kParamNoiseMix       = 1,  /* 0..1                     */
    kParamBandwidth      = 2,  /* 0..1 (Q factor)          */
    kParamGateThreshold  = 3,  /* 0..1 → maps to 0..0.1   */
    kParamEnvRelease     = 4,  /* 0..1                     */
    kParamInputGain      = 5,  /* 0..1 → maps to 0..2     */
    kParamCount          = 6,
};
