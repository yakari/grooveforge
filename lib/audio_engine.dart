import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cc_mapping_service.dart';

class ChannelState {
  String? soundfontPath;
  int program = 0;
  int bank = 0;

  ChannelState();

  Map<String, dynamic> toJson() => {
    'soundfontPath': soundfontPath,
    'program': program,
    'bank': bank,
  };

  factory ChannelState.fromJson(Map<String, dynamic> json) => ChannelState()
    ..soundfontPath = json['soundfontPath']
    ..program = json['program'] ?? 0
    ..bank = json['bank'] ?? 0;
}

class AudioEngine {
  final MidiPro _midiPro = MidiPro();
  bool _isInitialized = false;

  final List<String> loadedSoundfonts = [];
  final Map<String, int> _sfPathToIdMobile = {};
  final Map<String, int> _sfPathToIdLinux = {};
  int _linuxSfIdCounter = 1;

  final List<ChannelState> channels = List.generate(16, (i) => ChannelState());

  Process? _fluidSynthProcess;
  CcMappingService? ccMappingService;

  final ValueNotifier<String?> toastNotifier = ValueNotifier(null);
  final ValueNotifier<int> stateNotifier = ValueNotifier(0);

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    if (Platform.isLinux) {
      _fluidSynthProcess?.kill();
      _fluidSynthProcess = await Process.start(
        '/usr/bin/fluidsynth',
        ['-a', 'alsa', '-m', 'alsa_seq'],
      );
    }

