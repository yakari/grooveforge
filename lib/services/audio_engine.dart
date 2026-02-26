import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grooveforge/services/cc_mapping_service.dart';
import '../services/sf2_parser.dart';
import 'package:grooveforge/models/chord_detector.dart';

enum ScaleType {
  standard,
  pentatonic,
  blues,
  dorian,
  mixolydian,
  harmonicMinor,
  melodicMinor,
  wholeTone,
  diminished,
}

class ChannelState {
  String? soundfontPath;
  int program = 0;
  int bank = 0;
  final ValueNotifier<Set<int>> activeNotes = ValueNotifier({});
  final ValueNotifier<ChordMatch?> lastChord = ValueNotifier(null);
  final ValueNotifier<bool> isScaleLocked = ValueNotifier(false);
  final ValueNotifier<ScaleType> currentScaleType = ValueNotifier(
    ScaleType.standard,
  );
  final Map<int, int> activeKeyMappings =
      {}; // Track which key was actually played for note-off
  final Map<int, int> snappedKeyOwners =
      {}; // Maps logical note -> physical key that currently owns it

  ChannelState();

  Map<String, dynamic> toJson() => {
    'soundfontPath': soundfontPath,
    'program': program,
    'bank': bank,
    // Note: runtime state like activeNotes, lastChord, and configurations like scale lock
    // are intentionally not serialized, as they are ephemeral performance session state.
  };

  factory ChannelState.fromJson(Map<String, dynamic> json) => ChannelState()
    ..soundfontPath = json['soundfontPath']
    ..program = json['program'] ?? 0
    ..bank = json['bank'] ?? 0;
}

class AudioEngine {
  final MidiPro _midiPro = MidiPro();
  bool _isInitialized = false;

  final List<String> loadedSoundfonts = []; // Platform specific mappings
  final Map<String, int> _sfPathToIdMobile = {};
  final Map<String, int> _sfPathToIdLinux = {};
  int _linuxSfIdCounter = 1;

  // Custom SF2 Patch Names Cache
  final Map<String, Map<int, Map<int, String>>> sf2Presets = {};

  final List<ChannelState> channels = List.generate(16, (i) => ChannelState());

  Process? _fluidSynthProcess;
  CcMappingService? ccMappingService;

  final ValueNotifier<String?> toastNotifier = ValueNotifier(null);
  final ValueNotifier<int> stateNotifier = ValueNotifier(0);

  // Dashboard UI State
  final ValueNotifier<List<int>> visibleChannels = ValueNotifier(
    List.generate(16, (i) => i),
  );

  /// Optional drag-to-play glissando feature on the virtual piano
  final ValueNotifier<bool> dragToPlay = ValueNotifier(false);

  /// Target CC for incoming Aftertouch messages (defaults to 1 = Modulation/Vibrato)
  final ValueNotifier<int> aftertouchDestCc = ValueNotifier(1);

  /// User preference for chord notation format (e.g. 'Standard' vs 'Solfege')
  final ValueNotifier<String> notationFormat = ValueNotifier('Standard');

  /// Number of keys to show simultaneously in the Virtual Piano (default 88)
  // Using number of white keys (22 implies a 37-key piano default)
  final ValueNotifier<int> pianoKeysToShow = ValueNotifier(22);

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    if (Platform.isLinux) {
      _fluidSynthProcess?.kill();
      _fluidSynthProcess = await Process.start('/usr/bin/fluidsynth', [
        '-a',
        'alsa',
        '-m',
        'alsa_seq',
      ]);
    }

    await _restoreState();
    _isInitialized = true;

