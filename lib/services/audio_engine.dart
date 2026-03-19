import 'dart:io';
import 'dart:async';
import 'dart:math' show min;
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
import 'package:permission_handler/permission_handler.dart';

const String vocoderMode = 'vocoderMode';

/// A single GFPA-managed jam connection.
///
/// Multiple entries with different
/// [followerCh] values are supported — one per configured (master, target) pair
/// across all active GFPA Jam Mode slots.
class GFpaJamEntry {
  const GFpaJamEntry({
    required this.masterCh,
    required this.followerCh,
    required this.scaleType,
    required this.bassNoteMode,
    this.bpmLockBeats = 0,
  });

  /// 0-indexed master MIDI channel (chord/bass detection source).
  final int masterCh;

  /// 0-indexed follower MIDI channel (notes are snapped here).
  final int followerCh;

  final ScaleType scaleType;

  /// When true, uses the lowest active note on [masterCh] as the scale root
  /// instead of the chord-based detection.
  final bool bassNoteMode;

  /// Number of beats per scale-lock window. 0 = off (real-time), 1 = every
  /// beat, 2 = every 2 beats, 4 = every bar (4/4). The scale only updates
  /// when the elapsed wall-clock time since the last update exceeds one window.
  final int bpmLockBeats;
}

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

  /// Whether this channel is currently muted.
  ///
  /// When true, [AudioEngine.playNote] skips audio emission but still tracks
  /// UI state (active notes, chord detection). Note-off always goes through
  /// to prevent stuck notes when unmuting.
  final ValueNotifier<bool> isMuted = ValueNotifier(false);

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

  final Map<String, Map<int, Map<int, String>>> sf2Presets = {};
  final List<ChannelState> channels = List.generate(16, (i) => ChannelState());

  bool _isVocoderActive = false;
  CcMappingService? ccMappingService;

  final ValueNotifier<String?> toastNotifier = ValueNotifier(null);
  final ValueNotifier<int> stateNotifier = ValueNotifier(0);

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

  final ValueNotifier<int> pianoKeysToShow = ValueNotifier<int>(22); // 22 white keys = 37 total keys (3 octaves)
  final ValueNotifier<String> notationFormat = ValueNotifier<String>('Standard');
  final ValueNotifier<String?> lastSeenVersion = ValueNotifier(null);

  Future<void> markWelcomeAsSeen(String version) async {
    lastSeenVersion.value = version;
    await _saveState();
  }

  // --- Vocoder DSP State ---
  final ValueNotifier<int> vocoderWaveform = ValueNotifier(
    0,
  ); // 0=Saw, 1=Square, 2=Choral (glottal ensemble), 3=Neutral (pitch-only)
  final ValueNotifier<double> vocoderNoiseMix = ValueNotifier(
    0.05,
  ); // 0.0 - 1.0 (will scale to 2.0 in C)
  final ValueNotifier<double> vocoderEnvRelease = ValueNotifier(
    0.02,
  ); // 0.0 - 1.0 (will scale to 0.0001 - 0.05 in C)
  final ValueNotifier<double> vocoderBandwidth = ValueNotifier(
    0.2, // Default Q ~8.0
  );
  final ValueNotifier<double> vocoderGateThreshold = ValueNotifier(
    0.01, // 0.0 = gate off, typical live use: ~0.02-0.05
  );

  /// Callbacks injected by [RackState] so the engine can read transport state
  /// without a hard dependency on [TransportEngine].
  double Function() bpmProvider = () => 120.0;
  bool Function() isPlayingProvider = () => false;

  /// Called by [_handleSystemCommand] when a looper system action CC fires.
  ///
  /// Set by [RackScreen] so that looper engine calls can be dispatched from the
  /// audio MIDI pipeline without creating a hard dependency on [LooperEngine].
  /// Arguments: the system action code (1009-1013) and the CC value (0-127).
  void Function(int actionCode, int ccValue)? onLooperSystemAction;

  final ValueNotifier<int> vocoderInputDeviceIndex = ValueNotifier<int>(-1);
  final ValueNotifier<int> vocoderInputAndroidDeviceId = ValueNotifier<int>(-1);
  final ValueNotifier<int> vocoderOutputAndroidDeviceId = ValueNotifier<int>(
    -1,
  );
  final ValueNotifier<double> vocoderInputGain = ValueNotifier<double>(1.0);

  /// Master output gain sent to the FluidSynth process (`gain` command).
  ///
  /// Linux default is 3.0 — the previous 5.0 was too loud relative to VST
  /// output. Initialized before FluidSynth starts so the `-g` flag already
  /// uses the persisted value.
  /// Master output gain for the built-in FluidSynth engine (all platforms).
  ///
  /// Default is 3.0 — lower than the old hardcoded 5.0 which was too loud on
  /// Linux. The value is persisted and applied live without a soundfont reload.
  /// Restored from SharedPreferences on init; if no saved value exists the
  /// default is 3.0 on Linux and 5.0 on Android/other (matching prior
  /// behaviour for existing installs).
  final ValueNotifier<double> fluidSynthGain = ValueNotifier<double>(3.0);

  static const audioConfigChannel = MethodChannel(
    'com.grooveforge.grooveforge/audio_config',
  );

  /// Applies the current [fluidSynthGain] value to all active FluidSynth
  /// instances, regardless of platform.
  ///
  /// - **Linux**: sends a `gain <value>` command to the FluidSynth child
  ///   process via stdin — takes effect on the running engine immediately.
  /// - **Android / other**: calls [MidiPro.setGain] which routes through the
  ///   `flutter_midi_pro` method channel to `fluid_synth_set_gain()` on every
  ///   loaded synth instance.
  void applyFluidSynthGain() {
    if (!kIsWeb && Platform.isLinux) {
      AudioInputFFI().keyboardSetGain(fluidSynthGain.value);
    } else {
      MidiPro().setGain(fluidSynthGain.value);
    }
  }

  void updateVocoderParameters() {
    AudioInputFFI().setVocoderParameters(
      waveform: vocoderWaveform.value,
      noiseMix: vocoderNoiseMix.value,
      envRelease: vocoderEnvRelease.value,
      bandwidth: vocoderBandwidth.value,
    );
    AudioInputFFI().setGateThreshold(vocoderGateThreshold.value);
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
    if (!kIsWeb && Platform.isAndroid) {
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
    if (kIsWeb || !Platform.isAndroid) return [];
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
    if (kIsWeb || !Platform.isAndroid) return [];
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

  /// GFPA-managed jam entries, updated by [RackState] whenever a Jam Mode slot
  /// is added, removed, enabled, or reconfigured.
  ///
  /// Each GFPA Jam Mode slot has its own enabled flag and scale choice,
  /// applied in [playNote] independently of any global toggle.
  final ValueNotifier<List<GFpaJamEntry>> gfpaJamEntries = ValueNotifier([]);

  /// User preference to display borders around scale-mapped key groups in Jam Mode.
  final ValueNotifier<bool> showJamModeBorders = ValueNotifier(true);

  /// User preference to color physical out-of-scale keys in red when mapped in Jam Mode.
  final ValueNotifier<bool> highlightWrongNotes = ValueNotifier(true);

  // --- Chord Release Logic ---

  /// Holds pending Timers used to apply the 30ms "wait-and-see" anti-flicker delay.
  final List<Timer?> _chordUpdateTimers = List.generate(16, (i) => null);
  final List<int> _lastNoteCounts = List.generate(16, (i) => 0);

  /// Last known bass-root scale pitch-classes per follower channel.
  /// Keyed by follower channel index. Persists after master notes are released
  /// so walking-bass snapping still works between note changes.
  final Map<int, Set<int>> _lastBassScalePcs = {};

  /// BPM-locked scale pitch-classes per follower channel.
  /// Only updated when the beat-window elapsed time has expired.
  /// Used by both shading and snapping when [GFpaJamEntry.bpmLockBeats] > 0.
  final Map<int, Set<int>> _bpmLockedScalePcs = {};

  /// Wall-clock timestamp of the last scale update per follower channel,
  /// used to enforce the beat-window gap in BPM lock mode.
  final Map<int, DateTime> _lastScaleLockTime = {};

  SharedPreferences? _prefs;

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }
    initStatus.value = 'Loading preferences...';
    _prefs = await SharedPreferences.getInstance();
    
    if (!kIsWeb && Platform.isAndroid) {
      initStatus.value = 'Checking permissions...';
      try {
        final status = await Permission.microphone.request();
        if (status != PermissionStatus.granted) {
          debugPrint('GrooveForge: Microphone permission not granted: $status');
        }
      } catch (e) {
        debugPrint('GrooveForge: permission_handler failed on Android: $e');
      }
    }

    if (!kIsWeb) {
      if (Platform.isLinux) {
        initStatus.value = 'Starting FluidSynth backend...';
        // Use libfluidsynth directly (in-process, no audio driver) so that
        // the dart_vst_host ALSA thread can drive rendering via
        // keyboard_render_block() — same mechanism as Theremin/Stylophone.
        // keyboard_init() is idempotent: safe to call on re-initialisation.
        final ok = AudioInputFFI().keyboardInit(48000.0);
        if (ok == 1) {
          AudioInputFFI().keyboardSetGain(fluidSynthGain.value);
          debugPrint('AudioEngine: FluidSynth initialised via FFI');
        } else {
          debugPrint('AudioEngine: FluidSynth FFI init failed');
        }
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
    }

    initStatus.value = 'Restoring saved state...';
    await _restoreState();

    initStatus.value = 'Checking bundled soundfonts...';
    await _ensureDefaultSoundfont();

    _isInitialized = true;
    initStatus.value = 'Ready';

    if (!kIsWeb && Platform.isAndroid) {
      _setupAudioDeviceChangeListener();
      // Check right now if any saved device is already stale
      _resetDisconnectedDevices();
    }

    pianoKeysToShow.addListener(_saveState);
    gfpaJamEntries.addListener(_propagateJamScaleUpdate);
    showJamModeBorders.addListener(_saveState);
    highlightWrongNotes.addListener(_saveState);
    dragToPlay.addListener(_saveState);
    verticalGestureAction.addListener(_saveState);
    horizontalGestureAction.addListener(_saveState);
    aftertouchDestCc.addListener(_saveState);
    autoScrollEnabled.addListener(_saveState);
    notationFormat.addListener(_saveState);

    // Vocoder Listeners
    vocoderWaveform.addListener(_saveState);
    vocoderWaveform.addListener(updateVocoderParameters);
    vocoderNoiseMix.addListener(_saveState);
    vocoderNoiseMix.addListener(updateVocoderParameters);
    vocoderEnvRelease.addListener(_saveState);
    vocoderEnvRelease.addListener(updateVocoderParameters);
    vocoderBandwidth.addListener(_saveState);
    vocoderBandwidth.addListener(updateVocoderParameters);
    vocoderInputGain.addListener(_saveState);
    vocoderInputGain.addListener(updateVocoderParameters);
    vocoderGateThreshold.addListener(_saveState);
    vocoderGateThreshold.addListener(updateVocoderParameters);

    fluidSynthGain.addListener(_saveState);
    fluidSynthGain.addListener(applyFluidSynthGain);

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
  }

  Future<void> _ensureDefaultSoundfont() async {
    if (kIsWeb) {
      // Web: AudioContext requires a user gesture before it can run (browser
      // autoplay policy). WorkletSynthesizer initialises its AudioWorklet
      // thread only after the context is running, so awaiting soundfont load
      // here would hang the splash screen forever.
      //
      // Instead: pre-assign the asset path to every channel so the UI is
      // ready, then kick off the load in the background. The first time the
      // user plays a note the context resumes, the worklet initialises, and
      // subsequent notes produce sound. Any notes fired before the load
      // completes are silently dropped (sfId = -1 → no-op).
      const assetPath = 'assets/soundfonts/default.sf2';
      if (!loadedSoundfonts.contains(assetPath)) {
        for (int i = 0; i < 16; i++) {
          if (channels[i].soundfontPath == null ||
              channels[i].soundfontPath!.isEmpty) {
            channels[i].soundfontPath = assetPath;
          }
        }
        // Fire-and-forget: completes after user's first interaction resumes
        // the AudioContext.
        _loadWebSoundfontInBackground(assetPath);
      }
      return;
    }

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

  /// Loads the web default soundfont in the background.
  ///
  /// Called once during init without awaiting it. The load requires the
  /// AudioContext to be running (user gesture), so it may pend silently
  /// until the user first interacts with the app. Once the sfId is
  /// available the channel instrument assignments are applied and all
  /// queued notes can play.
  Future<void> _loadWebSoundfontInBackground(String assetPath) async {
    try {
      final sfId = await _midiPro.loadSoundfontAsset(assetPath: assetPath);
      if (sfId == -1) {
        debugPrint('GrooveForge Web: soundfont load returned -1 (JS bridge not ready)');
        return;
      }
      _sfPathToIdMobile[assetPath] = sfId;
      loadedSoundfonts.add(assetPath);
      for (int i = 0; i < 16; i++) {
        if (channels[i].soundfontPath == assetPath) {
          _applyChannelInstrument(i);
        }
      }
      stateNotifier.value++;
      debugPrint('GrooveForge Web: default soundfont loaded (sfId=$sfId)');
    } catch (e) {
      debugPrint('GrooveForge Web: error loading default soundfont: $e');
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
    await _prefs!.setBool('jam_show_borders', showJamModeBorders.value);
    await _prefs!.setBool('jam_highlight_wrong', highlightWrongNotes.value);
    await _prefs!.setBool('auto_scroll_enabled', autoScrollEnabled.value);
    await _prefs!.setString('last_seen_version', lastSeenVersion.value ?? "");

    // FluidSynth gain (Linux)
    await _prefs!.setDouble('fluidsynth_gain', fluidSynthGain.value);

    // Vocoder Parameters
    await _prefs!.setInt('vocoder_waveform', vocoderWaveform.value);
    await _prefs!.setDouble('vocoder_noise_mix', vocoderNoiseMix.value);
    await _prefs!.setDouble('vocoder_env_release', vocoderEnvRelease.value);
    await _prefs!.setDouble('vocoder_bandwidth', vocoderBandwidth.value);
    await _prefs!.setDouble('vocoder_input_gain', vocoderInputGain.value);
    await _prefs!.setDouble(
      'vocoder_gate_threshold',
      vocoderGateThreshold.value,
    );
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
  }

  Future<void> _restoreState() async {
    if (_prefs == null) {
      return;
    }

    // Restore FluidSynth gain — applied immediately via stdin if the process
    // is already running (only meaningful on Linux).
    fluidSynthGain.value =
        _prefs!.getDouble('fluidsynth_gain') ??
        (!kIsWeb && Platform.isLinux ? 3.0 : 5.0);

    // Restore Vocoder Parameters FIRST so capture starts with correct device
    vocoderWaveform.value = _prefs!.getInt('vocoder_waveform') ?? 0;
    vocoderNoiseMix.value = _prefs!.getDouble('vocoder_noise_mix') ?? 0.05;
    vocoderEnvRelease.value = _prefs!.getDouble('vocoder_env_release') ?? 0.02;
    vocoderBandwidth.value = _prefs!.getDouble('vocoder_bandwidth') ?? 0.2;
    vocoderInputGain.value = _prefs!.getDouble('vocoder_input_gain') ?? 1.0;
    vocoderGateThreshold.value =
        _prefs!.getDouble('vocoder_gate_threshold') ?? 0.01;
    vocoderInputDeviceIndex.value =
        _prefs!.getInt('vocoder_input_device_index') ?? -1;
    vocoderInputAndroidDeviceId.value =
        _prefs!.getInt('vocoder_input_android_device_id') ?? -1;
    vocoderOutputAndroidDeviceId.value =
        _prefs!.getInt('vocoder_output_android_device_id') ?? -1;
    // Apply logic to C engine immediately
    updateVocoderParameters();

    if (!kIsWeb) {
      // Native: reload soundfonts from their saved file paths and apply them.
      final List<String>? savedSfs =
          _prefs!.getStringList('loaded_soundfonts');
      final Map<String, String> migrationMap = {};
      if (savedSfs != null) {
        for (final path in savedSfs) {
          final file = File(path);
          if (file.existsSync()) {
            final migratedPath = await loadSoundfont(file, save: false);
            migrationMap[path] = migratedPath;
          }
        }
      }

      final List<String>? savedChannels =
          _prefs!.getStringList('channels_state');
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
    } else {
      // Web: no writable filesystem — restore only bank/program per channel.
      // The soundfont itself is loaded in _ensureDefaultSoundfont().
      final List<String>? savedChannels =
          _prefs!.getStringList('channels_state');
      if (savedChannels != null && savedChannels.length == 16) {
        for (int i = 0; i < 16; i++) {
          final state = ChannelState.fromJson(jsonDecode(savedChannels[i]));
          channels[i].program = state.program;
          channels[i].bank = state.bank;
        }
      }
    }

    _updateVocoderCaptureState();

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

    stateNotifier.value++;
  }

  Future<String> loadSoundfont(File soundfont, {bool save = true}) async {
    if (kIsWeb) {
      // File-based soundfont loading is not supported on web. Custom soundfonts
      // can be added in a future update via a web-compatible file-bytes path.
      debugPrint(
          'GrooveForge Web: loadSoundfont(File) is not supported on web.');
      return soundfont.path;
    }
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
        // keyboard_load_sf() returns the FluidSynth-assigned sfId directly,
        // replacing the old counter-based stub ID used with the subprocess.
        final sfId = AudioInputFFI().keyboardLoadSf(targetPath);
        if (sfId < 0) {
          throw Exception('Failed to load soundfont via FluidSynth: $targetPath');
        }
        _sfPathToIdLinux[targetPath] = sfId;
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
    if (!kIsWeb && Platform.isLinux) {
      int? sfId = _sfPathToIdLinux[path];
      if (sfId != null) {
        AudioInputFFI().keyboardUnloadSf(sfId);
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
      // Apply correct parameters (Device Index, gain, etc.) BEFORE starting capture
      updateVocoderParameters();

      bool started = AudioInputFFI().startCapture();
      if (started) {
        _isVocoderActive = true;
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
    if (!kIsWeb && Platform.isLinux) {
      int? sfId = _sfPathToIdLinux[state.soundfontPath!];
      if (sfId != null) {
        AudioInputFFI().keyboardProgramSelect(channel, sfId, state.bank, state.program);
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
    return (!kIsWeb && Platform.isLinux)
        ? (_sfPathToIdLinux[path] ?? -1)
        : (_sfPathToIdMobile[path] ?? -1);
  }

  /// Plays a short metronome click on GM percussion channel 9.
  /// [isDownbeat] selects a louder accent note (side-stick) vs a soft wood-block.
  void playMetronomeClick(bool isDownbeat) {
    const int percChannel = 9;
    // GM drum notes: 37 = side stick (downbeat accent), 76 = high wood block (regular beat).
    final int note = isDownbeat ? 37 : 76;
    final int velocity = isDownbeat ? 100 : 75;
    if (!kIsWeb && Platform.isLinux) {
      AudioInputFFI().keyboardNoteOn(percChannel, note, velocity);
      Future.delayed(const Duration(milliseconds: 40), () {
        AudioInputFFI().keyboardNoteOff(percChannel, note);
      });
    } else {
      // On mobile use any loaded soundfont; channel 9 follows GM percussion in most SF2 files.
      final int sfId = _sfPathToIdMobile.isNotEmpty ? _sfPathToIdMobile.values.first : -1;
      if (sfId != -1) {
        _midiPro.playNote(sfId: sfId, channel: percChannel, key: note, velocity: velocity);
        Future.delayed(const Duration(milliseconds: 40), () {
          _midiPro.stopNote(sfId: sfId, channel: percChannel, key: note);
        });
      }
    }
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
                // Looper (1009-1013) and mute (1014) actions are channel-agnostic:
                // fire once with the full mapping rather than once per channel.
                if (mapping.targetCc >= 1009) {
                  _handleSystemCommand(
                    mapping.targetCc,
                    channel,
                    data2,
                    muteChannels: mapping.muteChannels,
                  );
                } else if (mapping.targetChannel == -1) {
                  // Broadcast system action to all 16 channels.
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
  /// Updates the active-note set for a channel **without** routing to FluidSynth
  /// or flutter_midi_pro. Use for VST3 slots where audio is handled externally.
  void noteOnUiOnly({required int channel, required int key}) {
    final current = Set<int>.from(channels[channel].activeNotes.value);
    current.add(key);
    channels[channel].activeNotes.value = current;
  }

  void noteOffUiOnly({required int channel, required int key}) {
    final current = Set<int>.from(channels[channel].activeNotes.value);
    current.remove(key);
    channels[channel].activeNotes.value = current;
  }

  /// Returns the scale-snapped note for [channel] and [key] without any
  /// side effects (no audio routed, no UI state changed, no mapping stored).
  ///
  /// Applies GFPA Jam Mode snapping if an active jam entry covers [channel],
  /// or the classic per-channel scale lock if enabled. Returns [key] unchanged
  /// when no lock is active.
  ///
  /// Used by external MIDI routing in [RackScreen] to snap notes before they
  /// are forwarded through patch cables — keeping the same pitch correction
  /// that the on-screen piano and [playNote] apply.
  int snapNoteForChannel(int channel, int key) {
    // Classic per-channel scale lock (UI toggle on each GFK slot).
    if (channels[channel].isScaleLocked.value &&
        channels[channel].lastChord.value != null) {
      return _snapKeyToScale(
        key,
        channels[channel].lastChord.value!,
        channels[channel].currentScaleType.value,
      );
    }
    // GFPA Jam Mode — snap if this channel is a declared follower.
    for (final entry in gfpaJamEntries.value) {
      if (entry.followerCh == channel) {
        return _snapKeyToGfpaJam(key, entry);
      }
    }
    return key;
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
    if (channels[channel].isScaleLocked.value &&
        channels[channel].lastChord.value != null) {
      keyToPlay = _snapKeyToScale(
        key,
        channels[channel].lastChord.value!,
        channels[channel].currentScaleType.value,
      );
    }
    // GFPA Jam Mode — per-slot scale/mode
    else {
      for (final entry in gfpaJamEntries.value) {
        if (entry.followerCh == channel) {
          keyToPlay = _snapKeyToGfpaJam(key, entry);
          break;
        }
      }
    }

    if (keyToPlay != key) {
      channels[channel].activeKeyMappings[key] = keyToPlay;
    }

    int? currentOwner = channels[channel].snappedKeyOwners[keyToPlay];
    if (currentOwner != null && currentOwner != key) {
      if (!kIsWeb && Platform.isLinux) {
        AudioInputFFI().keyboardNoteOff(channel, keyToPlay);
      } else {
        int sfId = _getSfIdForChannel(channel);
        if (sfId != -1) {
          _midiPro.stopNote(sfId: sfId, channel: channel, key: keyToPlay);
        }
      }
    }

    channels[channel].snappedKeyOwners[keyToPlay] = key;

    // Skip audio emission when the channel is muted (UI tracking continues above).
    if (channels[channel].isMuted.value) return;

    // Route to Vocoder
    if (channels[channel].soundfontPath == vocoderMode) {
      AudioInputFFI().playNote(key: keyToPlay, velocity: velocity);
    } else {
      if (!kIsWeb && Platform.isLinux) {
        AudioInputFFI().keyboardNoteOn(channel, keyToPlay, velocity);
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
        if (!kIsWeb && Platform.isLinux) {
          AudioInputFFI().keyboardNoteOff(channel, keyToStop);
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
    // Don't update if the channel's scale is locked (classic per-channel lock).
    if (channels[channel].isScaleLocked.value) {
      return;
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

    // Classic per-channel scale lock: update this channel's own validPitchClasses.
    if (match != null && channels[channel].isScaleLocked.value) {
      final info = _getScaleInfo(
        match,
        channels[channel].currentScaleType.value,
      );
      final root = match.rootPc;
      final allowedPcs = info.intervals.map((i) => (root + i) % 12).toSet();
      channels[channel].validPitchClasses.value = allowedPcs;
    }

    // Propagate validPitchClasses to GFPA Jam Mode followers watching this channel
    for (final entry in gfpaJamEntries.value.where((e) => e.masterCh == channel)) {
      final followerCh = entry.followerCh;
      if (followerCh < 0 || followerCh >= 16) continue;
      if (entry.bassNoteMode) {
        // Bass note: root is the lowest currently active note
        if (notes.isNotEmpty) {
          final rootPc = notes.reduce(min) % 12;
          final intervals = _gfpaBassNoteIntervals(entry.scaleType);
          final pcs = intervals.map((i) => (rootPc + i) % 12).toSet();
          _lastBassScalePcs[followerCh] = pcs;
          if (_shouldUpdateLockedScale(entry, followerCh)) {
            channels[followerCh].validPitchClasses.value = pcs;
            _bpmLockedScalePcs[followerCh] = pcs;
          }
        }
        // When notes are empty keep the previous scale so the piano stays highlighted
      } else {
        // Chord mode: use the detected chord root
        final effectiveMatch = match ?? channels[channel].lastChord.value;
        if (effectiveMatch != null) {
          final info = _getScaleInfo(effectiveMatch, entry.scaleType);
          final allowedPcs =
              info.intervals.map((i) => (effectiveMatch.rootPc + i) % 12).toSet();
          if (_shouldUpdateLockedScale(entry, followerCh)) {
            channels[followerCh].validPitchClasses.value = allowedPcs;
            _bpmLockedScalePcs[followerCh] = allowedPcs;
          }
        }
      }
    }
  }

  /// Forces a resynchronization of valid pitch classes across all channels.
  ///
  /// Called when GFPA jam entries change (follower map, scale type, etc.).
  /// Clears non-follower channel constraints, then propagates scales to GFPA followers.
  void _propagateJamScaleUpdate() {
    final gfpaFollowers = gfpaJamEntries.value.map((e) => e.followerCh).toSet();
    // Clear per-follower caches for channels that are no longer followers.
    _lastBassScalePcs.removeWhere((ch, _) => !gfpaFollowers.contains(ch));
    _bpmLockedScalePcs.removeWhere((ch, _) => !gfpaFollowers.contains(ch));
    _lastScaleLockTime.removeWhere((ch, _) => !gfpaFollowers.contains(ch));

    // ── Clear non-GFPA-follower channels ──────────────────────────────────
    for (int i = 0; i < 16; i++) {
      if (gfpaFollowers.contains(i)) continue;
      if (!channels[i].isScaleLocked.value) {
        channels[i].validPitchClasses.value = null;
      } else {
        final match = channels[i].lastChord.value;
        if (match != null) {
          final info = _getScaleInfo(match, channels[i].currentScaleType.value);
          final root = match.rootPc;
          channels[i].validPitchClasses.value =
              info.intervals.map((interv) => (root + interv) % 12).toSet();
        }
      }
    }

    if (gfpaJamEntries.value.isEmpty) {
      stateNotifier.value++;
      return;
    }

    // ── GFPA Jam: propagate scale to GFPA follower channels ──────────────
    for (final entry in gfpaJamEntries.value) {
      final masterCh = entry.masterCh;
      final followerCh = entry.followerCh;
      if (followerCh < 0 || followerCh >= 16) continue;
      if (entry.bassNoteMode) {
        final active = channels[masterCh].activeNotes.value;
        if (active.isNotEmpty) {
          final rootPc = active.reduce(min) % 12;
          final intervals = _gfpaBassNoteIntervals(entry.scaleType);
          final pcs = intervals.map((i) => (rootPc + i) % 12).toSet();
          channels[followerCh].validPitchClasses.value = pcs;
          _lastBassScalePcs[followerCh] = pcs;
        } else {
          channels[followerCh].validPitchClasses.value = null;
        }
      } else {
        final masterChord = channels[masterCh].lastChord.value;
        if (masterChord != null) {
          final info = _getScaleInfo(masterChord, entry.scaleType);
          channels[followerCh].validPitchClasses.value =
              info.intervals.map((i) => (masterChord.rootPc + i) % 12).toSet();
        } else {
          channels[followerCh].validPitchClasses.value = null;
        }
      }
    }

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

  /// Returns true when it is safe to update the locked scale for [followerCh].
  ///
  /// When [entry.bpmLockBeats] > 0 and the transport is playing, the scale is
  /// frozen for one beat-window (measured by wall-clock). The window duration
  /// is `bpmLockBeats * 60 / bpm` seconds. Outside that window (or when the
  /// transport is stopped, or lock is off) this always returns true.
  bool _shouldUpdateLockedScale(GFpaJamEntry entry, int followerCh) {
    if (entry.bpmLockBeats <= 0 || !isPlayingProvider()) return true;
    final bpm = bpmProvider();
    if (bpm <= 0) return true;
    final windowMs = (entry.bpmLockBeats * 60000.0 / bpm).round();
    final last = _lastScaleLockTime[followerCh];
    if (last == null) {
      _lastScaleLockTime[followerCh] = DateTime.now();
      return true;
    }
    if (DateTime.now().difference(last).inMilliseconds >= windowMs) {
      _lastScaleLockTime[followerCh] = DateTime.now();
      return true;
    }
    return false;
  }

  /// Snaps [key] to the nearest in-scale pitch for a GFPA jam [entry].
  ///
  /// In chord mode the scale is derived from the chord detected on [entry.masterCh].
  /// In bass-note mode the lowest active note on [entry.masterCh] becomes the root.
  /// Returns the note that [key] would be snapped to on [channel] if it is a
  int _snapKeyToGfpaJam(int key, GFpaJamEntry entry) {
    final followerCh = entry.followerCh;
    final masterCh = entry.masterCh;
    Set<int> scalePcs;

    // BPM lock: when the transport is playing and a lock window is active,
    // snap to the last committed locked scale so snapping stays in sync with
    // the visual shading — both only update on beat-window boundaries.
    if (entry.bpmLockBeats > 0 && isPlayingProvider()) {
      final locked = _bpmLockedScalePcs[followerCh];
      if (locked != null && locked.isNotEmpty) {
        scalePcs = locked;
        // skip real-time computation, jump straight to snapping
        if (scalePcs.isEmpty) return key;
        int bestDistance = 999;
        int bestKey = key;
        for (int offset = 0; offset <= 12; offset++) {
          final down = key - offset;
          if (scalePcs.contains(down % 12) && offset < bestDistance) {
            bestDistance = offset;
            bestKey = down;
          }
          final up = key + offset;
          if (scalePcs.contains(up % 12) && offset < bestDistance) {
            bestDistance = offset;
            bestKey = up;
          }
          if (bestDistance < 999) break;
        }
        return bestKey;
      }
    }

    if (entry.bassNoteMode) {
      final active = channels[masterCh].activeNotes.value;
      if (active.isEmpty) {
        // When no master notes are held, use the last known bass scale so
        // notes can still be snapped to the most recently played root.
        final lastPcs = _lastBassScalePcs[followerCh];
        if (lastPcs == null || lastPcs.isEmpty) return key;
        scalePcs = lastPcs;
      } else {
        final bassNote = active.reduce(min);
        final rootPc = bassNote % 12;
        scalePcs = _gfpaBassNoteIntervals(entry.scaleType)
            .map((i) => (rootPc + i) % 12)
            .toSet();
      }
    } else {
      final masterChord = channels[masterCh].lastChord.value;
      if (masterChord == null) return key;
      final info = _getScaleInfo(masterChord, entry.scaleType);
      scalePcs = info.intervals
          .map((i) => (masterChord.rootPc + i) % 12)
          .toSet();
    }

    if (scalePcs.isEmpty) return key;

    // Snap to the nearest in-scale pitch class (same bidirectional search as
    // _snapKeyToScale but operating directly on pitch-class sets).
    int bestDistance = 999;
    int bestKey = key;
    for (int offset = 0; offset <= 12; offset++) {
      final down = key - offset;
      if (scalePcs.contains(down % 12) && offset < bestDistance) {
        bestDistance = offset;
        bestKey = down;
      }
      final up = key + offset;
      if (scalePcs.contains(up % 12) && offset < bestDistance) {
        bestDistance = offset;
        bestKey = up;
      }
      if (bestDistance < 999) break;
    }
    return bestKey;
  }

  /// Scale intervals for bass-note detection mode (no chord quality context).
  /// Mirrors GFJamModePlugin._intervalsFor — kept in sync manually.
  static List<int> _gfpaBassNoteIntervals(ScaleType type) {
    switch (type) {
      case ScaleType.standard:
      case ScaleType.classical:
      case ScaleType.jazz:
        return [0, 2, 4, 5, 7, 9, 11];
      case ScaleType.pentatonic:
      case ScaleType.asiatic:
        return [0, 2, 4, 7, 9];
      case ScaleType.blues:
      case ScaleType.rock:
        return [0, 2, 3, 4, 7, 9];
      case ScaleType.oriental:
        return [0, 1, 4, 5, 7, 8, 10];
      case ScaleType.dorian:
        return [0, 2, 3, 5, 7, 9, 10];
      case ScaleType.mixolydian:
        return [0, 2, 4, 5, 7, 9, 10];
      case ScaleType.harmonicMinor:
        return [0, 2, 3, 5, 7, 8, 11];
      case ScaleType.melodicMinor:
        return [0, 2, 3, 5, 7, 9, 11];
      case ScaleType.wholeTone:
        return [0, 2, 4, 6, 8, 10];
      case ScaleType.diminished:
        return [0, 1, 3, 4, 6, 7, 9, 10];
    }
  }

  /// Executes high-level application actions triggered by mapped hardware CC commands.
  ///
  /// Includes a 250ms debounce for toggle/cycle actions to prevent hardware
  /// drum pads from double-triggering continuous events. Actions include
  /// starting Jam Mode (1007), cycling scales (1008), or sweeping patches (1005).
  /// Dispatches a resolved system action coming from a CC mapping.
  ///
  /// [targetAction] is the system action code (1001-1014).
  /// [incomingChannel] is the MIDI channel on which the original CC arrived (0-15).
  /// [value] is the raw CC value (0-127).
  /// [muteChannels] carries the set of channels to toggle for action 1014;
  /// ignored for all other action codes.
  void _handleSystemCommand(
    int targetAction,
    int incomingChannel,
    int value, {
    Set<int>? muteChannels,
  }) {
    // ── Looper actions (1009-1013): delegate to LooperEngine via callback ──
    if (targetAction >= 1009 && targetAction <= 1013) {
      onLooperSystemAction?.call(targetAction, value);
      return;
    }

    // ── Channel mute/unmute action (1014) ───────────────────────────────────
    if (targetAction == 1014) {
      // Toggle the muted state for every channel listed in the mapping.
      for (final ch in muteChannels ?? <int>{}) {
        if (ch >= 0 && ch < channels.length) {
          channels[ch].isMuted.value = !channels[ch].isMuted.value;
        }
      }
      return;
    }

    if ([1001, 1002, 1003, 1004, 1007, 1008].contains(targetAction)) {
      String debounceKey = '${targetAction}_$incomingChannel';
      int now = DateTime.now().millisecondsSinceEpoch;
      int lastTime = (_prefs?.getInt('last_sys_cmd_$debounceKey')) ?? 0;
      if (now - lastTime < 250) {
        return;
      }
      _prefs?.setInt('last_sys_cmd_$debounceKey', now);

      if (targetAction == 1007) {
        channels[incomingChannel].isScaleLocked.value =
            !channels[incomingChannel].isScaleLocked.value;
        toastNotifier.value =
            'Scale Lock [Ch $incomingChannel]: ${channels[incomingChannel].isScaleLocked.value ? "ON" : "OFF"}';
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
        final currentTypes = ScaleType.values;
        int nextIndex =
            (channels[incomingChannel].currentScaleType.value.index + 1) %
            currentTypes.length;
        channels[incomingChannel].currentScaleType.value =
            currentTypes[nextIndex];
        toastNotifier.value =
            'Scale Type [Ch $incomingChannel]: ${currentTypes[nextIndex].name}';
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
    // When the channel is running the vocoder DSP, forward CC to the native C
    // engine instead of FluidSynth — the C oscillator handles CC#1 (vibrato).
    if (channels[channel].soundfontPath == vocoderMode) {
      AudioInputFFI().controlChange(controller, value);
    } else {
      _sendControlChange(channel: channel, controller: controller, value: value);
    }
  }

  void setPitchBend({required int channel, required int value}) {
    // When the channel is running the vocoder DSP, route pitch bend to the
    // native C oscillator rather than FluidSynth — the C engine owns those voices.
    if (channels[channel].soundfontPath == vocoderMode) {
      AudioInputFFI().pitchBend(value);
    } else {
      _sendPitchBend(channel: channel, value: value);
    }
  }

  void _sendControlChange({
    required int channel,
    required int controller,
    required int value,
  }) {
    if (!kIsWeb && Platform.isLinux) {
      AudioInputFFI().keyboardControlChange(channel, controller, value);
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
    if (!kIsWeb && Platform.isLinux) {
      AudioInputFFI().keyboardPitchBend(channel, value);
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
    sf2Presets.clear();
    for (int i = 0; i < 16; i++) {
      channels[i] = ChannelState();
    }
    dragToPlay.value = true;
    verticalGestureAction.value = GestureAction.vibrato;
    horizontalGestureAction.value = GestureAction.glissando;
    aftertouchDestCc.value = 1;
    notationFormat.value = 'Standard';
    pianoKeysToShow.value = 22;
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
