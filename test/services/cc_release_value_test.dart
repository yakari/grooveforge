// Tests for the "neutral value on release" CC mapping option.
//
// Ribbons and touch strips send 0 when the finger lifts, and also send 0 when
// it slides all the way to the low end. The detector tells them apart by how
// the 0 arrives: a slide passes through the values in between, a release
// jumps. These tests drive the real engine path (processMidiPacket) so the
// detector, the mapping and the dispatch are exercised together.

import 'dart:typed_data';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/services/cc_mapping_service.dart';

/// Hardware CC the simulated ribbon sends on.
const int _ribbonCc = 16;

/// A continuous slot-parameter target, which stays in Dart when dispatched.
const SlotParamTarget _cutoff = SlotParamTarget(
  slotId: 'slot-1',
  paramKey: 'cutoff',
  mode: CcParamMode.absolute,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AudioEngine engine;
  late CcMappingService service;
  late List<int> received;

  setUp(() {
    engine = AudioEngine()..markInitializedForTest();
    service = CcMappingService();
    engine.ccMappingService = service;
    received = [];
    engine.onSlotParamCc = (slotId, paramKey, mode, value, directValue) =>
        received.add(value);
  });

  /// Sends one CC from the ribbon on MIDI channel 1, through the engine.
  void ribbon(int value, {int channel = 0}) {
    engine.processMidiPacket(MidiPacket(
      Uint8List.fromList([0xB0 | channel, _ribbonCc, value]),
      0,
      MidiDevice('test', 'test', 'native', true),
    ));
  }

  void mapRibbon({int? releaseValue}) {
    service.addMapping(CcMapping(
      incomingCc: _ribbonCc,
      target: _cutoff,
      releaseValue: releaseValue,
    ));
  }

  group('with a release value', () {
    setUp(() => mapRibbon(releaseValue: 64));

    test('a jump to 0 is a release and sends the neutral value', () {
      for (final v in [40, 60, 90]) {
        ribbon(v);
      }
      ribbon(0);
      expect(received, [40, 60, 90, 64]);
    });

    test('sliding down to 0 reaches 0', () {
      for (final v in [20, 12, 6, 3, 1, 0]) {
        ribbon(v);
      }
      expect(received.last, 0,
          reason: 'the low end of the ribbon must stay playable');
    });

    test('a repeated 0 after a release keeps the neutral value', () {
      ribbon(90);
      ribbon(0);
      ribbon(0);
      expect(received, [90, 64, 64]);
    });

    test('touching again after a release plays normally', () {
      ribbon(90);
      ribbon(0);
      ribbon(30);
      ribbon(2);
      ribbon(0);
      expect(received, [90, 64, 30, 2, 0]);
    });

    test('a first event of 0 is passed through', () {
      // No history: nothing to say it was a jump.
      ribbon(0);
      expect(received, [0]);
    });

    test('other channels keep their own history', () {
      ribbon(90, channel: 0);
      ribbon(2, channel: 1);
      ribbon(0, channel: 1);
      expect(received, [90, 2, 0],
          reason: 'channel 2 slid down; channel 1 being high is irrelevant');
    });
  });

  test('without a release value, 0 is passed through', () {
    mapRibbon();
    ribbon(90);
    ribbon(0);
    expect(received, [90, 0]);
  });

  test('mappings sharing a CC each apply their own setting', () {
    mapRibbon(releaseValue: 64);
    mapRibbon();
    ribbon(90);
    ribbon(0);
    expect(received, [90, 90, 64, 0]);
  });

  group('model', () {
    test('only continuous targets accept a release value', () {
      expect(CcMapping.supportsReleaseValue(_cutoff), isTrue);
      expect(
          CcMapping.supportsReleaseValue(
              const GmCcTarget(targetCc: 1, targetChannel: -2)),
          isTrue);
      expect(
          CcMapping.supportsReleaseValue(
              const GlobalTarget(action: GlobalAction.systemVolume)),
          isTrue);
      expect(
          CcMapping.supportsReleaseValue(const SlotParamTarget(
              slotId: 'slot-1', paramKey: 'bypass', mode: CcParamMode.toggle)),
          isFalse);
      expect(
          CcMapping.supportsReleaseValue(
              const SystemTarget(actionCode: 1009, targetChannel: -2)),
          isFalse);
      expect(
          CcMapping.supportsReleaseValue(
              const TransportTarget(action: TransportAction.playStop)),
          isFalse);
    });

    test('a release value survives a .gf JSON round-trip', () {
      const mapping = CcMapping(
          incomingCc: _ribbonCc, target: _cutoff, releaseValue: 64);
      expect(CcMapping.fromJson(mapping.toJson()).releaseValue, 64);
    });

    test('mappings without one stay free of the field', () {
      const mapping = CcMapping(incomingCc: _ribbonCc, target: _cutoff);
      expect(mapping.toJson(), isNot(contains('releaseValue')));
      expect(CcMapping.fromJson(mapping.toJson()).releaseValue, isNull);
    });

    test('swapping slots keeps the release value', () {
      mapRibbon(releaseValue: 64);
      service.swapSlotReferences('slot-1', 'slot-2');
      final m = service.mappingsNotifier.value.single;
      expect((m.target as SlotParamTarget).slotId, 'slot-2');
      expect(m.releaseValue, 64);
    });

    test('replaceMapping edits in place, keeping list order', () {
      service.addMapping(const CcMapping(
          incomingCc: 1, target: GmCcTarget(targetCc: 74, targetChannel: -2)));
      mapRibbon();
      service.addMapping(const CcMapping(
          incomingCc: 2, target: GmCcTarget(targetCc: 71, targetChannel: -2)));

      final ribbonMapping = service.mappingsNotifier.value[1];
      service.replaceMapping(
          ribbonMapping, ribbonMapping.withReleaseValue(64));

      final list = service.mappingsNotifier.value;
      expect(list.map((m) => m.incomingCc), [1, _ribbonCc, 2]);
      expect(list[1].releaseValue, 64);
      expect(service.getMappings(_ribbonCc).single.releaseValue, 64);
    });
  });
}
