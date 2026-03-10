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

  /// Guards against concurrent [connect] calls (e.g. polling timer firing
  /// while [_tryAutoConnect] is already awaiting [connectToDevice]).
  bool _isConnecting = false;

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

    // Linux, Windows, and macOS (at launch) implementations often don't emit native setup events reliably.
    // Poll every 2 seconds to detect hotplugged or unplugged devices.
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
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
    final lastDeviceName = prefs.getString('last_midi_device_name');
    
    if (lastDeviceId != null || lastDeviceName != null) {
      debugPrint('MidiService: Last saved device ID: $lastDeviceId, Name: $lastDeviceName');
    }

    for (var device in devs) {
      // macOS assigns new random IDs to USB MIDI devices across reconnections.
      // Match by ID first, and fallback to matching the exact name if we have one.
      final isLastDevice = device.id == lastDeviceId || 
                           (lastDeviceName != null && device.name == lastDeviceName);
      
      // If it's a new device, OR if it's our last device and it's NOT connected yet, process it.
      if (!_knownDeviceIds.contains(device.id) || (isLastDevice && !device.connected)) {
        if (!_knownDeviceIds.contains(device.id)) {
          debugPrint('MidiService: New device found: ${device.id} (${device.name})');
          _knownDeviceIds.add(device.id);
        }

        if (isLastDevice) {
          if (_isConnecting) {
            debugPrint('MidiService: Already connecting — skipping reconnect for ${device.name}');
          } else {
            try {
              debugPrint('MidiService: Attempting auto-reconnect to ${device.name}...');
              _isConnecting = true;
              await connect(device);
              debugPrint('MidiService: Auto-reconnected to ${device.name}');
            } catch (e) {
              debugPrint('MidiService: Failed to auto-reconnect to ${device.name}: $e');
            } finally {
              _isConnecting = false;
            }
          }
        } else if (!device.connected) {
          debugPrint('MidiService: Prompting for new device: ${device.name}');
          _newDeviceController.add(device);
        }
      }
    }
  }

  /// Attempts to automatically reconnect to the last used MIDI device.
  Future<void> _tryAutoConnect() async {
    debugPrint('MidiService: INITIAL _tryAutoConnect');
    final prefs = await SharedPreferences.getInstance();
    final lastDeviceId = prefs.getString('last_midi_device_id');
    final lastDeviceName = prefs.getString('last_midi_device_name');
    
    if (lastDeviceId == null && lastDeviceName == null) {
      debugPrint('MidiService: No last device saved.');
      return;
    }
    debugPrint('MidiService: Want to reconnect to ID: $lastDeviceId or Name: $lastDeviceName');

    final devs = await _midiCommand.devices;
    if (devs == null || devs.isEmpty) {
      debugPrint('MidiService: No devices found yet during INITIAL scan.');
      return;
    }

    debugPrint('MidiService: Initial scan found: ${devs.map((e) => e.id)}');

    for (var device in devs) {
      _knownDeviceIds.add(device.id);
      
      final isLastDevice = device.id == lastDeviceId || 
                           (lastDeviceName != null && device.name == lastDeviceName);
                           
      if (isLastDevice) {
        if (!_isConnecting) {
          try {
            _isConnecting = true;
            await connect(device);
            debugPrint('MidiService: Initial auto-connect success: ${device.name}');
          } catch (e) {
            debugPrint('MidiService: Initial auto-connect failed: $e. Will retry in polling.');
          } finally {
            _isConnecting = false;
          }
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
    await prefs.setString('last_midi_device_name', device.name);
  }

  void disconnect(MidiDevice device) async {
    _midiCommand.disconnectDevice(device);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_midi_device_id');
    await prefs.remove('last_midi_device_name');
  }

  void dispose() {
    _pollingTimer?.cancel();
    _rxSubscription?.cancel();
    _setupSubscription?.cancel();
    _newDeviceController.close();
    _midiCommand.teardown();
  }
}
