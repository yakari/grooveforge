// Tests for the Xen MIDI FX plugin.
//
// Covers the three things the module promises and that nothing else in the
// codebase already guarantees:
//
//   1. **The gesture** — holding a note while tapping a scale latches that
//      note as the tonic, and the root then stays put (unlike Jam Mode's
//      bass-note mode, which keeps re-deriving it).
//   2. **Note-off integrity** — a snapped note must be released at the pitch
//      it was started on, even if the scale or root changed while it was
//      held. Getting this wrong produces stuck notes, which is the worst
//      failure mode a live performance module can have.
//   3. **Tuning hand-off** — the host is handed a table exactly when the
//      scale actually needs one, and a clear when it does not.
//
// The plugin takes its two host dependencies as callbacks, so none of this
// needs an AudioEngine.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/plugins/gf_xen_plugin.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

/// Transport stub — Xen ignores it entirely, but [processMidi] requires one.
const _transport = GFTransportContext.stopped;

/// Builds a plugin whose held notes and tuning sink the test controls.
///
/// [held] is mutated in place by tests to simulate the player's hands;
/// [pushed] records every table the plugin hands to the host, so tests can
/// assert on both the value and the number of pushes.
({GFXenPlugin plugin, Set<int> held, List<Float64List?> pushed}) makePlugin() {
  final held = <int>{};
  final pushed = <Float64List?>[];
  final plugin = GFXenPlugin(
    heldNotesProvider: () => held,
    tuningSink: pushed.add,
  );
  return (plugin: plugin, held: held, pushed: pushed);
}

TimestampedMidiEvent noteOn(int key, {int channel = 0, int velocity = 100}) =>
    TimestampedMidiEvent(
      ppqPosition: 0.0,
      status: 0x90 | channel,
      data1: key,
      data2: velocity,
    );

TimestampedMidiEvent noteOff(int key, {int channel = 0}) =>
    TimestampedMidiEvent(
      ppqPosition: 0.0,
      status: 0x80 | channel,
      data1: key,
      data2: 0,
    );

