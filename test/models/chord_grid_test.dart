import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/widgets/chord_grid.dart';
import 'package:grooveforge/models/rehearsal.dart';
import 'package:grooveforge/services/rehearsal_merge.dart';

Rehearsal _rehearsal({int lamport = 0}) => Rehearsal(
      id: 'reh-1',
      title: 'Tune',
      bpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      createdAt: DateTime(2026, 1, 1),
      members: [],
      parts: [],
      lamport: lamport,
    );

RehearsalBar _bar(List<String?> slots) => RehearsalBar(slots: slots);

void main() {
  group('a bar', () {
    test('holds a chord per slot, and slots may be empty', () {
      // The case that decided the model: four slots with the second left
      // blank means the first chord holds through beat two.
      final bar = _bar(['C', null, 'Am', 'G']);
      expect(bar.division, 4);
      expect(bar.slots[1], isNull);
      expect(bar.isEmpty, isFalse);
    });

    test('an untouched bar is empty', () {
      expect(_bar([null]).isEmpty, isTrue);
      expect(_bar([null, null]).isEmpty, isTrue);
    });

    test('re-dividing keeps chords where they were played', () {
      // Not where they were *indexed*: the chord on beat three belongs in the
      // second half, which is where it sounds.
      final four = _bar(['C', null, 'Am', 'G']);
      final two = four.withDivision(2);
      expect(two.slots, ['C', 'Am']);
    });

    test('re-dividing upwards leaves the new slots empty', () {
      final one = _bar(['C']);
      expect(one.withDivision(4).slots, ['C', null, null, null]);
    });

    test('a narrowing that would collide keeps the first chord', () {
      // Two chords landing in one slot: the earlier one is the one that was
      // played there, so it wins rather than being overwritten.
      final four = _bar(['C', 'D', 'Am', 'G']);
      expect(four.withDivision(2).slots, ['C', 'Am']);
    });

    test('it survives a round trip', () {
      final bar = _bar(['C#m7', null, 'Gm7b5', null]);
      final back = RehearsalBar.fromJson(bar.toJson());
      expect(back.slots, bar.slots);
    });
  });

  group('the form on the document', () {
    test('it round-trips with the rehearsal', () {
      final r = _rehearsal()
        ..chords.addAll([_bar(['C']), _bar(['Am', 'F'])]);
      final back = Rehearsal.fromJson(r.toJson());
      expect(back.formBars, 2);
      expect(back.chords[1].slots, ['Am', 'F']);
    });

    test('a tune with no chart has no form length', () {
      expect(_rehearsal().formBars, 0);
    });
  });

  group('merging a chart', () {
    test('the newer chart wins whole', () {
      // A form is a shape, not a stream of edits: half of one chart and half
      // of another is not a tune anybody wrote.
      final local = _rehearsal()..chords.add(_bar(['C']));
      final remote = _rehearsal(lamport: 5)
        ..chords.addAll([_bar(['Am']), _bar(['F'])])
        ..touch(RehearsalField.chords, 'zzz');

      mergeRehearsal(local, remote);

      expect(local.formBars, 2);
      expect(local.chords.first.slots, ['Am']);
    });

    test('an older chart does not overwrite a newer one', () {
      final local = _rehearsal(lamport: 9)
        ..chords.add(_bar(['Am']))
        ..touch(RehearsalField.chords, 'zzz');
      final remote = _rehearsal(lamport: 1)
        ..chords.add(_bar(['C']))
        ..touch(RehearsalField.chords, 'aaa');

      mergeRehearsal(local, remote);

      expect(local.chords.single.slots, ['Am']);
    });

    test('the merged bars are copies, not the peer objects', () {
      // The remote document is thrown away after a merge; sharing its bars
      // would leave the local one holding objects a later edit could mutate.
      final local = _rehearsal();
      final remote = _rehearsal(lamport: 3)
        ..chords.add(_bar(['C']))
        ..touch(RehearsalField.chords, 'zzz');

      mergeRehearsal(local, remote);
      remote.chords.first.slots[0] = 'MUTATED';

      expect(local.chords.first.slots.first, 'C');
    });
  });

  group('typing a chord', () {
    /// Runs text through the field's formatter the way the framework does.
    String typed(String text) {
      const formatter = chordCasingForTesting;
      return formatter
          .formatEditUpdate(
            const TextEditingValue(),
            TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length),
            ),
          )
          .text;
    }

    test('the root is raised and nothing else is', () {
      // The bug this replaced: a keyboard set to capitalise every character
      // turned this into ABM7SUS4, which is not a chord anyone can type.
      expect(typed('abm7sus4'), 'Abm7sus4');
      expect(typed('cm'), 'Cm');
      expect(typed('gm7b5'), 'Gm7b5');
    });

    test('a bass after a slash is raised too', () {
      expect(typed('c/g'), 'C/G');
      expect(typed('am(m7)/b'), 'Am(m7)/B');
    });

    test('the length never changes, so the caret stays put', () {
      for (final s in ['abm7sus4', 'c/g', '']) {
        expect(typed(s).length, s.length, reason: s);
      }
    });
  });
}