    // Persist UI preferences immediately on changes
    pianoKeysToShow.addListener(_saveState);
  }

  Future<void> _saveState() async {
    if (_prefs == null) return;
    await _prefs!.setStringList('loaded_soundfonts', loadedSoundfonts);

    List<String> channelsJson = channels
        .map((c) => jsonEncode(c.toJson()))
        .toList();
    await _prefs!.setStringList('channels_state', channelsJson);

    await _prefs!.setString(
      'visible_channels',
      jsonEncode(visibleChannels.value),
    );
    await _prefs!.setBool('drag_to_play', dragToPlay.value);
    await _prefs!.setInt('aftertouch_dest_cc', aftertouchDestCc.value);
    await _prefs!.setString('notation_format', notationFormat.value);
    await _prefs!.setInt('piano_keys_to_show', pianoKeysToShow.value);
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

        if (state.soundfontPath != null &&
            loadedSoundfonts.contains(state.soundfontPath)) {
          _applyChannelInstrument(i);
        }
      }
    }

    // Restore UI visible channels filter
    String? savedVisibleChannels = _prefs!.getString('visible_channels');
    if (savedVisibleChannels != null) {
      try {
        final List<dynamic> decoded = jsonDecode(savedVisibleChannels);
        visibleChannels.value = decoded.cast<int>();
      } catch (e) {
        debugPrint('Error decoding visible channels: $e');
      }
    }

    // Restore Drag to Play toggle
    bool? savedDragToPlay = _prefs!.getBool('drag_to_play');
    if (savedDragToPlay != null) {
      dragToPlay.value = savedDragToPlay;
    }

    int? savedAftertouchDest = _prefs!.getInt('aftertouch_dest_cc');
    if (savedAftertouchDest != null) {
      aftertouchDestCc.value = savedAftertouchDest;
    }

    String? savedNotationFormat = _prefs!.getString('notation_format');
    if (savedNotationFormat != null) {
      notationFormat.value = savedNotationFormat;
    }

    int? savedPianoKeysToShow = _prefs!.getInt('piano_keys_to_show');
    if (savedPianoKeysToShow != null) {
      if (savedPianoKeysToShow == 88 || savedPianoKeysToShow == 52) {
        // Enforce the new 37-key (22 white keys) default if they had the old default
        pianoKeysToShow.value = 22;
      } else {
        pianoKeysToShow.value = savedPianoKeysToShow;
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

    // Parse custom patch names from SF2 metadata
    sf2Presets[path] = await Sf2Parser.parsePresets(path);

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
    sf2Presets.remove(path);

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
        _fluidSynthProcess?.stdin.writeln(
          'select $channel $sfId ${state.bank} ${state.program}',
        );
      }
    } else {
      int? sfId = _sfPathToIdMobile[state.soundfontPath!];
      if (sfId != null) {
        _midiPro.selectInstrument(
          sfId: sfId,
          channel: channel,
          bank: state.bank,
          program: state.program,
        );
      }
    }
  }

  int _getSfIdForChannel(int channel) {
    String? path = channels[channel].soundfontPath;
    if (path == null) return -1;
    return Platform.isLinux
        ? (_sfPathToIdLinux[path] ?? -1)
        : (_sfPathToIdMobile[path] ?? -1);
  }

  /// Returns the internal SF2 patch name for a specific channel's program/bank if available
  String? getCustomPatchName(int channelIndex) {
    if (channelIndex < 0 || channelIndex >= 16) return null;
    final state = channels[channelIndex];
    if (state.soundfontPath == null) return null;

    final sfPresets = sf2Presets[state.soundfontPath!];
    if (sfPresets == null) return null;

    final bankPresets = sfPresets[state.bank];
    if (bankPresets == null) return null;

    return bankPresets[state.program];
  }

  void processMidiPacket(MidiPacket packet) {
    if (!_isInitialized || packet.data.isEmpty) return;

    final statusByte = packet.data[0];
    final command = statusByte & 0xF0;
    final channel = statusByte & 0x0F;

    if (packet.data.length >= 2) {
      int data1 = packet.data[1];
      int data2 = packet.data.length >= 3 ? packet.data[2] : 0;

      switch (command) {
        case 0x90: // Note On
          if (ccMappingService != null) {
            ccMappingService!.updateLastEvent('Note On', channel, data1, data2);
          }
          if (data2 > 0) {
            playNote(channel: channel, key: data1, velocity: data2);
          } else {
            stopNote(channel: channel, key: data1);
          }
          break;
        case 0x80: // Note Off
          if (ccMappingService != null) {
            ccMappingService!.updateLastEvent(
              'Note Off',
              channel,
              data1,
              data2,
            );
          }
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
                } else if (mapping.targetChannel >= 0 &&
                    mapping.targetChannel <= 15) {
                  _handleSystemCommand(
                    mapping.targetCc,
                    mapping.targetChannel,
                    data2,
                  );
                } else {
                  _handleSystemCommand(mapping.targetCc, channel, data2);
                }
                return;
              } else if (mapping.targetChannel == -1) {
                for (int i = 0; i < 16; i++) {
                  _sendControlChange(
                    channel: i,
                    controller: mapping.targetCc,
                    value: data2,
                  );
                }
              } else if (mapping.targetChannel == -2) {
                _sendControlChange(
                  channel: channel,
                  controller: mapping.targetCc,
                  value: data2,
                );
              } else {
                _sendControlChange(
                  channel: mapping.targetChannel,
                  controller: mapping.targetCc,
                  value: data2,
                );
              }
            } else {
              _sendControlChange(
                channel: channel,
                controller: data1,
                value: data2,
              );
            }
          } else {
            _sendControlChange(
              channel: channel,
              controller: data1,
              value: data2,
            );
          }
          break;
        case 0xE0: // Pitch Bend
          int pitchValue = (data2 << 7) | data1;
          _sendPitchBend(channel: channel, value: pitchValue);
          break;
        case 0xD0: // Channel Aftertouch
          _sendControlChange(
            channel: channel,
            controller: aftertouchDestCc.value,
            value: data1,
          );
          break;
      }
    }
  }

  void playNote({
    required int channel,
    required int key,
    required int velocity,
  }) {
    // Update active notes (raw visual input keys)
    final currentNotes = Set<int>.from(channels[channel].activeNotes.value);
    currentNotes.add(key);
    channels[channel].activeNotes.value = currentNotes;

    int keyToPlay = key;

    // Apply scale locking
    if (channels[channel].isScaleLocked.value &&
        channels[channel].lastChord.value != null) {
      keyToPlay = _snapKeyToScale(
        key,
        channels[channel].lastChord.value!,
        channels[channel].currentScaleType.value,
      );
      channels[channel].activeKeyMappings[key] = keyToPlay;
    }

    // Check if another physical key currently owns this logical note
    int? currentOwner = channels[channel].snappedKeyOwners[keyToPlay];
    if (currentOwner != null && currentOwner != key) {
      // Retrigger: Cut off the previous key's note seamlessly before striking again
      if (Platform.isLinux && _fluidSynthProcess != null) {
        _fluidSynthProcess!.stdin.writeln('noteoff $channel $keyToPlay');
      } else {
        int sfId = _getSfIdForChannel(channel);
        if (sfId != -1) {
          _midiPro.stopNote(sfId: sfId, channel: channel, key: keyToPlay);
        }
      }
    }

    // Take ownership of the logical note
    channels[channel].snappedKeyOwners[keyToPlay] = key;

    // Play the note
    if (Platform.isLinux && _fluidSynthProcess != null) {
      _fluidSynthProcess!.stdin.writeln('noteon $channel $keyToPlay $velocity');
    } else {
      int sfId = _getSfIdForChannel(channel);
      if (sfId != -1) {
        _midiPro.playNote(
          sfId: sfId,
          channel: channel,
          key: keyToPlay,
          velocity: velocity,
        );
      }
    }
    _updateChordState(channel);
  }

  void stopNote({required int channel, required int key}) {
    // Update active notes (raw visual input keys)
    final currentNotes = Set<int>.from(channels[channel].activeNotes.value);
    currentNotes.remove(key);
    channels[channel].activeNotes.value = currentNotes;

    int keyToStop = key;

    // Retrieve the actually played key if scale lock engaged it
    if (channels[channel].activeKeyMappings.containsKey(key)) {
      keyToStop = channels[channel].activeKeyMappings.remove(key)!;
    }

    // Check if our physical key is still the owner of this logical note
    int? currentOwner = channels[channel].snappedKeyOwners[keyToStop];

    if (currentOwner == key) {
      // We own the note, so let's finally stop it
      channels[channel].snappedKeyOwners.remove(keyToStop);

      if (Platform.isLinux && _fluidSynthProcess != null) {
        _fluidSynthProcess!.stdin.writeln('noteoff $channel $keyToStop');
      } else {
        int sfId = _getSfIdForChannel(channel);
        if (sfId != -1) {
          _midiPro.stopNote(sfId: sfId, channel: channel, key: keyToStop);
        }
      }
    }
    _updateChordState(channel);
  }

  void _updateChordState(int channel) {
    // If the scale is already locked, do NOT update the chord. We want to keep
    // the currently locked scale intact until they unlock it.
    if (channels[channel].isScaleLocked.value) return;

    final format = notationFormat.value.toLowerCase() == 'solfege'
        ? NotationFormat.solfege
        : NotationFormat.standard;

    final notes = channels[channel].activeNotes.value;
    final match = ChordDetector.identifyChord(notes, format: format);

    // We only update if we successfully detect a chord.
    // This way if they lift their hands, the last chord stays on screen
    // (and available for locking)
    if (match != null) {
      channels[channel].lastChord.value = match;
    }
  }

  int _snapKeyToScale(int originalKey, ChordMatch chord, ScaleType scaleType) {
    Set<int> allowedPcs;

    if (scaleType == ScaleType.standard) {
      allowedPcs = Set.from(chord.scalePitchClasses);
    } else {
      int root = chord.rootPc;
      List<int> intervals;
      switch (scaleType) {
        case ScaleType.pentatonic:
          intervals = chord.isMinor ? [0, 3, 5, 7, 10] : [0, 2, 4, 7, 9];
          break;
        case ScaleType.blues:
          intervals = chord.isMinor ? [0, 3, 5, 6, 7, 10] : [0, 2, 3, 4, 7, 9];
          break;
        case ScaleType.dorian:
          intervals = [0, 2, 3, 5, 7, 9, 10];
          break;
        case ScaleType.mixolydian:
          intervals = [0, 2, 4, 5, 7, 9, 10];
          break;
        case ScaleType.harmonicMinor:
          intervals = [0, 2, 3, 5, 7, 8, 11];
          break;
        case ScaleType.melodicMinor:
          intervals = [0, 2, 3, 5, 7, 9, 11];
          break;
        case ScaleType.wholeTone:
          intervals = [0, 2, 4, 6, 8, 10];
          break;
        case ScaleType.diminished: // Half-Whole
          intervals = [0, 1, 3, 4, 6, 7, 9, 10];
          break;
        default:
          intervals = [0, 2, 4, 5, 7, 9, 11]; // Fallback
      }
      allowedPcs = intervals.map((i) => (root + i) % 12).toSet();
    }

    int bestDistance = 999;
    int bestKey = originalKey;

    // Provide a reasonable search radius
    for (int offset = 0; offset <= 12; offset++) {
      int upKey = originalKey + offset;
      if (allowedPcs.contains(upKey % 12)) {
        if (offset < bestDistance) {
          bestDistance = offset;
          bestKey = upKey;
        }
      }

      int downKey = originalKey - offset;
      if (allowedPcs.contains(downKey % 12)) {
        if (offset < bestDistance) {
          bestDistance = offset;
          bestKey = downKey;
        }
      }

      if (bestDistance < 999) break; // Found nearest
    }

    return bestKey;
  }

  final Map<String, int> _lastSystemCommandTime = {};

  void _handleSystemCommand(int targetAction, int incomingChannel, int value) {
    if ([1001, 1002, 1003, 1004, 1007, 1008].contains(targetAction)) {
      // Debounce logic to support hardware pads that strictly send `0` or burst `127` then `0`.
      String debounceKey = '${targetAction}_$incomingChannel';
      int now = DateTime.now().millisecondsSinceEpoch;
      int lastTime = _lastSystemCommandTime[debounceKey] ?? 0;
      if (now - lastTime < 250) {
        return; // Ignore rapid consecutive triggers from release signals
      }
      _lastSystemCommandTime[debounceKey] = now;

      if (targetAction == 1001) {
        // Next Soundfont
        _cycleChannelSoundfont(incomingChannel, 1);
      } else if (targetAction == 1002) {
        // Prev Soundfont
        _cycleChannelSoundfont(incomingChannel, -1);
      } else if (targetAction == 1003) {
        // Next Patch
        _changePatchIndex(incomingChannel, 1);
      } else if (targetAction == 1004) {
        // Prev Patch
        _changePatchIndex(incomingChannel, -1);
      } else if (targetAction == 1007) {
        // Toggle Scale Lock
        channels[incomingChannel].isScaleLocked.value =
            !channels[incomingChannel].isScaleLocked.value;
        toastNotifier.value =
            'Scale Lock [Ch $incomingChannel]: ${channels[incomingChannel].isScaleLocked.value ? "ON" : "OFF"}';
      } else if (targetAction == 1008) {
        // Cycle Scale Type
        final currentTypes = ScaleType.values;
        int nextIndex =
            (channels[incomingChannel].currentScaleType.value.index + 1) %
            currentTypes.length;
        channels[incomingChannel].currentScaleType.value =
            currentTypes[nextIndex];
        toastNotifier.value =
            'Scale Type [Ch $incomingChannel]: ${currentTypes[nextIndex].name}';
      }
    } else if (targetAction == 1005) {
      // Absolute Patch Index Sweep
      assignPatchToChannel(incomingChannel, value);
      toastNotifier.value = 'Patch Sweep [Ch $incomingChannel]: Program $value';
    } else if (targetAction == 1006) {
      // Absolute Bank Index Sweep
      int program = channels[incomingChannel].program;
      assignPatchToChannel(incomingChannel, program, bank: value);
      toastNotifier.value =
          'Bank/Tone Sweep [Ch $incomingChannel]: Bank $value';
    }
  }

  void _cycleChannelSoundfont(int channel, int delta) {
    if (loadedSoundfonts.isEmpty) return;

    String? current = channels[channel].soundfontPath;
    int currentIndex = current != null ? loadedSoundfonts.indexOf(current) : -1;

    int nextIndex = (currentIndex + delta) % loadedSoundfonts.length;
    if (nextIndex < 0) nextIndex = loadedSoundfonts.length - 1;

    assignSoundfontToChannel(channel, loadedSoundfonts[nextIndex]);
    toastNotifier.value =
        'Assigned Soundfont [Ch $channel]: ${loadedSoundfonts[nextIndex].split(Platform.pathSeparator).last}';
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
    toastNotifier.value =
        'Patch Changed [Ch $channel]: Program $newProgram (Bank $bank)';
  }

  void _sendControlChange({
    required int channel,
    required int controller,
    required int value,
  }) {
    if (!_isInitialized) return;
    if (Platform.isLinux && _fluidSynthProcess != null) {
      _fluidSynthProcess!.stdin.writeln('cc $channel $controller $value');
    } else {
      int sfId = _getSfIdForChannel(channel);
      if (sfId != -1) {
        _midiPro.controlChange(
          sfId: sfId,
          channel: channel,
          controller: controller,
          value: value,
        );
      }
    }
  }

  void _sendPitchBend({required int channel, required int value}) {
    if (Platform.isLinux && _fluidSynthProcess != null) {
      _fluidSynthProcess!.stdin.writeln('pitch_bend $channel $value');
    } else {
      int sfId = _getSfIdForChannel(channel);
      if (sfId != -1) {
        _midiPro.pitchBend(sfId: sfId, channel: channel, value: value);
      }
    }
  }

  void dispose() {
    if (Platform.isLinux) {
      _fluidSynthProcess?.kill();
    }
  }
}
