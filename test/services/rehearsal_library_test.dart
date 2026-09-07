import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/services/rehearsal_library.dart';

/// Exercises the rehearsal library against a real temporary directory rather
/// than a mock filesystem: the things most likely to break here — the atomic
/// rename on save, deleting a superseded take, skipping a corrupt folder — are
/// all filesystem behaviour, and a mock would happily agree with a wrong
/// implementation.
void main() {
  late Directory tmp;
  late RehearsalLibrary library;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('gf_reh_test');
    library = RehearsalLibrary(rootOverride: tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('creating', () {
    test('a new rehearsal has one member with one part, and persists', () async {
      final r = await library.create(
        title: 'Autumn Leaves',
        memberName: 'Yann',
        instrument: 'guitar',
        bpm: 132,
        beatsPerBar: 3,
      );

      expect(r.title, 'Autumn Leaves');
      expect(r.bpm, 132);
      expect(r.beatsPerBar, 3);
      expect(r.members, hasLength(1));
      expect(r.parts, hasLength(1));
      expect(r.parts.single.memberId, r.members.single.id);
      expect(r.parts.single.isRecorded, isFalse);

      // And it is on disk, not just in memory.
      final manifest = File('${tmp.path}/rehearsals/${r.id}/rehearsal.json');
      expect(await manifest.exists(), isTrue);
    });

    test('ids are unique across rehearsals', () async {
      final a = await library.create(
          title: 'A', memberName: 'Y', instrument: 'guitar');
      final b = await library.create(
          title: 'B', memberName: 'Y', instrument: 'guitar');
      expect(a.id, isNot(b.id));
      expect(a.parts.single.id, isNot(b.parts.single.id));
    });

    test('the default count-in is two bars', () async {
      final r = await library.create(
          title: 'A', memberName: 'Y', instrument: 'drums');
      expect(r.countInBars, 2);
    });
  });

  group('loading', () {
    test('round-trips every field through JSON', () async {
      final created = await library.create(
        title: 'Blue in Green',
        memberName: 'Léa',
        instrument: 'saxophone',
        bpm: 62.5,
        countInBars: 1,
      );

      final fresh = RehearsalLibrary(rootOverride: tmp);
      await fresh.load();

      expect(fresh.rehearsals, hasLength(1));
      final r = fresh.rehearsals.single;
      expect(r.id, created.id);
      expect(r.title, 'Blue in Green');
      expect(r.bpm, 62.5);
      expect(r.countInBars, 1);
      expect(r.members.single.displayName, 'Léa');
      expect(r.members.single.instrument, 'saxophone');
    });

    test('newest first', () async {
      final first = await library.create(
          title: 'First', memberName: 'Y', instrument: 'guitar');
      // createdAt is wall-clock, so without a gap the sort has nothing to go on.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = await library.create(
          title: 'Second', memberName: 'Y', instrument: 'guitar');

      final fresh = RehearsalLibrary(rootOverride: tmp);
      await fresh.load();
      expect(fresh.rehearsals.map((r) => r.id), [second.id, first.id]);
    });

    test('a corrupt manifest costs one rehearsal, not the library', () async {
      final good = await library.create(
          title: 'Good', memberName: 'Y', instrument: 'guitar');
      final bad = await library.create(
          title: 'Bad', memberName: 'Y', instrument: 'guitar');
      await File('${tmp.path}/rehearsals/${bad.id}/rehearsal.json')
          .writeAsString('{ this is not json');

      final fresh = RehearsalLibrary(rootOverride: tmp);
      await fresh.load();

      expect(fresh.rehearsals, hasLength(1));
      expect(fresh.rehearsals.single.id, good.id);
    });
  });

  group('takes', () {
    test('committing one bumps the revision and names the next file', () async {
      final r = await library.create(
          title: 'A', memberName: 'Y', instrument: 'guitar');
      final part = r.parts.single;

      expect(library.nextTakeFileName(part), '${part.id}-1.wav');

      await library.commitTake(r, part,
          fileName: library.nextTakeFileName(part),
          frames: 48000,
          sampleRate: 48000,
          compensationFrames: 1440);

      expect(part.isRecorded, isTrue);
      expect(part.take!.revision, 1);
      expect(part.take!.frames, 48000);
      expect(part.take!.compensationFrames, 1440);
      expect(part.take!.duration, const Duration(seconds: 1));
      expect(library.nextTakeFileName(part), '${part.id}-2.wav');
    });

    test('re-recording deletes the superseded audio', () async {
      final r = await library.create(
          title: 'A', memberName: 'Y', instrument: 'guitar');
      final part = r.parts.single;

      // Stand in for a real recording: the library only cares that the file
      // named by the take exists and goes away when superseded.
      final takes = await library.takesDir(r.id);
      final first = File('${takes.path}/${part.id}-1.wav');
      await first.writeAsBytes(List.filled(128, 0));
      await library.commitTake(r, part,
          fileName: '${part.id}-1.wav',
          frames: 1,
          sampleRate: 48000,
          compensationFrames: 0);

      final second = File('${takes.path}/${part.id}-2.wav');
      await second.writeAsBytes(List.filled(128, 0));
      await library.commitTake(r, part,
          fileName: '${part.id}-2.wav',
          frames: 2,
          sampleRate: 48000,
          compensationFrames: 0);

      expect(part.take!.revision, 2);
      expect(await first.exists(), isFalse,
          reason: 'the superseded take should not linger on disk');
      expect(await second.exists(), isTrue);
    });

    test('a take survives a reload', () async {
      final r = await library.create(
          title: 'A', memberName: 'Y', instrument: 'bassGuitar');
      await library.commitTake(r, r.parts.single,
          fileName: 'x.wav',
          frames: 96000,
          sampleRate: 48000,
          compensationFrames: 900);

      final fresh = RehearsalLibrary(rootOverride: tmp);
      await fresh.load();
      final take = fresh.rehearsals.single.parts.single.take;
      expect(take, isNotNull);
      expect(take!.frames, 96000);
      expect(take.compensationFrames, 900);
    });
  });

  group('grid', () {
    test('is frozen as soon as any part is recorded', () async {
      final r = await library.create(
          title: 'A', memberName: 'Y', instrument: 'guitar');
      expect(r.isGridFrozen, isFalse);

      await library.commitTake(r, r.parts.single,
          fileName: 'x.wav',
          frames: 100,
          sampleRate: 48000,
          compensationFrames: 0);

      expect(r.isGridFrozen, isTrue,
          reason: 'every recorded take is aligned to the current grid');
    });

    test('length is the longest take', () async {
      final r = await library.create(
          title: 'A', memberName: 'Y', instrument: 'guitar');
      final second = await library.addPart(r,
          memberId: r.members.single.id, instrument: 'vocals');

      await library.commitTake(r, r.parts.first,
          fileName: 'a.wav',
          frames: 1000,
          sampleRate: 48000,
          compensationFrames: 0);
      await library.commitTake(r, second,
          fileName: 'b.wav',
          frames: 7000,
          sampleRate: 48000,
          compensationFrames: 0);

      expect(r.lengthFrames, 7000);
      expect(r.recordedPartCount, 2);
    });
  });

  group('parts', () {
    test('one member can own several', () async {
      final r = await library.create(
          title: 'A', memberName: 'Yann', instrument: 'guitar');
      final member = r.members.single;
      final vocals = await library.addPart(r,
          memberId: member.id, instrument: 'vocals');

      expect(r.parts, hasLength(2));
      expect(r.parts.every((p) => p.memberId == member.id), isTrue);
      expect(vocals.instrument, 'vocals');
    });
  });

  group('local state', () {
    test('never enters the shared manifest', () async {
      final r = await library.create(
          title: 'A', memberName: 'Y', instrument: 'guitar');
      final part = r.parts.single;

      final state = await library.loadLocalState(r.id);
      state.mutedPartIds.add(part.id);
      state.gains[part.id] = 0.25;
      state.compensationFrames = 1390;
      await library.saveLocalState(r.id, state);

      // The shared document must not mention any of it — mute and gain are one
      // player's monitoring choices and have no business syncing.
      final manifest =
          await File('${tmp.path}/rehearsals/${r.id}/rehearsal.json')
              .readAsString();
      expect(manifest.contains('mutedPartIds'), isFalse);
      expect(manifest.contains('compensationFrames'), isFalse,
          reason: 'no take has been committed, so nothing carries one yet');
      expect(manifest.contains('0.25'), isFalse);

      final reloaded = await library.loadLocalState(r.id);
      expect(reloaded.isMuted(part.id), isTrue);
      expect(reloaded.gainFor(part.id), 0.25);
      expect(reloaded.gainFor('unknown-part'), 1.0);
      expect(reloaded.compensationFrames, 1390);
    });

    test('missing local state falls back to sane defaults', () async {
      final r = await library.create(
          title: 'A', memberName: 'Y', instrument: 'guitar');
      await File('${tmp.path}/rehearsals/${r.id}/self.json').delete();

      final state = await library.loadLocalState(r.id);
      expect(state.compensationFrames, 0);
      expect(state.metronomeEnabled, isTrue);
      expect(state.mutedPartIds, isEmpty);
    });

    test('unreadable local state does not throw', () async {
      final r = await library.create(
          title: 'A', memberName: 'Y', instrument: 'guitar');
      await File('${tmp.path}/rehearsals/${r.id}/self.json')
          .writeAsString('nonsense{{');

      final state = await library.loadLocalState(r.id);
      expect(state.metronomeEnabled, isTrue);
    });
  });

  group('deleting', () {
    test('removes the folder and every take with it', () async {
      final r = await library.create(
          title: 'A', memberName: 'Y', instrument: 'guitar');
      final takes = await library.takesDir(r.id);
      await File('${takes.path}/big.wav').writeAsBytes(List.filled(4096, 1));

      expect(await library.sizeOnDisk(r.id), greaterThan(4000));

      await library.delete(r.id);
      expect(library.rehearsals, isEmpty);
      expect(await Directory('${tmp.path}/rehearsals/${r.id}').exists(), isFalse);
    });
  });

  group('manifest format', () {
    test('carries a version and a logical clock from the start', () async {
      final r = await library.create(
          title: 'A', memberName: 'Y', instrument: 'guitar');
      final json = jsonDecode(
              await File('${tmp.path}/rehearsals/${r.id}/rehearsal.json')
                  .readAsString())
          as Map<String, dynamic>;

      // Both exist before they are needed, so the first rehearsals recorded
      // will not need a migration once syncing lands.
      expect(json['formatVersion'], 1);
      expect(json['lamport'], 0);
    });
  });
}
