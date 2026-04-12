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

  /// Bring up the stylophone for a rack slot that has just been added or
  /// restored from disk. Starts the native oscillator on the first call and
  /// syncs any saved waveform / vibrato state from [instance].
  ///
  /// Idempotent per slot: calling twice for the same slot is handled by the
  /// caller (rack-level add-plugin is single-shot).
  void onStylophoneAdded(GFpaPluginInstance instance) {
    _stylophoneRefCount += 1;
    if (_stylophoneRefCount == 1) {
      AudioInputFFI().styloStart();
    }
    _syncStylophoneState(instance);
  }

  /// Tear down the stylophone when a rack slot is removed. Decrements the
  /// ref count and stops the native oscillator only when the last slot goes
  /// away.
  void onStylophoneRemoved() {
    if (_stylophoneRefCount == 0) return;
    _stylophoneRefCount -= 1;
    if (_stylophoneRefCount == 0) {
      AudioInputFFI().styloNoteOff();
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
}
