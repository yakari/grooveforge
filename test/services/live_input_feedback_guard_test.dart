import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/services/gfpa_android_bindings.dart';
import 'package:grooveforge/services/live_input_feedback_guard.dart';

/// Device ids as a Galaxy phone might report them.
const _phoneMic = 22;
const _usbMic = 47;
const _phoneSpeaker = 3;
const _usbHeadset = 35;

const _types = <int, int>{
  _phoneMic: AndroidAudioDeviceType.builtinMic,
  _usbMic: 11, // TYPE_USB_DEVICE
  _phoneSpeaker: AndroidAudioDeviceType.builtinSpeaker,
  _usbHeadset: 22, // TYPE_USB_HEADSET
};

/// A guard driven by mutable fake routes, recording every native mute call.
class _Harness {
  int captureId = _usbMic;
  int outputId = _usbHeadset;
  final List<bool> muteCalls = [];
  late final LiveInputFeedbackGuard guard = LiveInputFeedbackGuard(
    readCaptureDeviceId: () => captureId,
    readOutputDeviceId: () => outputId,
    loadDeviceTypes: () async => _types,
    applyMute: muteCalls.add,
    // Long enough that only explicit tick() calls drive the tests.
    pollInterval: const Duration(hours: 1),
  );

  /// Activates the guard and lets the first device-list load complete.
  Future<void> activate() async {
    guard.setActive(true);
    await pumpEventQueue();
  }
}

void main() {
  group('isFeedbackRisk', () {
    test('phone mic into phone speaker is a risk', () {
      expect(
        LiveInputFeedbackGuard.isFeedbackRisk(
          captureType: AndroidAudioDeviceType.builtinMic,
          outputDeviceId: _phoneSpeaker,
          outputType: AndroidAudioDeviceType.builtinSpeaker,
        ),
        isTrue,
      );
    });

    test('a USB mic cannot howl through the phone speaker', () {
      expect(
        LiveInputFeedbackGuard.isFeedbackRisk(
          captureType: 11,
          outputDeviceId: _phoneSpeaker,
          outputType: AndroidAudioDeviceType.builtinSpeaker,
        ),
        isFalse,
      );
    });

    test('the direct USB output is safe even with the phone mic', () {
      expect(
        LiveInputFeedbackGuard.isFeedbackRisk(
          captureType: AndroidAudioDeviceType.builtinMic,
          outputDeviceId: kRoutedDeviceUsbDirect,
          outputType: null,
        ),
        isFalse,
      );
    });
  });

  group('guard', () {
    test('mutes when unplugging drops the routes onto the phone', () async {
      final h = _Harness();
      await h.activate();
      expect(h.guard.state, FeedbackGuardState.safe);
      expect(h.muteCalls, isEmpty);

      // The hub is pulled: Android falls back to the phone's mic and speaker.
      h.captureId = _phoneMic;
      h.outputId = _phoneSpeaker;
      h.guard.tick();

      expect(h.guard.state, FeedbackGuardState.muted);
      expect(h.muteCalls, [true]);
    });

    test('lifts the mute once the route is safe again', () async {
      final h = _Harness();
      h.captureId = _phoneMic;
      h.outputId = _phoneSpeaker;
      await h.activate();
      expect(h.guard.state, FeedbackGuardState.muted);

      // Headphones plugged in.
      h.outputId = _usbHeadset;
      h.guard.tick();

      expect(h.guard.state, FeedbackGuardState.safe);
      expect(h.muteCalls, [true, false]);
    });

    test('"unmute anyway" holds until the route changes, then re-arms', () async {
      final h = _Harness();
      h.captureId = _phoneMic;
      h.outputId = _phoneSpeaker;
      await h.activate();

      h.guard.unmuteAnyway();
      h.guard.tick(); // still phone mic + speaker: the user's choice stands
      expect(h.guard.state, FeedbackGuardState.overridden);

      h.outputId = _usbHeadset; // safe route clears the override
      h.guard.tick();
      h.outputId = _phoneSpeaker; // risky again: muted again
      h.guard.tick();

      expect(h.guard.state, FeedbackGuardState.muted);
      expect(h.muteCalls, [true, false, true]);
    });

    test('an untyped device id waits for the device list instead of guessing', () async {
      var loads = 0;
      final muteCalls = <bool>[];
      final guard = LiveInputFeedbackGuard(
        readCaptureDeviceId: () => _phoneMic,
        readOutputDeviceId: () => _phoneSpeaker,
        loadDeviceTypes: () async {
          loads++;
          return _types;
        },
        applyMute: muteCalls.add,
        pollInterval: const Duration(hours: 1),
      );

      guard.setActive(true);
      expect(muteCalls, isEmpty, reason: 'no decision before types are known');

      await pumpEventQueue();
      expect(loads, 1);
      expect(guard.state, FeedbackGuardState.muted);
      guard.setActive(false);
    });

    test('an id no device list knows is loaded once, then left unmuted', () async {
      var loads = 0;
      final muteCalls = <bool>[];
      final guard = LiveInputFeedbackGuard(
        readCaptureDeviceId: () => 999,
        readOutputDeviceId: () => _phoneSpeaker,
        loadDeviceTypes: () async {
          loads++;
          return _types;
        },
        applyMute: muteCalls.add,
        pollInterval: const Duration(hours: 1),
      );

      guard.setActive(true);
      await pumpEventQueue();
      guard.tick();
      guard.tick();
      await pumpEventQueue();

      expect(loads, 1, reason: 'no reload storm for an unknown id');
      expect(guard.state, FeedbackGuardState.safe);
      expect(muteCalls, isEmpty);
      guard.setActive(false);
    });

    test('deactivating (Live Input uncabled) always lifts the mute', () async {
      final h = _Harness();
      h.captureId = _phoneMic;
      h.outputId = _phoneSpeaker;
      await h.activate();

      h.guard.setActive(false);

      expect(h.guard.state, FeedbackGuardState.safe);
      expect(h.muteCalls, [true, false]);
    });

    test('capture not running is never muted', () async {
      final h = _Harness();
      h.captureId = -1;
      h.outputId = _phoneSpeaker;
      await h.activate();

      expect(h.guard.state, FeedbackGuardState.safe);
      expect(h.muteCalls, isEmpty);
      h.guard.setActive(false);
    });
  });
}
