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
#include "public.sdk/source/vst/hosting/parameterchanges.h"
#include "public.sdk/source/vst/hosting/eventlist.h"
#include "public.sdk/source/common/memorystream.h"

using namespace Steinberg;
using namespace Steinberg::Vst;

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

  std::mutex mtx;

  DVH_PluginState()
  : inputParamChanges(64),
    outputParamChanges(64),
    inputEvents(128) {}
};
