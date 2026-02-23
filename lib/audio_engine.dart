import 'dart:io';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';

class AudioEngine {
  final MidiPro _midiPro = MidiPro();
  bool _isInitialized = false;
  int? _sfId;

  Future<void> init(File soundfont) async {
    _sfId = await _midiPro.loadSoundfontFile(filePath: soundfont.path);
    _isInitialized = true;
  }

  void processMidiPacket(MidiPacket packet) {
    if (!_isInitialized || packet.data.isEmpty) return;

    final statusByte = packet.data[0];
    final command = statusByte & 0xF0;
    final channel = statusByte & 0x0F;

    if (packet.data.length >= 3) {
      final data1 = packet.data[1];
      final data2 = packet.data[2];

      switch (command) {
        case 0x90: // Note On
          if (data2 > 0) {
            playNote(channel: channel, key: data1, velocity: data2);
          } else {
            // Velocity 0 is often interpreted as Note Off
            stopNote(channel: channel, key: data1);
          }
          break;
        case 0x80: // Note Off
          stopNote(channel: channel, key: data1);
          break;
        case 0xB0: // Control Change (CC)
          // Handle Mod wheel, volume, ribbons on Vortex
          // Example mapping can be done here. 
          break;
        case 0xE0: // Pitch Bend
          // Combine data1 and data2 for 14-bit pitch bend value
          break;
      }
    }
  }

  void playNote({required int channel, required int key, required int velocity}) {
    if (_sfId != null) {
      _midiPro.playNote(sfId: _sfId!, channel: channel, key: key, velocity: velocity);
    }
  }

  void stopNote({required int channel, required int key}) {
    if (_sfId != null) {
      _midiPro.stopNote(sfId: _sfId!, channel: channel, key: key);
    }
  }
}
