import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/audio_latency_status.dart';
import 'package:grooveforge/services/audio_latency_monitor.dart';

const _streamOpen = 1 << 0;
const _lowLatencyGranted = 1 << 1;
const _exclusiveGranted = 1 << 2;
const _lowLatencyLatched = 1 << 3;

/// A stream that got everything it asked for.
const _healthyBits = _streamOpen | _lowLatencyGranted | _exclusiveGranted;

/// A session that has given up on the fast path.
const _latchedBits = _streamOpen | _lowLatencyLatched;

/// A monitor driven by a mutable fake bus, recording every clear request.
class _Harness {
  int bits = _healthyBits;
  int bufferUs = 4000;
  int clearCalls = 0;
  int notifications = 0;

  late final AudioLatencyMonitor monitor = AudioLatencyMonitor(
    readStatus: () => AudioLatencyStatus.fromNative(bits, bufferUs),
    clearLatches: () {
      clearCalls++;
      // The native side clears the latch and reopens on its own thread; the
      // test stands in for that by flipping the bus here.
      bits = _healthyBits;
      bufferUs = 4000;
    },
    enabled: true,
    // Long enough that only explicit start()/recover() calls drive the tests.
    pollInterval: const Duration(hours: 1),
  );

  _Harness() {
    monitor.addListener(() => notifications++);
  }
}

void main() {
  test('start() reads the bus immediately', () {
    final h = _Harness()..bits = _latchedBits;
    expect(h.monitor.status.isLatched, isFalse); // nothing read yet
    h.monitor.start();
    expect(h.monitor.status.isLatched, isTrue);
    h.monitor.dispose();
  });

  test('a disabled monitor never touches the bus', () {
    // Desktop, iOS and web have no AAudio bus; calling into the bindings
    // there would throw rather than report "healthy".
    var reads = 0;
    final monitor = AudioLatencyMonitor(
      readStatus: () {
        reads++;
        return AudioLatencyStatus.fromNative(_latchedBits, 66000);
      },
      clearLatches: () => fail('must not clear latches when disabled'),
      enabled: false,
    );
    monitor.start();
    monitor.recover();
    expect(reads, 0);
    expect(monitor.status, AudioLatencyStatus.unavailable);
    monitor.dispose();
  });

  test('notifies only when something actually changed', () {
    final h = _Harness();
    h.monitor.start();
    final afterStart = h.notifications;

    // Same bits again: a poll that found nothing new must not rebuild the
    // app bar every two seconds.
    h.monitor.start(); // no-op, timer already running
    expect(h.notifications, afterStart);

    h.bits = _latchedBits;
    h.bufferUs = 66000;
    h.monitor.stop();
    h.monitor.start(); // forces a fresh read
    expect(h.notifications, greaterThan(afterStart));
    h.monitor.dispose();
  });

  group('recover', () {
    test('clears the latches and reports progress meanwhile', () async {
      final h = _Harness()
        ..bits = _latchedBits
        ..bufferUs = 66000;
      h.monitor.start();
      expect(h.monitor.status.canRecover, isTrue);

      h.monitor.recover();
      expect(h.clearCalls, 1);
      // The native reopen is still in flight, so the button must keep showing
      // progress rather than snapping back to the same message.
      expect(h.monitor.recovering, isTrue);

      // The monitor re-reads shortly after, without waiting for the next poll.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(h.monitor.recovering, isFalse);
      expect(h.monitor.status.isLatched, isFalse);
      expect(h.monitor.status.isDegraded, isFalse);
      h.monitor.dispose();
    });

    test('a second press while recovering is ignored', () {
      final h = _Harness()..bits = _latchedBits;
      h.monitor.start();
      h.monitor.recover();
      h.monitor.recover();
      expect(h.clearCalls, 1);
      h.monitor.dispose();
    });

    test('stops showing progress even when the latch survives', () async {
      // The honest dead end: the platform refuses the fast path again. The
      // button must stop spinning so the sheet can say so.
      final h = _Harness()..bits = _latchedBits;
      final monitor = AudioLatencyMonitor(
        readStatus: () => AudioLatencyStatus.fromNative(h.bits, 66000),
        clearLatches: () {}, // nothing changes
        enabled: true,
        pollInterval: const Duration(hours: 1),
      );
      monitor.start();
      monitor.recover();
      expect(monitor.recovering, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(monitor.recovering, isFalse);
      expect(monitor.status.isLatched, isTrue);
      monitor.dispose();
    });
  });
}
