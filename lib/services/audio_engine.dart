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
import 'package:audio_session/audio_session.dart';
import 'package:grooveforge/models/chord_detector.dart';
import 'package:grooveforge/services/audio_input_ffi.dart';

const String vocoderMode = 'vocoderMode';

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

enum GestureAction { none, pitchBend, vibrato, glissando }

/// Represents the current configuration and playback state for a single MIDI channel.
///
/// Holds the selected soundfont, bank, and program, as well as real-time performance
/// data like active notes, the last detected chord, and scale locking settings.
class ChannelState {
  /// Absolute path to the currently assigned Soundfont file. Null if none is loaded.
  String? soundfontPath;

  /// Currently assigned MIDI program (instrument patch), 0-127.
  int program = 0;

  /// Currently assigned MIDI bank (0 for Standard GM).
  int bank = 0;

  /// Set of physical keys currently being held down on this channel.
  final ValueNotifier<Set<int>> activeNotes = ValueNotifier({});

  /// The most recent intelligently identified chord configuration, used to derive scales.
  final ValueNotifier<ChordMatch?> lastChord = ValueNotifier(null);

  /// (Classic Mode) Whether this specific channel is frozen to its current scale.
  final ValueNotifier<bool> isScaleLocked = ValueNotifier(false);

  /// (Classic Mode) The specific scale degree template applied to this channel.
  final ValueNotifier<ScaleType> currentScaleType = ValueNotifier(
    ScaleType.standard,
  );

  /// Tracks shifted notes during snapping (Physical Key pressed -> Logical Note playing).
  /// This ensures that releasing the physical key sends a note-off for the shifted pitch.
  final Map<int, int> activeKeyMappings = {};

  /// Maps Logical Note -> Physical Key currently driving it.
  /// Resolves conflicts if two distinct physical keys snap to the exact same pitch.
  final Map<int, int> snappedKeyOwners = {};

  /// A visual reference set of pitch classes (0-11) allowed in the current active scale.
  final ValueNotifier<Set<int>?> validPitchClasses = ValueNotifier(null);

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

/// The core service managing MIDI routing, audio synthesis, and intelligent playback features.
///
/// [AudioEngine] acts as the central hub of GrooveForge, initializing the appropriate
/// synthesizer backend (FluidSynth on Linux, flutter_midi_pro on mobile), managing soundfonts,
/// processing incoming MIDI events, and handling advanced features like Smart Jam Mode
/// and scale synchronization across multiple channels.
class AudioEngine extends ChangeNotifier {
  /// The synthesizer library used for rendering audio on Mobile/macOS.
  final MidiPro _midiPro = MidiPro();
  bool _isInitialized = false;

  /// Human-readable status string used during the app splash screen startup sequence.
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

  bool _isVocoderActive = false;
  CcMappingService? ccMappingService;

  final ValueNotifier<String?> toastNotifier = ValueNotifier(null);
  final ValueNotifier<int> stateNotifier = ValueNotifier(0);

  final ValueNotifier<List<int>> visibleChannels = ValueNotifier(
    List.generate(16, (i) => i),
  );

  final ValueNotifier<bool> dragToPlay = ValueNotifier<bool>(true);
  // Gestures
  final verticalGestureAction = ValueNotifier<GestureAction>(
    GestureAction.vibrato,
  );
  final horizontalGestureAction = ValueNotifier<GestureAction>(
    GestureAction.glissando,
  );
  final ValueNotifier<bool> isGestureInProgress = ValueNotifier<bool>(false);
  int _activeGestureCount = 0;
  Timer? _healthCheckTimer;

  void updateGestureState(bool interacting) {
    if (interacting) {
      _activeGestureCount++;
    } else {
      _activeGestureCount--;
    }
    isGestureInProgress.value = _activeGestureCount > 0;
  }

  final ValueNotifier<int> aftertouchDestCc = ValueNotifier<int>(1);
  final ValueNotifier<bool> autoScrollEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<String?> lastSeenVersion = ValueNotifier(null);

  Future<void> markWelcomeAsSeen(String version) async {
    lastSeenVersion.value = version;
    await _saveState();
  }

  final ValueNotifier<String> notationFormat = ValueNotifier('Standard');
  final ValueNotifier<int> pianoKeysToShow = ValueNotifier(22);

