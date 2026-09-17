/// What the optional direct USB output (Android) is currently doing.
///
/// The direct output exists for one situation: Android plays to a single USB
/// audio device, so plugging a USB microphone next to a USB DAC makes Android
/// drop the DAC. When the user enables the preference, GrooveForge streams to
/// such a DAC itself. These states say whether that is happening and, if not,
/// why — which is the only way the user can tell a missing permission from an
/// unsupported DAC.
enum UsbDirectOutputState {
  /// The preference is off.
  off,

  /// Enabled, but no attached USB device can play audio.
  noDevice,

  /// Enabled, but Android already plays to a USB output — the normal path
  /// reaches the DAC, so nothing needs replacing.
  androidRoutes,

  /// Waiting for the user to answer Android's USB permission dialog.
  permission,

  /// The user declined USB permission. Replugging the DAC asks again.
  denied,

  /// Streaming to the DAC.
  active,

  /// The DAC has no format the direct output can play (it needs USB Audio
  /// Class 1 at the app's sample rate, without a feedback endpoint).
  unsupported,

  /// Opening or streaming failed. Replugging the DAC tries again.
  error,
}

/// A snapshot of the direct USB output, as reported by the Android plugin.
class UsbDirectOutputStatus {
  /// What the direct output is doing.
  final UsbDirectOutputState state;

  /// The DAC this status is about (product name or USB IDs), when there is one.
  final String? deviceLabel;

  /// Stream format while [state] is [UsbDirectOutputState.active]; 0 otherwise.
  final int sampleRate;
  final int channels;
  final int bits;

  const UsbDirectOutputStatus({
    required this.state,
    this.deviceLabel,
    this.sampleRate = 0,
    this.channels = 0,
    this.bits = 0,
  });

  /// Status reported where the direct output does not exist or cannot be read.
  static const unavailable = UsbDirectOutputStatus(
    state: UsbDirectOutputState.off,
  );

  /// Parses the plugin's status map. Unknown or missing values fall back to
  /// [UsbDirectOutputState.off] rather than throwing, so a newer native side
  /// cannot break the preferences screen.
  factory UsbDirectOutputStatus.fromMap(Map<String, dynamic>? map) {
    if (map == null) return unavailable;
    return UsbDirectOutputStatus(
      state: _parseState(map['state']),
      deviceLabel: map['device'] as String?,
      sampleRate: _asInt(map['sampleRate']),
      channels: _asInt(map['channels']),
      bits: _asInt(map['bits']),
    );
  }

  static UsbDirectOutputState _parseState(Object? code) {
    for (final state in UsbDirectOutputState.values) {
      if (state.name == code) return state;
    }
    return UsbDirectOutputState.off;
  }

  static int _asInt(Object? value) => value is int ? value : 0;
}