void main() {
  group('identity', () {
    test('is a MIDI FX plugin with a stable id', () {
      final f = makePlugin();
      expect(f.plugin.pluginId, 'com.grooveforge.xen');
      expect(f.plugin.name, 'Xen');
      expect(f.plugin.type, GFPluginType.midiFx);
    });
  });

  group('the gesture — hold a note, tap a scale', () {
    test('the lowest held note becomes the tonic', () {
      final f = makePlugin();
      // Player holds a D minor shape and taps "Rast".
      f.held.addAll({62, 65, 69});
      f.plugin.selectScale('maqamRast');

      expect(f.plugin.scale.id, 'maqamRast');
      expect(f.plugin.rootPc, 2, reason: 'D (62) is the lowest held note');
    });

    test('the root is the pitch class, whatever the octave', () {
      final f = makePlugin();
      f.held.add(38); // D1
      f.plugin.selectScale('maqamRast');
      expect(f.plugin.rootPc, 2);
    });

    test('the latched root stays put once the keys are released', () {
      final f = makePlugin();
      f.held.add(64); // E
      f.plugin.selectScale('maqamBayati');
      expect(f.plugin.rootPc, 4);

      // Player lifts their hand and plays elsewhere. Unlike Jam Mode's
      // bass-note detection, the tonic must not follow.
      f.held.clear();
      expect(f.plugin.rootPc, 4);
    });

    test('tapping through scales with nothing held keeps the tonic', () {
      final f = makePlugin();
      f.held.add(67); // G
      f.plugin.selectScale('maqamRast');
      f.held.clear();

      // Auditioning scales must not silently reset the tonic to C.
      f.plugin.selectScale('ragaYaman');
      expect(f.plugin.rootPc, 7);
      expect(f.plugin.scale.id, 'ragaYaman');
    });

    test('an unknown scale id is ignored rather than throwing', () {
      final f = makePlugin();
      f.plugin.selectScale('maqamRast');
      f.plugin.selectScale('scale.from.a.newer.build');
      expect(f.plugin.scale.id, 'maqamRast');
    });

    test('latchRoot moves the tonic without changing scale', () {
      final f = makePlugin();
      f.held.add(60);
      f.plugin.selectScale('ragaBhairav');
      f.held
        ..clear()
        ..add(65); // F
      f.plugin.latchRoot();

      expect(f.plugin.rootPc, 5);
      expect(f.plugin.scale.id, 'ragaBhairav');
    });
  });

  group('snap stage', () {
    test('leaves in-scale notes untouched', () {
      final f = makePlugin();
      f.plugin.setRoot(0);
      f.plugin.selectScale('major');
      final out = f.plugin.processMidi([noteOn(64)], _transport);
      expect(out.single.data1, 64);
    });

    test('pulls an out-of-scale note to the nearest allowed key', () {
      final f = makePlugin();
      f.plugin.setRoot(0);
      f.plugin.selectScale('major');
      // C# is not in C major; C is a semitone below, D a semitone above.
      final out = f.plugin.processMidi([noteOn(61)], _transport);
      expect(out.single.data1, 60, reason: 'ties resolve downward');
    });

    test('preserves velocity and channel', () {
      final f = makePlugin();
      f.plugin.setRoot(0);
      f.plugin.selectScale('major');
      final out = f.plugin
          .processMidi([noteOn(61, channel: 5, velocity: 77)], _transport)
          .single;
      expect(out.data2, 77);
      expect(out.midiChannel, 5);
    });

    test('is a no-op when disabled', () {
      final f = makePlugin();
      f.plugin.setRoot(0);
      f.plugin.selectScale('major');
      f.plugin.setSnapEnabled(false);
      final out = f.plugin.processMidi([noteOn(61)], _transport);
      expect(out.single.data1, 61);
    });

    test('a maqam snaps by key layout, not by its quarter-tones', () {
      final f = makePlugin();
      f.plugin.setRoot(0);
      f.plugin.selectScale('maqamRast');
      // Rast occupies the same keys as C major; the quarter-flat third is the
      // tuning stage's business, so E must still arrive as E.
      expect(f.plugin.processMidi([noteOn(64)], _transport).single.data1, 64);
      expect(f.plugin.processMidi([noteOn(61)], _transport).single.data1, 60);
    });

    test('a temperament constrains nothing', () {
      final f = makePlugin();
      f.plugin.setRoot(0);
      f.plugin.selectScale('justIntonation');
      // All twelve keys belong to the scale, so every note passes through.
      for (final key in [60, 61, 62, 63, 66, 70]) {
        expect(f.plugin.processMidi([noteOn(key)], _transport).single.data1, key);
      }
    });

    test('non-note events pass through untouched', () {
      final f = makePlugin();
      f.plugin.setRoot(0);
      f.plugin.selectScale('major');
      const cc = TimestampedMidiEvent(
        ppqPosition: 0.0, status: 0xB0, data1: 1, data2: 64,
      );
      expect(f.plugin.processMidi([cc], _transport).single, same(cc));
    });
  });

  group('note-off integrity', () {
    test('a snapped note is released at the pitch it sounded', () {
      final f = makePlugin();
      f.plugin.setRoot(0);
      f.plugin.selectScale('major');

      final on = f.plugin.processMidi([noteOn(61)], _transport).single;
      final off = f.plugin.processMidi([noteOff(61)], _transport).single;
      expect(on.data1, 60);
      expect(off.data1, 60, reason: 'the release must match the attack');
    });

    test('a root change mid-note does not strand the note', () {
      final f = makePlugin();
      f.plugin.setRoot(0);
      f.plugin.selectScale('major');
      final on = f.plugin.processMidi([noteOn(61)], _transport).single;
      expect(on.data1, 60);

      // The player performs the gesture again while the note is still down.
      f.held.add(66); // F#
      f.plugin.selectScale('major');
      expect(f.plugin.rootPc, 6);

      // Under F# major, key 61 would now snap to 61 itself — but the sounding
      // voice is at 60, and that is what has to be released.
      final off = f.plugin.processMidi([noteOff(61)], _transport).single;
      expect(off.data1, 60, reason: 'stale mapping would leave a stuck note');
    });

    test('a note held across a snap-disable is still released correctly', () {
      final f = makePlugin();
      f.plugin.setRoot(0);
      f.plugin.selectScale('major');
      f.plugin.processMidi([noteOn(61)], _transport);

      f.plugin.setSnapEnabled(false);
      // With snapping off processMidi passes everything through, so the
      // note-off arrives at 61 while the voice sounds at 60. This is a known
      // edge: the host's own key-owner bookkeeping releases the voice. What
      // must not happen is the plugin inventing a third pitch.
      final off = f.plugin.processMidi([noteOff(61)], _transport).single;
      expect(off.data1, 61);
    });

    test('channels keep independent mappings', () {
      final f = makePlugin();
      f.plugin.setRoot(0);
      f.plugin.selectScale('major');
      f.plugin.processMidi([noteOn(61, channel: 0)], _transport);
      f.plugin.processMidi([noteOn(61, channel: 1)], _transport);

      expect(
        f.plugin.processMidi([noteOff(61, channel: 1)], _transport).single.data1,
        60,
      );
      // Releasing on channel 1 must not have consumed channel 0's mapping.
      expect(
        f.plugin.processMidi([noteOff(61, channel: 0)], _transport).single.data1,
        60,
      );
    });

    test('an unmapped note-off passes through', () {
      final f = makePlugin();
      f.plugin.setRoot(0);
      f.plugin.selectScale('major');
      // A note already sounding when the module was patched in must still be
      // releasable.
      expect(f.plugin.processMidi([noteOff(61)], _transport).single.data1, 61);
    });
  });

  group('tuning hand-off', () {
    test('an equal-tempered scale asks the host to clear the tuning', () {
      final f = makePlugin();
      f.plugin.selectScale('major');
      expect(f.pushed.last, isNull,
          reason: 'an all-zero table and no table sound the same; prefer none');
      expect(f.plugin.tuningTable, isNull);
    });

    test('a microtonal scale hands over a 128-entry table', () {
      final f = makePlugin();
      f.plugin.selectScale('maqamRast');
      final table = f.pushed.last;
      expect(table, isNotNull);
      expect(table!.length, 128);
      expect(table[64], -50.0, reason: 'E is the half-flat third of Rast on C');
    });

    test('the table follows the latched root', () {
      final f = makePlugin();
      f.held.add(62); // D
      f.plugin.selectScale('maqamRast');
      final table = f.pushed.last!;
      expect(table[66], -50.0, reason: 'rooted on D, the third is F#');
      expect(table[64], 0.0);
    });

    test('disabling the tune stage clears the tuning', () {
      final f = makePlugin();
      f.plugin.selectScale('maqamRast');
      expect(f.pushed.last, isNotNull);

      f.plugin.setTuneEnabled(false);
      expect(f.pushed.last, isNull);
      expect(f.plugin.tuningTable, isNull);
    });

    test('re-enabling it reinstates the table', () {
      final f = makePlugin();
      f.plugin.selectScale('ragaYaman');
      f.plugin.setTuneEnabled(false);
      f.plugin.setTuneEnabled(true);
      expect(f.pushed.last, isNotNull);
    });

    test('disposing returns the target to equal temperament', () async {
      final f = makePlugin();
      f.plugin.selectScale('maqamRast');
      await f.plugin.dispose();
      expect(f.pushed.last, isNull,
          reason: 'a tuning outliving the module would detune the next plugin');
    });
  });

  group('piano display', () {
    test('reports the keys the scale allows', () {
      final f = makePlugin();
      f.plugin.setRoot(0);
      f.plugin.selectScale('major');
      expect(f.plugin.validPitchClasses, {0, 2, 4, 5, 7, 9, 11});
    });

    test('reports no constraint when snapping is off', () {
      final f = makePlugin();
      f.plugin.setRoot(0);
      f.plugin.selectScale('major');
      f.plugin.setSnapEnabled(false);
      expect(f.plugin.validPitchClasses, isNull);
    });

    test('marks only the keys that are actually detuned', () {
      final f = makePlugin();
      f.plugin.setRoot(0);
      f.plugin.selectScale('maqamRast');
      expect(f.plugin.centsByPitchClass, {4: -50.0, 11: -50.0});
    });

    test('marks nothing when the tune stage is off', () {
      final f = makePlugin();
      f.plugin.selectScale('maqamRast');
      f.plugin.setTuneEnabled(false);
      expect(f.plugin.centsByPitchClass, isEmpty);
    });
  });

  group('state', () {
    test('round-trips through save and load', () {
      final a = makePlugin();
      a.held.add(65);
      a.plugin.selectScale('ragaTodi');
      a.plugin.setSnapEnabled(false);
      final saved = a.plugin.getState();

      final b = makePlugin();
      b.plugin.loadState(saved);
      expect(b.plugin.scale.id, 'ragaTodi');
      expect(b.plugin.rootPc, 5);
      expect(b.plugin.snapEnabled, isFalse);
      expect(b.plugin.tuneEnabled, isTrue);
    });

    test('saves the scale id, not its catalogue index', () {
      // A saved project has to survive the catalogue gaining a scale in the
      // middle, which would shift every index after it.
      final f = makePlugin();
      f.plugin.selectScale('werckmeisterIII');
      expect(f.plugin.getState()['scaleId'], 'werckmeisterIII');
    });

    test('falls back to a default when the saved scale is unknown', () {
      final f = makePlugin();
      f.plugin.loadState({'scaleId': 'scale.from.a.newer.build', 'rootPc': 3});
      expect(f.plugin.scale.id, GFScaleLibrary.fallback.id);
      expect(f.plugin.rootPc, 3, reason: 'the rest of the state still applies');
    });

    test('loading pushes the restored tuning to the host', () {
      final f = makePlugin();
      f.plugin.loadState({'scaleId': 'maqamRast', 'rootPc': 0});
      expect(f.pushed.last, isNotNull);
      expect(f.pushed.last![64], -50.0);
    });
  });

  group('parameters', () {
    test('scale and root round-trip through the parameter interface', () {
      final f = makePlugin();
      final index = GFScaleLibrary.all.indexOf(GFScaleLibrary.maqamBayati);
      f.plugin.setParameter(GFXenPlugin.paramScale, index.toDouble());
      f.plugin.setParameter(GFXenPlugin.paramRoot, 9);

      expect(f.plugin.scale.id, 'maqamBayati');
      expect(f.plugin.rootPc, 9);
      expect(f.plugin.getParameter(GFXenPlugin.paramScale), index.toDouble());
      expect(f.plugin.getParameter(GFXenPlugin.paramRoot), 9.0);
    });

    test('out-of-range values are clamped rather than crashing', () {
      final f = makePlugin();
      f.plugin.setParameter(GFXenPlugin.paramScale, 9999);
      expect(f.plugin.scale, GFScaleLibrary.all.last);
      f.plugin.setParameter(GFXenPlugin.paramRoot, -5);
      expect(f.plugin.rootPc, 0);
    });

    test('the declared parameter range covers the whole catalogue', () {
      final f = makePlugin();
      final scaleParam = f.plugin.parameters
          .firstWhere((p) => p.id == GFXenPlugin.paramScale);
      expect(scaleParam.max, (GFScaleLibrary.all.length - 1).toDouble());
    });
  });
}
