import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grooveforge/services/cc_mapping_service.dart';
import '../services/sf2_parser.dart';
import 'package:grooveforge/models/chord_detector.dart';

enum ScaleType {
  standard,
  jazz,
  blues,
  rock,
  asiatic,
  oriental,
  classical,
  pentatonic,
  dorian,
  mixolydian,
  harmonicMinor,
  melodicMinor,
  wholeTone,
  diminished,
}

enum ScaleLockMode { classic, jam }

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
  };

  factory ChannelState.fromJson(Map<String, dynamic> json) =>
      ChannelState()
        ..soundfontPath = json['soundfontPath']
        ..program = json['program'] ?? 0
        ..bank = json['bank'] ?? 0;
}

class AudioEngine {
  final MidiPro _midiPro = MidiPro();
  bool _isInitialized = false;

  final ValueNotifier<String> initStatus = ValueNotifier(
    'Starting audio engine...',
  );

  final List<String> loadedSoundfonts = [];
  final Map<String, int> _sfPathToIdMobile = {};
  final Map<String, int> _sfPathToIdLinux = {};
  int _linuxSfIdCounter = 1;

  final Map<String, Map<int, Map<int, String>>> sf2Presets = {};
  final List<ChannelState> channels = List.generate(16, (i) => ChannelState());

  Process? _fluidSynthProcess;
  CcMappingService? ccMappingService;

  final ValueNotifier<String?> toastNotifier = ValueNotifier(null);
  final ValueNotifier<int> stateNotifier = ValueNotifier(0);

  final ValueNotifier<List<int>> visibleChannels = ValueNotifier(
    List.generate(16, (i) => i),
  );

  final ValueNotifier<bool> dragToPlay = ValueNotifier<bool>(true);
  final ValueNotifier<bool> verticalPitchBendEnabled = ValueNotifier<bool>(
    true,
  );
  final ValueNotifier<bool> horizontalVibratoEnabled = ValueNotifier<bool>(
    true,
  );
  final ValueNotifier<bool> isGestureInProgress = ValueNotifier<bool>(false);
  int _activeGestureCount = 0;

  void updateGestureState(bool interacting) {
    if (interacting) {
      _activeGestureCount++;
    } else {
      _activeGestureCount--;
    }
    isGestureInProgress.value = _activeGestureCount > 0;
  }

  final ValueNotifier<int> aftertouchDestCc = ValueNotifier<int>(1);
  final ValueNotifier<String> notationFormat = ValueNotifier('Standard');
  final ValueNotifier<int> pianoKeysToShow = ValueNotifier(22);

  // Jam Mode State
  final ValueNotifier<ScaleLockMode> lockModePreference = ValueNotifier(
    ScaleLockMode.jam,
  );
  final ValueNotifier<bool> jamEnabled = ValueNotifier(false);
  final ValueNotifier<int> jamMasterChannel = ValueNotifier(1); // Default Ch 2
  final ValueNotifier<Set<int>> jamSlaveChannels = ValueNotifier({
    0,
  }); // Default Ch 1
  final ValueNotifier<ScaleType> jamScaleType = ValueNotifier(
    ScaleType.standard,
  );

  // Chord Release Logic
  final List<Timer?> _chordUpdateTimers = List.generate(16, (i) => null);
  final List<int> _lastNoteCounts = List.generate(16, (i) => 0);

