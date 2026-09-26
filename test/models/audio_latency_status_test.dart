import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/audio_latency_status.dart';

// The OBOE_LATENCY_* bits, spelled out here rather than imported so that a
// change to the native header has to be made deliberately on both sides.
const _streamOpen = 1 << 0;
const _lowLatencyGranted = 1 << 1;
const _exclusiveGranted = 1 << 2;
const _lowLatencyLatched = 1 << 3;
const _exclusiveLatched = 1 << 4;
const _externalClock = 1 << 5;

/// The bits of a stream that got everything it asked for.
const _healthy = _streamOpen | _lowLatencyGranted | _exclusiveGranted;

void main() {
  group('fromNative', () {
    test('reads every bit independently', () {
      final status = AudioLatencyStatus.fromNative(
        _streamOpen | _lowLatencyLatched | _exclusiveLatched,
        4000,
      );
      expect(status.streamOpen, isTrue);
      expect(status.lowLatencyGranted, isFalse);
      expect(status.exclusiveGranted, isFalse);
      expect(status.lowLatencyLatched, isTrue);
      expect(status.exclusiveLatched, isTrue);
      expect(status.externalClock, isFalse);
    });

    test('converts the buffer latency from microseconds', () {
      expect(
        AudioLatencyStatus.fromNative(_healthy, 4000).bufferMs,
        closeTo(4.0, 0.001),
      );
    });

    test('a negative buffer latency means no stream, not zero', () {
      // Zero would render as "0.0 ms", which reads as an impossibly good
      // result rather than as an absence of measurement.
      expect(AudioLatencyStatus.fromNative(0, -1).bufferMs, isNull);
    });
  });

  group('isDegraded', () {
    test('false when the fast path was granted', () {
      expect(AudioLatencyStatus.fromNative(_healthy, 4000).isDegraded, isFalse);
    });

    test('true when low latency was refused', () {
      final status = AudioLatencyStatus.fromNative(_streamOpen, 66000);
      expect(status.isDegraded, isTrue);
    });

    test('losing only the exclusive endpoint is not degraded', () {
      // Shared low-latency costs a few milliseconds, not the hundreds that
      // warrant interrupting a player. Flagging it would train the user to
      // ignore the indicator.
      final status = AudioLatencyStatus.fromNative(
        _streamOpen | _lowLatencyGranted,
        4000,
      );
      expect(status.isDegraded, isFalse);
    });

    test('false while the direct USB output is the clock', () {
      // AAudio's modes describe a stream nobody is listening to: the USB
      // streamer bypasses Android's stack entirely.
      final status = AudioLatencyStatus.fromNative(
        _externalClock | _lowLatencyLatched,
        -1,
      );
      expect(status.isDegraded, isFalse);
    });

    test('false before any stream has been opened', () {
      expect(AudioLatencyStatus.fromNative(0, -1).isDegraded, isFalse);
    });
  });

  group('isLatched', () {
    test('only the low-latency latch counts', () {
      // The exclusive latch clears itself on the next output device change,
      // and leaves the stream on the low-latency path meanwhile. It is not
      // the failure the escape hatch exists for.
      final exclusiveOnly = AudioLatencyStatus.fromNative(
        _streamOpen | _lowLatencyGranted | _exclusiveLatched,
        4000,
      );
      expect(exclusiveOnly.isLatched, isFalse);
      expect(exclusiveOnly.canRecover, isFalse);

      final lowLatency = AudioLatencyStatus.fromNative(
        _streamOpen | _lowLatencyLatched,
        66000,
      );
      expect(lowLatency.isLatched, isTrue);
      expect(lowLatency.canRecover, isTrue);
    });
  });

  test('unavailable reports nothing wrong and nothing to recover', () {
    const status = AudioLatencyStatus.unavailable;
    expect(status.isDegraded, isFalse);
    expect(status.isLatched, isFalse);
    expect(status.canRecover, isFalse);
    expect(status.bufferMs, isNull);
  });
}
