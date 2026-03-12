import 'plugin_instance.dart';

/// The built-in GrooveForge Keyboard plugin, available on all platforms.
///
/// Wraps the existing FluidSynth synthesizer backend. Each instance represents
/// one rack slot with its own MIDI channel, soundfont, bank, and program.
///
/// Vocoder mode has been removed from keyboard slots — use the standalone
/// GFPA Vocoder plugin ([com.grooveforge.vocoder]) instead.
class GrooveForgeKeyboardPlugin implements PluginInstance {
  @override
  final String id;

  @override
  int midiChannel; // 1-16

  /// Absolute path to the loaded .sf2 file, or null (default soundfont).
  String? soundfontPath;

  int bank;
  int program;

  GrooveForgeKeyboardPlugin({
    required this.id,
    required this.midiChannel,
    this.soundfontPath,
    this.bank = 0,
    this.program = 0,
  });

  @override
  String get displayName => 'GrooveForge Keyboard';

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'grooveforge_keyboard',
    'midiChannel': midiChannel,
    'state': {
      'soundfontPath': soundfontPath,
      'bank': bank,
      'program': program,
    },
  };

  factory GrooveForgeKeyboardPlugin.fromJson(Map<String, dynamic> json) {
    final state = (json['state'] as Map<String, dynamic>?) ?? {};
    final sf = state['soundfontPath'] as String?;
    return GrooveForgeKeyboardPlugin(
      id: json['id'] as String,
      midiChannel: (json['midiChannel'] as num?)?.toInt() ?? 1,
      // Old .gf files may have 'vocoderMode' here — silently migrate to null
      // since vocoder mode is no longer supported on keyboard slots.
      soundfontPath: (sf == 'vocoderMode') ? null : sf,
      bank: (state['bank'] as num?)?.toInt() ?? 0,
      program: (state['program'] as num?)?.toInt() ?? 0,
    );
  }

  GrooveForgeKeyboardPlugin copyWith({
    String? id,
    int? midiChannel,
    String? soundfontPath,
    bool clearSoundfont = false,
    int? bank,
    int? program,
  }) => GrooveForgeKeyboardPlugin(
    id: id ?? this.id,
    midiChannel: midiChannel ?? this.midiChannel,
    soundfontPath:
        clearSoundfont ? null : (soundfontPath ?? this.soundfontPath),
    bank: bank ?? this.bank,
    program: program ?? this.program,
  );
}
