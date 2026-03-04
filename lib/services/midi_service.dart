import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A wrapper service around [FlutterMidiCommand] to manage hardware connections.
///
/// Handles discovering available Bluetooth/USB MIDI devices, establishing connections,
/// routing incoming MIDI data packets, and persisting the last connected device
/// for automatic reconnection on subsequent app launches.
class MidiService {
  final MidiCommand _midiCommand = MidiCommand();
  StreamSubscription<MidiPacket>? _rxSubscription;
  StreamSubscription<String>? _setupSubscription;

  Function(MidiPacket)? onMidiDataReceived;

  final Set<String> _knownDeviceIds = {};
  final StreamController<MidiDevice> _newDeviceController =
      StreamController<MidiDevice>.broadcast();

  Stream<MidiDevice> get onNewDeviceDetected => _newDeviceController.stream;

  Timer? _pollingTimer;

  MidiService() {
    debugPrint('MidiService: Initializing...');

    final setupStream = _midiCommand.onMidiSetupChanged;
    if (setupStream != null) {
      debugPrint('MidiService: Subscribing to onMidiSetupChanged');
      _setupSubscription = setupStream.listen((event) {
        debugPrint('MidiService: onMidiSetupChanged event: $event');
        _handleSetupChanged();
      });
    } else {
      debugPrint('MidiService: onMidiSetupChanged is null!');
    }

    _midiCommand.onMidiDataReceived?.listen((packet) {
      if (onMidiDataReceived != null) {
        onMidiDataReceived!(packet);
      }
    });

    // Linux and Windows flutter_midi_command implementations often don't emit native setup events.
    // Poll every 2 seconds to detect hotplugged or unplugged devices.
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows)) {
      debugPrint(
        'MidiService: Starting polling timer for ${Platform.operatingSystem}',
      );
      _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _handleSetupChanged();
      });
    }

    _tryAutoConnect();
  }

  Future<void> _handleSetupChanged() async {
    // Only log every few polls if nothing changed to avoid spamming?
    // No, user says they see NO logs, so let's log everything for now.
    debugPrint('MidiService: Checking for device changes...');
    final devs = await _midiCommand.devices;
    if (devs == null) {
      debugPrint('MidiService: Devices list is NULL');
      return;
    }

    final currentDeviceIds = devs.map((e) => e.id).toSet();
    debugPrint('MidiService: Current devices: $currentDeviceIds');

    // Remove disconnected devices from known list so they can be discovered again if replugged
    _knownDeviceIds.removeWhere((id) {
      bool removed = !currentDeviceIds.contains(id);
      if (removed) debugPrint('MidiService: Removed $id from known devices');
      return removed;
    });

    final prefs = await SharedPreferences.getInstance();
    final lastDeviceId = prefs.getString('last_midi_device_id');

    for (var device in devs) {
      if (!_knownDeviceIds.contains(device.id)) {
        debugPrint(
          'MidiService: New device found: ${device.id} (${device.name})',
        );
        _knownDeviceIds.add(device.id);

        if (device.id == lastDeviceId) {
          try {
            await connect(device);
            debugPrint('Auto-reconnected to MIDI device: ${device.name}');
          } catch (e) {
            debugPrint('Failed to auto-reconnect to MIDI device: $e');
            prefs.remove('last_midi_device_id');
          }
        } else if (!device.connected) {
          debugPrint('MidiService: Prompting for new device: ${device.name}');
          // It's a brand new device, neither known nor recently auto-connected
          _newDeviceController.add(device);
        } else {
          debugPrint(
            'MidiService: Device ${device.name} is already connected, ignoring prompt.',
          );
        }
      }
    }
  }

  /// Attempts to automatically reconnect to the last used MIDI device.
  ///
  /// Reads the device ID from [SharedPreferences] and attempts connection
  /// if the device is currently visible/available.
  Future<void> _tryAutoConnect() async {
    debugPrint('MidiService: _tryAutoConnect called');
    final prefs = await SharedPreferences.getInstance();
    final lastDeviceId = prefs.getString('last_midi_device_id');

    final devs = await _midiCommand.devices;
    if (devs == null) {
      debugPrint('MidiService: _tryAutoConnect found no devices early.');
      return;
    }

    // Track initially discovered devices so they aren't treated as "newly plugged in"
    for (var d in devs) {
      _knownDeviceIds.add(d.id);
    }
    debugPrint('MidiService: initial known devices: $_knownDeviceIds');

    if (lastDeviceId == null) return;

    for (var device in devs) {
      if (device.id == lastDeviceId) {
        try {
          await connect(device);
          debugPrint('Auto-connected to MIDI device: ${device.name}');
        } catch (e) {
          debugPrint('Failed to auto-connect to MIDI device: $e');
          prefs.remove('last_midi_device_id'); // Clear if connection fails
        }
        break;
      }
    }
  }

  Stream<List<MidiDevice>>? get devicesStream =>
      _midiCommand.onMidiSetupChanged?.map((_) => []);

  Future<List<MidiDevice>> get devices async {
    final devs = await _midiCommand.devices;
    return devs ?? [];
  }

  Future<void> connect(MidiDevice device) async {
    await _midiCommand.connectToDevice(device);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_midi_device_id', device.id);
  }

  void disconnect(MidiDevice device) async {
    _midiCommand.disconnectDevice(device);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_midi_device_id');
  }

  void dispose() {
    _pollingTimer?.cancel();
    _rxSubscription?.cancel();
    _setupSubscription?.cancel();
    _newDeviceController.close();
    _midiCommand.teardown();
  }
}
