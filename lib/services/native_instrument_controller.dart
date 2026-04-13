import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/gfpa_plugin_instance.dart';
import 'audio_input_ffi.dart';
import 'gfpa_android_bindings.dart';

/// Wraps the rack-lifetime (as opposed to widget-lifetime) native-synth
/// management for monophonic, global-state instruments (stylophone and
/// theremin).
///
/// ## Why this exists
///
/// The rack is a lazy [ReorderableListView.builder] — off-screen slot widgets
/// never mount. Previously, each widget's `initState` called
/// [AudioInputFFI.styloStart] / [AudioInputFFI.thereminStart], and its
/// `dispose` called the matching `*Stop`. This tied native-synth lifetime to
/// the widget lifecycle: scrolling a slot off-screen silenced the instrument
/// entirely, and scrolling it back re-started from scratch. CC-triggered
/// actions aimed at an off-screen stylophone were silent until the user
/// scrolled to it.
///
/// The controller moves that lifetime up to "slot present in the rack". It
/// is called from two places:
///
///   1. Splash-screen project load, for every persisted slot.
///   2. `RackState.addPlugin` / `RackState.removePlugin`, for runtime
///      additions and deletions.
///
/// ## Reference counting
///
/// Both native synths are global singletons (one native oscillator per
/// instrument type, regardless of how many rack slots reference it). The
/// controller ref-counts slots of each type so `start` only calls the native
/// bring-up on the first slot, and `stop` only tears down when the last slot
/// is removed.
class NativeInstrumentController {
  NativeInstrumentController._();
  static final NativeInstrumentController instance =
      NativeInstrumentController._();

  int _stylophoneRefCount = 0;
  int _thereminRefCount = 0;
  int _vocoderRefCount = 0;
  int _liveInputRefCount = 0;

  /// Bring up the stylophone for a rack slot that has just been added or
  /// restored from disk. Starts the native oscillator on the first call and
  /// syncs any saved waveform / vibrato state from [instance].
  ///
  /// **On Android**, also routes the native render function onto the shared
  /// AAudio bus on slot [kBusSlotStylophone] (101) so GFPA effects can
  /// process the stylophone's output AND so the audio looper can cable
  /// directly into it. Miniaudio playback is silenced via capture mode to
  /// prevent double output.
  ///
  /// Idempotent per slot: calling twice for the same slot is handled by the
  /// caller (rack-level add-plugin is single-shot).
  void onStylophoneAdded(GFpaPluginInstance instance) {
    _stylophoneRefCount += 1;
    if (_stylophoneRefCount == 1) {
      AudioInputFFI().styloStart();
      if (!kIsWeb && Platform.isAndroid) {
        // Silence miniaudio; let the Oboe bus render the oscillator instead.
        // Mirrors the theremin pattern — the native DSP state stays
        // singleton, but the audio path flows through the shared bus.
        AudioInputFFI().styloSetCaptureMode(enabled: true);
        final fnAddr = AudioInputFFI().styloBusRenderFnAddr();
        GfpaAndroidBindings.instance
            .oboeStreamAddSource(fnAddr, kBusSlotStylophone);
      }
    }
    _syncStylophoneState(instance);
  }

  /// Tear down the stylophone when a rack slot is removed. Decrements the
  /// ref count and stops the native oscillator only when the last slot goes
  /// away.
  ///
  /// On Android, the Oboe bus source is removed BEFORE the native device is
  /// stopped so the audio callback cannot dereference freed DSP state — the
  /// remove call blocks until any in-flight snapshot drains. This mirrors
  /// the theremin teardown order for the same reason.
  void onStylophoneRemoved() {
    if (_stylophoneRefCount == 0) return;
    _stylophoneRefCount -= 1;
    if (_stylophoneRefCount == 0) {
      AudioInputFFI().styloNoteOff();
      if (!kIsWeb && Platform.isAndroid) {
        GfpaAndroidBindings.instance.oboeStreamRemoveSource(kBusSlotStylophone);
        AudioInputFFI().styloSetCaptureMode(enabled: false);
      }
      AudioInputFFI().styloStop();
    }
  }

