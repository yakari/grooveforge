import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/rehearsal.dart';
import 'package:grooveforge/services/rehearsal_merge.dart';

/// The merge is the whole reason syncing can work without a server, so these
/// tests lean hard on the two properties that make it safe: it never loses a
/// take, and it is symmetric — both devices reach the same document from their
/// own point of view. Anything else is a detail; those two are the contract.

Rehearsal _rehearsal({
  String id = 'r1',
  String title = 'Tune',
  double bpm = 120,
  int lamport = 0,
}) =>
    Rehearsal(
      id: id,
      title: title,
      bpm: bpm,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      createdAt: DateTime(2026, 1, 1),
      members: [],
      parts: [],
      lamport: lamport,
    );

RehearsalPart _part(String id, {int? takeRevision, String member = 'm1'}) {
  final p = RehearsalPart(id: id, memberId: member, instrument: 'guitar');
  if (takeRevision != null) {
    p.take = RehearsalTake(
      fileName: '$id-$takeRevision.wav',
      revision: takeRevision,
      frames: 48000 * takeRevision,
      sampleRate: 48000,
      compensationFrames: 0,
      recordedAt: DateTime(2026, 1, 1),
    );
  }
  return p;
}

/// Deep-copies through JSON, so a merge cannot accidentally share objects with
/// the document it merged from — which would make symmetry tests pass for the
/// wrong reason.
Rehearsal _copy(Rehearsal r) =>
    Rehearsal.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);

