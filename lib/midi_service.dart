import 'dart:async';
import 'package:flutter_midi_command/flutter_midi_command.dart';

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
  }

  Stream<List<MidiDevice>>? get devicesStream => _midiCommand.onMidiSetupChanged?.map((_) => []);

  Future<List<MidiDevice>> get devices async {
    final devs = await _midiCommand.devices;
    return devs ?? [];
  }

  Future<void> connect(MidiDevice device) async {
    await _midiCommand.connectToDevice(device);
  }

  void disconnect(MidiDevice device) {
    _midiCommand.disconnectDevice(device);
  }

  void dispose() {
    _rxSubscription?.cancel();
    _setupSubscription?.cancel();
    _midiCommand.teardown();
  }
}