    await _restoreState();
    _isInitialized = true;
  }

  Future<void> _saveState() async {
    if (_prefs == null) return;
    await _prefs!.setStringList('loaded_soundfonts', loadedSoundfonts);
    
    List<String> channelsJson = channels.map((c) => jsonEncode(c.toJson())).toList();
    await _prefs!.setStringList('channels_state', channelsJson);
  }

  Future<void> _restoreState() async {
    if (_prefs == null) return;
    
    // Restore soundfonts
    List<String>? savedSfs = _prefs!.getStringList('loaded_soundfonts');
    if (savedSfs != null) {
      for (String path in savedSfs) {
        if (File(path).existsSync()) {
           await loadSoundfont(File(path), save: false);
        }
      }
    }

    // Restore channels
    List<String>? savedChannels = _prefs!.getStringList('channels_state');
    if (savedChannels != null && savedChannels.length == 16) {
      
      // Delay before applying patches so Fluidsynth has time to load large SF2s into RAM
      if (Platform.isLinux && savedSfs != null && savedSfs.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 1500)); 
      }
      
      for (int i = 0; i < 16; i++) {
        var state = ChannelState.fromJson(jsonDecode(savedChannels[i]));
        channels[i] = state;
        
        if (state.soundfontPath != null && loadedSoundfonts.contains(state.soundfontPath)) {
          _applyChannelInstrument(i);
        }
      }
    }
    stateNotifier.value++;
  }

  Future<void> loadSoundfont(File soundfont, {bool save = true}) async {
    String path = soundfont.path;
    if (loadedSoundfonts.contains(path)) return;

    if (Platform.isLinux) {
      _fluidSynthProcess?.stdin.writeln('load "$path"');
      _sfPathToIdLinux[path] = _linuxSfIdCounter++;
    } else {
      int sfId = await _midiPro.loadSoundfontFile(filePath: path);
      _sfPathToIdMobile[path] = sfId;
    }

    loadedSoundfonts.add(path);
    if (save) await _saveState();
    
    toastNotifier.value = 'Loaded: ${soundfont.uri.pathSegments.last}';
    stateNotifier.value++;
  }

  Future<void> unloadSoundfont(String path) async {
    if (!loadedSoundfonts.contains(path)) return;
    
    if (Platform.isLinux) {
       int? id = _sfPathToIdLinux[path];
       if (id != null) {
         _fluidSynthProcess?.stdin.writeln('unload $id');
       }
       _sfPathToIdLinux.remove(path);
    } else {
      // flutter_midi_pro 3.1.6 does not natively expose unloadSoundfont yet,
      // But we can just clear it from our mapped states.
      _sfPathToIdMobile.remove(path);
    }

    loadedSoundfonts.remove(path);
    
    // Clear any channels using it
    for (int i = 0; i < 16; i++) {
      if (channels[i].soundfontPath == path) {
        channels[i].soundfontPath = null;
      }
    }

    await _saveState();
    toastNotifier.value = 'Unloaded Soundfont';
    stateNotifier.value++;
  }

  void assignSoundfontToChannel(int channel, String path) {
    if (channel < 0 || channel > 15 || !loadedSoundfonts.contains(path)) return;
    channels[channel].soundfontPath = path;
    _applyChannelInstrument(channel);
    _saveState();
    stateNotifier.value++;
  }

  void assignPatchToChannel(int channel, int program, {int? bank}) {
    if (channel < 0 || channel > 15) return;
    channels[channel].program = program;
    if (bank != null) channels[channel].bank = bank;
    _applyChannelInstrument(channel);
    _saveState();
    stateNotifier.value++;
  }

  void _applyChannelInstrument(int channel) {
    ChannelState state = channels[channel];
    if (state.soundfontPath == null) return;
    
    if (Platform.isLinux) {
      int? sfId = _sfPathToIdLinux[state.soundfontPath!];
      if (sfId != null) {
        _fluidSynthProcess?.stdin.writeln('select $channel $sfId ${state.bank} ${state.program}');
      }
    } else {
      int? sfId = _sfPathToIdMobile[state.soundfontPath!];
      if (sfId != null) {
        _midiPro.selectInstrument(sfId: sfId, channel: channel, bank: state.bank, program: state.program);
      }
    }
  }

  int _getSfIdForChannel(int channel) {
    String? path = channels[channel].soundfontPath;
    if (path == null) return -1;
    return Platform.isLinux ? (_sfPathToIdLinux[path] ?? -1) : (_sfPathToIdMobile[path] ?? -1);
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
          if (ccMappingService != null) ccMappingService!.updateLastEvent('Note On', channel, data1, data2);
          if (data2 > 0) {
            playNote(channel: channel, key: data1, velocity: data2);
          } else {
            stopNote(channel: channel, key: data1);
          }
          break;
        case 0x80: // Note Off
          if (ccMappingService != null) ccMappingService!.updateLastEvent('Note Off', channel, data1, data2);
          stopNote(channel: channel, key: data1);
          break;
        case 0xB0: // Control Change (CC)
          if (ccMappingService != null) {
            ccMappingService!.updateLastEvent('CC', channel, data1, data2);
            final mapping = ccMappingService!.getMapping(data1);
            if (mapping != null) {
              if (mapping.targetCc >= 1000) {
                 if (mapping.targetChannel == -1) {
                   for (int i = 0; i < 16; i++) {
                      _handleSystemCommand(mapping.targetCc, i, data2);
                   }
                 } else if (mapping.targetChannel >= 0 && mapping.targetChannel <= 15) {
                   _handleSystemCommand(mapping.targetCc, mapping.targetChannel, data2);
                 } else {
                   _handleSystemCommand(mapping.targetCc, channel, data2);
                 }
                 return;
              } else if (mapping.targetChannel == -1) {
                for (int i = 0; i < 16; i++) {
                  _sendControlChange(channel: i, controller: mapping.targetCc, value: data2);
                }
              } else if (mapping.targetChannel == -2) {
                _sendControlChange(channel: channel, controller: mapping.targetCc, value: data2);
              } else {
                _sendControlChange(channel: mapping.targetChannel, controller: mapping.targetCc, value: data2);
              }
            } else {
               _sendControlChange(channel: channel, controller: data1, value: data2);
            }
          } else {
            _sendControlChange(channel: channel, controller: data1, value: data2);
          }
          break;
        case 0xE0: // Pitch Bend
          int pitchValue = (data2 << 7) | data1;
          _sendPitchBend(channel: channel, value: pitchValue);
          break;
      }
    }
  }

  void playNote({required int channel, required int key, required int velocity}) {
    if (Platform.isLinux && _fluidSynthProcess != null) {
      _fluidSynthProcess!.stdin.writeln('noteon $channel $key $velocity');
    } else {
      int sfId = _getSfIdForChannel(channel);
      if (sfId != -1) {
         _midiPro.playNote(sfId: sfId, channel: channel, key: key, velocity: velocity);
      }
    }
  }

  void stopNote({required int channel, required int key}) {
    if (Platform.isLinux && _fluidSynthProcess != null) {
       _fluidSynthProcess!.stdin.writeln('noteoff $channel $key');
    } else {
      int sfId = _getSfIdForChannel(channel);
      if (sfId != -1) {
         _midiPro.stopNote(sfId: sfId, channel: channel, key: key);
      }
    }
  }

  void _handleSystemCommand(int targetAction, int incomingChannel, int value) {
    bool isTrigger = value > 64;
    
    if (targetAction == 1001 && isTrigger) { // Next Soundfont
       _cycleChannelSoundfont(incomingChannel, 1);
    } else if (targetAction == 1002 && isTrigger) { // Prev Soundfont
       _cycleChannelSoundfont(incomingChannel, -1);
    } else if (targetAction == 1003 && isTrigger) { // Next Patch
       _changePatchIndex(incomingChannel, 1);
    } else if (targetAction == 1004 && isTrigger) { // Prev Patch
       _changePatchIndex(incomingChannel, -1);
    } else if (targetAction == 1005) { // Absolute Patch Index Sweep
       assignPatchToChannel(incomingChannel, value);
       toastNotifier.value = 'Patch Sweep [Ch $incomingChannel]: Program $value';
    } else if (targetAction == 1006) { // Absolute Bank Index Sweep
       int program = channels[incomingChannel].program;
       assignPatchToChannel(incomingChannel, program, bank: value);
       toastNotifier.value = 'Bank/Tone Sweep [Ch $incomingChannel]: Bank $value';
    }
  }

  void _cycleChannelSoundfont(int channel, int delta) {
    if (loadedSoundfonts.isEmpty) return;
    
    String? current = channels[channel].soundfontPath;
    int currentIndex = current != null ? loadedSoundfonts.indexOf(current) : -1;
    
    int nextIndex = (currentIndex + delta) % loadedSoundfonts.length;
    if (nextIndex < 0) nextIndex = loadedSoundfonts.length - 1;
    
    assignSoundfontToChannel(channel, loadedSoundfonts[nextIndex]);
    toastNotifier.value = 'Assigned Soundfont [Ch $channel]: ${loadedSoundfonts[nextIndex].split(Platform.pathSeparator).last}';
  }

  void _changePatchIndex(int channel, int delta) {
    int newProgram = channels[channel].program + delta;
    int bank = channels[channel].bank;
    if (newProgram > 127) {
       newProgram = 0;
       bank++;
    } else if (newProgram < 0) {
       newProgram = 127;
       bank--;
       if (bank < 0) bank = 0;
    }
    assignPatchToChannel(channel, newProgram, bank: bank);
    toastNotifier.value = 'Patch Changed [Ch $channel]: Program $newProgram (Bank $bank)';
  }

  void _sendControlChange({required int channel, required int controller, required int value}) {
    if (!_isInitialized) return;
    if (Platform.isLinux && _fluidSynthProcess != null) {
      _fluidSynthProcess!.stdin.writeln('cc $channel $controller $value');
    }
  }

  void _sendPitchBend({required int channel, required int value}) {
    if (Platform.isLinux && _fluidSynthProcess != null) {
      _fluidSynthProcess!.stdin.writeln('pitch_bend $channel $value');
    }
  }

  void dispose() {
    if (Platform.isLinux) {
      _fluidSynthProcess?.kill();
    }
  }
}