void main() {
  group('takes', () {
    test('a part only the peer has arrives, and its audio is requested', () {
      final local = _rehearsal();
      final remote = _rehearsal()..parts.add(_part('p-bass', takeRevision: 1));

      final out = mergeRehearsal(local, remote);

      expect(out.changed, isTrue);
      expect(local.parts.map((p) => p.id), ['p-bass']);
      expect(out.partsToFetch, ['p-bass'],
          reason: 'the manifest has the take but the audio is still remote');
    });

    test('a higher revision wins and is fetched', () {
      final local = _rehearsal()..parts.add(_part('p1', takeRevision: 1));
      final remote = _rehearsal()..parts.add(_part('p1', takeRevision: 3));

      final out = mergeRehearsal(local, remote);

      expect(local.parts.single.take!.revision, 3);
      expect(out.partsToFetch, ['p1']);
    });

    test('a lower revision is ignored and nothing is fetched', () {
      final local = _rehearsal()..parts.add(_part('p1', takeRevision: 5));
      final remote = _rehearsal()..parts.add(_part('p1', takeRevision: 2));

      final out = mergeRehearsal(local, remote);

      expect(local.parts.single.take!.revision, 5);
      expect(out.partsToFetch, isEmpty);
      expect(out.changed, isFalse);
    });

    test('an equal revision is the same take and is not re-fetched', () {
      final local = _rehearsal()..parts.add(_part('p1', takeRevision: 2));
      final remote = _rehearsal()..parts.add(_part('p1', takeRevision: 2));

      final out = mergeRehearsal(local, remote);

      expect(out.partsToFetch, isEmpty,
          reason: 'megabytes moved to arrive at what is already here');
      expect(out.changed, isFalse);
    });

    test('a peer with no take never clears one we have', () {
      final local = _rehearsal()..parts.add(_part('p1', takeRevision: 4));
      final remote = _rehearsal()..parts.add(_part('p1'));

      mergeRehearsal(local, remote);

      expect(local.parts.single.take, isNotNull,
          reason: 'losing a recording to a merge is the one unforgivable bug');
      expect(local.parts.single.take!.revision, 4);
    });

    test('parts from both sides are unioned, not replaced', () {
      final local = _rehearsal()
        ..parts.addAll([_part('p1', takeRevision: 1), _part('p2')]);
      final remote = _rehearsal()
        ..parts.addAll([_part('p2', takeRevision: 1), _part('p3', takeRevision: 2)]);

      final out = mergeRehearsal(local, remote);

      expect(local.parts.map((p) => p.id).toSet(), {'p1', 'p2', 'p3'});
      expect(out.partsToFetch.toSet(), {'p2', 'p3'});
    });
  });

  group('members', () {
    test('unknown members are added, known ones left alone', () {
      final local = _rehearsal()
        ..members.add(RehearsalMember(
            id: 'm1', displayName: 'Yann', instrument: 'guitar'));
      final remote = _rehearsal()
        ..members.addAll([
          RehearsalMember(
              id: 'm1', displayName: 'CHANGED', instrument: 'drums'),
          RehearsalMember(id: 'm2', displayName: 'Léa', instrument: 'vocals'),
        ]);

      mergeRehearsal(local, remote);

      expect(local.members, hasLength(2));
      expect(local.members.firstWhere((m) => m.id == 'm1').displayName, 'Yann');
      expect(local.members.firstWhere((m) => m.id == 'm2').displayName, 'Léa');
    });
  });

  group('metadata', () {
    test('an untouched field never overwrites a touched one', () {
      final local = _rehearsal(bpm: 132)..touch(RehearsalField.bpm, 'deviceA');
      final remote = _rehearsal(bpm: 120); // never edited, so zero clock

      final out = mergeRehearsal(local, remote);

      expect(local.bpm, 132);
      expect(out.changed, isFalse);
    });

    test('the later edit wins', () {
      final local = _rehearsal(bpm: 100)..touch(RehearsalField.bpm, 'deviceA');
      final remote = _rehearsal(bpm: 90, lamport: 5)
        ..touch(RehearsalField.bpm, 'deviceB');

      mergeRehearsal(local, remote);

      expect(local.bpm, 90);
      expect(local.clockFor(RehearsalField.bpm).device, 'deviceB');
    });

    test('fields are independent — a tempo edit does not drag the title', () {
      final local = _rehearsal(title: 'Local title', bpm: 100)
        ..touch(RehearsalField.title, 'deviceA');
      final remote = _rehearsal(title: 'Remote title', bpm: 90, lamport: 9)
        ..touch(RehearsalField.bpm, 'deviceB');

      mergeRehearsal(local, remote);

      expect(local.bpm, 90, reason: 'the peer edited the tempo');
      expect(local.title, 'Local title',
          reason: 'and only the tempo — the title was never theirs to change');
    });

    test('a simultaneous edit resolves the same way on both devices', () {
      // Two devices edit the same field while apart, and arrive at the same
      // counter. Without a deterministic tiebreak each would keep its own
      // value and the two would never converge.
      Rehearsal makeA() => _rehearsal(bpm: 100)..touch(RehearsalField.bpm, 'aaa');
      Rehearsal makeB() => _rehearsal(bpm: 140)..touch(RehearsalField.bpm, 'zzz');

      final onDeviceA = makeA();
      mergeRehearsal(onDeviceA, makeB());

      final onDeviceB = makeB();
      mergeRehearsal(onDeviceB, makeA());

      expect(onDeviceA.bpm, onDeviceB.bpm,
          reason: 'both devices must land on the same tempo');
      expect(onDeviceA.bpm, 140, reason: 'the higher device id breaks the tie');
    });

    test('the document clock ends ahead of both sides', () {
      final local = _rehearsal(lamport: 3);
      final remote = _rehearsal(lamport: 11);

      mergeRehearsal(local, remote);

      expect(local.lamport, 11);
      // And the next local edit must not reuse a counter the peer already has.
      local.touch(RehearsalField.title, 'deviceA');
      expect(local.lamport, 12);
    });
  });

  group('master', () {
    RehearsalMaster master({String name = 'tune.mp3', int frames = 960000,
        int offset = 0}) =>
        RehearsalMaster(
          fileName: 'master.wav',
          sourceName: name,
          frames: frames,
          sampleRate: 48000,
          offsetFrames: offset,
        );

    test('arrives from the peer and is fetched', () {
      final local = _rehearsal();
      final remote = _rehearsal()
        ..master = master()
        ..touch(RehearsalField.master, 'deviceB');

      final out = mergeRehearsal(local, remote);

      expect(local.master, isNotNull);
      expect(out.masterToFetch, isTrue);
      expect(out.changed, isTrue);
    });

    test('a re-anchored downbeat syncs without moving the audio again', () {
      final local = _rehearsal()
        ..master = master(offset: 0)
        ..touch(RehearsalField.master, 'deviceA');
      final remote = _rehearsal(lamport: 7)
        ..master = master(offset: 64883)
        ..touch(RehearsalField.master, 'deviceB');

      final out = mergeRehearsal(local, remote);

      expect(local.master!.offsetFrames, 64883);
      expect(out.changed, isTrue);
      expect(out.masterToFetch, isFalse,
          reason: 'same recording, only the grid anchor moved');
    });

    test('an untouched peer never removes ours', () {
      final local = _rehearsal()
        ..master = master()
        ..touch(RehearsalField.master, 'deviceA');
      final remote = _rehearsal();

      final out = mergeRehearsal(local, remote);

      expect(local.master, isNotNull);
      expect(out.masterToFetch, isFalse);
    });
  });

  group('convergence', () {
    test('merging twice changes nothing the second time', () {
      final local = _rehearsal()..parts.add(_part('p1', takeRevision: 1));
      final remote = _rehearsal(lamport: 4)
        ..parts.addAll([_part('p1', takeRevision: 2), _part('p2', takeRevision: 1)])
        ..title = 'Theirs'
        ..touch(RehearsalField.title, 'deviceB');

      final first = mergeRehearsal(local, _copy(remote));
      expect(first.changed, isTrue);

      final second = mergeRehearsal(local, _copy(remote));
      expect(second.changed, isFalse,
          reason: 'a settled pair must stop exchanging data');
      expect(second.partsToFetch, isEmpty);
    });

    test('two devices reach the same document from either direction', () {
      Rehearsal deviceA() => _rehearsal(title: 'A side')
        ..parts.addAll([_part('p1', takeRevision: 2), _part('pA', takeRevision: 1)])
        ..members.add(RehearsalMember(
            id: 'mA', displayName: 'Yann', instrument: 'guitar'))
        ..touch(RehearsalField.title, 'aaa');

      Rehearsal deviceB() => _rehearsal(title: 'B side', lamport: 6)
        ..parts.addAll([_part('p1', takeRevision: 5), _part('pB', takeRevision: 3)])
        ..members.add(RehearsalMember(
            id: 'mB', displayName: 'Léa', instrument: 'vocals'))
        ..touch(RehearsalField.title, 'zzz');

      final a = deviceA();
      mergeRehearsal(a, deviceB());
      final b = deviceB();
      mergeRehearsal(b, deviceA());

      expect(a.title, b.title);
      expect(a.bpm, b.bpm);
      expect(a.parts.map((p) => p.id).toSet(),
          b.parts.map((p) => p.id).toSet());
      expect(a.members.map((m) => m.id).toSet(),
          b.members.map((m) => m.id).toSet());
      // The point of the whole exercise: the same take wins on both sides.
      for (final id in ['p1', 'pA', 'pB']) {
        final ta = a.parts.firstWhere((p) => p.id == id).take;
        final tb = b.parts.firstWhere((p) => p.id == id).take;
        expect(ta?.revision, tb?.revision, reason: 'part $id diverged');
      }
      expect(a.parts.firstWhere((p) => p.id == 'p1').take!.revision, 5);
    });
  });
}
