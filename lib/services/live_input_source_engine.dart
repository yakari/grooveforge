import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/live_input_source_plugin_instance.dart';
import 'audio_engine.dart';
import 'audio_input_ffi.dart';

/// Lightweight description of a hardware audio input device as reported
/// by the native layer (miniaudio on desktop, Oboe/AAudio on Android).
///
/// The [index] is the position returned by
/// [AudioInputFFI.getCaptureDeviceName] and is the handle the native
/// side uses to identify the device. The [name] is already human-readable
/// and can be shown directly in a dropdown.
@immutable
class LiveInputDevice {
  final int index;
  final String name;

  const LiveInputDevice({required this.index, required this.name});

  @override
  bool operator ==(Object other) =>
      other is LiveInputDevice && other.index == index && other.name == name;

  @override
  int get hashCode => Object.hash(index, name);
}

/// Engine backing one or more [LiveInputSourcePluginInstance] rack slots.
///
/// Responsibilities:
///   - Enumerate capture devices and publish them to the UI.
///   - Track the set of active Live Input slots and ensure the shared
///     miniaudio capture device is running whenever at least one is
///     attached. The device is shared with the vocoder, so stopping it
///     is left to [AudioEngine]: Session 2 never calls stopCapture here.
///   - Push the selected gain down to the native passthrough whenever
///     the user drags the slider.
///   - Poll the native peak meter at ~30 Hz while any slot is attached,
///     and republish per-slot levels for the UI to render.
///
/// Multi-slot gain handling: the native side has a single shared gain
/// register (the capture ring is a singleton). In Session 2 we bind the
/// register to the most-recently-touched slot. A future pass can lift
/// this into a per-slot gain once the native side grows a per-source
/// render block.
class LiveInputSourceEngine extends ChangeNotifier {
  LiveInputSourceEngine(this._audioEngine);

  /// Used to query the Android-side `AudioManager` for input devices
  /// (the miniaudio path on Android only reports the default device).
  /// On desktop this is unused — we fall back to the native FFI.
  final AudioEngine _audioEngine;

  /// Cached device list. Refreshed on [refreshDevices] (and initially on
  /// first UI mount) so an unplugged device disappears from the dropdown
  /// without having to restart the app.
  List<LiveInputDevice> _devices = const [];
  List<LiveInputDevice> get devices => _devices;

  /// Slot IDs that currently have a mounted Live Input Source slot UI.
  /// When this set becomes non-empty we start capture and the meter
  /// timer; when it drains to zero we cancel the timer (capture is left
  /// running for the vocoder's benefit).
  final Set<String> _activeSlots = {};

  /// Per-slot last-known peak level in dBFS (−∞…0), updated by the meter
  /// poll timer while the slot is attached.
  final Map<String, double> _peakDb = {};
  double peakDbFor(String slotId) =>
      _peakDb[slotId] ?? double.negativeInfinity;

  /// Meter polling timer. Null when no slot is attached.
  Timer? _meterTimer;

  // ── Device enumeration ─────────────────────────────────────────────────

  /// Populate [devices] from the native layer. Safe to call repeatedly.
  ///
  /// On Android the miniaudio capture backend only reports the default
  /// device, so we query the platform-channel
  /// [AudioEngine.getAndroidInputDevices] that goes through `AudioManager`
  /// and returns the full list including USB / Bluetooth inputs. On
  /// desktop the miniaudio FFI is authoritative.
  Future<void> refreshDevices() async {
    final list = <LiveInputDevice>[];
    if (!kIsWeb && Platform.isAndroid) {
      final androidDevices = await _audioEngine.getAndroidInputDevices();
      for (final d in androidDevices) {
        final name = d['name']?.toString() ?? '';
        final id = (d['id'] as num?)?.toInt() ?? -1;
        if (name.isEmpty || id < 0) continue;
        list.add(LiveInputDevice(index: id, name: name));
      }
    } else {
      final ffi = AudioInputFFI();
      final count = ffi.getCaptureDeviceCount();
      for (int i = 0; i < count; i++) {
        final name = ffi.getCaptureDeviceName(i);
        if (name.isEmpty) continue;
        list.add(LiveInputDevice(index: i, name: name));
      }
    }
    if (!listEquals(list, _devices)) {
      _devices = list;
      notifyListeners();
    }
  }