  // --- Vocoder DSP State ---
  final ValueNotifier<int> vocoderWaveform = ValueNotifier(
    0,
  ); // 0=Saw, 1=Square
  final ValueNotifier<double> vocoderNoiseMix = ValueNotifier(
    0.05,
  ); // 0.0 - 1.0 (will scale to 2.0 in C)
  final ValueNotifier<double> vocoderEnvRelease = ValueNotifier(
    0.02,
  ); // 0.0 - 1.0 (will scale to 0.0001 - 0.05 in C)
  final ValueNotifier<double> vocoderBandwidth = ValueNotifier(
    0.2, // Default Q ~8.0
  );
  final ValueNotifier<int> vocoderInputDeviceIndex = ValueNotifier<int>(-1);
  final ValueNotifier<int> vocoderInputAndroidDeviceId = ValueNotifier<int>(-1);
  final ValueNotifier<int> vocoderOutputAndroidDeviceId = ValueNotifier<int>(
    -1,
  );
  final ValueNotifier<double> vocoderInputGain = ValueNotifier<double>(1.0);

  static const audioConfigChannel = MethodChannel(
    'com.grooveforge.grooveforge/audio_config',
  );

  void updateVocoderParameters() {
    AudioInputFFI().setVocoderParameters(
      waveform: vocoderWaveform.value,
      noiseMix: vocoderNoiseMix.value,
      envRelease: vocoderEnvRelease.value,
      bandwidth: vocoderBandwidth.value,
    );
    AudioInputFFI().setCaptureDeviceConfig(
      vocoderInputDeviceIndex.value,
      vocoderInputGain.value,
      vocoderInputAndroidDeviceId.value,
      vocoderOutputAndroidDeviceId.value,
    );
  }

  bool _isRestartingCapture = false;

  /// Restart the audio capture engine (stop + start with a short delay).
  /// This is the Dart-side equivalent of the "Refresh Mic" button.
  /// Guards against re-entrant calls (e.g. due to Fluidsynth Oboe recovery loops).
  Future<void> restartCapture() async {
    if (_isRestartingCapture) {
      debugPrint('GrooveForge: restartCapture skipped — already in progress.');
      return;
    }
    _isRestartingCapture = true;
    try {
      debugPrint('GrooveForge: Restarting audio capture from Dart...');
      AudioInputFFI().stopCapture();
      await Future.delayed(const Duration(milliseconds: 200));
      AudioInputFFI().startCapture();
      debugPrint('GrooveForge: Audio capture restarted.');
      // Cooldown: ignore any further restart requests for 500ms
      await Future.delayed(const Duration(milliseconds: 500));
    } finally {
      _isRestartingCapture = false;
    }
  }

  /// Listens for device plug/unplug events from Android's AudioDeviceCallback
  /// (registered in MainActivity.kt) and auto-resets stale device selections.
  void _setupAudioDeviceChangeListener() {
    audioConfigChannel.setMethodCallHandler((call) async {
      if (call.method == 'audioDevicesChanged') {
        debugPrint(
          'GrooveForge: Audio devices changed — checking for stale selections.',
        );
        await _resetDisconnectedDevices();
        notifyListeners();
      }
    });
  }

  /// If the currently selected input or output device ID is no longer in the
  /// enumerated device list, reset it to -1 (system default).
  Future<void> _resetDisconnectedDevices() async {
    try {
      final inputs = await getAndroidInputDevices();
      final inputIds = inputs.map((d) => d['id'] as int).toSet();
      final currentIn = vocoderInputAndroidDeviceId.value;
      if (currentIn != -1 && !inputIds.contains(currentIn)) {
        debugPrint(
          'GrooveForge: Input device $currentIn gone — resetting to default.',
        );
        vocoderInputAndroidDeviceId.value = -1;
      }

      final outputs = await getAndroidOutputDevices();
      final outputIds = outputs.map((d) => d['id'] as int).toSet();
      final currentOut = vocoderOutputAndroidDeviceId.value;
      if (currentOut != -1 && !outputIds.contains(currentOut)) {
        debugPrint(
          'GrooveForge: Output device $currentOut gone — resetting to default.',
        );
        vocoderOutputAndroidDeviceId.value = -1;
      }
    } catch (e) {
      debugPrint('GrooveForge: _resetDisconnectedDevices error: $e');
    }
  }

