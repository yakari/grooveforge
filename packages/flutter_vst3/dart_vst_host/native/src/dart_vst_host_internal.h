// Internal shared header for dart_vst_host translation units.
// NOT part of the public API — do not include from outside the native/ directory.
#pragma once

#include <array>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "pluginterfaces/base/funknown.h"
#include "pluginterfaces/base/ipluginbase.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "pluginterfaces/vst/ivstmessage.h"
#include "public.sdk/source/vst/hosting/module.h"
#include "public.sdk/source/vst/hosting/plugprovider.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"
#include "public.sdk/source/vst/hosting/parameterchanges.h"
#include "public.sdk/source/vst/hosting/eventlist.h"
#include "public.sdk/source/common/memorystream.h"

using namespace Steinberg;
using namespace Steinberg::Vst;

/// Host state object storing global context for a set of plugins.
///
/// Owns a HostApplication which VST3 plug-ins can query for host services.
/// The sample rate and max block size are set once at creation and used
/// by all plug-ins registered with this host.
struct DVH_HostState {
  double sr;
  int32 maxBlock;
  HostApplication hostApp;
  DVH_HostState(double s, int32 m) : sr(s), maxBlock(m) {
    Vst::PluginContextFactory::instance().setPluginContext(&hostApp);
  }
};

struct DVH_PluginState {
  std::shared_ptr<VST3::Hosting::Module> module;
  // PlugProvider must stay alive for the lifetime of the plugin: its destructor
  // calls terminate() on the component and controller. Without keeping it alive
  // the plugin is terminated immediately after dvh_load_plugin returns.
  std::shared_ptr<Steinberg::Vst::PlugProvider> plugProvider;
  VST3::Hosting::ClassInfo classInfo;
  IPtr<IComponent>      component;
  IPtr<IAudioProcessor> processor;
  IPtr<IEditController> controller;
  IPtr<IConnectionPoint> compCP;
  IPtr<IConnectionPoint> ctrlCP;

  ParameterChanges inputParamChanges;
  ParameterChanges outputParamChanges;
  EventList        inputEvents;

  ProcessSetup setup{};
  bool  active{false};
  int32 numAudioInputBuses{0};
  int32 numAudioOutputBuses{1};
  bool  singleComponent{false};

  // ── Pre-allocated process buffers (avoid heap allocation on RT thread) ──
  // Sized once in dvh_resume() when numAudioOutputBuses and maxBlock are known.

  /// Scratch buffer for secondary output buses (bus 1, 2, … — bus 0 uses
  /// the caller-provided outL/outR pointers directly).
  /// Layout: bus1L[maxBlock], bus1R[maxBlock], bus2L[maxBlock], …
  std::vector<float> procScratch;
  /// Per-bus stereo pointer pairs: outPtrs[i] = { left*, right* }.
  std::vector<std::array<float*, 2>> procOutPtrs;
  /// AudioBusBuffers for output buses.
  std::vector<AudioBusBuffers> procOutBufs;
  /// AudioBusBuffers for input buses.
  std::vector<AudioBusBuffers> procInBufs;

  std::mutex mtx;

  DVH_PluginState()
  : inputParamChanges(64),
    outputParamChanges(64),
    inputEvents(128) {}
};
