// Internal shared header for dart_vst_host translation units.
// NOT part of the public API — do not include from outside the native/ directory.
#pragma once

#include <array>
#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

// ── Cross-TU helpers (audio backend ↔ main) ────────────────────────────────

/// Broadcast transport state to all JACK AudioState instances (Linux).
void dvh_jack_update_transport(double bpm, int32_t timeSigNum,
                                int32_t isPlaying, double positionInBeats);

/// Broadcast transport state to all desktop AudioState instances
/// (macOS CoreAudio + Windows WASAPI, both via miniaudio). Defined in
/// `dart_vst_host_audio_desktop.cpp`.
void dvh_desktop_update_transport(double bpm, int32_t timeSigNum,
                                   int32_t isPlaying, double positionInBeats);

/// Re-prepares an active plug-in for [sample_rate] when it was resumed at
/// another rate. The Dart side resumes plug-ins at 48 kHz before the audio
/// backend has said what it runs at; JACK on PipeWire often runs at 44.1 kHz,
/// and a plug-in set up for the wrong rate plays out of tune. Called by the
/// JACK backend when it starts, when a plug-in joins the audio loop, and when
/// the server's rate changes. Not for the audio thread.
extern "C" void dvh_match_sample_rate(void* plugin, double sample_rate);

#include "pluginterfaces/base/funknown.h"
#include "pluginterfaces/base/ipluginbase.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivstmidicontrollers.h"
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

/// One MIDI or parameter message waiting to reach a plug-in's process().
///
/// Written by the UI thread (Dart, through FFI), read by the audio thread.
/// The VST3 EventList and ParameterChanges containers are not thread-safe,
/// so the UI thread never touches them: it posts messages here, and the
/// audio thread moves them into those containers at the start of a block.
struct DVH_PendingMsg {
  enum Kind : uint8_t { kNoteOn, kNoteOff, kParam };
  Kind    kind{kNoteOn};
  int16_t channel{0};
  /// Note number for notes, parameter id for parameter changes.
  int32_t id{0};
  /// Velocity (0-1) for notes, normalized value (0-1) for parameters.
  float   value{0.f};
};

/// Number of messages a plug-in can have waiting between two audio blocks.
/// A block is a few milliseconds; 512 covers a full chord with every key's
/// expression many times over. When full, new messages are dropped rather
/// than blocking the UI or the audio thread.
constexpr uint32_t kDvhPendingCapacity = 512;

/// MIDI controller numbers a plug-in can map to parameters: the 128 CCs plus
/// the VST3 pseudo-controllers kAfterTouch (128) and kPitchBend (129).
constexpr int32_t kDvhMidiControllers = 130;

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

  // ── Messages from the UI thread (single producer, single consumer) ──────
  // Ring buffer: the UI thread writes at pendingHead, the audio thread reads
  // at pendingTail. Indices only grow; a slot is index % capacity.
  std::array<DVH_PendingMsg, kDvhPendingCapacity> pending{};
  std::atomic<uint32_t> pendingHead{0};
  std::atomic<uint32_t> pendingTail{0};

  // ── MIDI controller → parameter table (IMidiMapping) ────────────────────
  // VST3 has no event for CC or pitch bend: a plug-in that responds to them
  // maps each controller to one of its parameters. The table is read once at
  // load (getMidiControllerAssignment may only be called off the audio
  // thread). -1 means the plug-in ignores that controller on that channel.
  std::array<std::array<int32_t, kDvhMidiControllers>, 16> midiMap{};

  DVH_PluginState()
  : inputParamChanges(64),
    outputParamChanges(64),
    inputEvents(128) {}
};
