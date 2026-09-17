import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_input_ffi.dart';
import 'gfpa_android_bindings.dart';

/// Android `AudioDeviceInfo.TYPE_*` values the feedback guard cares about.
abstract final class AndroidAudioDeviceType {
  /// The earpiece used for calls — quiet, but right next to the microphone.
  static const int builtinEarpiece = 1;

  /// The phone's loudspeaker.
  static const int builtinSpeaker = 2;

  /// The phone's own microphone(s).
  static const int builtinMic = 15;

  /// Loudspeaker variant used for alarms and ringtones.
  static const int builtinSpeakerSafe = 24;
}

/// Whether Live Input is feeding the rack, silenced by the guard, or
/// deliberately left on by the user.
enum FeedbackGuardState {
  /// No feedback risk, or Live Input is not feeding the rack at all.
  safe,

  /// Phone mic into phone speaker: Live Input is silenced.
  muted,

  /// Same risk, but the user chose to hear Live Input anyway.
  overridden,
}

/// Keeps Live Input from howling through the phone's own speaker.
///
/// When a USB microphone or interface is unplugged, Android quietly falls
/// back to the phone's built-in mic and loudspeaker. A Live Input cabled into
/// the rack then plays the mic straight into a speaker a few centimetres
/// away, and at any useful gain that becomes acoustic feedback (a "larsen")
/// within a second.
///
/// The guard checks, several times a second while Live Input feeds the rack,
/// where the capture and the output are *actually* routed. If it is phone mic
/// into phone speaker, Live Input is silenced at the native level (its meter
/// keeps working) until the route changes — or until the user explicitly asks
/// to hear it anyway, as Loopy Pro and GarageBand also allow.
///
/// Headphones, Bluetooth, USB outputs and the direct USB output are all safe:
/// the mic cannot hear them. Only Android is guarded; desktop users choose
/// their devices explicitly and have no silent fallback to worry about.
class LiveInputFeedbackGuard extends ChangeNotifier {
  /// Production guard, wired to the native capture/output and Android's
  /// device list.
  static final LiveInputFeedbackGuard instance = LiveInputFeedbackGuard(
    readCaptureDeviceId: () => AudioInputFFI().getCaptureDeviceId(),
    readOutputDeviceId: () =>
        GfpaAndroidBindings.instance.oboeStreamGetRoutedDeviceId(),
    loadDeviceTypes: _loadAndroidDeviceTypes,
    applyMute: (muted) =>
        AudioInputFFI().liveInputSetFeedbackMute(muted: muted),
    enabled: !kIsWeb && Platform.isAndroid,
  );

  /// Builds a guard from its inputs and outputs; tests pass fakes.
  ///
  /// [readCaptureDeviceId] — device id the capture stream is routed to, or
  ///   negative when capture is not running.
  /// [readOutputDeviceId] — device id the output plays to; 0 when no stream,
  ///   [kRoutedDeviceUsbDirect] for the direct USB output.
  /// [loadDeviceTypes] — every known device id mapped to its Android type.
  /// [applyMute] — silences (true) or restores (false) Live Input natively.
  /// [enabled] — false turns the guard into a no-op (non-Android platforms).
  LiveInputFeedbackGuard({
    required int Function() readCaptureDeviceId,
    required int Function() readOutputDeviceId,
    required Future<Map<int, int>> Function() loadDeviceTypes,
    required void Function(bool muted) applyMute,
    this.pollInterval = const Duration(milliseconds: 100),
    bool enabled = true,
  })  : _readCaptureDeviceId = readCaptureDeviceId,
        _readOutputDeviceId = readOutputDeviceId,
        _loadDeviceTypes = loadDeviceTypes,
        _applyMute = applyMute,
        _enabled = enabled;

  final int Function() _readCaptureDeviceId;
  final int Function() _readOutputDeviceId;
  final Future<Map<int, int>> Function() _loadDeviceTypes;
  final void Function(bool muted) _applyMute;
  final bool _enabled;

  /// How often the routes are checked while active. Feedback takes a few
  /// hundred milliseconds to build, so 100 ms stops it before it is loud.
  final Duration pollInterval;

  FeedbackGuardState _state = FeedbackGuardState.safe;

  /// What the guard is currently doing, for the Live Input slot UI.
  FeedbackGuardState get state => _state;

  Timer? _timer;

  /// Whether Live Input is currently silenced natively.
  bool _muted = false;

  Map<int, int> _deviceTypes = const {};
  bool _loadingTypes = false;

  /// Ids a fresh device list still could not type. Decided as unknown rather
  /// than reloading the list on every tick.
  Set<int> _untypeable = const {};

