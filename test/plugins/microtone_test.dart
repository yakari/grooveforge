// Tests for the Microtone MIDI FX plugin.
//
// Covers two layers:
//
//   1. The .gfpd descriptor: identity, parameter list, defaults, type — pins
//      down the on-disk contract so a save-file regression cannot silently
//      drop or reorder a parameter.
//
//   2. The MicrotoneNode behaviour. The node is a monotonic re-attack engine:
//      every change to the held set produces a fresh attack (Note-Off old,
//      PitchBend, Note-On new) pre-bent to the cluster median. The Attack
//      Delay parameter selects how the FIRST note of a cluster fires:
//        - 0 ms  → fire immediately on the first key press.
//        - >0 ms → gather keys for the delay, then fire one clean attack at
//                  the cluster median (tick-driven). A tap released before
//                  the delay still fires so notes are never dropped.
//
// Time-dependent tests inject synthetic timestamps by sleeping briefly
// between calls — the node uses DateTime.now() internally.

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Descriptor contract ────────────────────────────────────────────────────

  group('Microtone descriptor', () {
    late GFPluginDescriptor descriptor;

    setUpAll(() async {
      final yaml =
          await rootBundle.loadString('assets/plugins/microtone.gfpd');
      final parsed = GFDescriptorLoader.parse(yaml);
      expect(parsed, isNotNull, reason: 'microtone.gfpd must parse cleanly');
      descriptor = parsed!;
    });

    test('identity fields are correct', () {
      expect(descriptor.id, 'com.grooveforge.microtone');
      expect(descriptor.name, 'Microtone');
      expect(descriptor.type, GFPluginType.midiFx);
    });

    test('exposes the 4 expected parameters in declared order', () {
      final ids = descriptor.parameters.map((p) => p.id).toList();
      expect(ids, [
        'chord_window',
        'cluster_mode',
        'bend_range',
        'velocity_mode',
      ]);
    });

    test('attack-delay parameter spans 0–80 ms and defaults to 30', () {
      final p = descriptor.parameters.firstWhere((p) => p.id == 'chord_window');
      expect(p.min, 0.0, reason: '0 ms = immediate-fire mode');
      expect(p.max, 80.0);
      expect(p.defaultValue, 30.0,
          reason: 'deferred by default so single microtonal notes are clean');
    });

    test('other parameter defaults are musically sensible', () {
      double def(String id) =>
          descriptor.parameters.firstWhere((p) => p.id == id).defaultValue;
      expect(def('cluster_mode'), 0.0); // OuterAverage
      expect(def('bend_range'), 0.0); // ±2 st
      expect(def('velocity_mode'), 0.0); // Average
    });
  });

  // ── Immediate mode (attack delay = 0) ──────────────────────────────────────

  group('MicrotoneNode — immediate mode (delay 0)', () {
    late MicrotoneNode node;
    final ctx = const GFMidiNodeContext(
      sourceChannelIndex: 0,
      scaleProvider: _nullScale,
    );
    const transport = GFTransportContext.stopped;

    setUp(() {
      node = MicrotoneNode('micro');
      node.initialize(ctx);
      node.setParam('chordWindow', 0.0); // 0 ms → immediate fire
      node.setParam('clusterMode', 0.0); // OuterAverage
      node.setParam('bendRange', 0.0); // ±2 st
      node.setParam('velocityMode', 0.0); // Average
    });

    test('first press fires Note-On immediately at chromatic pitch', () {
      final out = node.processMidi(
        [_noteOn(channel: 0, pitch: 60, velocity: 100)],
        transport,
      );
      expect(out.length, 2);
      expect(_isPitchBend(out[0]), isTrue);
      expect(_pitchBend14(out[0]), 8192, reason: 'single note → centre bend');
      expect(out[1].isNoteOn, isTrue);
      expect(out[1].data1, 60);
    });

    test('second press re-attacks immediately at the bent pitch', () {
      node.processMidi([_noteOn(channel: 0, pitch: 60, velocity: 100)], transport);
      final p2 = node.processMidi(
        [_noteOn(channel: 0, pitch: 61, velocity: 80)],
        transport,
      );
      // Re-attack: Note-Off(60) → PitchBend → Note-On(60).
      expect(p2.where((e) => e.isNoteOff), hasLength(1));
      expect(p2.where((e) => e.isNoteOn), hasLength(1));
      // OuterAverage of (60, 61) = 60.5 → +0.5 st → bend 10240.
      expect(_pitchBend14(p2.firstWhere(_isPitchBend)), 10240);
      // Velocity = average of (100, 80) = 90.
      expect(p2.firstWhere((e) => e.isNoteOn).data2, 90);
    });

    test('partial release re-attacks immediately (no settle window at delay 0)',
        () {
      node.processMidi([_noteOn(channel: 0, pitch: 60, velocity: 100)], transport);
      node.processMidi([_noteOn(channel: 0, pitch: 64, velocity: 100)], transport);
      // Lift one finger — in immediate mode the re-attack fires at once.
      final off = node.processMidi(
        [_noteOff(channel: 0, pitch: 64)],
        transport,
      );
      expect(off.where((e) => e.isNoteOff), hasLength(1));
      expect(off.where((e) => e.isNoteOn), hasLength(1));
      expect(off.firstWhere((e) => e.isNoteOn).data1, 60);
      expect(_pitchBend14(off.firstWhere(_isPitchBend)), 8192);
    });
  });

  // ── Deferred mode (attack delay > 0) ───────────────────────────────────────

  group('MicrotoneNode — deferred mode (delay 30 ms)', () {
    late MicrotoneNode node;
    final ctx = const GFMidiNodeContext(
      sourceChannelIndex: 0,
      scaleProvider: _nullScale,
    );
    const transport = GFTransportContext.stopped;

    setUp(() {
      node = MicrotoneNode('micro');
      node.initialize(ctx);
      node.setParam('chordWindow', 30.0 / 80.0); // 30 ms
      node.setParam('clusterMode', 0.0);
      node.setParam('bendRange', 0.0);
      node.setParam('velocityMode', 0.0);
    });

    test('first press is deferred — no immediate output', () {
      final out = node.processMidi(
        [_noteOn(channel: 0, pitch: 60, velocity: 100)],
        transport,
      );
      expect(out, isEmpty, reason: 'attack is deferred until the window ends');
      // tick() before the window expires still emits nothing.
      expect(node.tick(transport), isEmpty);
    });

    test('two-key cluster fires once at the median when the window expires',
        () async {
      node.processMidi([_noteOn(channel: 0, pitch: 60, velocity: 100)], transport);
      node.processMidi([_noteOn(channel: 0, pitch: 61, velocity: 80)], transport);
      // Both accumulate silently.
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final fired = node.tick(transport);
      // Single clean attack: PitchBend → Note-On (no Note-Off, no prior voice).
      expect(fired.where((e) => e.isNoteOff), isEmpty,
          reason: 'first attack has no prior voice to silence');
      expect(fired.where((e) => e.isNoteOn), hasLength(1));
      // OuterAverage of (60, 61) = 60.5 → +0.5 st → bend 10240.
      expect(_pitchBend14(fired.firstWhere(_isPitchBend)), 10240);
      final noteOn = fired.firstWhere((e) => e.isNoteOn);
      expect(noteOn.data1, 60, reason: 'base = lowest held pitch');
      expect(noteOn.data2, 90, reason: 'velocity = average of 100 and 80');
    });

    test('quick tap released before the window still fires (no drop)', () {
      // Press then release in the same synthetic instant — faster than the
      // 30 ms window. The note must still be emitted (fire + release).
      node.processMidi([_noteOn(channel: 0, pitch: 60, velocity: 100)], transport);
      final off = node.processMidi(
        [_noteOff(channel: 0, pitch: 60)],
        transport,
      );
      expect(off.any((e) => e.isNoteOn && e.data1 == 60), isTrue,
          reason: 'early release must fire the gathered note');
      expect(off.any((e) => e.isNoteOff && e.data1 == 60), isTrue,
          reason: 'then release it for a short staccato note');
    });

    test('a key released before the window does not cancel the cluster',
        () async {
      // Press C + C#, release C# (still inside the window). The cluster keeps
      // gathering with {C}; the eventual attack is a clean C.
      node.processMidi([_noteOn(channel: 0, pitch: 60, velocity: 100)], transport);
      node.processMidi([_noteOn(channel: 0, pitch: 61, velocity: 100)], transport);
      final r = node.processMidi(
        [_noteOff(channel: 0, pitch: 61)],
        transport,
      );
      expect(r, isEmpty, reason: 'still gathering — no output on a partial release');

      await Future<void>.delayed(const Duration(milliseconds: 60));
      final fired = node.tick(transport);
      expect(fired.where((e) => e.isNoteOn), hasLength(1));
      expect(fired.firstWhere((e) => e.isNoteOn).data1, 60);
      expect(_pitchBend14(fired.firstWhere(_isPitchBend)), 8192,
          reason: 'cluster reduced to a single C → centre bend');
    });

    test('press after the cluster sounds re-attacks immediately', () async {
      node.processMidi([_noteOn(channel: 0, pitch: 60, velocity: 100)], transport);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      node.tick(transport); // deferred first attack (C) fires here.

      // Now sounding — a new press re-attacks right away (no second deferral).
      final p = node.processMidi(
        [_noteOn(channel: 0, pitch: 64, velocity: 100)],
        transport,
      );
      expect(p.where((e) => e.isNoteOff), hasLength(1));
      expect(p.where((e) => e.isNoteOn), hasLength(1));
      // OuterAverage (60, 64) = 62 → +2 st → saturates at 16383.
      expect(_pitchBend14(p.firstWhere(_isPitchBend)), 16383);
    });

    test('peeling one finger (held) re-attacks at the smaller cluster',
        () async {
      node.processMidi([_noteOn(channel: 0, pitch: 60, velocity: 100)], transport);
      node.processMidi([_noteOn(channel: 0, pitch: 64, velocity: 100)], transport);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      node.tick(transport); // fires the {60,64} cluster (D).

      // Lift the upper key and HOLD the lower — the re-attack is deferred...
      final off = node.processMidi(
        [_noteOff(channel: 0, pitch: 64)],
        transport,
      );
      expect(off, isEmpty, reason: 'release re-attack is deferred a settle window');

      // ...and fires once the settle window expires (no further release).
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final fired = node.tick(transport);
      expect(fired.where((e) => e.isNoteOff), hasLength(1),
          reason: 're-attack silences the old voice');
      expect(fired.where((e) => e.isNoteOn), hasLength(1),
          reason: 're-attack starts the smaller-cluster voice');
      expect(fired.firstWhere((e) => e.isNoteOn).data1, 60);
      expect(_pitchBend14(fired.firstWhere(_isPitchBend)), 8192,
          reason: 'cluster reduced to a single C → centre bend');
    });

    test('releasing both keys within the settle window is a clean stop',
        () async {
      node.processMidi([_noteOn(channel: 0, pitch: 60, velocity: 100)], transport);
      node.processMidi([_noteOn(channel: 0, pitch: 61, velocity: 100)], transport);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      node.tick(transport); // fires the quarter-tone cluster.

      // Release C# then C in quick succession (the player's complaint scenario)
      // — both within the 30 ms settle window, so the deferred re-attack must
      // be cancelled and only a single Note-Off emitted.
      final r1 = node.processMidi([_noteOff(channel: 0, pitch: 61)], transport);
      final r2 = node.processMidi([_noteOff(channel: 0, pitch: 60)], transport);
      // A stray tick between the releases must NOT have fired a re-attack.
      final t = node.tick(transport);

      expect(r1, isEmpty, reason: 'first release defers, emits nothing yet');
      expect(r2.where((e) => e.isNoteOn), isEmpty,
          reason: 'no extra note attacked when the cluster stops');
      expect(r2.where((e) => e.isNoteOff), hasLength(1));
      expect(r2.firstWhere((e) => e.isNoteOff).data1, 60,
          reason: 'Note-Off targets the sounding base pitch');
      // The bend is intentionally NOT reset on Note-Off — resetting it would
      // snap the release tail from the microtone to the chromatic pitch (the
      // "phantom note"). So the stop emits only a Note-Off, no pitch-bend.
      expect(r2.where(_isPitchBend), isEmpty,
          reason: 'no bend reset on Note-Off — tail keeps its microtone');
      expect(t.where((e) => e.isNoteOn), isEmpty,
          reason: 'the cancelled re-attack must never fire from tick');
    });

    test('press during a pending release re-attack cancels and re-attacks now',
        () async {
      node.processMidi([_noteOn(channel: 0, pitch: 60, velocity: 100)], transport);
      node.processMidi([_noteOn(channel: 0, pitch: 64, velocity: 100)], transport);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      node.tick(transport); // {60,64} sounding.

      node.processMidi([_noteOff(channel: 0, pitch: 64)], transport); // defers
      // Press a new key before the settle window expires.
      final p = node.processMidi(
        [_noteOn(channel: 0, pitch: 67, velocity: 100)],
        transport,
      );
      // Immediate press re-attack at {60,67}; the pending release re-attack
      // must not also fire from a later tick.
      expect(p.where((e) => e.isNoteOn), hasLength(1));
      expect(node.tick(transport).where((e) => e.isNoteOn), isEmpty,
          reason: 'press cleared the pending release re-attack');
    });

    test('CC events pass through unchanged', () {
      const cc = TimestampedMidiEvent(
        ppqPosition: 0.0,
        status: 0xB0,
        data1: 1,
        data2: 64,
      );
      expect(node.processMidi([cc], transport), [cc]);
    });
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

TimestampedMidiEvent _noteOn({
  required int channel,
  required int pitch,
  required int velocity,
}) =>
    TimestampedMidiEvent(
      ppqPosition: 0,
      status: 0x90 | (channel & 0x0F),
      data1: pitch,
      data2: velocity,
    );

TimestampedMidiEvent _noteOff({
  required int channel,
  required int pitch,
}) =>
    TimestampedMidiEvent(
      ppqPosition: 0,
      status: 0x80 | (channel & 0x0F),
      data1: pitch,
      data2: 0,
    );

/// True iff [e] is a pitch-bend event (status nibble 0xE0).
bool _isPitchBend(TimestampedMidiEvent e) => (e.status & 0xF0) == 0xE0;

/// Decode the 14-bit pitch-bend value (data1 = LSB, data2 = MSB).
int _pitchBend14(TimestampedMidiEvent e) => (e.data2 << 7) | e.data1;

/// Stub scale provider — Microtone does not use it.
Set<int>? _nullScale() => null;
