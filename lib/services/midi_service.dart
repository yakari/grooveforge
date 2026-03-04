import 'dart:async';
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

  MidiService() {
    _midiCommand.onMidiDataReceived?.listen((packet) {
      if (onMidiDataReceived != null) {
        onMidiDataReceived!(packet);
      }
    });
    _tryAutoConnect();
  }

  /// Attempts to automatically reconnect to the last used MIDI device.
  ///
  /// Reads the device ID from [SharedPreferences] and attempts connection
  /// if the device is currently visible/available.
  Future<void> _tryAutoConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final lastDeviceId = prefs.getString('last_midi_device_id');
    if (lastDeviceId == null) return;

    final devs = await _midiCommand.devices;
    if (devs == null) return;

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
    _rxSubscription?.cancel();
    _setupSubscription?.cancel();
    _midiCommand.teardown();
  }
}