  Future<List<String>> getAvailableMicrophones() async {
    if (Platform.isAndroid) {
      try {
        final List<dynamic>? devices = await audioConfigChannel.invokeMethod(
          'getAudioInputDevices',
        );
        if (devices != null) {
          return devices.map((d) => "${d['name']} (ID: ${d['id']})").toList();
        }
      } catch (e) {
        debugPrint('Error getting Android audio devices: $e');
      }
    }

    final count = AudioInputFFI().getCaptureDeviceCount();
    final List<String> names = [];
    for (int i = 0; i < count; i++) {
      names.add(AudioInputFFI().getCaptureDeviceName(i));
    }
    return names;
  }

  Future<List<Map<String, dynamic>>> getAndroidInputDevices() async {
    if (!Platform.isAndroid) return [];
    try {
      final List<dynamic>? devices = await audioConfigChannel.invokeMethod(
        'getAudioInputDevices',
      );
      if (devices == null) return [];
      return devices
          .cast<Map<dynamic, dynamic>>()
          .map((d) => d.cast<String, dynamic>())
          .toList();
    } catch (e) {
      debugPrint('GrooveForge: getAndroidInputDevices error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAndroidOutputDevices() async {
    if (!Platform.isAndroid) return [];
    try {
      final List<dynamic>? devices = await audioConfigChannel.invokeMethod(
        'getAudioOutputDevices',
      );
      return devices
              ?.cast<Map<dynamic, dynamic>>()
              .map((d) => d.cast<String, dynamic>())
              .toList() ??
          [];
    } catch (e) {
      debugPrint('Error getting Android audio output devices: $e');
      return [];
    }
  }

  // --- Jam Mode State ---

  /// User preference selecting between independent channels (Classic) or central intelligence (Jam).
  final ValueNotifier<ScaleLockMode> lockModePreference = ValueNotifier(
    ScaleLockMode.jam,
  );

  /// Whether the Jam Mode feature is actively engaged overriding independent scales.
  final ValueNotifier<bool> jamEnabled = ValueNotifier(false);

  /// The channel driving the harmony. Its chords dictate the scale for the Slaves.
  final ValueNotifier<int> jamMasterChannel = ValueNotifier(1); // Default Ch 2

  /// Channels instructed to snap their outgoing note pitches to the Master's harmony.
  final ValueNotifier<Set<int>> jamSlaveChannels = ValueNotifier({
    0,
  }); // Default Ch 1

  /// The template scale (e.g. Minor Pentatonic) applied based on the Master's root note.
  final ValueNotifier<ScaleType> jamScaleType = ValueNotifier(
    ScaleType.standard,
  );

  /// User preference to display borders around scale-mapped key groups in Jam Mode.
  final ValueNotifier<bool> showJamModeBorders = ValueNotifier(true);

  /// User preference to color physical out-of-scale keys in red when mapped in Jam Mode.
  final ValueNotifier<bool> highlightWrongNotes = ValueNotifier(true);

  // --- Chord Release Logic ---

  /// Holds pending Timers used to apply the 30ms "wait-and-see" anti-flicker delay.
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
    } else {
      try {
        final session = await AudioSession.instance;
        await session.configure(
          AudioSessionConfiguration(
            avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
            avAudioSessionCategoryOptions:
                AVAudioSessionCategoryOptions.allowBluetooth |
                AVAudioSessionCategoryOptions.allowBluetoothA2dp,
            androidAudioAttributes: AndroidAudioAttributes(
              // Use `media` usage — `voiceCommunication` forces the Android
              // voice processing stack (echo canceller, NS, AGC) on the mix
              // side which adds significant latency on some devices.
              contentType: AndroidAudioContentType.music,
              usage: AndroidAudioUsage.media,
            ),
            androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
            androidWillPauseWhenDucked: true,
          ),
        );
      } catch (e) {
        debugPrint('Error configuring audio session for Bluetooth: $e');
      }
    }

    initStatus.value = 'Restoring saved state...';
    await _restoreState();

    initStatus.value = 'Checking bundled soundfonts...';
    await _ensureDefaultSoundfont();

    _isInitialized = true;
    initStatus.value = 'Ready';

    if (Platform.isAndroid) {
      _setupAudioDeviceChangeListener();
      // Check right now if any saved device is already stale
      _resetDisconnectedDevices();
    }

    pianoKeysToShow.addListener(_saveState);
    lockModePreference.addListener(_saveState);
    lockModePreference.addListener(_propagateJamScaleUpdate);
    jamEnabled.addListener(_saveState);
    jamEnabled.addListener(_propagateJamScaleUpdate);
    jamMasterChannel.addListener(_saveState);
    jamSlaveChannels.addListener(_saveState);
    jamScaleType.addListener(_propagateJamScaleUpdate);
    jamSlaveChannels.addListener(_propagateJamScaleUpdate);
    jamScaleType.addListener(_saveState);
    jamSlaveChannels.addListener(_saveState);
    showJamModeBorders.addListener(_saveState);
    highlightWrongNotes.addListener(_saveState);
    dragToPlay.addListener(_saveState);
    verticalGestureAction.addListener(_saveState);
    horizontalGestureAction.addListener(_saveState);
    aftertouchDestCc.addListener(_saveState);
    autoScrollEnabled.addListener(_saveState);
    notationFormat.addListener(_saveState);
    vocoderInputDeviceIndex.addListener(_saveState);
    vocoderInputDeviceIndex.addListener(updateVocoderParameters);
    vocoderInputDeviceIndex.addListener(restartCapture);
    vocoderInputAndroidDeviceId.addListener(_saveState);
    vocoderInputAndroidDeviceId.addListener(() {
      updateVocoderParameters();
      restartCapture();
    });
    vocoderOutputAndroidDeviceId.addListener(_saveState);
    vocoderOutputAndroidDeviceId.addListener(() {
      updateVocoderParameters();
      restartCapture();
    });
    vocoderInputGain.addListener(_saveState);
    vocoderInputGain.addListener(updateVocoderParameters);
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
    await _prefs!.setString(
      'verticalGestureAction',
      verticalGestureAction.value.name,
    );
    await _prefs!.setString(
      'horizontalGestureAction',
      horizontalGestureAction.value.name,
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
    await _prefs!.setBool('jam_show_borders', showJamModeBorders.value);
    await _prefs!.setBool('jam_highlight_wrong', highlightWrongNotes.value);
    await _prefs!.setBool('auto_scroll_enabled', autoScrollEnabled.value);
    await _prefs!.setString('last_seen_version', lastSeenVersion.value ?? "");
    await _prefs!.setInt(
      'vocoder_input_device_index',
      vocoderInputDeviceIndex.value,
    );
    await _prefs!.setInt(
      'vocoder_input_android_device_id',
      vocoderInputAndroidDeviceId.value,
    );
    await _prefs!.setInt(
      'vocoder_output_android_device_id',
      vocoderOutputAndroidDeviceId.value,
    );
    await _prefs!.setDouble('vocoder_input_gain', vocoderInputGain.value);
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
            (state.soundfontPath == vocoderMode ||
                loadedSoundfonts.contains(state.soundfontPath))) {
          _applyChannelInstrument(i);
        }
      }
    }

