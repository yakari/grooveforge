import '../models/vst3_plugin_instance.dart';

/// Stub VstHostService for mobile and web platforms where VST3 hosting
/// is not supported. All methods are no-ops or throw immediately.
class VstHostService {
  static final VstHostService instance = VstHostService._();
  VstHostService._();

  bool get isSupported => false;

  Future<void> initialize() async {}

  Future<Vst3PluginInstance?> loadPlugin(String path, String slotId) async =>
      null;

  void unloadPlugin(String slotId) {}

  void noteOn(String slotId, int channel, int note, double velocity) {}

  void noteOff(String slotId, int channel, int note) {}

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
