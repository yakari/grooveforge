import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/audio_engine.dart';

/// Debug screen for investigating USB audio device enumeration on Android.
///
/// Displays every [AudioDeviceInfo] returned by `AudioManager.getDevices()`
/// with full detail: device ID, product name, type, direction (source/sink),
/// supported sample rates, channel counts, and encodings.
///
/// This screen is part of the Multi-USB Audio investigation (roadmap Step 1).
/// It helps verify which USB devices the system enumerates when a USB hub with
/// multiple audio interfaces is connected, and whether their IDs can be passed
/// to AAudio's `setDeviceId()` for independent input/output routing.
class UsbAudioDebugScreen extends StatefulWidget {
  const UsbAudioDebugScreen({super.key});

  @override
  State<UsbAudioDebugScreen> createState() => _UsbAudioDebugScreenState();
}

class _UsbAudioDebugScreenState extends State<UsbAudioDebugScreen> {
  List<Map<String, dynamic>> _devices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchDevices();
  }

  Future<void> _fetchDevices() async {
    setState(() => _loading = true);
    final engine = context.read<AudioEngine>();
    final devices = await engine.getAndroidAudioDeviceDetails();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isAndroid = !kIsWeb && Platform.isAndroid;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.usbAudioDebugTitle),
        actions: [
          if (isAndroid)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.usbAudioDebugRefresh,
              onPressed: _fetchDevices,
            ),
        ],
      ),
      body: _buildBody(l10n, isAndroid),
    );
  }

  Widget _buildBody(AppLocalizations l10n, bool isAndroid) {
    if (!isAndroid) {
      return Center(child: Text(l10n.usbAudioDebugPlatformOnly));
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_devices.isEmpty) {
      return Center(child: Text(l10n.usbAudioDebugNoDevices));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _devices.length,
      itemBuilder: (context, index) => _DeviceCard(
        device: _devices[index],
        l10n: l10n,
      ),
    );
  }
}

/// Displays a single audio device's full [AudioDeviceInfo] data.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.l10n});

  final Map<String, dynamic> device;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = device['id'] as int? ?? -1;
    final name = device['productName'] as String? ?? '?';
    final typeString = device['typeString'] as String? ?? '?';
    final isSource = device['isSource'] as bool? ?? false;
    final isSink = device['isSink'] as bool? ?? false;
    final sampleRates = _intList(device['sampleRates']);
    final channelCounts = _intList(device['channelCounts']);
    final encodings = _intList(device['encodings']);
    final address = device['address'] as String?;

    // Direction label.
    final direction = (isSource && isSink)
        ? l10n.usbAudioDebugInputOutput
        : isSource
            ? l10n.usbAudioDebugInput
            : l10n.usbAudioDebugOutput;

    // Direction icon and colour.
    final directionIcon = isSource && isSink
        ? Icons.swap_horiz
        : isSource
            ? Icons.mic
            : Icons.volume_up;
    final isUsb = typeString.contains('USB');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isUsb ? theme.colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: product name + type chip.
            Row(
              children: [
                Icon(directionIcon, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Chip(
                  label: Text(typeString,
                      style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Detail rows.
            _row(l10n.usbAudioDebugDeviceId, '$id'),
            _row(l10n.usbAudioDebugDirection, direction),
            _row(
              l10n.usbAudioDebugSampleRates,
              sampleRates.isEmpty
                  ? l10n.usbAudioDebugAny
                  : sampleRates.map((r) => '${r ~/ 1000}k').join(', '),
            ),
            _row(
              l10n.usbAudioDebugChannelCounts,
              channelCounts.isEmpty
                  ? l10n.usbAudioDebugAny
                  : channelCounts.join(', '),
            ),
            _row(
              l10n.usbAudioDebugEncodings,
              encodings.isEmpty
                  ? l10n.usbAudioDebugAny
                  : encodings.map(_encodingLabel).join(', '),
            ),
            if (address != null && address.isNotEmpty)
              _row(l10n.usbAudioDebugAddress, address),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// Converts a dynamic list (from the platform channel) to `List<int>`.
  List<int> _intList(dynamic value) {
    if (value is List) return value.whereType<int>().toList();
    return [];
  }

  /// Human-readable label for Android AudioFormat encoding constants.
  ///
  /// Values from [AudioFormat](https://developer.android.com/reference/android/media/AudioFormat).
  String _encodingLabel(int encoding) {
    return switch (encoding) {
      1 => 'DEFAULT',
      2 => 'PCM_16BIT',
      3 => 'PCM_8BIT',
      4 => 'PCM_FLOAT',
      5 => 'AC3',
      6 => 'E_AC3',
      7 => 'DTS',
      8 => 'DTS_HD',
      21 => 'PCM_24BIT',
      22 => 'PCM_32BIT',
      _ => 'ENC_$encoding',
    };
  }
}
