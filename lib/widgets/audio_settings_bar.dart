import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/audio_engine.dart';
import 'rotary_knob.dart';


/// A compact horizontal bar displayed just below the [TransportBar] that
/// exposes the most frequently adjusted audio settings without opening the
/// full Preferences screen.
///
/// Contents vary by platform:
/// - **Linux**: FluidSynth output-gain knob, mic-sensitivity knob, mic-device
///   dropdown.
/// - **Android**: mic-sensitivity knob, mic-device dropdown, output-device
///   dropdown.
/// - **Other platforms**: mic-sensitivity knob, mic-device dropdown.
///
/// The bar is shown or hidden by [RackScreen] using an [AnimatedSize] wrapper
/// driven by a [ValueNotifier<bool>] that the [TransportBar] toggle controls.
class AudioSettingsBar extends StatelessWidget {
  const AudioSettingsBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final engine = context.watch<AudioEngine>();

    return Container(
      color: Colors.black38,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // ── FluidSynth gain (all platforms) ──────────────────────────────
          _GainKnob(engine: engine, l10n: l10n),
          const SizedBox(width: 12),
          const _Divider(),
          const SizedBox(width: 12),

          // ── Mic sensitivity knob ─────────────────────────────────────────
          _MicSensitivityKnob(engine: engine, l10n: l10n),
          const SizedBox(width: 12),
          const _Divider(),
          const SizedBox(width: 12),

          // ── Mic device dropdown ──────────────────────────────────────────
          _MicDeviceDropdown(engine: engine, l10n: l10n),

          // ── Output device dropdown (Android only) ────────────────────────
          if (!kIsWeb && Platform.isAndroid) ...[
            const SizedBox(width: 12),
            const _Divider(),
            const SizedBox(width: 12),
            _OutputDeviceDropdown(engine: engine, l10n: l10n),
          ],
        ],
      ),
    );
  }
}

// ─── FluidSynth gain knob ────────────────────────────────────────────────────

/// Rotary knob that controls the FluidSynth master output gain (all platforms).
///
/// Range 0.0–10.0 matching FluidSynth's own gain limits.
class _GainKnob extends StatelessWidget {
  const _GainKnob({required this.engine, required this.l10n});

  final AudioEngine engine;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: engine.fluidSynthGain,
      builder: (context, gain, _) => RotaryKnob(
        value: gain,
        min: 0.0,
        max: 10.0,
        label: l10n.audioSettingsBarGain,
        icon: Icons.volume_up,
        size: 40,
        isCompact: true,
        onChanged: (val) => engine.fluidSynthGain.value = val,
      ),
    );
  }
}

// ─── Mic sensitivity knob ────────────────────────────────────────────────────

/// Rotary knob that controls the microphone capture gain (vocoderInputGain).
///
/// Range 0.0–20.0 matching the Preferences slider.
class _MicSensitivityKnob extends StatelessWidget {
  const _MicSensitivityKnob({required this.engine, required this.l10n});

  final AudioEngine engine;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: engine.vocoderInputGain,
      builder: (context, gain, _) => RotaryKnob(
        value: gain,
        min: 0.0,
        max: 20.0,
        label: l10n.audioSettingsBarMicSensitivity,
        icon: Icons.mic,
        size: 40,
        isCompact: true,
        onChanged: (val) => engine.vocoderInputGain.value = val,
      ),
    );
  }
}

// ─── Mic device dropdown ─────────────────────────────────────────────────────

/// Compact dropdown that selects the active microphone / capture device.
///
/// On Android, devices are identified by their system integer ID; on other
/// platforms by their sequential index in the ALSA/CoreAudio device list.
class _MicDeviceDropdown extends StatelessWidget {
  const _MicDeviceDropdown({required this.engine, required this.l10n});

  final AudioEngine engine;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: (!kIsWeb && Platform.isAndroid)
          ? engine.getAndroidInputDevices()
          : engine.getAvailableMicrophones(),
      builder: (context, snapshot) {
        final devices = snapshot.data ?? <dynamic>[];

        return _CompactDeviceDropdown(
          label: l10n.audioSettingsBarMicDevice,
          icon: Icons.mic_none,
          currentValueListenable: (!kIsWeb && Platform.isAndroid)
              ? engine.vocoderInputAndroidDeviceId
              : engine.vocoderInputDeviceIndex,
          defaultLabel: l10n.micSelectionDefault,
          devices: devices,
          onChanged: (val) {
            if (!kIsWeb && Platform.isAndroid) {
              engine.vocoderInputAndroidDeviceId.value = val;
            } else {
              engine.vocoderInputDeviceIndex.value = val;
            }
          },
        );
      },
    );
  }
}

// ─── Output device dropdown (Android) ────────────────────────────────────────

/// Compact dropdown that selects the audio output device (Android only).
class _OutputDeviceDropdown extends StatelessWidget {
  const _OutputDeviceDropdown({required this.engine, required this.l10n});

  final AudioEngine engine;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: engine.getAndroidOutputDevices(),
      builder: (context, snapshot) {
        final devices = (snapshot.data ?? <Map<String, dynamic>>[])
            .map((d) => d as dynamic)
            .toList();

        return _CompactDeviceDropdown(
          label: l10n.audioSettingsBarOutputDevice,
          icon: Icons.headset,
          currentValueListenable: engine.vocoderOutputAndroidDeviceId,
          defaultLabel: l10n.audioOutputDefault,
          devices: devices,
          onChanged: (val) => engine.vocoderOutputAndroidDeviceId.value = val,
        );
      },
    );
  }
}

// ─── Shared compact device dropdown ──────────────────────────────────────────

/// A small labelled [DropdownButton] used for both input and output device
/// selection in the [AudioSettingsBar].
///
/// [devices] may be either a `List<String>` (index-based, Linux/macOS) or a
/// `List<Map>` with `{id, name}` keys (Android). [currentValueListenable]
/// holds the currently selected ID/index (−1 = system default).
class _CompactDeviceDropdown extends StatelessWidget {
  const _CompactDeviceDropdown({
    required this.label,
    required this.icon,
    required this.currentValueListenable,
    required this.defaultLabel,
    required this.devices,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final ValueNotifier<int> currentValueListenable;
  final String defaultLabel;

  /// Either `List<String>` (index-based) or `List<Map<dynamic, dynamic>>` (Android).
  final List<dynamic> devices;

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: currentValueListenable,
      builder: (context, currentId, _) {
        // Build dropdown items: default (-1) plus one per device.
        final items = <DropdownMenuItem<int>>[
          DropdownMenuItem(value: -1, child: Text(defaultLabel)),
          ...List.generate(devices.length, (i) {
            final device = devices[i];
            final int val =
                device is Map ? (device['id'] as int? ?? i) : i;
            final String name =
                device is Map ? (device['name'] as String? ?? '$i') : device as String;
            return DropdownMenuItem(value: val, child: Text(name));
          }),
        ];

        // Ensure currentId is among the items (guard against disconnected device).
        final hasMatch = items.any((item) => item.value == currentId);
        final effectiveValue = hasMatch ? currentId : -1;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: Colors.white54),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 2),
            DropdownButton<int>(
              value: effectiveValue,
              isDense: true,
              underline: const SizedBox.shrink(),
              style: const TextStyle(fontSize: 12, color: Colors.white),
              dropdownColor: Colors.grey[900],
              items: items,
              onChanged: (val) {
                if (val != null) onChanged(val);
              },
            ),
          ],
        );
      },
    );
  }
}

// ─── Vertical divider helper ──────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 36, color: Colors.white12);
  }
}
