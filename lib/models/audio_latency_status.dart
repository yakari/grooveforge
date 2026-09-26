/// Which output path the Android audio bus is on, and whether it is stuck there.
///
/// Android can put GrooveForge on a slow output path two different ways, and
/// the difference decides what the user should do about it:
///
///  * **Refused at open time.** AAudio would not grant the fast path for this
///    stream — another app holds the exclusive endpoint, the route is odd, the
///    device simply cannot. The next route change may well grant it. Nothing
///    to do but know about it.
///  * **Latched for the session.** An earlier failure made the engine give up
///    on the fast path, and every stream opened since is deliberately slow.
///    This one never recovers on its own: it stands until the latches are
///    cleared or the app is restarted.
///
/// The second case is the one that ruins a rehearsal — a quarter of a second
/// of delay that survives leaving and reopening the screen, with nothing on
/// screen to explain it. [isLatched] is what the UI offers a way out of.
///
/// Mirrors the `OBOE_LATENCY_*` bit flags in `oboe_stream_android.h`.
class AudioLatencyStatus {
  /// A stream is open on the AAudio bus.
  final bool streamOpen;

  /// AAudio granted `PERFORMANCE_MODE_LOW_LATENCY` on the open stream.
  ///
  /// Without it the stream sits on the normal mixer path and feels laggy
  /// however small the buffer is.
  final bool lowLatencyGranted;

  /// AAudio granted an exclusive (MMAP) endpoint on the open stream.
  ///
  /// Without it the AudioFlinger mixer and its HAL buffers are added on top of
  /// the app's own buffer — costly, but far less so than losing
  /// [lowLatencyGranted].
  final bool exclusiveGranted;

  /// The session has given up on the low-latency path entirely.
  ///
  /// The expensive latch: every stream opened from here on uses
  /// `PERFORMANCE_MODE_NONE`, the legacy AudioTrack path, worth hundreds of
  /// milliseconds. Set after the engine saw the platform's audio server abort
  /// on an MMAP stream, which is severe enough to be worth avoiding — but a
  /// false positive costs a playable instrument.
  final bool lowLatencyLatched;

  /// The session has given up on asking for an exclusive (MMAP) endpoint.
  final bool exclusiveLatched;

  /// The direct USB output is clocking the bus, so AAudio's modes say nothing
  /// about what the user actually hears.
  final bool externalClock;

  /// Buffer latency in milliseconds, or `null` when no stream is open.
  ///
  /// Only the part the app controls. The HAL adds its own on top, and on the
  /// legacy path so does the AudioFlinger mixer — which is exactly why a small
  /// number here is not proof that all is well when [lowLatencyGranted] is
  /// false.
  final double? bufferMs;

  const AudioLatencyStatus({
    required this.streamOpen,
    required this.lowLatencyGranted,
    required this.exclusiveGranted,
    required this.lowLatencyLatched,
    required this.exclusiveLatched,
    required this.externalClock,
    this.bufferMs,
  });

  /// Status reported where there is no AAudio bus to ask (web, desktop, iOS).
  static const unavailable = AudioLatencyStatus(
    streamOpen: false,
    lowLatencyGranted: false,
    exclusiveGranted: false,
    lowLatencyLatched: false,
    exclusiveLatched: false,
    externalClock: false,
  );

  // Bit positions, kept in step with OBOE_LATENCY_* in oboe_stream_android.h.
  static const int _bitStreamOpen = 1 << 0;
  static const int _bitLowLatencyGranted = 1 << 1;
  static const int _bitExclusiveGranted = 1 << 2;
  static const int _bitLowLatencyLatched = 1 << 3;
  static const int _bitExclusiveLatched = 1 << 4;
  static const int _bitExternalClock = 1 << 5;

  /// Parses the native bitmask, with [bufferLatencyUs] as reported alongside
  /// it (negative means no stream).
  factory AudioLatencyStatus.fromNative(int bits, int bufferLatencyUs) {
    return AudioLatencyStatus(
      streamOpen: bits & _bitStreamOpen != 0,
      lowLatencyGranted: bits & _bitLowLatencyGranted != 0,
      exclusiveGranted: bits & _bitExclusiveGranted != 0,
      lowLatencyLatched: bits & _bitLowLatencyLatched != 0,
      exclusiveLatched: bits & _bitExclusiveLatched != 0,
      externalClock: bits & _bitExternalClock != 0,
      bufferMs: bufferLatencyUs >= 0 ? bufferLatencyUs / 1000.0 : null,
    );
  }

  /// Whether a latch is holding this session on a slow path.
  ///
  /// Only [lowLatencyLatched] counts. [exclusiveLatched] on its own still
  /// leaves the stream on the low-latency path — a few milliseconds dearer,
  /// not the failure worth interrupting the user about — and it clears itself
  /// on the next output device change, which [lowLatencyLatched] does not.
  bool get isLatched => lowLatencyLatched;

  /// Whether the user is hearing more delay than this device can manage.
  ///
  /// False while [externalClock] is set: the direct USB output bypasses
  /// Android's stack, so AAudio's modes describe a stream nobody is listening
  /// to. Also false with no stream open, where there is nothing to report yet
  /// rather than something wrong.
  bool get isDegraded {
    if (externalClock || !streamOpen) return false;
    return !lowLatencyGranted;
  }

  /// Whether clearing the latches could plausibly help.
  ///
  /// The escape hatch is offered only for the latch, not for a refusal the
  /// engine had no part in: reopening a stream that AAudio simply would not
  /// grant the fast path to just reopens it the same way.
  bool get canRecover => isLatched;
}
