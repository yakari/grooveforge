import '../models/plugin_instance.dart';
import '../models/vst3_plugin_instance.dart';
import 'audio_graph.dart';

// Re-export so callers always get Vst3PluginType from the same import.
export '../models/vst3_plugin_instance.dart' show Vst3PluginType;

/// Stub VstHostService for mobile and web platforms where VST3 hosting
/// is not supported. All methods are no-ops or throw immediately.
class VstHostService {
  static final VstHostService instance = VstHostService._();
  VstHostService._();

  bool get isSupported => false;

  Future<void> initialize() async {}

  Future<Vst3PluginInstance?> loadPlugin(
    String path,
    String slotId, {
    Vst3PluginType pluginType = Vst3PluginType.instrument,
  }) async => null;

  void unloadPlugin(String slotId) {}

  void noteOn(String slotId, int channel, int note, double velocity) {}

  void noteOff(String slotId, int channel, int note) {}

  void pitchBend(String slotId, int channel, double semitones) {}

  void controlChange(String slotId, int channel, int cc, int value) {}

  void setTransport({
    required double bpm,
    required int timeSigNum,
    required int timeSigDen,
    required bool isPlaying,
    required double positionInBeats,
    required int positionInSamples,
  }) {}

  bool setParameter(String slotId, int paramId, double normalized) => false;

  double getParameter(String slotId, int paramId) => 0.0;

  List<VstParamInfo> getParameters(String slotId) => [];

  Map<int, String> getUnitNames(String slotId) => {};

  Future<List<String>> scanPluginPaths(List<String> searchPaths) async => [];

  static List<String> get defaultSearchPaths => [];

  void startAudio() {}
  void stopAudio() {}

  bool openEditor(String slotId, {String title = 'Plugin Editor'}) => false;
  void closeEditor(String slotId) {}
  bool isEditorOpen(String slotId) => false;

  void syncAudioRouting(
    AudioGraph graph,
    List<PluginInstance> allPlugins, {
    Map<String, int> keyboardSfIds = const {},
  }) {}

  /// Stub: no-op — native GFPA DSP is not supported on this platform.
  void registerGfpaDsp(String slotId, String pluginId) {}

  /// Stub: no-op.
  void unregisterGfpaDsp(String slotId) {}

  /// Stub: no-op.
  void setGfpaDspParam(String slotId, String paramId, double physicalValue) {}

  /// Stub: no-op.
  void setGfpaDspBypass(String slotId, bool bypassed) {}

  void dispose() {}
}

/// Describes a single VST3 parameter (ID, display name, unit string, group).
class VstParamInfo {
  final int id;
  final String title;
  final String units;
  final int unitId;

  const VstParamInfo({
    required this.id,
    required this.title,
    required this.units,
    this.unitId = -1,
  });
}
