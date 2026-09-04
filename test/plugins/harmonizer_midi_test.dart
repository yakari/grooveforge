// Tests for the MIDI Harmonizer (`com.grooveforge.harmonizer`).
//
// Two things are pinned here:
//
//   1. The descriptor contract — paramIds 0/1/2 must keep the meaning they
//      shipped with, because a saved `.gf` project stores parameter values
//      by paramId. Renumbering them would silently rewrite every user's
//      harmony when their project next loads.
//
//   2. The node's voice-count behaviour — how many harmony notes come out
//      for a given count, and that note-offs always match the note-ons that
//      were actually sent.

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Harmonizer descriptor', () {
    late GFPluginDescriptor descriptor;

    setUpAll(() async {
      final yaml = await rootBundle.loadString('assets/plugins/harmonizer.gfpd');
      final parsed = GFDescriptorLoader.parse(yaml);
      expect(parsed, isNotNull, reason: 'harmonizer.gfpd must parse cleanly');
      descriptor = parsed!;
    });

    test('identity fields are correct', () {
      expect(descriptor.id, 'com.grooveforge.harmonizer');
      expect(descriptor.type, GFPluginType.midiFx);
    });

    test('the original three paramIds keep their meaning', () {
      // Version 1.0.0 shipped these three ids. A project saved then must
      // still load with the same harmony, so the mapping is frozen.
      expect(descriptor.paramById('interval1')!.paramId, 0);
      expect(descriptor.paramById('interval2')!.paramId, 1);
      expect(descriptor.paramById('snap_to_scale')!.paramId, 2);
    });

    test('the new voices are appended after them', () {
      expect(descriptor.paramById('voice_count')!.paramId, 3);
      expect(descriptor.paramById('interval3')!.paramId, 4);
      expect(descriptor.paramById('interval4')!.paramId, 5);
    });

    test('voice count defaults to 2, matching the previous behaviour', () {
      final p = descriptor.paramById('voice_count')!;
      expect(p.min, 1.0);
      expect(p.max, 4.0);
      expect(p.defaultValue, 2.0);
    });

    test('interval knobs declare an interval readout', () {
      for (final id in ['interval1', 'interval2', 'interval3', 'interval4']) {
        expect(descriptor.paramById(id)!.display, GFParamDisplay.interval,
            reason: '$id should print the interval it names');
      }
      expect(descriptor.paramById('voice_count')!.display,
          GFParamDisplay.integer);
    });
  });

  group('HarmonizeNode voices', () {
    /// Builds a node with [count] voices and the given intervals, wired the
    /// way the descriptor wires it (normalised values over each declared
    /// range).
    HarmonizeNode buildNode(int count, List<int> semitones) {
      final node = HarmonizeNode('harm');
      node.setParam('voiceCount', (count - 1) / 3.0);
      for (var i = 0; i < semitones.length; i++) {
        node.setParam('interval${i + 1}', semitones[i] / 24.0);
      }
      node.setParam('snapToScale', 0.0);
      return node;
    }

    /// Note-on for middle C on channel 1.
    TimestampedMidiEvent noteOn(int pitch) => TimestampedMidiEvent(
          ppqPosition: 0,
          status: 0x90,
          data1: pitch,
          data2: 100,
        );

    /// Matching note-off.
    TimestampedMidiEvent noteOff(int pitch) => TimestampedMidiEvent(
          ppqPosition: 0,
          status: 0x80,
          data1: pitch,
          data2: 0,
        );

    const transport = GFTransportContext.stopped;

    test('the count knob decides how many harmony notes are added', () {
      for (var count = 1; count <= 4; count++) {
        final node = buildNode(count, [3, 7, 12, 16]);
        final out = node.processMidi([noteOn(60)], transport);
        // The played note always passes through, so output is 1 + voices.
        expect(out.length, count + 1, reason: '$count voices');
        expect(out.first.data1, 60);
      }
    });

    test('a four-voice stack emits the intervals it was given', () {
      final node = buildNode(4, [3, 7, 12, 16]);
      final out = node.processMidi([noteOn(60)], transport);
      expect(out.map((e) => e.data1).toList(), [60, 63, 67, 72, 76]);
    });

    test('an interval of zero is skipped even inside the count', () {
      // Doubling a note at unison adds nothing audible, so a voice set to 0
      // stays silent rather than emitting a duplicate.
      final node = buildNode(4, [0, 7, 0, 16]);
      final out = node.processMidi([noteOn(60)], transport);
      expect(out.map((e) => e.data1).toList(), [60, 67, 76]);
    });

    test('note-offs match the note-ons even after the count drops', () {
      final node = buildNode(4, [3, 7, 12, 16]);
      node.processMidi([noteOn(60)], transport);

      // The user turns the harmony down to a single voice while the note is
      // still held. All four harmony notes must still be released, or the
      // synth is left with three stuck notes.
      node.setParam('voiceCount', 0.0);
      final out = node.processMidi([noteOff(60)], transport);
      expect(out.map((e) => e.data1).toList(), [60, 63, 67, 72, 76]);
    });
  });
}
