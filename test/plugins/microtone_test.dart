// Tests for the Microtone MIDI FX plugin.
//
// Covers two layers:
//
//   1. The .gfpd descriptor: identity, parameter list, defaults, type — pins
//      down the on-disk contract so a save-file regression cannot silently
//      drop or reorder a parameter.
//
//   2. The MicrotoneNode behaviour — re-attack model: the first key press
//      fires a Note-On immediately at the chromatic pitch; every subsequent
//      change to the held set produces a re-attack sequence (Note-Off the
//      old voice, pitch-bend to the new microtone, Note-On the new voice).
//      Rapid presses inside the chord window are collapsed into a single
//      re-attack at the window's expiry.
//
// Time-dependent tests inject synthetic timestamps by sleeping briefly
// between calls — the node uses DateTime.now() internally, mirroring the
// real audio host.

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
      // Order must match the paramId numbering so a saved .gf project can
      // remap paramId → semantic role unambiguously after a future update.
      final ids = descriptor.parameters.map((p) => p.id).toList();
      expect(ids, [
        'chord_window',
        'cluster_mode',
        'bend_range',
        'velocity_mode',
      ]);
    });

    test('parameter defaults are musically sensible', () {
      double def(String id) =>
          descriptor.parameters.firstWhere((p) => p.id == id).defaultValue;
      // 35 ms chord window — well above typical two-finger asynchrony (~10 ms).
      expect(def('chord_window'), 35.0);
      // Cluster mode 0 = OuterAverage (predictable for two-finger gestures).
      expect(def('cluster_mode'), 0.0);
      // Bend range 0 = ±2 st (General MIDI default).
      expect(def('bend_range'), 0.0);
      // Velocity mode 0 = Average (smoother dynamics across cluster).
      expect(def('velocity_mode'), 0.0);
    });

    test('parameter ranges match the design spec', () {
      GFDescriptorParameter p(String id) =>
          descriptor.parameters.firstWhere((p) => p.id == id);
      expect(p('chord_window').min, 10.0);
      expect(p('chord_window').max, 80.0);
    });
  });

  // ── MicrotoneNode runtime behaviour ────────────────────────────────────────

  group('MicrotoneNode', () {
    late MicrotoneNode node;

    /// Default GFMidiNodeContext — Microtone does not use scale or source
    /// channel, but the API still requires them.
    final ctx = const GFMidiNodeContext(
      sourceChannelIndex: 0,
      scaleProvider: _nullScale,
    );

    /// Stopped transport — the node ignores transport state entirely (its
    /// timing is wall-clock based).
    const transport = GFTransportContext.stopped;

    setUp(() {
      node = MicrotoneNode('micro');
      node.initialize(ctx);
      // 35 ms maps to (35 − 10) / 70 = 0.357.
      node.setParam('chordWindow', (35.0 - 10.0) / 70.0);
      node.setParam('clusterMode', 0.0); // OuterAverage
      node.setParam('bendRange', 0.0); // ±2 st
      node.setParam('velocityMode', 0.0); // Average
    });

    test('single press fires Note-On immediately with centre bend', () {
      final out = node.processMidi(
        [_noteOn(channel: 0, pitch: 60, velocity: 100)],
        transport,
      );

      expect(out.length, 2,
          reason: 'expected centre pitch-bend + Note-On in the same block');
      // Pitch-bend FIRST so the synth applies it before sounding the note.
      expect(_isPitchBend(out[0]), isTrue);
      expect(_pitchBend14(out[0]), 8192,
          reason: 'single-note cluster has no offset — bend must be centre');
      expect(out[1].isNoteOn, isTrue);
      expect(out[1].data1, 60);
      expect(out[1].data2, 100);
    });

    test('two-press cluster inside chord window: queue and fire one re-attack',
        () async {
      // First press fires the chromatic Note-On immediately.
      final p1 = node.processMidi(
        [_noteOn(channel: 0, pitch: 60, velocity: 100)],
        transport,
      );
      expect(p1.where((e) => e.isNoteOn), hasLength(1));
      expect(p1.firstWhere((e) => e.isNoteOn).data1, 60);

      // Second press inside the window: queued — NO immediate output.
      final p2 = node.processMidi(
        [_noteOn(channel: 0, pitch: 61, velocity: 80)],
        transport,
      );
      expect(p2, isEmpty,
          reason: 'press inside the chord window must defer to tick()');

      // Tick before the window expires: still nothing.
      expect(node.tick(transport), isEmpty);

      // Wait past the window — tick() now fires the queued re-attack.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final fired = node.tick(transport);

      // Re-attack sequence: Note-Off(60) → PitchBend → Note-On(60).
      expect(fired, hasLength(3));
      expect(fired[0].isNoteOff, isTrue);
      expect(fired[0].data1, 60);

      expect(_isPitchBend(fired[1]), isTrue);
      // OuterAverage of (60, 61) = 60.5 → +0.5 st above basePitch (60).
      // bend = 8192 + round(0.5 / 2.0 * 8191) = 10240.
      expect(_pitchBend14(fired[1]), 10240);

      expect(fired[2].isNoteOn, isTrue);
      expect(fired[2].data1, 60);
      // Velocity = average of (100, 80) = 90.
      expect(fired[2].data2, 90);
    });

    test('press after the chord window: immediate re-attack, no queue', () async {
      node.processMidi([_noteOn(channel: 0, pitch: 60, velocity: 100)], transport);
      // Wait past the window so the next press is a "deliberate" addition.
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final p2 = node.processMidi(
        [_noteOn(channel: 0, pitch: 64, velocity: 100)],
        transport,
      );

      // Immediate re-attack: Note-Off → PitchBend → Note-On.
      expect(p2.where((e) => e.isNoteOff), hasLength(1));
      expect(p2.where(_isPitchBend), hasLength(1));
      expect(p2.where((e) => e.isNoteOn), hasLength(1));

      // OuterAverage of (60, 64) = 62 → +2 st → saturates at 16383.
      expect(_pitchBend14(p2.firstWhere(_isPitchBend)), 16383);
    });

    test('partial release: immediate re-attack at the smaller cluster', () async {
      node.processMidi([_noteOn(channel: 0, pitch: 60, velocity: 100)], transport);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      node.processMidi([_noteOn(channel: 0, pitch: 64, velocity: 100)], transport);
      // We now have a sounding cluster {60, 64} bent toward D.

      // Release the upper key — cluster shrinks to {60}. Re-attack fires now.
      final off = node.processMidi(
        [_noteOff(channel: 0, pitch: 64)],
        transport,
      );

      expect(off.where((e) => e.isNoteOff), hasLength(1),
          reason: 're-attack must silence the old voice');
      expect(off.where((e) => e.isNoteOn), hasLength(1),
          reason: 're-attack must start a new voice');
      // New cluster {60}: target = 60, bend = centre.
      expect(_pitchBend14(off.firstWhere(_isPitchBend)), 8192);
      // New base pitch == lowest held = 60.
      expect(off.firstWhere((e) => e.isNoteOn).data1, 60);
    });

    test('all notes off emits Note-Off + bend reset to centre', () {
      node.processMidi([_noteOn(channel: 0, pitch: 60, velocity: 100)], transport);

      final r = node.processMidi(
        [_noteOff(channel: 0, pitch: 60)],
        transport,
      );

      final noteOff = r.where((e) => e.isNoteOff).toList();
      expect(noteOff, hasLength(1));
      expect(noteOff.first.data1, 60);

      final centeredBend = r.where(_isPitchBend).toList();
      expect(centeredBend, hasLength(1));
      expect(_pitchBend14(centeredBend.first), 8192,
          reason: 'pitch-bend must reset to centre on all-notes-off');
    });

    test('CC events pass through unchanged', () {
      const cc = TimestampedMidiEvent(
        ppqPosition: 0.0,
        status: 0xB0,
        data1: 1,
        data2: 64,
      );
      final out = node.processMidi([cc], transport);
      expect(out, [cc]);
    });

    test('short tap (under chord window) still produces audible Note-On', () {
      // Regression test for the original "swallowed taps" bug: pressing and
      // releasing faster than the chord window must still emit a clean
      // Note-On / Note-Off pair.
      final onOut = node.processMidi(
        [_noteOn(channel: 0, pitch: 60, velocity: 100)],
        transport,
      );
      expect(onOut.any((e) => e.isNoteOn && e.data1 == 60), isTrue);

      final offOut = node.processMidi(
        [_noteOff(channel: 0, pitch: 60)],
        transport,
      );
      expect(offOut.any((e) => e.isNoteOff && e.data1 == 60), isTrue);
    });

    test('LastNote velocity mode tracks the most recently pressed key',
        () async {
      node.setParam('velocityMode', 1.0); // LastNote

      node.processMidi([_noteOn(channel: 0, pitch: 60, velocity: 40)], transport);
      node.processMidi([_noteOn(channel: 0, pitch: 64, velocity: 110)], transport);

      // Re-attack fires from tick() once the window expires.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final fired = node.tick(transport);
      final noteOn = fired.firstWhere((e) => e.isNoteOn);
      expect(noteOn.data2, 110,
          reason: 'LastNote mode uses the most recently pressed key velocity');
    });

    test('basePitch re-locks to lowest held on re-attack (limits saturation)',
        () async {
      // Press C (60) then much later E (64). After the window, the re-attack
      // uses basePitch = lowest held = 60. Then release C: cluster = {64},
      // re-attack must use basePitch = 64 with bend = centre, not the saturated
      // bend that would result from keeping basePitch = 60.
      node.processMidi([_noteOn(channel: 0, pitch: 60, velocity: 100)], transport);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      node.processMidi([_noteOn(channel: 0, pitch: 64, velocity: 100)], transport);

      final off = node.processMidi(
        [_noteOff(channel: 0, pitch: 60)],
        transport,
      );

      final newNoteOn = off.firstWhere((e) => e.isNoteOn);
      expect(newNoteOn.data1, 64,
          reason: 'basePitch must re-lock to the new lowest held pitch');
      expect(_pitchBend14(off.firstWhere(_isPitchBend)), 8192,
          reason: 'single-pitch cluster centres the bend');
    });
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Convenience constructor: build a Note-On [TimestampedMidiEvent] with the
/// raw MIDI status byte computed from [channel].
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

/// Convenience constructor: build a Note-Off [TimestampedMidiEvent].
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

/// Decode the 14-bit pitch-bend value from a pitch-bend event.
///
/// MIDI encoding: data1 = LSB (low 7 bits), data2 = MSB (high 7 bits).
int _pitchBend14(TimestampedMidiEvent e) => (e.data2 << 7) | e.data1;

/// Stub scale provider for [GFMidiNodeContext] — Microtone does not use it.
Set<int>? _nullScale() => null;