  /// Push saved waveform and vibrato state from [instance] to the native
  /// synth. Called on add and also on demand (e.g. after a soundfont swap).
  void _syncStylophoneState(GFpaPluginInstance instance) {
    final waveform = (instance.state['waveform'] as num?)?.toInt() ?? 0;
    if (waveform > 0 && waveform <= 3) {
      AudioInputFFI().styloSetWaveform(waveform);
    }
    final vibrato =
        (instance.state['vibrato'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.0;
    if (vibrato > 0.0) {
      AudioInputFFI().styloSetVibrato(vibrato);
    }
  }

  /// Bring up the theremin for a rack slot that has just been added or
  /// restored from disk. On Android this also routes the native render
  /// function onto the shared AAudio bus so GFPA effects (WAH, reverb, …)
  /// can process the theremin's output.
  void onThereminAdded(GFpaPluginInstance instance) {
    _thereminRefCount += 1;
    if (_thereminRefCount == 1) {
      AudioInputFFI().thereminStart();
      if (!kIsWeb && Platform.isAndroid) {
        // Silence the miniaudio device so only the AAudio bus renders the
        // oscillator — prevents double audio output on Android.
        AudioInputFFI().thereminSetCaptureMode(enabled: true);
        final fnAddr = AudioInputFFI().thereminBusRenderFnAddr();
        GfpaAndroidBindings.instance
            .oboeStreamAddSource(fnAddr, kBusSlotTheremin);
      }
    }
    _syncThereminState(instance);
  }

  /// Tear down the theremin when a rack slot is removed.
  ///
  /// On Android, the AAudio bus source is removed BEFORE stopping the native
  /// synth so the audio callback cannot dereference freed DSP state. The
  /// remove call blocks until any in-flight snapshot drains.
  void onThereminRemoved() {
    if (_thereminRefCount == 0) return;
    _thereminRefCount -= 1;
    if (_thereminRefCount == 0) {
      AudioInputFFI().thereminSetVolume(0.0);
      if (!kIsWeb && Platform.isAndroid) {
        GfpaAndroidBindings.instance.oboeStreamRemoveSource(kBusSlotTheremin);
        AudioInputFFI().thereminSetCaptureMode(enabled: false);
      }
      AudioInputFFI().thereminStop();
    }
  }

  /// Push saved vibrato depth from [instance] to the native theremin.
  void _syncThereminState(GFpaPluginInstance instance) {
    final vibrato =
        (instance.state['vibrato'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.0;
    AudioInputFFI().thereminSetVibrato(vibrato);
  }

  /// Bring up Android Oboe-bus routing for the vocoder when a rack slot is
  /// added or restored from disk.
  ///
  /// **This method is Android-only and a pure routing switch.** Unlike
  /// [onStylophoneAdded] / [onThereminAdded], it does NOT start or stop any
  /// miniaudio device — the vocoder's mic capture device is managed
  /// independently by [AudioEngine.startCapture] / [stopCapture] (called
  /// from the preferences screen and on-demand when the user grants mic
  /// permission). What changes here is only which code path produces the
  /// playback signal:
  ///
  ///   - **Without a vocoder slot in the rack** (ref count 0): miniaudio's
  ///     `data_callback` owns playback and writes the DSP output directly
  ///     to the device.
  ///   - **With ≥1 vocoder slot in the rack** (ref count > 0): capture mode
  ///     is enabled — miniaudio writes silence — and `vocoder_bus_render`
  ///     is registered on Oboe bus slot [kBusSlotVocoder] so the shared
  ///     AAudio callback pulls the DSP on demand. This is what makes
  ///     GFPA effect insert chains and the audio looper able to see the
  ///     vocoder signal.
  ///
  /// On non-Android platforms the call is a no-op because desktop drives
  /// the vocoder through the JACK / CoreAudio master-render list instead.
  void onVocoderAdded() {
    _vocoderRefCount += 1;
    if (kIsWeb || !Platform.isAndroid) return;
    if (_vocoderRefCount == 1) {
      AudioInputFFI().vocoderSetCaptureMode(enabled: true);
      final fnAddr = AudioInputFFI().vocoderBusRenderFnAddr();
      GfpaAndroidBindings.instance
          .oboeStreamAddSource(fnAddr, kBusSlotVocoder);
    }
  }

  /// Tear down Android Oboe-bus routing for the vocoder when a rack slot is
  /// removed. On the last slot removal, removes the bus source BEFORE
  /// disabling capture mode so the audio callback cannot dereference the
  /// render function after it may have been unloaded. Mirrors the theremin
  /// teardown order.
  ///
  /// No-op on non-Android platforms.
  void onVocoderRemoved() {
    if (_vocoderRefCount == 0) return;
    _vocoderRefCount -= 1;
    if (kIsWeb || !Platform.isAndroid) return;
    if (_vocoderRefCount == 0) {
      GfpaAndroidBindings.instance.oboeStreamRemoveSource(kBusSlotVocoder);
      AudioInputFFI().vocoderSetCaptureMode(enabled: false);
    }
  }

  /// Bring up shared capture for a Live Input Source slot. First slot
  /// added starts the shared miniaudio capture device; subsequent slots
  /// are a no-op. Capture is shared with the vocoder, so it is left
  /// running until the last capture consumer goes away.
  ///
  /// The Android Oboe-bus source registration is **not** done here — it
  /// lives in [syncLiveInputBusSource] because the bus mixer always sums
  /// the source into the master output, and a Live Input slot with no
  /// downstream cable would leak raw mic audio into everything.
  void onLiveInputAdded() {
    _liveInputRefCount += 1;
    if (_liveInputRefCount != 1) return;
    AudioInputFFI().startCapture();
  }

  /// Decrement the Live Input ref count on slot removal. The Oboe bus
  /// source (if any) is torn down separately via [syncLiveInputBusSource]
  /// on the next routing rebuild.
  ///
  /// Capture itself is left running because it is shared with the vocoder.
  /// Stopping it here would silence the vocoder too.
  void onLiveInputRemoved() {
    if (_liveInputRefCount == 0) return;
    _liveInputRefCount -= 1;
  }

  /// Whether the Live Input Source is currently registered as a source on
  /// the shared Oboe bus (Android only). Tracked here so the routing sync
  /// path can call add/remove exactly once per transition without having
  /// to probe the native layer.
  bool _liveInputBusActive = false;

  /// Drive Oboe bus registration for the Live Input Source from routing
  /// state. Called by `_syncAudioRoutingAndroid` on every rebuild.
  ///
  /// [shouldBeActive] is true when at least one Live Input slot has an
  /// outgoing audio cable (into a GFPA effect or the audio looper).
  /// Transitions register/unregister `live_input_bus_render` on bus slot
  /// [kBusSlotLiveInput]; same-state calls are no-ops.
  ///
  /// Idle slots therefore stay silent — unlike the theremin/stylophone,
  /// which are user-driven instruments where always-in-mix makes sense.
  void syncLiveInputBusSource({required bool shouldBeActive}) {
    if (kIsWeb || !Platform.isAndroid) return;
    if (shouldBeActive == _liveInputBusActive) return;
    if (shouldBeActive) {
      final fnAddr = AudioInputFFI().liveInputBusRenderFnAddr();
      GfpaAndroidBindings.instance
          .oboeStreamAddSource(fnAddr, kBusSlotLiveInput);
    } else {
      GfpaAndroidBindings.instance
          .oboeStreamRemoveSource(kBusSlotLiveInput);
    }
    _liveInputBusActive = shouldBeActive;
  }
}
