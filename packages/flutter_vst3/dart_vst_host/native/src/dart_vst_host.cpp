// Copyright (c) 2025
//
// This file implements a minimal VST3 hosting layer exposing a C API
// suitable for use from Dart via FFI. It loads VST3 modules using
// Steinberg’s public hosting API and wraps components in opaque
// handles. Audio processing is provided for stereo 32‑bit floating
// point buffers. MIDI note on/off events and parameter changes are
// queued into the component prior to each process call.

#include "dart_vst_host.h"

#include <array>
#include <cstdio>
#include <memory>
#include <string>
#include <vector>
#include <mutex>

#include "pluginterfaces/base/ipluginbase.h"
#include "pluginterfaces/base/funknown.h"
#include "pluginterfaces/vst/ivstunits.h"
#include "public.sdk/source/vst/utility/stringconvert.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivsthostapplication.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "pluginterfaces/vst/ivstevents.h"
#include "pluginterfaces/vst/vsttypes.h"
#include "pluginterfaces/vst/vstspeaker.h"
#include "pluginterfaces/vst/ivstmessage.h"

#include "public.sdk/source/vst/hosting/module.h"
#include "public.sdk/source/vst/hosting/plugprovider.h"
#include "public.sdk/source/vst/vsteventshelper.h"
#include "public.sdk/source/vst/hosting/eventlist.h"
#include "public.sdk/source/vst/utility/stringconvert.h"

using namespace Steinberg;
using namespace Steinberg::Vst;

// DVH_HostState is defined in dart_vst_host_internal.h (shared with
// dart_vst_host_jack.cpp so the JACK callback can read sr and maxBlock).
#include "dart_vst_host_internal.h"

static Steinberg::Vst::ProcessContext g_transportContext{};
static std::mutex g_transportMtx;

// Utility converting tresult into 0/1 for C API. Steinberg returns
// kResultTrue on success and kResultFalse or error codes on failure.
static int32_t toOK(tresult r) { return r == kResultTrue ? 1 : 0; }

