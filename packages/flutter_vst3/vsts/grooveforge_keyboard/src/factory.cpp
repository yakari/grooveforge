/**
 * GrooveForge Keyboard — VST3 Plugin Factory (single-TU compilation)
 *
 * Processor and controller are included directly so BEGIN_FACTORY_DEF can
 * reference their createInstance statics without cross-unit linkage.
 */

// Pull in the two implementation units before the factory macro.
#include "processor.cpp"
#include "controller.cpp"

#include "public.sdk/source/main/pluginfactory.h"

// Linux VST3 requires ModuleEntry / ModuleExit in addition to GetPluginFactory.
// pluginfactory.h provides GetPluginFactory; linuxmain.cpp provides the other two.
#if defined(__linux__)
#include "public.sdk/source/main/linuxmain.cpp"
#endif

#define stringCompanyName  "GrooveForge"
#define stringCompanyWeb   "https://github.com/grooveforge"
#define stringCompanyEmail "grooveforge@example.com"

BEGIN_FACTORY_DEF(stringCompanyName, stringCompanyWeb, stringCompanyEmail)

    DEF_CLASS2(INLINE_UID_FROM_FUID(kGrooveForgeKeyboardProcessorUID),
               PClassInfo::kManyInstances,
               kVstAudioEffectClass,
               "GrooveForge Keyboard",
               Vst::kDistributable,
               Vst::PlugType::kInstrumentSynth,
               "1.0.0",
               kVstVersionString,
               GrooveForgeKeyboardProcessor::createInstance)

    DEF_CLASS2(INLINE_UID_FROM_FUID(kGrooveForgeKeyboardControllerUID),
               PClassInfo::kManyInstances,
               kVstComponentControllerClass,
               "GrooveForge Keyboard Controller",
               0, "",
               "1.0.0",
               kVstVersionString,
               GrooveForgeKeyboardController::createInstance)

END_FACTORY
