/**
 * GrooveForge Vocoder — VST3 Plugin Factory (single-TU compilation)
 */

#include "processor.cpp"
#include "controller.cpp"

#include "public.sdk/source/main/pluginfactory.h"

// Linux VST3 requires ModuleEntry / ModuleExit in addition to GetPluginFactory.
#if defined(__linux__)
#include "public.sdk/source/main/linuxmain.cpp"
#endif

#define stringCompanyName  "GrooveForge"
#define stringCompanyWeb   "https://github.com/grooveforge"
#define stringCompanyEmail "grooveforge@example.com"

BEGIN_FACTORY_DEF(stringCompanyName, stringCompanyWeb, stringCompanyEmail)

    DEF_CLASS2(INLINE_UID_FROM_FUID(kGrooveForgeVocoderProcessorUID),
               PClassInfo::kManyInstances,
               kVstAudioEffectClass,
               "GrooveForge Vocoder",
               Vst::kDistributable,
               Vst::PlugType::kFxModulation,
               "1.0.0",
               kVstVersionString,
               GrooveForgeVocoderProcessor::createInstance)

    DEF_CLASS2(INLINE_UID_FROM_FUID(kGrooveForgeVocoderControllerUID),
               PClassInfo::kManyInstances,
               kVstComponentControllerClass,
               "GrooveForge Vocoder Controller",
               0, "",
               "1.0.0",
               kVstVersionString,
               GrooveForgeVocoderController::createInstance)

END_FACTORY