extern "C" {

DVH_API const char* dvh_get_version() {
#ifdef __APPLE__
    return "1.2.0-macOS-FIXED";
#elif defined(__linux__)
    return "1.2.0-Linux";
#else
    return "1.2.0-Generic";
#endif
}

// Create a new host state with the given sample rate and maximum
// block size. This sets up the VST context factory to point at
// HostApplication for plug‑ins to query host information.
DVH_Host dvh_create_host(double sample_rate, int32_t max_block) {
  auto* h = new DVH_HostState(sample_rate, max_block);
  return (DVH_Host)h;
}

// Destroy a previously created host. Frees all resources. Plug‑ins
// loaded with this host must be destroyed before destroying the host.
void dvh_destroy_host(DVH_Host host) {
  if (!host) return;
  delete (DVH_HostState*)host;
}

// Load a VST3 plug‑in from a module path. Optionally specify a class
// UID string; if null or empty the first Audio Module Class is used.
// On success a new DVH_PluginState is allocated and returned. On
// failure returns nullptr.
DVH_Plugin dvh_load_plugin(DVH_Host host, const char* module_path_utf8, const char* class_uid_or_null) {
  if (!host || !module_path_utf8) return nullptr;
  auto* hs = (DVH_HostState*)host;

  std::string err;
  auto mod = VST3::Hosting::Module::create(module_path_utf8, err);
  if (!mod) return nullptr;

  VST3::Hosting::ClassInfo chosen;
  bool found = false;
  for (auto& ci : mod->getFactory().classInfos()) {
    if (class_uid_or_null && *class_uid_or_null) {
      if (ci.ID().toString() == std::string(class_uid_or_null)) {
        chosen = ci;
        found = true;
        break;
      }
    } else {
      if (ci.category() == std::string("Audio Module Class")) {
        chosen = ci;
        found = true;
        break;
      }
    }
  }
  if (!found) return nullptr;

  // PlugProvider handles the full VST3 initialization sequence:
  //   component->initialize(), controller create+initialize, connect, setComponentState.
  // We MUST keep it alive in DVH_PluginState — its destructor calls terminate().
  auto plugProvider = std::make_shared<Vst::PlugProvider>(mod->getFactory(), chosen, true);
  if (!plugProvider->initialize()) return nullptr;

  auto* ps = new DVH_PluginState();
  ps->module      = mod;
  ps->plugProvider = plugProvider; // keep alive — owns terminate() lifecycle
  ps->classInfo   = chosen;
  ps->component   = plugProvider->getComponentPtr();

  if (!ps->component) { delete ps; return nullptr; }

  ps->processor = Steinberg::FUnknownPtr<IAudioProcessor>(ps->component);
  if (!ps->processor) { delete ps; return nullptr; }

  // PlugProvider::initialize() already initialized and connected the controller.
  // For single-component plugins (IEditController in the component), getControllerPtr()
  // returns null — fall back to querying from the component.
  ps->controller = plugProvider->getControllerPtr();
  if (!ps->controller) {
    IEditController* ec = nullptr;
    if (ps->component->queryInterface(IEditController::iid, (void**)&ec) == kResultTrue && ec) {
      ps->controller = ec;
      ec->release();
      ps->singleComponent = true;
      // PlugProvider already called component->initialize(); the single-component
      // controller IS the component, so we must NOT initialize it again.
    }
  }

  // IConnectionPoints are only needed for cleanup disconnect in dvh_unload_plugin.
  // PlugProvider already connected them; we just grab references for disconnection.
  ps->component->queryInterface(IConnectionPoint::iid, (void**)&ps->compCP);
  if (ps->controller && !ps->singleComponent)
    ps->controller->queryInterface(IConnectionPoint::iid, (void**)&ps->ctrlCP);

  // Synchronise component state to controller so JUCE-based plugins (Surge XT,
  // DISTRHO, etc.) can build their internal processor reference before createView().
  // PlugProvider does NOT do this — we must call it ourselves.
  if (ps->controller && !ps->singleComponent) {
    MemoryStream stateStream;
    if (ps->component->getState(&stateStream) == kResultTrue) {
      stateStream.seek(0, IBStream::kIBSeekSet, nullptr);
      tresult sr = ps->controller->setComponentState(&stateStream);
      fprintf(stderr, "[dart_vst_host] setComponentState result=%d\n", (int)sr);
    } else {
      fprintf(stderr, "[dart_vst_host] getState() failed — skipping setComponentState\n");
    }
  }

  fprintf(stderr, "[dart_vst_host] loaded: component=%p controller=%p singleComponent=%d paramCount=%d\n",
          (void*)ps->component.get(), (void*)ps->controller.get(),
          (int)ps->singleComponent,
          ps->controller ? ps->controller->getParameterCount() : 0);

  return (DVH_Plugin)ps;
}

// Unload a previously loaded plug‑in. Terminates the component and
// controller and frees the DVH_PluginState. Does nothing if p is
// nullptr.
void dvh_unload_plugin(DVH_Plugin p) {
  if (!p) return;
  auto* ps = (DVH_PluginState*)p;
  if (ps->active) {
    ps->processor->setProcessing(false);
    ps->component->setActive(false);
    ps->active = false;
  }
  // PlugProvider owns the terminate() lifecycle and will call it when ps->plugProvider
  // is released (destroyed with ps). Do NOT call terminate() manually here to avoid
  // double-terminate which corrupts JUCE-based plugins.
  delete ps;
  // ps->plugProvider shared_ptr goes out of scope here, PlugProvider::releasePlugIn()
  // disconnects component/controller and calls terminate() exactly once.
}

// Activate processing for a plug‑in.
//
// Instrument plugins (synthesizers) typically expose 0 audio input buses and
// 1 (or more) stereo output buses. Effect plugins expose ≥1 input + ≥1 output.
// We probe the actual bus counts and build correctly-sized SpeakerArrangement
// arrays so that plugins with multiple buses (e.g. Surge XT with its Scene B
// output) are handled without setBusArrangements() returning kResultFalse.
int32_t dvh_resume(DVH_Plugin p, double sample_rate, int32_t max_block) {
  if (!p) return 0;
  auto* ps = (DVH_PluginState*)p;
  std::lock_guard<std::mutex> g(ps->mtx);

  const int32 numAudioIn  = ps->component->getBusCount(kAudio, kInput);
  const int32 numAudioOut = ps->component->getBusCount(kAudio, kOutput);
  if (numAudioOut == 0) return 0;

  // Build stereo arrangements for every declared bus.
  std::vector<SpeakerArrangement> inArrs(numAudioIn,  SpeakerArr::kStereo);
  std::vector<SpeakerArrangement> outArrs(numAudioOut, SpeakerArr::kStereo);

  SpeakerArrangement* inPtr  = numAudioIn  > 0 ? inArrs.data()  : nullptr;
  SpeakerArrangement* outPtr = numAudioOut > 0 ? outArrs.data() : nullptr;

  // Try the full bus count first; fall back to first-bus-only for strict plugins.
  if (ps->processor->setBusArrangements(inPtr, numAudioIn, outPtr, numAudioOut) != kResultTrue) {
    SpeakerArrangement stereo = SpeakerArr::kStereo;
    if (ps->processor->setBusArrangements(inPtr, std::min(numAudioIn, 1),
                                          &stereo, 1) != kResultTrue) {
      return 0;
    }
  }

  // Activate all buses so the plugin can route audio through them.
  for (int32 i = 0; i < numAudioIn;  ++i) ps->component->activateBus(kAudio, kInput,  i, true);
  for (int32 i = 0; i < numAudioOut; ++i) ps->component->activateBus(kAudio, kOutput, i, true);

  // Record for use in dvh_process_stereo_f32.
  ps->numAudioInputBuses  = numAudioIn;
  ps->numAudioOutputBuses = numAudioOut;

  ps->setup.processMode = kRealtime;
  ps->setup.symbolicSampleSize = kSample32;
  ps->setup.maxSamplesPerBlock = max_block;
  ps->setup.sampleRate = sample_rate;

  if (ps->processor->setupProcessing(ps->setup) != kResultTrue) return 0;
  if (ps->component->setActive(true) != kResultTrue) return 0;
  if (ps->processor->setProcessing(true) != kResultTrue) return 0;

  // Pre-allocate process buffers so dvh_process_stereo_f32 never allocates
  // on the audio thread.  Secondary output buses (bus 1+) get scratch memory;
  // bus 0 uses the caller's outL/outR pointers directly.
  const int32_t secOut = std::max(0, numAudioOut - 1);
  ps->procScratch.assign(secOut * 2 * max_block, 0.f);
  ps->procOutPtrs.resize(numAudioOut);
  ps->procOutBufs.resize(numAudioOut);
  ps->procInBufs.resize(std::max(numAudioIn, 1));

  ps->active = true;
  fprintf(stderr, "[dart_vst_host] dvh_resume(p=%p) success: sr=%.1f maxBlock=%d numIn=%d numOut=%d\n",
          p, sample_rate, max_block, numAudioIn, numAudioOut);
  fflush(stderr);
  return 1;
}

// Suspend processing for a plug‑in. Deactivates processing and the
// component. Returns 1 on success.
int32_t dvh_suspend(DVH_Plugin p) {
  if (!p) return 0;
  auto* ps = (DVH_PluginState*)p;
  std::lock_guard<std::mutex> g(ps->mtx);
  if (!ps->active) return 1;
  ps->processor->setProcessing(false);
  ps->component->setActive(false);
  ps->active = false;
  return 1;
}

// Process a block of stereo audio. Copies input buffers into the
// plug‑in’s buffers, calls process(), then copies the output back
// out. Parameter changes and MIDI events are consumed each block.
int32_t dvh_process_stereo_f32(DVH_Plugin p,
                               const float* inL, const float* inR,
                               float* outL, float* outR,
                               int32_t num_frames) {
  if (!p || !inL || !inR || !outL || !outR || num_frames <= 0) return 0;
  auto* ps = (DVH_PluginState*)p;
  std::lock_guard<std::mutex> g(ps->mtx);

  // ── Output buses (pre-allocated in dvh_resume — zero allocation) ────────
  // Bus 0 = caller's outL/outR; secondary buses → procScratch.
  const int32 numOut = ps->numAudioOutputBuses;
  ps->procOutPtrs[0] = { outL, outR };
  for (int32 i = 1; i < numOut; ++i) {
    ps->procOutPtrs[i] = {
      ps->procScratch.data() + (i - 1) * 2 * num_frames,
      ps->procScratch.data() + (i - 1) * 2 * num_frames + num_frames
    };
  }
  for (int32 i = 0; i < numOut; ++i) {
    ps->procOutBufs[i] = {};
    ps->procOutBufs[i].numChannels = 2;
    ps->procOutBufs[i].channelBuffers32 = ps->procOutPtrs[i].data();
  }

  // ── Input buses (pre-allocated in dvh_resume — zero allocation) ────────
  const int32 numIn = ps->numAudioInputBuses;
  const float* inChannels[2] = { inL, inR };
  for (int32 i = 0; i < numIn; ++i) {
    ps->procInBufs[i] = {};
    ps->procInBufs[i].numChannels = 2;
    ps->procInBufs[i].channelBuffers32 = const_cast<float**>(inChannels);
  }

  // ── ProcessContext ────────────────────────────────────────────────────────
  ProcessContext ctxCopy;
  {
      std::lock_guard<std::mutex> lock(g_transportMtx);
      ctxCopy = g_transportContext;
      if (g_transportContext.state & Steinberg::Vst::ProcessContext::kPlaying) {
          g_transportContext.projectTimeSamples += num_frames;
          double currentBps = g_transportContext.tempo / 60.0;
          double beatsPerSample = currentBps / ps->setup.sampleRate;
          g_transportContext.projectTimeMusic += beatsPerSample * num_frames;
      }
  }
  ctxCopy.sampleRate = ps->setup.sampleRate;

  // ── ProcessData ───────────────────────────────────────────────────────────
  ProcessData data{};
  data.processMode        = ps->setup.processMode;
  data.symbolicSampleSize = ps->setup.symbolicSampleSize;
  data.numSamples         = num_frames;
  data.numInputs          = numIn;
  data.inputs             = numIn  > 0 ? ps->procInBufs.data()  : nullptr;
  data.numOutputs         = numOut;
  data.outputs            = numOut > 0 ? ps->procOutBufs.data() : nullptr;
  data.inputParameterChanges  = &ps->inputParamChanges;
  data.outputParameterChanges = &ps->outputParamChanges;
  data.inputEvents            = &ps->inputEvents;
  data.processContext         = &ctxCopy;

  auto r = ps->processor->process(data);

  ps->inputParamChanges.clearQueue();
  ps->outputParamChanges.clearQueue();
  ps->inputEvents.clear();

  return toOK(r);
}

// Queue a note on event for the plug‑in. The event is added to the
// inputEvents list and consumed on the next process() call. Returns
// 1 on success.
int32_t dvh_note_on(DVH_Plugin p, int32_t channel, int32_t note, float velocity) {
  if (!p) return 0;
  auto* ps = (DVH_PluginState*)p;
  fprintf(stderr, "[dart_vst_host] note_on ch=%d note=%d vel=%.2f active=%d\n",
          channel, note, velocity, (int)ps->active);
  Vst::Event e{};
  e.type = Vst::Event::kNoteOnEvent;
  e.sampleOffset = 0;
  e.noteOn.channel = (int16)channel;
  e.noteOn.pitch = (int16)note;
  e.noteOn.velocity = velocity;
  return toOK(ps->inputEvents.addEvent(e));
}

// Queue a note off event for the plug‑in. Returns 1 on success.
int32_t dvh_note_off(DVH_Plugin p, int32_t channel, int32_t note, float velocity) {
  if (!p) return 0;
  auto* ps = (DVH_PluginState*)p;
  Vst::Event e{};
  e.type = Vst::Event::kNoteOffEvent;
  e.sampleOffset = 0;
  e.noteOff.channel = (int16)channel;
  e.noteOff.pitch = (int16)note;
  e.noteOff.velocity = velocity;
  return toOK(ps->inputEvents.addEvent(e));
}

// Retrieve the number of parameters defined by the plug‑in’s
// controller. Returns zero if no controller is present.
int32_t dvh_param_count(DVH_Plugin p) {
  if (!p) return 0;
  auto* ps = (DVH_PluginState*)p;
  if (!ps->controller) return 0;
  return ps->controller->getParameterCount();
}

// Helper to copy UTF‑8 strings into user provided buffers. Ensures
// null‑termination and truncates if necessary.
static void copy_utf8(const std::string& s, char* out, int32_t cap) {
  if (!out || cap <= 0) return;
  auto n = (int32_t)s.size();
  if (n >= cap) n = cap - 1;
  memcpy(out, s.data(), (size_t)n);
  out[n] = 0;
}

// Retrieve parameter information by index. Fills out the parameter
// ID and copies the title and units into provided UTF‑8 buffers.
int32_t dvh_param_info(DVH_Plugin p, int32_t index,
                       int32_t* id_out,
                       char* title_utf8, int32_t title_cap,
                       char* units_utf8, int32_t units_cap) {
  if (!p) return 0;
  auto* ps = (DVH_PluginState*)p;
  if (!ps->controller) return 0;
  ParameterInfo pi{};
  if (ps->controller->getParameterInfo(index, pi) != kResultTrue) return 0;
  if (id_out) *id_out = (int32_t)pi.id;
  std::string title, units;
  {
    auto t = Steinberg::Vst::StringConvert::convert(pi.title);
    title = t;
    auto u = Steinberg::Vst::StringConvert::convert(pi.units);
    units = u;
  }
  copy_utf8(title, title_utf8, title_cap);
  copy_utf8(units, units_utf8, units_cap);
  return 1;
}

// Get the current normalized value of a parameter. Returns 0.0 if
// the controller is not present.
float dvh_get_param_normalized(DVH_Plugin p, int32_t param_id) {
  if (!p) return 0.f;
  auto* ps = (DVH_PluginState*)p;
  if (!ps->controller) return 0.f;
  return (float)ps->controller->getParamNormalized((ParamID)param_id);
}

// Set a normalized value for a parameter. The value is also enqueued
// into the inputParamChanges list so the processor sees the change on
// the next process() call. Returns 1 on success.
int32_t dvh_set_param_normalized(DVH_Plugin p, int32_t param_id, float normalized) {
  if (!p) return 0;
  auto* ps = (DVH_PluginState*)p;
  if (!ps->controller) return 0;

  ps->controller->setParamNormalized((ParamID)param_id, normalized);

  int32 idx = 0;
  IParamValueQueue* q = ps->inputParamChanges.addParameterData((ParamID)param_id, idx);
  if (!q) return 0;
  q->addPoint(0, normalized, idx);
  return 1;
}

// Returns the unitId for the parameter at [index], or -1 on failure.
// Plugins use unitIds to group related parameters (e.g. oscillators, filters).
int32_t dvh_param_unit_id(DVH_Plugin p, int32_t index) {
  if (!p) return -1;
  auto* ps = (DVH_PluginState*)p;
  if (!ps->controller) return -1;
  ParameterInfo pi{};
  if (ps->controller->getParameterInfo(index, pi) != kResultTrue) return -1;
  return (int32_t)pi.unitId;
}

// Returns the number of parameter groups (units) declared by the plugin.
int32_t dvh_unit_count(DVH_Plugin p) {
  if (!p) return 0;
  auto* ps = (DVH_PluginState*)p;
  if (!ps->controller) return 0;
  IUnitInfo* ui = nullptr;
  if (ps->controller->queryInterface(IUnitInfo::iid, (void**)&ui) != kResultTrue || !ui)
    return 0;
  const int32 count = ui->getUnitCount();
  ui->release();
  return (int32_t)count;
}

// Fills [name_out] with the UTF-8 name for the unit whose ID is [unit_id].
// Returns 1 on success, 0 if not found or IUnitInfo is not available.
int32_t dvh_unit_name(DVH_Plugin p, int32_t unit_id,
                      char* name_out, int32_t name_cap) {
  if (!p || !name_out || name_cap <= 0) return 0;
  auto* ps = (DVH_PluginState*)p;
  if (!ps->controller) return 0;
  IUnitInfo* ui = nullptr;
  if (ps->controller->queryInterface(IUnitInfo::iid, (void**)&ui) != kResultTrue || !ui)
    return 0;
  const int32 count = ui->getUnitCount();
  for (int32 i = 0; i < count; i++) {
    UnitInfo info{};
    if (ui->getUnitInfo(i, info) == kResultTrue && (int32_t)info.id == unit_id) {
      auto name = Steinberg::Vst::StringConvert::convert(info.name);
      copy_utf8(name, name_out, name_cap);
      ui->release();
      return 1;
    }
  }
  ui->release();
  return 0;
}

DVH_API void dvh_set_transport(double bpm, int32_t timeSigNum, int32_t timeSigDen, int32_t isPlaying, double positionInBeats, int32_t positionInSamples) {
  std::lock_guard<std::mutex> lock(g_transportMtx);
  g_transportContext.tempo = bpm;
  g_transportContext.timeSigNumerator = timeSigNum;
  g_transportContext.timeSigDenominator = timeSigDen;
  if (isPlaying) {
      g_transportContext.state |= Steinberg::Vst::ProcessContext::kPlaying;
  } else {
      g_transportContext.state &= ~Steinberg::Vst::ProcessContext::kPlaying;
  }
  // Only overwrite position if resetting to 0 to avoid jitter when just changing BPM.
  if (positionInBeats == 0.0 && positionInSamples == 0) {
      g_transportContext.projectTimeMusic = 0.0;
      g_transportContext.projectTimeSamples = 0;
  }
  g_transportContext.state |= Steinberg::Vst::ProcessContext::kTempoValid |
                              Steinberg::Vst::ProcessContext::kTimeSigValid |
                              Steinberg::Vst::ProcessContext::kProjectTimeMusicValid;
}

} // extern "C"