    _updateVocoderCaptureState();

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
    // Gestures
    final vActStr = _prefs!.getString('verticalGestureAction');
    if (vActStr != null) {
      verticalGestureAction.value = GestureAction.values.firstWhere(
        (e) => e.name == vActStr,
        orElse: () => GestureAction.vibrato,
      );
    }
    final hActStr = _prefs!.getString('horizontalGestureAction');
    if (hActStr != null) {
      horizontalGestureAction.value = GestureAction.values.firstWhere(
        (e) => e.name == hActStr,
        orElse: () => GestureAction.glissando,
      );
    }
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

    bool? savedShowJamModeBorders = _prefs!.getBool('jam_show_borders');
    if (savedShowJamModeBorders != null) {
      showJamModeBorders.value = savedShowJamModeBorders;
    }

    bool? savedHighlightWrongNotes = _prefs!.getBool('jam_highlight_wrong');
    if (savedHighlightWrongNotes != null) {
      highlightWrongNotes.value = savedHighlightWrongNotes;
    }

    autoScrollEnabled.value = _prefs!.getBool('auto_scroll_enabled') ?? false;

    lastSeenVersion.value = _prefs!.getString('last_seen_version');

    vocoderInputDeviceIndex.value =
        _prefs!.getInt('vocoder_input_device_index') ?? -1;
    vocoderInputAndroidDeviceId.value =
        _prefs!.getInt('vocoder_input_android_device_id') ?? -1;
    vocoderOutputAndroidDeviceId.value =
        _prefs!.getInt('vocoder_output_android_device_id') ?? -1;
    vocoderInputGain.value = _prefs!.getDouble('vocoder_input_gain') ?? 1.0;

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
    _updateVocoderCaptureState();
    await _saveState();
    toastNotifier.value = 'Unloaded Soundfont';
    stateNotifier.value++;
  }

  void assignSoundfontToChannel(int channel, String path) {
    if (channel < 0 || channel > 15) return;
    if (path != vocoderMode && !loadedSoundfonts.contains(path)) return;

    channels[channel].soundfontPath = path;
    _applyChannelInstrument(channel);
    _updateVocoderCaptureState();
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

  void _updateVocoderCaptureState() {
    bool requiresVocoder = channels.any((c) => c.soundfontPath == vocoderMode);
    if (requiresVocoder && !_isVocoderActive) {
      bool started = AudioInputFFI().startCapture();
      if (started) {
        _isVocoderActive = true;
        updateVocoderParameters();
        // Enable latency debug logging — monitor with: adb logcat -s GrooveForgeAudio
        AudioInputFFI().setLatencyDebug(enabled: true);
        debugPrint(
          'GrooveForge: Vocoder started — latency debug ON. '
          'Run: adb logcat -s GrooveForgeAudio',
        );
        _startHealthWatcher();
      }
    } else if (!requiresVocoder && _isVocoderActive) {
      _stopHealthWatcher();
      AudioInputFFI().setLatencyDebug(enabled: false);
      AudioInputFFI().stopCapture();
      _isVocoderActive = false;
    }
  }

  void _startHealthWatcher() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
      if (!_isVocoderActive) {
        timer.cancel();
        return;
      }
      if (AudioInputFFI().getEngineHealth() == 1) {
        debugPrint(
          'GrooveForge: Audio engine detected as UNHEALTHY. Triggering self-healing restart...',
        );
        restartCapture();
      }
    });
  }

  void _stopHealthWatcher() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  void _applyChannelInstrument(int channel) {
    ChannelState state = channels[channel];
    if (state.soundfontPath == null || state.soundfontPath == vocoderMode) {
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

  /// Interprets raw MIDI packets sent from external controllers or internal virtual keyboards.
  ///
  /// Routes Note On/Off commands to the synthesizer and forwards Control Change (CC)
  /// messages to the [CcMappingService] for potential remapping or app-level system actions.
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

  /// Plays a MIDI note, applying Scale Locking or Jam Mode snapping algorithms if active.
  ///
  /// **Snapping Architecture:**
  /// If snapping is required, the input [key] is transposed to the nearest valid note in the scale.
  /// This mapping (`input -> played`) is saved in `activeKeyMappings` so [stopNote]
  /// correctly stops the transposed pitch later even if the scale has moved on.
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

    // Route to Vocoder
    if (channels[channel].soundfontPath == vocoderMode) {
      AudioInputFFI().playNote(key: keyToPlay, velocity: velocity);
    } else {
      if (Platform.isLinux && _fluidSynthProcess != null) {
        _fluidSynthProcess!.stdin.writeln(
          'noteon $channel $keyToPlay $velocity',
        );
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
    }
    Future.microtask(() => _updateChordState(channel, isNoteOn: true));
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

      if (channels[channel].soundfontPath == vocoderMode) {
        AudioInputFFI().stopNote(key: keyToStop);
      } else {
        if (Platform.isLinux && _fluidSynthProcess != null) {
          _fluidSynthProcess!.stdin.writeln('noteoff $channel $keyToStop');
        } else {
          int sfId = _getSfIdForChannel(channel);
          if (sfId != -1) {
            _midiPro.stopNote(sfId: sfId, channel: channel, key: keyToStop);
          }
        }
      }
    }
    Future.microtask(() => _updateChordState(channel, isNoteOn: false));
  }

  /// Evaluates the currently held notes to mathematically determine the active chord structure.
  ///
  /// **Chord Stabilization Algorithm:**
  /// Uses a 50ms grace period (`_chordUpdateTimers`) during 'Note Off' events.
  /// This distinguishes between deliberate chord changes and accidental timing imperfections
  /// when releasing a physical chord (humans rarely lift 4 fingers simultaneously on the millisecond).
  /// If all notes are released, the system retains the last "Peak Chord" in memory so
  /// Jam Slaves don't lose their harmony context during brief silences.
  void _updateChordState(int channel, {required bool isNoteOn}) {
    // In Jam mode, we ONLY update the master channel's chord.
    // In Classic mode, we don't update if already locked.
    if (lockModePreference.value == ScaleLockMode.classic) {
      if (channels[channel].isScaleLocked.value) {
        return;
      }
    }

    // Cancel any pending "wait-and-see" timer
    _chordUpdateTimers[channel]?.cancel();
    _chordUpdateTimers[channel] = null;

    final notes = channels[channel].activeNotes.value;

    if (isNoteOn) {
      // Instant Enrichment (Note On)
      _performChordUpdate(channel, notes);
    } else {
      // Grace Period (Note Off)
      // We wait 50ms before updating the chord state.
      // This allows for non-simultaneous finger releases without the chord "flickering"
      // through simpler intermediary states (like a C5 when lifting a CMaj7).
      _chordUpdateTimers[channel] = Timer(const Duration(milliseconds: 50), () {
        final currentNotes = channels[channel].activeNotes.value;
        if (currentNotes.isNotEmpty) {
          // Deliberate Partial Release: Update identity
          _performChordUpdate(channel, currentNotes);
        } else {
          // Total Release: Keep peak chord identity (no-op)
          _lastNoteCounts[channel] = 0;
        }
        _chordUpdateTimers[channel] = null;
      });
    }
  }

  /// Physically runs the [ChordDetector] algorithm on the active notes and caches the result.
  ///
  /// If Jam Mode is active and this channel is the Master, it immediately calculates the
  /// new allowed pitch classes for the deduced scale and propagates them to all Slave channels.
  void _performChordUpdate(int channel, Set<int> notes) {
    final format =
        notationFormat.value.toLowerCase() == 'solfege'
            ? NotationFormat.solfege
            : NotationFormat.standard;
    final match = ChordDetector.identifyChord(notes, format: format);
    if (match != null) {
      channels[channel].lastChord.value = match;
    }
    _lastNoteCounts[channel] = notes.length;

    // Update validPitchClasses
    if (lockModePreference.value == ScaleLockMode.jam &&
        channel == jamMasterChannel.value) {
      if (match != null) {
        final info = _getScaleInfo(match, jamScaleType.value);
        final root = match.rootPc;
        final allowedPcs = info.intervals.map((i) => (root + i) % 12).toSet();

        // Update Master
        channels[channel].validPitchClasses.value = allowedPcs;

        // Propagate to active Slaves
        if (jamEnabled.value) {
          for (int slaveIdx in jamSlaveChannels.value) {
            if (slaveIdx >= 0 && slaveIdx < 16) {
              channels[slaveIdx].validPitchClasses.value = allowedPcs;
            }
          }
        }
      }
    } else if (lockModePreference.value == ScaleLockMode.classic) {
      if (match != null && channels[channel].isScaleLocked.value) {
        final info = _getScaleInfo(
          match,
          channels[channel].currentScaleType.value,
        );
        final root = match.rootPc;
        final allowedPcs = info.intervals.map((i) => (root + i) % 12).toSet();
        channels[channel].validPitchClasses.value = allowedPcs;
      }
    }
  }

  /// Forces a resynchronization of valid pitch classes across all channels.
  ///
  /// Called when Jam Mode settings change (e.g., Master channel swapped, target scale type changed).
  /// It clears locks on channels if Jam Mode is disabled, or explicitly forces slaves to adopt
  /// the new Master constraints.
  void _propagateJamScaleUpdate() {
    if (lockModePreference.value != ScaleLockMode.jam || !jamEnabled.value) {
      for (int i = 0; i < 16; i++) {
        if (lockModePreference.value != ScaleLockMode.classic ||
            !channels[i].isScaleLocked.value) {
          channels[i].validPitchClasses.value = null;
        } else {
          // If switching to classic and it is locked, recalculate its scale
          final match = channels[i].lastChord.value;
          if (match != null) {
            final info = _getScaleInfo(
              match,
              channels[i].currentScaleType.value,
            );
            final root = match.rootPc;
            channels[i].validPitchClasses.value =
                info.intervals.map((interv) => (root + interv) % 12).toSet();
          }
        }
      }
      stateNotifier.value++;
      return;
    }

    final masterIdx = jamMasterChannel.value;
    final masterChord = channels[masterIdx].lastChord.value;
    if (masterChord == null) {
      return;
    }

    final info = _getScaleInfo(masterChord, jamScaleType.value);
    final root = masterChord.rootPc;
    final allowedPcs = info.intervals.map((i) => (root + i) % 12).toSet();

    // Update Master
    channels[masterIdx].validPitchClasses.value = allowedPcs;

    // Propagate to all Slaves
    for (int slaveIdx in jamSlaveChannels.value) {
      if (slaveIdx >= 0 && slaveIdx < 16) {
        channels[slaveIdx].validPitchClasses.value = allowedPcs;
      }
    }

    // Force UI rebuild for slaves, in case the master chord changed to a relative scale
    // where pitch classes are identical but the root changed (so UI labels and rendering update).
    stateNotifier.value++;
  }

  /// Returns a descriptive name for the effective scale being used.
  String getDescriptiveScaleName(ChordMatch? chord, ScaleType type) {
    if (chord == null) {
      return type.name.toUpperCase();
    }
    return _getScaleInfo(chord, type).name;
  }

  /// Returns the name of the dominant note (typically the 5th) of the current scale.
  String? getDominantNoteName(ChordMatch? chord) {
    if (chord == null) {
      return null;
    }
    // Dominant is 7 semitones (perfect 5th) from root in most western scales used here
    final dominantPc = (chord.rootPc + 7) % 12;
    return _getNoteName(dominantPc);
  }

  String _getNoteName(int midiNote) {
    const noteNames = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    return noteNames[midiNote % 12];
  }

  /// Constructs a [_ScaleInfo] object containing intervals and a descriptive name for a given [ScaleType].
  ///
  /// This mapping dynamically adjusts based on the chord's quality (Major vs. Minor)
  /// and upper extensions. For example, a "Jazz" scale applied to a m7b5 chord
  /// will automatically yield a Locrian #2 scale instead of a standard Dorian or Aeolian.
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

  /// The core algorithm for quantizing "wrong" notes to harmony-correct notes.
  ///
  /// Given an [originalKey] that the user physically pressed, it calculates the closest
  /// mathematically valid MIDI note within the allowed [scaleType] built upon the [chord]'s root.
  /// It searches bidirectionally (up and down) semitone by semitone until a match is found.
  int _snapKeyToScale(int originalKey, ChordMatch chord, ScaleType scaleType) {
    final info = _getScaleInfo(chord, scaleType);
    final root = chord.rootPc;
    final allowedPcs = info.intervals.map((i) => (root + i) % 12).toSet();
    int bestDistance = 999;
    int bestKey = originalKey;
    for (int offset = 0; offset <= 12; offset++) {
      int downKey = originalKey - offset;
      if (allowedPcs.contains(downKey % 12)) {
        if (offset < bestDistance) {
          bestDistance = offset;
          bestKey = downKey;
        }
      }
      int upKey = originalKey + offset;
      if (allowedPcs.contains(upKey % 12)) {
        if (offset < bestDistance) {
          bestDistance = offset;
          bestKey = upKey;
        }
      }
      if (bestDistance < 999) {
        break;
      }
    }
    return bestKey;
  }

  /// Executes high-level application actions triggered by mapped hardware CC commands.
  ///
  /// Includes a 250ms debounce for toggle/cycle actions to prevent hardware
  /// drum pads from double-triggering continuous events. Actions include
  /// starting Jam Mode (1007), cycling scales (1008), or sweeping patches (1005).
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
    verticalGestureAction.value = GestureAction.vibrato;
    horizontalGestureAction.value = GestureAction.glissando;
    aftertouchDestCc.value = 1;
    notationFormat.value = 'Standard';
    pianoKeysToShow.value = 22;
    lockModePreference.value = ScaleLockMode.classic;
    jamEnabled.value = false;
    jamMasterChannel.value = 1;
    jamSlaveChannels.value = {0};
    jamScaleType.value = ScaleType.standard;
    vocoderInputDeviceIndex.value = -1;
    vocoderInputAndroidDeviceId.value = -1;
    vocoderInputGain.value = 1.0;
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