  // ── Slot lifecycle ─────────────────────────────────────────────────────

  /// Called by the slot UI when it mounts. Pushes the current gain and
  /// starts the meter poll timer on the first attach.
  ///
  /// Capture-device startup and Oboe-bus registration are owned by
  /// [NativeInstrumentController.onLiveInputAdded], which runs at the
  /// *rack* level (project load / add plugin) so the audio path exists
  /// even while the widget is not mounted.
  void attachSlot(LiveInputSourcePluginInstance plugin) {
    final wasEmpty = _activeSlots.isEmpty;
    _activeSlots.add(plugin.id);
    if (wasEmpty) {
      _startMeterTimer();
    }
    // Push the persisted gain so the native side matches the UI state
    // even if the slot was just restored from a .gf file.
    AudioInputFFI().liveInputSetGainDb(plugin.gainDb);
    AudioInputFFI()
        .liveInputSetMonitorMute(muted: plugin.monitorMute);
    refreshDevices();
  }

  /// Called by the slot UI when it unmounts (slot deleted or app
  /// exiting). Stops the meter timer once the last slot is gone.
  /// Does not stop the capture device — that lifecycle belongs to
  /// [AudioEngine] which also owns the vocoder path.
  void detachSlot(String slotId) {
    _activeSlots.remove(slotId);
    _peakDb.remove(slotId);
    if (_activeSlots.isEmpty) {
      _stopMeterTimer();
    }
  }

  // ── Setters (write-through to native) ──────────────────────────────────

  void selectDevice(LiveInputSourcePluginInstance plugin, String deviceId) {
    if (plugin.deviceId == deviceId) return;
    plugin.deviceId = deviceId;
    notifyListeners();
  }

  void setChannelPair(LiveInputSourcePluginInstance plugin, String pair) {
    if (plugin.channelPair == pair) return;
    plugin.channelPair = pair;
    notifyListeners();
  }

  void setGainDb(LiveInputSourcePluginInstance plugin, double gainDb) {
    final clamped = gainDb.clamp(-24.0, 24.0).toDouble();
    if (plugin.gainDb == clamped) return;
    plugin.gainDb = clamped;
    AudioInputFFI().liveInputSetGainDb(clamped);
    notifyListeners();
  }

  void setMonitorMute(LiveInputSourcePluginInstance plugin, bool muted) {
    if (plugin.monitorMute == muted) return;
    plugin.monitorMute = muted;
    AudioInputFFI().liveInputSetMonitorMute(muted: muted);
    notifyListeners();
  }

  // ── Peak metering ──────────────────────────────────────────────────────

  void _startMeterTimer() {
    _meterTimer?.cancel();
    _meterTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final peakLin = AudioInputFFI().getLiveInputPeak();
      // Convert linear amplitude to dBFS. Guard the log against zero so
      // the meter shows "−∞" (drawn as a flat bar) during silence.
      final peakDb = peakLin <= 1e-6
          ? double.negativeInfinity
          : 20.0 * (math.log(peakLin) / math.ln10);
      // Apply the same peak to every attached slot — Session 2 has a
      // single shared capture device, so every visible slot reads the
      // same signal.
      for (final slotId in _activeSlots) {
        _peakDb[slotId] = peakDb;
      }
      notifyListeners();
    });
  }

  void _stopMeterTimer() {
    _meterTimer?.cancel();
    _meterTimer = null;
  }

  @override
  void dispose() {
    _stopMeterTimer();
    super.dispose();
  }
}
