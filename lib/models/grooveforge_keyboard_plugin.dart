import 'plugin_instance.dart';
import 'plugin_role.dart';

/// The built-in GrooveForge Keyboard plugin, available on all platforms.
///
/// Wraps the existing FluidSynth + vocoder synthesizer backend. Each instance
/// represents one rack slot with its own MIDI channel, soundfont, bank/patch,
/// master/slave Jam role, and vocoder settings.
///
/// The vocoder DSP itself is a global singleton (one C engine); however, each
/// plugin instance stores its own vocoder parameter set so that settings are
/// preserved per slot in .gf project files. The active slot's settings are
/// applied to the engine whenever the slot enters vocoder mode.
class GrooveForgeKeyboardPlugin implements PluginInstance {
  @override
  final String id;

  @override
  int midiChannel; // 1-16

  @override
  PluginRole role;

  /// Absolute path to the loaded .sf2 file, 'vocoderMode', or null (default).
  String? soundfontPath;

  int bank;
  int program;

  // --- Vocoder settings (only active when soundfontPath == 'vocoderMode') ---
  int vocoderWaveform;
  double vocoderNoiseMix;
  double vocoderEnvRelease;
  double vocoderBandwidth;
  double vocoderGateThreshold;
  double vocoderInputGain;

  GrooveForgeKeyboardPlugin({
    required this.id,
    required this.midiChannel,
    required this.role,
    this.soundfontPath,
    this.bank = 0,
    this.program = 0,
    this.vocoderWaveform = 0,
    this.vocoderNoiseMix = 0.05,
    this.vocoderEnvRelease = 0.02,
    this.vocoderBandwidth = 0.2,
    this.vocoderGateThreshold = 0.01,
    this.vocoderInputGain = 1.0,
  });

  bool get isVocoderMode => soundfontPath == 'vocoderMode';

  @override
  String get displayName => 'GrooveForge Keyboard';

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'grooveforge_keyboard',
    'midiChannel': midiChannel,
    'role': role.name,
    'state': {
      'soundfontPath': soundfontPath,
      'bank': bank,
      'program': program,
      'vocoderWaveform': vocoderWaveform,
      'vocoderNoiseMix': vocoderNoiseMix,
      'vocoderEnvRelease': vocoderEnvRelease,
      'vocoderBandwidth': vocoderBandwidth,
      'vocoderGateThreshold': vocoderGateThreshold,
      'vocoderInputGain': vocoderInputGain,
    },
  };

  factory GrooveForgeKeyboardPlugin.fromJson(Map<String, dynamic> json) {
    final state = (json['state'] as Map<String, dynamic>?) ?? {};
    return GrooveForgeKeyboardPlugin(
      id: json['id'] as String,
      midiChannel: (json['midiChannel'] as num?)?.toInt() ?? 1,
      role: PluginRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => PluginRole.slave,
      ),
      soundfontPath: state['soundfontPath'] as String?,
      bank: (state['bank'] as num?)?.toInt() ?? 0,
      program: (state['program'] as num?)?.toInt() ?? 0,
      vocoderWaveform: (state['vocoderWaveform'] as num?)?.toInt() ?? 0,
      vocoderNoiseMix: (state['vocoderNoiseMix'] as num?)?.toDouble() ?? 0.05,
      vocoderEnvRelease:
          (state['vocoderEnvRelease'] as num?)?.toDouble() ?? 0.02,
      vocoderBandwidth:
          (state['vocoderBandwidth'] as num?)?.toDouble() ?? 0.2,
      vocoderGateThreshold:
          (state['vocoderGateThreshold'] as num?)?.toDouble() ?? 0.01,
      vocoderInputGain:
          (state['vocoderInputGain'] as num?)?.toDouble() ?? 1.0,
    );
  }

  GrooveForgeKeyboardPlugin copyWith({
    String? id,
    int? midiChannel,
    PluginRole? role,
    String? soundfontPath,
    bool clearSoundfont = false,
    int? bank,
    int? program,
    int? vocoderWaveform,
    double? vocoderNoiseMix,
    double? vocoderEnvRelease,
    double? vocoderBandwidth,
    double? vocoderGateThreshold,
    double? vocoderInputGain,
  }) => GrooveForgeKeyboardPlugin(
    id: id ?? this.id,
    midiChannel: midiChannel ?? this.midiChannel,
    role: role ?? this.role,
    soundfontPath:
        clearSoundfont ? null : (soundfontPath ?? this.soundfontPath),
    bank: bank ?? this.bank,
    program: program ?? this.program,
    vocoderWaveform: vocoderWaveform ?? this.vocoderWaveform,
    vocoderNoiseMix: vocoderNoiseMix ?? this.vocoderNoiseMix,
    vocoderEnvRelease: vocoderEnvRelease ?? this.vocoderEnvRelease,
    vocoderBandwidth: vocoderBandwidth ?? this.vocoderBandwidth,
    vocoderGateThreshold: vocoderGateThreshold ?? this.vocoderGateThreshold,
    vocoderInputGain: vocoderInputGain ?? this.vocoderInputGain,
  );
}
