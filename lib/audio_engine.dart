import 'dart:io';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'cc_mapping_service.dart';

class AudioEngine {
  final MidiPro _midiPro = MidiPro();
  bool _isInitialized = false;
  int? _sfId;

  // CC Mapping
  CcMappingService? ccMappingService;

  // Linux specific
  Process? _fluidSynthProcess;

  Future<void> init(File soundfont) async {
    if (Platform.isLinux) {
      // Fallback for Linux desktop testing using local fluidsynth CLI
      _fluidSynthProcess?.kill();
      
      // Start fluidsynth with ALSA audio driver, no shell interface, and load the soundfont
      _fluidSynthProcess = await Process.start(
        '/usr/bin/fluidsynth',
        ['-a', 'alsa', '-m', 'alsa_seq', '-n', soundfont.path],
      );

      _isInitialized = true;
    } else {
      // Native high-performance audio for Android/iOS/macOS
      _sfId = await _midiPro.loadSoundfontFile(filePath: soundfont.path);
      _isInitialized = true;
    }
  }

  void processMidiPacket(MidiPacket packet) {
    if (!_isInitialized || packet.data.isEmpty) return;

    final statusByte = packet.data[0];
    final command = statusByte & 0xF0;
    final channel = statusByte & 0x0F;

    if (packet.data.length >= 3) {
      int data1 = packet.data[1];
      final int data2 = packet.data[2];

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
          if (ccMappingService != null) {
            ccMappingService!.updateLastReceived(data1, data2);
            data1 = ccMappingService!.getTargetCc(data1);
          }
          _sendControlChange(channel: channel, controller: data1, value: data2);
          break;
        case 0xE0: // Pitch Bend
          int pitchValue = (data2 << 7) | data1; // 14-bit
          _sendPitchBend(channel: channel, value: pitchValue);
          break;
      }
    }
  }

  void playNote({required int channel, required int key, required int velocity}) {
    if (Platform.isLinux && _fluidSynthProcess != null) {
      _fluidSynthProcess!.stdin.writeln('noteon $channel $key $velocity');
    } else if (_sfId != null) {
      _midiPro.playNote(sfId: _sfId!, channel: channel, key: key, velocity: velocity);
    }
  }

  void stopNote({required int channel, required int key}) {
    if (Platform.isLinux && _fluidSynthProcess != null) {
      _fluidSynthProcess!.stdin.writeln('noteoff $channel $key');
    } else if (_sfId != null) {
      _midiPro.stopNote(sfId: _sfId!, channel: channel, key: key);
    }
  }

  void _sendControlChange({required int channel, required int controller, required int value}) {
    if (Platform.isLinux && _fluidSynthProcess != null) {
      _fluidSynthProcess!.stdin.writeln('cc $channel $controller $value');
    } else {
      // For MidiPro, we might need a specific method if supported, 
      // but keeping it structural for now.
    }
  }

  void _sendPitchBend({required int channel, required int value}) {
    if (Platform.isLinux && _fluidSynthProcess != null) {
      _fluidSynthProcess!.stdin.writeln('pitch_bend $channel $value');
    } else {
      // Implement PitchBend for MidiPro when needed
    }
  }

  void dispose() {
    if (Platform.isLinux) {
      _fluidSynthProcess?.kill();
    }
  }
}
