import 'package:bonsoir/bonsoir.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/services/rehearsal_discovery.dart';

/// Builds a resolved advertisement the way a real stack hands one over.
BonsoirService _service({
  required String name,
  required String device,
  required String rehearsal,
  String host = '192.168.1.50',
  int port = 4000,
}) =>
    BonsoirService(
      name: name,
      type: RehearsalDiscovery.serviceType,
      port: port,
      hostAddresses: [host],
      attributes: {'d': device, 'r': rehearsal},
    );

void main() {
  group('peer identity', () {
    test('a renamed service is the same peer, not a second one', () {
      final discovery = RehearsalDiscovery();
      discovery.remember(_service(
          name: 'test2', device: 'dev-a', rehearsal: 'reh-1'));
      // mDNS renames on a name collision. Same device, new label.
      discovery.remember(_service(
          name: 'test2 (3)', device: 'dev-a', rehearsal: 'reh-1'));

      expect(discovery.peersFor('reh-1'), hasLength(1));
    });

    test('different devices sharing a tune are different peers', () {
      final discovery = RehearsalDiscovery();
      discovery.remember(_service(
          name: 'test2 · aaa', device: 'dev-a', rehearsal: 'reh-1'));
      discovery.remember(_service(
          name: 'test2 · bbb',
          device: 'dev-b',
          rehearsal: 'reh-1',
          host: '192.168.1.51'));

      expect(discovery.peersFor('reh-1'), hasLength(2));
    });
  });

  group('goodbyes', () {
    test('a peer that still answers survives a goodbye', () async {
      final discovery = RehearsalDiscovery()
        ..reachabilityProbe = (_) async => true;
      final service =
          _service(name: 'test2', device: 'dev-a', rehearsal: 'reh-1');
      discovery.remember(service);
      await discovery.onLost(service);

      // A rename withdraws a name while the device stays put.
      expect(discovery.peersFor('reh-1'), hasLength(1));
    });

    test('a peer that has stopped listening goes at once', () async {
      final discovery = RehearsalDiscovery()
        ..reachabilityProbe = (_) async => false;
      final service =
          _service(name: 'test2', device: 'dev-a', rehearsal: 'reh-1');
      discovery.remember(service);
      await discovery.onLost(service);

      expect(discovery.peersFor('reh-1'), isEmpty,
          reason: 'the room should not show a device that has left');
    });

    test('without a probe the peer waits out the grace period', () async {
      final discovery = RehearsalDiscovery();
      final service =
          _service(name: 'test2', device: 'dev-a', rehearsal: 'reh-1');
      discovery.remember(service);
      await discovery.onLost(service);

      expect(discovery.peersFor('reh-1'), hasLength(1));
      discovery.sweepStale();
      expect(discovery.peersFor('reh-1'), hasLength(1),
          reason: 'the grace period has not elapsed yet');
    });

    test('a sighting during the probe keeps the peer', () async {
      late final RehearsalDiscovery discovery;
      final service =
          _service(name: 'test2', device: 'dev-a', rehearsal: 'reh-1');
      discovery = RehearsalDiscovery()
        ..reachabilityProbe = (_) async {
          // The device re-announced while we were knocking on the door.
          discovery.remember(service);
          return false;
        };
      discovery.remember(service);
      await discovery.onLost(service);

      expect(discovery.peersFor('reh-1'), hasLength(1),
          reason: 'a fresh sighting outranks a stale goodbye');
    });

    test('talking to a peer clears a goodbye', () async {
      final discovery = RehearsalDiscovery();
      final service =
          _service(name: 'test2', device: 'dev-a', rehearsal: 'reh-1');
      discovery.remember(service);
      await discovery.onLost(service);
      discovery.confirmReachable('192.168.1.50');

      final peer = discovery.peersFor('reh-1').single;
      // Sighting pushed back to now, so the grace period no longer applies.
      expect(
        DateTime.now().difference(peer.seenAt),
        lessThan(const Duration(seconds: 1)),
      );
    });
  });

  test('the advertised name is unique per device', () {
    final a = RehearsalDiscovery.instanceName('test2', 'aaaaaaaaaaaa');
    final b = RehearsalDiscovery.instanceName('test2', 'bbbbbbbbbbbb');
    expect(a, isNot(b),
        reason: 'a collision is what makes the daemon rename services');
    expect(a.length, lessThan(63), reason: 'must fit in a DNS label');

    // A long tune title must not push the name over the label limit either.
    final long = RehearsalDiscovery.instanceName('x' * 200, 'aaaaaaaaaaaa');
    expect(long.length, lessThan(63));
  });
}