  final Map<int, DateTime> _lastNoteOffTime = {};
  SharedPreferences? _prefs;

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }
    initStatus.value = 'Loading preferences...';
    _prefs = await SharedPreferences.getInstance();

    if (Platform.isLinux) {
      initStatus.value = 'Starting FluidSynth backend...';
      _fluidSynthProcess?.kill();
      _fluidSynthProcess = await Process.start('/usr/bin/fluidsynth', [
        '-a',
        'alsa',
        '-m',
        'alsa_seq',
      ]);
    }

    initStatus.value = 'Restoring saved state...';
    await _restoreState();

    initStatus.value = 'Checking bundled soundfonts...';
    await _ensureDefaultSoundfont();

    _isInitialized = true;
    initStatus.value = 'Ready';

    pianoKeysToShow.addListener(_saveState);
    lockModePreference.addListener(_saveState);
    jamEnabled.addListener(_saveState);
    jamMasterChannel.addListener(_saveState);
    jamSlaveChannels.addListener(_saveState);
    jamScaleType.addListener(_saveState);
    dragToPlay.addListener(_saveState);
    verticalPitchBendEnabled.addListener(_saveState);
    horizontalVibratoEnabled.addListener(_saveState);
    aftertouchDestCc.addListener(_saveState);
    notationFormat.addListener(_saveState);
  }

  Future<void> _ensureDefaultSoundfont() async {
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final soundfontsDirPath = p.join(appSupportDir.path, 'soundfonts');
      final soundfontsDir = Directory(soundfontsDirPath);

      if (!soundfontsDir.existsSync()) {
        await soundfontsDir.create(recursive: true);
      }

      final defaultSfPath = p.join(soundfontsDirPath, 'default_soundfont.sf2');
      final defaultSfFile = File(defaultSfPath);

      if (!defaultSfFile.existsSync()) {
        initStatus.value = 'Extracting default soundfont...';
        final ByteData data = await rootBundle.load(
          'assets/soundfonts/default.sf2',
        );
        final buffer = data.buffer;
        await defaultSfFile.writeAsBytes(
          buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }

      if (!loadedSoundfonts.contains(defaultSfFile.path)) {
        await loadSoundfont(defaultSfFile, save: false);
      }

      bool stateChanged = false;
      for (int i = 0; i < 16; i++) {
        if (channels[i].soundfontPath == null ||
            channels[i].soundfontPath!.isEmpty) {
          channels[i].soundfontPath = defaultSfFile.path;
          _applyChannelInstrument(i);
          stateChanged = true;
        }
      }

      if (stateChanged) {
        await _saveState();
        stateNotifier.value++;
      }
    } catch (e) {
      debugPrint('Error unpacking default soundfont: $e');
    }
  }

  Future<void> _saveState() async {
    if (_prefs == null) {
      return;
    }
    await _prefs!.setStringList('loaded_soundfonts', loadedSoundfonts);

    List<String> channelsJson =
        channels.map((c) => jsonEncode(c.toJson())).toList();
    await _prefs!.setStringList('channels_state', channelsJson);

    await _prefs!.setString(
      'visible_channels',
      jsonEncode(visibleChannels.value),
    );
    await _prefs!.setBool('drag_to_play', dragToPlay.value);
    await _prefs!.setBool(
      'vertical_pitch_bend_enabled',
      verticalPitchBendEnabled.value,
    );
    await _prefs!.setBool(
      'horizontal_vibrato_enabled',
      horizontalVibratoEnabled.value,
    );
    await _prefs!.setInt('aftertouch_dest_cc', aftertouchDestCc.value);
    await _prefs!.setString('notation_format', notationFormat.value);
    await _prefs!.setInt('piano_keys_to_show', pianoKeysToShow.value);

    // Save Jam State
    await _prefs!.setInt(
      'lock_mode_preference',
      lockModePreference.value.index,
    );
    await _prefs!.setBool('jam_enabled', jamEnabled.value);
    await _prefs!.setInt('jam_master_channel', jamMasterChannel.value);
    await _prefs!.setStringList(
      'jam_slave_channels',
      jamSlaveChannels.value.map((e) => e.toString()).toList(),
    );
    await _prefs!.setInt('jam_scale_type', jamScaleType.value.index);
  }

  Future<void> _restoreState() async {
    if (_prefs == null) {
      return;
    }

    List<String>? savedSfs = _prefs!.getStringList('loaded_soundfonts');
    Map<String, String> migrationMap = {};
    if (savedSfs != null) {
      for (String path in savedSfs) {
        final file = File(path);
        if (file.existsSync()) {
          String migratedPath = await loadSoundfont(file, save: false);
          migrationMap[path] = migratedPath;
        }
      }
    }

    List<String>? savedChannels = _prefs!.getStringList('channels_state');
    if (savedChannels != null && savedChannels.length == 16) {
      if (Platform.isLinux && savedSfs != null && savedSfs.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 1500));
      }

      for (int i = 0; i < 16; i++) {
        var state = ChannelState.fromJson(jsonDecode(savedChannels[i]));
        if (state.soundfontPath != null &&
            migrationMap.containsKey(state.soundfontPath)) {
          state.soundfontPath = migrationMap[state.soundfontPath];
        }
        channels[i] = state;
        if (state.soundfontPath != null &&
            loadedSoundfonts.contains(state.soundfontPath)) {
          _applyChannelInstrument(i);
        }
      }
    }

    String? savedVisibleChannels = _prefs!.getString('visible_channels');
    if (savedVisibleChannels != null) {
      try {
        final List<dynamic> decoded = jsonDecode(savedVisibleChannels);
        visibleChannels.value = decoded.cast<int>();
      } catch (e) {
        debugPrint('Error decoding visible channels: $e');
      }
    }

    dragToPlay.value = _prefs?.getBool('drag_to_play') ?? true;
    verticalPitchBendEnabled.value =
        _prefs?.getBool('vertical_pitch_bend_enabled') ?? true;
    horizontalVibratoEnabled.value =
        _prefs?.getBool('horizontal_vibrato_enabled') ?? true;
    aftertouchDestCc.value = _prefs?.getInt('aftertouch_dest_cc') ?? 1;

    String? savedNotationFormat = _prefs!.getString('notation_format');
    if (savedNotationFormat != null) {
      notationFormat.value = savedNotationFormat;
    }

    int? savedPianoKeysToShow = _prefs!.getInt('piano_keys_to_show');
    if (savedPianoKeysToShow != null) {
      if (savedPianoKeysToShow == 88 || savedPianoKeysToShow == 52) {
        pianoKeysToShow.value = 22;
      } else {
        pianoKeysToShow.value = savedPianoKeysToShow;
      }
    }

    int? savedLockMode = _prefs!.getInt('lock_mode_preference');
    if (savedLockMode != null) {
      lockModePreference.value = ScaleLockMode.values[savedLockMode];
    }

    bool? savedJamEnabled = _prefs!.getBool('jam_enabled');
    if (savedJamEnabled != null) {
      jamEnabled.value = savedJamEnabled;
    }

    int? savedJamMaster = _prefs!.getInt('jam_master_channel');
    if (savedJamMaster != null) {
      jamMasterChannel.value = savedJamMaster;
    }

    List<String>? savedJamSlaves = _prefs!.getStringList('jam_slave_channels');
    if (savedJamSlaves != null) {
      jamSlaveChannels.value = savedJamSlaves.map((e) => int.parse(e)).toSet();
    }

    int? savedJamScale = _prefs!.getInt('jam_scale_type');
    if (savedJamScale != null) {
      jamScaleType.value = ScaleType.values[savedJamScale];
    }

    stateNotifier.value++;
  }

  Future<String> loadSoundfont(File soundfont, {bool save = true}) async {
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final soundfontsDirPath = p.join(appSupportDir.path, 'soundfonts');
      final soundfontsDir = Directory(soundfontsDirPath);
      if (!soundfontsDir.existsSync()) {
        await soundfontsDir.create(recursive: true);
      }

      String originalPath = soundfont.path;
      String filename = p.basename(originalPath);
      String targetPath = p.join(soundfontsDirPath, filename);

      if (p.absolute(originalPath) != p.absolute(targetPath)) {
        if (!soundfont.existsSync()) {
          throw Exception('Source file does not exist: $originalPath');
        }
        final targetFile = File(targetPath);
        if (!targetFile.existsSync() ||
            targetFile.lengthSync() != soundfont.lengthSync()) {
          final bytes = await soundfont.readAsBytes();
          await targetFile.writeAsBytes(bytes);
        }
      }

      if (loadedSoundfonts.contains(targetPath)) {
        return targetPath;
      }
      loadedSoundfonts.add(targetPath);

      if (Platform.isLinux) {
        _fluidSynthProcess?.stdin.writeln('load "$targetPath"');
        _sfPathToIdLinux[targetPath] = _linuxSfIdCounter++;
      } else {
        int sfId = await _midiPro.loadSoundfontFile(filePath: targetPath);
        if (sfId == -1) {
          throw Exception('Failed to load soundfont at $targetPath');
        }
        _sfPathToIdMobile[targetPath] = sfId;
      }

      try {
        sf2Presets[targetPath] = await Sf2Parser.parsePresets(targetPath);
      } catch (e) {
        debugPrint('Error parsing SF2 presets: $e');
      }

      if (save) {
        await _saveState();
      }
      toastNotifier.value = 'Loaded: $filename';
      stateNotifier.value++;
      return targetPath;
    } catch (e) {
      debugPrint('Error loading soundfont: $e');
      toastNotifier.value = 'Error loading soundfont: $e';
      return soundfont.path;
    }
  }

  Future<void> unloadSoundfont(String path) async {
    if (!loadedSoundfonts.contains(path)) {
      return;
    }
    if (Platform.isLinux) {
      int? sfId = _sfPathToIdLinux[path];
      if (sfId != null) {
        _fluidSynthProcess?.stdin.writeln('unload $sfId');
      }
      _sfPathToIdLinux.remove(path);
    } else {
      _sfPathToIdMobile.remove(path);
    }
    loadedSoundfonts.remove(path);
    sf2Presets.remove(path);
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
    if (channel < 0 || channel > 15 || !loadedSoundfonts.contains(path)) {
      return;
    }
    channels[channel].soundfontPath = path;
    _applyChannelInstrument(channel);
    _saveState();
    stateNotifier.value++;
  }

  void assignPatchToChannel(int channel, int program, {int? bank}) {
    if (channel < 0 || channel > 15) {
      return;
    }
    channels[channel].program = program;
    if (bank != null) {
      channels[channel].bank = bank;
    }
    _applyChannelInstrument(channel);
    _saveState();
    stateNotifier.value++;
  }

  void _applyChannelInstrument(int channel) {
    ChannelState state = channels[channel];
    if (state.soundfontPath == null) {
      return;
    }
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
    if (path == null) {
      return -1;
    }
    return Platform.isLinux
        ? (_sfPathToIdLinux[path] ?? -1)
        : (_sfPathToIdMobile[path] ?? -1);
  }

  String? getCustomPatchName(int channelIndex) {
    if (channelIndex < 0 || channelIndex >= 16) {
      return null;
    }
    final state = channels[channelIndex];
    if (state.soundfontPath == null) {
      return null;
    }
    final sfPresets = sf2Presets[state.soundfontPath!];
    if (sfPresets == null) {
      return null;
    }
    final bankPresets = sfPresets[state.bank];
    if (bankPresets == null) {
      return null;
    }
    return bankPresets[state.program];
  }

  void processMidiPacket(MidiPacket packet) {
    if (!_isInitialized || packet.data.isEmpty) {
      return;
    }
    final statusByte = packet.data[0];
    final command = statusByte & 0xF0;
    final channel = statusByte & 0x0F;
    if (packet.data.length >= 2) {
      int data1 = packet.data[1];
      int data2 = packet.data.length >= 3 ? packet.data[2] : 0;
      switch (command) {
        case 0x90:
          if (ccMappingService != null) {
            ccMappingService!.updateLastEvent('Note On', channel, data1, data2);
          }
          if (data2 > 0) {
            playNote(channel: channel, key: data1, velocity: data2);
          } else {
            stopNote(channel: channel, key: data1);
          }
          break;
        case 0x80:
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
        case 0xB0:
          if (ccMappingService != null) {
            ccMappingService!.updateLastEvent('CC', channel, data1, data2);
            final mapping = ccMappingService!.getMapping(data1);
            if (mapping != null) {
              if (mapping.targetCc >= 1000) {
                // System actions
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
              } else {
                // Normal CC remapping
                if (mapping.targetChannel == -1) {
                  for (int i = 0; i < 16; i++) {
                    setControlChange(
                      channel: i,
                      controller: mapping.targetCc,
                      value: data2,
                    );
                  }
                } else if (mapping.targetChannel == -2) {
                  setControlChange(
                    channel: channel,
                    controller: mapping.targetCc,
                    value: data2,
                  );
                } else {
                  setControlChange(
                    channel: mapping.targetChannel,
                    controller: mapping.targetCc,
                    value: data2,
                  );
                }
              }
              return;
            }
          }
          // Default: send normal CC
          setControlChange(channel: channel, controller: data1, value: data2);
          break;
        case 0xE0:
          int pitchValue = (data2 << 7) | data1;
          setPitchBend(channel: channel, value: pitchValue);
          break;
        case 0xD0:
          setControlChange(
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
    // Reset expressive gestures on Note On to avoid stuck values
    setPitchBend(channel: channel, value: 8192); // Center
    setControlChange(channel: channel, controller: 1, value: 0); // Reset Mod

    final currentNotes = Set<int>.from(channels[channel].activeNotes.value);
    currentNotes.add(key);
    channels[channel].activeNotes.value = currentNotes;
    int keyToPlay = key;

    // Classic Scale Lock (per-channel)
    if (lockModePreference.value == ScaleLockMode.classic &&
        channels[channel].isScaleLocked.value &&
        channels[channel].lastChord.value != null) {
      keyToPlay = _snapKeyToScale(
        key,
        channels[channel].lastChord.value!,
        channels[channel].currentScaleType.value,
      );
    }
    // Jam Mode Scale Lock
    else if (lockModePreference.value == ScaleLockMode.jam &&
        jamEnabled.value &&
        jamSlaveChannels.value.contains(channel) &&
        channels[jamMasterChannel.value].lastChord.value != null) {
      keyToPlay = _snapKeyToScale(
        key,
        channels[jamMasterChannel.value].lastChord.value!,
        jamScaleType.value,
      );
    }

    if (keyToPlay != key) {
      channels[channel].activeKeyMappings[key] = keyToPlay;
    }

    int? currentOwner = channels[channel].snappedKeyOwners[keyToPlay];
    if (currentOwner != null && currentOwner != key) {
      if (Platform.isLinux && _fluidSynthProcess != null) {
        _fluidSynthProcess!.stdin.writeln('noteoff $channel $keyToPlay');
      } else {
        int sfId = _getSfIdForChannel(channel);
        if (sfId != -1) {
          _midiPro.stopNote(sfId: sfId, channel: channel, key: keyToPlay);
        }
      }
    }

    channels[channel].snappedKeyOwners[keyToPlay] = key;

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
    Future.microtask(() => _updateChordState(channel));
  }

  void stopNote({required int channel, required int key}) {
    final currentNotes = Set<int>.from(channels[channel].activeNotes.value);
    currentNotes.remove(key);
    channels[channel].activeNotes.value = currentNotes;

    // Debounce for Master Channel Chord Release
    if (lockModePreference.value == ScaleLockMode.jam &&
        channel == jamMasterChannel.value) {
      _lastNoteOffTime[key] = DateTime.now();
    }

    int keyToStop = key;
    if (channels[channel].activeKeyMappings.containsKey(key)) {
      keyToStop = channels[channel].activeKeyMappings.remove(key)!;
    }

    int? currentOwner = channels[channel].snappedKeyOwners[keyToStop];
    if (currentOwner == key) {
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
    Future.microtask(() => _updateChordState(channel));
  }

  void _updateChordState(int channel) {
    // In Jam mode, we ONLY update the master channel's chord.
    // In Classic mode, we don't update if already locked.
    if (lockModePreference.value == ScaleLockMode.classic) {
      if (channels[channel].isScaleLocked.value) {
        return;
      }
    }
    // In Jam mode, we allow all channels to update their detected chord for display.
    // Snapping logic (noteOn) correctly handles reference to the master channel.

    final notes = channels[channel].activeNotes.value;
    final count = notes.length;
    final lastCount = _lastNoteCounts[channel];

    // Cancel any pending "wait-and-see" timer
    _chordUpdateTimers[channel]?.cancel();
    _chordUpdateTimers[channel] = null;

    if (count > lastCount) {
      // Instant Enrichment (Note On)
      _performChordUpdate(channel, notes);
    } else if (count < lastCount) {
      // Grace Period (Note Off)
      _chordUpdateTimers[channel] = Timer(const Duration(milliseconds: 30), () {
        final currentNotes = channels[channel].activeNotes.value;
        if (currentNotes.isEmpty) {
          // Total Release: Keep peak chord identity (no-op)
          _lastNoteCounts[channel] = 0;
        } else {
          // Deliberate Partial Release: Update identity
          _performChordUpdate(channel, currentNotes);
        }
      });
    }

    // Note: We don't update _lastNoteCounts[channel] here if count < lastCount
    // to preserve the peak context until the timer fires.
    if (count > lastCount) {
      _lastNoteCounts[channel] = count;
    }
  }

  void _performChordUpdate(int channel, Set<int> notes) {
    final format =
        notationFormat.value.toLowerCase() == 'solfege'
            ? NotationFormat.solfege
            : NotationFormat.standard;
    final match = ChordDetector.identifyChord(notes, format: format);
    channels[channel].lastChord.value = match;
    _lastNoteCounts[channel] = notes.length;
  }

  /// Returns a descriptive name for the effective scale being used.
  String getDescriptiveScaleName(ChordMatch? chord, ScaleType type) {
    if (chord == null) {
      return type.name.toUpperCase();
    }
    return _getScaleInfo(chord, type).name;
  }

  _ScaleInfo _getScaleInfo(ChordMatch chord, ScaleType scaleType) {
    if (scaleType == ScaleType.standard) {
      final intervals = chord.scalePitchClasses.toList()..sort();
      String name = 'Standard';

      // Try to match specific mode names for the standard scale
      final modeMap = {
        '0,2,4,5,7,9,11': 'Ionian',
        '0,2,3,5,7,9,10': 'Dorian',
        '0,1,3,5,7,8,10': 'Phrygian',
        '0,2,4,6,7,9,11': 'Lydian',
        '0,2,4,5,7,9,10': 'Mixolydian',
        '0,2,3,5,7,8,10': 'Aeolian',
        '0,1,3,5,6,8,10': 'Locrian',
      };

      final key = intervals.join(',');
      if (modeMap.containsKey(key)) {
        name = modeMap[key]!;
      }

      return _ScaleInfo(intervals: intervals, name: name);
    }

    List<int> intervals;
    String name;

    switch (scaleType) {
      case ScaleType.pentatonic:
        intervals = chord.isMinor ? [0, 3, 5, 7, 10] : [0, 2, 4, 7, 9];
        name = chord.isMinor ? 'Minor Pentatonic' : 'Major Pentatonic';
        break;
      case ScaleType.blues:
        intervals = chord.isMinor ? [0, 3, 5, 6, 7, 10] : [0, 2, 3, 4, 7, 9];
        name = chord.isMinor ? 'Minor Blues' : 'Major Blues';
        break;
      case ScaleType.dorian:
        intervals = [0, 2, 3, 5, 7, 9, 10];
        name = 'Dorian';
        break;
      case ScaleType.mixolydian:
        intervals = [0, 2, 4, 5, 7, 9, 10];
        name = 'Mixolydian';
        break;
      case ScaleType.harmonicMinor:
        intervals = [0, 2, 3, 5, 7, 8, 11];
        name = 'Harmonic Minor';
        break;
      case ScaleType.melodicMinor:
        intervals = [0, 2, 3, 5, 7, 9, 11];
        name = 'Melodic Minor';
        break;
      case ScaleType.wholeTone:
        intervals = [0, 2, 4, 6, 8, 10];
        name = 'Whole Tone';
        break;
      case ScaleType.diminished:
        intervals = [0, 1, 3, 4, 6, 7, 9, 10];
        name = 'Diminished';
        break;
      case ScaleType.jazz:
        if (chord.isMinor) {
          if (chord.suffix == 'm7b5' || chord.suffix.contains('dim')) {
            intervals = [0, 2, 3, 5, 6, 8, 10];
            name = 'Locrian #2';
          } else if (chord.suffix.contains('7') ||
              (chord.extensionsMask & (1 << 9)) != 0) {
            intervals = [0, 2, 3, 5, 7, 9, 10];
            name = 'Dorian';
          } else {
            intervals = [0, 2, 3, 5, 7, 8, 10];
            name = 'Aeolian';
          }
        } else if (chord.suffix.contains('7') &&
            !chord.suffix.contains('maj7')) {
          bool isAltered = (chord.extensionsMask & 0x10A) != 0;
          if (isAltered) {
            intervals = [0, 1, 3, 4, 6, 8, 10];
            name = 'Altered Scale';
          } else if ((chord.extensionsMask & (1 << 6)) != 0) {
            intervals = [0, 2, 4, 6, 7, 9, 10];
            name = 'Lydian Dominant';
          } else {
            intervals = [0, 2, 4, 5, 7, 9, 10];
            name = 'Mixolydian';
          }
        } else {
          if ((chord.extensionsMask & (1 << 6)) != 0) {
            intervals = [0, 2, 4, 6, 7, 9, 11];
            name = 'Lydian';
          } else {
            intervals = [0, 2, 4, 5, 7, 9, 11];
            name = 'Ionian';
          }
        }
        break;
      case ScaleType.rock:
        intervals = [0, 2, 3, 4, 7, 9];
        name = 'Rock Hexatonic';
        break;
      case ScaleType.classical:
        intervals =
            chord.isMinor ? [0, 2, 3, 5, 7, 8, 11] : [0, 2, 4, 5, 7, 9, 11];
        name = chord.isMinor ? 'Harmonic Minor' : 'Natural Major';
        break;
      case ScaleType.asiatic:
        intervals = [0, 2, 4, 7, 9];
        name = 'Major Pentatonic';
        break;
      case ScaleType.oriental:
        intervals = [0, 1, 4, 5, 7, 8, 10];
        name = 'Phrygian Dominant';
        break;
      default:
        intervals = [0, 2, 4, 5, 7, 9, 11];
        name = 'Major';
    }

    return _ScaleInfo(intervals: intervals, name: name);
  }

  int _snapKeyToScale(int originalKey, ChordMatch chord, ScaleType scaleType) {
    final info = _getScaleInfo(chord, scaleType);
    final root = chord.rootPc;
    final allowedPcs = info.intervals.map((i) => (root + i) % 12).toSet();
    int bestDistance = 999;
    int bestKey = originalKey;
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
      if (bestDistance < 999) {
        break;
      }
    }
    return bestKey;
  }

  void _handleSystemCommand(int targetAction, int incomingChannel, int value) {
    if ([1001, 1002, 1003, 1004, 1007, 1008].contains(targetAction)) {
      String debounceKey = '${targetAction}_$incomingChannel';
      int now = DateTime.now().millisecondsSinceEpoch;
      int lastTime = (_prefs?.getInt('last_sys_cmd_$debounceKey')) ?? 0;
      if (now - lastTime < 250) {
        return;
      }
      _prefs?.setInt('last_sys_cmd_$debounceKey', now);

      if (targetAction == 1007) {
        if (lockModePreference.value == ScaleLockMode.jam) {
          jamEnabled.value = !jamEnabled.value;
          toastNotifier.value =
              'Jam Mode: ${jamEnabled.value ? "STARTED" : "STOPPED"}';
        } else {
          channels[incomingChannel].isScaleLocked.value =
              !channels[incomingChannel].isScaleLocked.value;
          toastNotifier.value =
              'Scale Lock [Ch $incomingChannel]: ${channels[incomingChannel].isScaleLocked.value ? "ON" : "OFF"}';
        }
        _saveState();
      } else if (targetAction == 1001) {
        _cycleChannelSoundfont(incomingChannel, 1);
      } else if (targetAction == 1002) {
        _cycleChannelSoundfont(incomingChannel, -1);
      } else if (targetAction == 1003) {
        _changePatchIndex(incomingChannel, 1);
      } else if (targetAction == 1004) {
        _changePatchIndex(incomingChannel, -1);
      } else if (targetAction == 1008) {
        if (lockModePreference.value == ScaleLockMode.jam) {
          final vals = ScaleType.values;
          jamScaleType.value =
              vals[(jamScaleType.value.index + 1) % vals.length];
          toastNotifier.value = 'Jam Scale: ${jamScaleType.value.name}';
        } else {
          final currentTypes = ScaleType.values;
          int nextIndex =
              (channels[incomingChannel].currentScaleType.value.index + 1) %
              currentTypes.length;
          channels[incomingChannel].currentScaleType.value =
              currentTypes[nextIndex];
          toastNotifier.value =
              'Scale Type [Ch $incomingChannel]: ${currentTypes[nextIndex].name}';
        }
        _saveState();
      }
    } else if (targetAction == 1005) {
      assignPatchToChannel(incomingChannel, value);
      toastNotifier.value = 'Patch Sweep [Ch $incomingChannel]: Program $value';
    } else if (targetAction == 1006) {
      assignPatchToChannel(
        incomingChannel,
        channels[incomingChannel].program,
        bank: value,
      );
      toastNotifier.value = 'Bank Sweep [Ch $incomingChannel]: Bank $value';
    }
  }

  void _cycleChannelSoundfont(int channel, int delta) {
    if (loadedSoundfonts.isEmpty) {
      return;
    }
    String? current = channels[channel].soundfontPath;
    int currentIndex = current != null ? loadedSoundfonts.indexOf(current) : -1;
    int nextIndex = (currentIndex + delta) % loadedSoundfonts.length;
    if (nextIndex < 0) {
      nextIndex = loadedSoundfonts.length - 1;
    }
    assignSoundfontToChannel(channel, loadedSoundfonts[nextIndex]);
  }

  void _changePatchIndex(int channel, int delta) {
    int nextProgram = (channels[channel].program + delta) % 128;
    if (nextProgram < 0) {
      nextProgram = 127;
    }
    assignPatchToChannel(channel, nextProgram);
  }

  void setControlChange({
    required int channel,
    required int controller,
    required int value,
  }) {
    _sendControlChange(channel: channel, controller: controller, value: value);
  }

  void setPitchBend({required int channel, required int value}) {
    _sendPitchBend(channel: channel, value: value);
  }

  void _sendControlChange({
    required int channel,
    required int controller,
    required int value,
  }) {
    if (Platform.isLinux && _fluidSynthProcess != null) {
      _fluidSynthProcess!.stdin.writeln('cc $channel $controller $value');
    } else {
      int sfId = _getSfIdForChannel(channel);
      _midiPro.controlChange(
        controller: controller,
        value: value,
        channel: channel,
        sfId: sfId == -1 ? 1 : sfId,
      );
    }
  }

  void _sendPitchBend({required int channel, required int value}) {
    if (Platform.isLinux && _fluidSynthProcess != null) {
      _fluidSynthProcess!.stdin.writeln('pitch_bend $channel $value');
    } else {
      int sfId = _getSfIdForChannel(channel);
      _midiPro.pitchBend(
        value: value,
        channel: channel,
        sfId: sfId == -1 ? 1 : sfId,
      );
    }
  }

  Future<void> resetAllPreferences() async {
    if (_prefs == null) {
      return;
    }
    await _prefs!.clear();
    loadedSoundfonts.clear();
    _sfPathToIdMobile.clear();
    _sfPathToIdLinux.clear();
    _linuxSfIdCounter = 1;
    sf2Presets.clear();
    for (int i = 0; i < 16; i++) {
      channels[i] = ChannelState();
    }
    visibleChannels.value = List.generate(16, (i) => i);
    dragToPlay.value = true;
    verticalPitchBendEnabled.value = true;
    horizontalVibratoEnabled.value = true;
    aftertouchDestCc.value = 1;
    notationFormat.value = 'Standard';
    pianoKeysToShow.value = 22;
    lockModePreference.value = ScaleLockMode.classic;
    jamEnabled.value = false;
    jamMasterChannel.value = 1;
    jamSlaveChannels.value = {0};
    jamScaleType.value = ScaleType.standard;
    _isInitialized = false;
    await init();
    stateNotifier.value++;
    toastNotifier.value = 'All preferences reset';
  }
}

class _ScaleInfo {
  final List<int> intervals;
  final String name;
  _ScaleInfo({required this.intervals, required this.name});
}