  /// Whether the given routes put the phone's mic next to its own speaker.
  ///
  /// [captureType] / [outputType] are Android device types, null when
  /// unknown. [outputDeviceId] is checked first because the direct USB output
  /// has no Android device, and nothing it plays can reach the phone's mic.
  static bool isFeedbackRisk({
    required int? captureType,
    required int outputDeviceId,
    required int? outputType,
  }) {
    if (outputDeviceId == kRoutedDeviceUsbDirect) return false;
    if (captureType != AndroidAudioDeviceType.builtinMic) return false;
    return outputType == AndroidAudioDeviceType.builtinSpeaker ||
        outputType == AndroidAudioDeviceType.builtinSpeakerSafe ||
        outputType == AndroidAudioDeviceType.builtinEarpiece;
  }

  /// Starts watching while Live Input feeds the rack, stops otherwise.
  ///
  /// Called by the routing sync whenever Live Input is (un)registered on the
  /// audio bus. Stopping lifts any mute: an uncabled Live Input feeds nothing.
  void setActive(bool active) {
    if (!_enabled) return;
    if (active) {
      _timer ??= Timer.periodic(pollInterval, (_) => tick());
      tick();
      return;
    }
    _timer?.cancel();
    _timer = null;
    _setState(FeedbackGuardState.safe, mute: false);
  }

  /// Lets Live Input through despite the risk, until the route changes.
  void unmuteAnyway() {
    if (_state != FeedbackGuardState.muted) return;
    _setState(FeedbackGuardState.overridden, mute: false);
  }

  /// Forgets the cached device types; called when devices are (un)plugged,
  /// since Android reassigns ids to reconnected devices.
  void invalidateDeviceTypes() {
    _deviceTypes = const {};
    _untypeable = const {};
  }

  /// One check of the current routes. Public for tests.
  @visibleForTesting
  void tick() {
    final captureId = _readCaptureDeviceId();
    final outputId = _readOutputDeviceId();

    // Capture not running: nothing can feed back.
    if (captureId < 0) {
      _setState(FeedbackGuardState.safe, mute: false);
      return;
    }

    final needsTypes = _isUntyped(captureId) ||
        (outputId > 0 && _isUntyped(outputId));
    if (needsTypes) {
      // A route onto a device we have not typed yet: decide once the list
      // arrives rather than guessing either way.
      _refreshDeviceTypes();
      return;
    }

    final risk = isFeedbackRisk(
      captureType: _deviceTypes[captureId],
      outputDeviceId: outputId,
      outputType: _deviceTypes[outputId],
    );

    if (!risk) {
      _setState(FeedbackGuardState.safe, mute: false);
    } else if (_state == FeedbackGuardState.safe) {
      _setState(FeedbackGuardState.muted, mute: true);
    }
    // Risk while muted or overridden: keep whatever the user has.
  }

  /// Whether [id] still needs a device-list load before it can be judged.
  bool _isUntyped(int id) =>
      !_deviceTypes.containsKey(id) && !_untypeable.contains(id);

  /// Reloads the device-type map, then re-checks immediately.
  Future<void> _refreshDeviceTypes() async {
    if (_loadingTypes) return;
    _loadingTypes = true;
    final wanted = {_readCaptureDeviceId(), _readOutputDeviceId()};
    try {
      _deviceTypes = await _loadDeviceTypes();
      _untypeable = {
        for (final id in wanted)
          if (id > 0 && !_deviceTypes.containsKey(id)) id,
      };
    } catch (e) {
      debugPrint('LiveInputFeedbackGuard: device list failed: $e');
    } finally {
      _loadingTypes = false;
    }
    if (_timer != null) tick();
  }

  void _setState(FeedbackGuardState next, {required bool mute}) {
    if (next == _state) return;
    _state = next;
    // Native calls only on an actual change: overridden -> safe, for one,
    // is a state change with the audio already flowing.
    if (mute != _muted) {
      _muted = mute;
      _applyMute(mute);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Every input and output device Android knows, id → type.
  static Future<Map<int, int>> _loadAndroidDeviceTypes() async {
    const channel = MethodChannel('com.grooveforge.grooveforge/audio_config');
    final types = <int, int>{};
    for (final method in ['getAudioInputDevices', 'getAudioOutputDevices']) {
      final devices = await channel.invokeMethod<List<dynamic>>(method) ?? [];
      for (final device in devices.cast<Map<dynamic, dynamic>>()) {
        final id = device['id'];
        final type = device['type'];
        if (id is int && type is int) types[id] = type;
      }
    }
    return types;
  }
}
