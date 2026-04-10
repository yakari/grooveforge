import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:provider/provider.dart';
import '../models/vst3_plugin_instance.dart';
import '../plugins/gf_keyboard_plugin.dart';
import '../plugins/gf_jam_mode_plugin.dart';
import '../plugins/gf_stylophone_plugin.dart';
import '../plugins/gf_theremin_plugin.dart';
import '../plugins/gf_vocoder_plugin.dart';
import '../services/audio_engine.dart';
import '../services/audio_graph.dart';
import '../services/audio_looper_engine.dart';
import '../services/cc_mapping_service.dart';
import '../services/drum_generator_engine.dart';
import '../services/looper_engine.dart';
import '../services/project_service.dart';
import '../services/rack_state.dart';
import '../services/vst_host_service.dart';
import '../services/transport_engine.dart';
import 'rack_screen.dart';
import '../l10n/app_localizations.dart';

/// The initial launch screen of the application.
///
/// Displays the app logo and provides visual feedback while the core audio
/// components (like the soundfont synthesizers) initialize in the background.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  /// Initializes the core application services.
  ///
  /// This method waits briefly to ensure the splash screen UI renders, then delegates
  /// to [AudioEngine.init] to begin loading soundfonts and starting the audio thread.
  /// Upon completion, it smoothly transitions to the main [SynthesizerScreen].
  Future<void> _initializeApp() async {
    final engine = context.read<AudioEngine>();
    final rack = context.read<RackState>();
    final transport = context.read<TransportEngine>();
    final audioGraph = context.read<AudioGraph>();
    final looperEngine = context.read<LooperEngine>();
    final drumEngine = context.read<DrumGeneratorEngine>();

    // Wait for the very first frame to finish before starting the heavy lifting.
    await Future.delayed(const Duration(milliseconds: 100));
    await engine.init();

    // Register built-in GFPA plugins so GFpaPluginInstance slots can resolve
    // their runtime implementations from GFPluginRegistry.
    _registerBuiltinGfpaPlugins(engine);

    if (!mounted) return;
    engine.initStatus.value = 'Restoring rack state...';
    // Use the shared ProjectService instance from the Provider so that
    // rack_screen.dart reads the same currentProjectPath.
    final projectService = context.read<ProjectService>();
    // Give ProjectService a direct reference to the CC mapping service so it
    // can load/save mappings without going through engine.ccMappingService
    // (which is null until RackScreen.initState assigns it).
    projectService.ccMappingService = context.read<CcMappingService>();
    final audioLooper = context.read<AudioLooperEngine>();
    projectService.audioLooperEngine = audioLooper;
    // Also give VstHostService a reference for syncAudioRouting.
    VstHostService.instance.audioLooperEngine = audioLooper;
    // Set the WAV importer for desktop.  VstHostService conditionally exports
    // the desktop implementation which has access to dart:ffi for WAV import.
    if (!kIsWeb) {
      audioLooper.wavImporter = VstHostService.instance.importAudioLooperWavs;
    }

    // Load the last autosave (or initialise defaults) BEFORE wiring up the
    // autosave callbacks.  This prevents spurious autosaves that would fire
    // mid-load (e.g. audioGraph.notifyListeners fires before looperEngine is
    // restored), which would overwrite persisted loop data with an empty state.
    debugPrint('SplashScreen: Calling loadOrInitDefault');
    await projectService.loadOrInitDefault(
        rack, engine, transport, audioGraph, looperEngine);
    debugPrint('SplashScreen: loadOrInitDefault returned');

    // Register autosave callbacks only AFTER the initial project load so
    // that every subsequent mutation (new slots, cable changes, etc.) is
    // persisted, without risking a race condition during restore.
    rack.onChanged = () =>
        projectService.autosave(rack, engine, transport, audioGraph, looperEngine);
    audioGraph.addListener(
      () => projectService.autosave(
          rack, engine, transport, audioGraph, looperEngine),
    );
    // Autosave whenever a drum generator parameter changes (swing, humanise,
    // count-in, fill frequency, soundfont, pattern selection, active toggle).
    // DrumGeneratorEngine.markDirty() fires onChanged; the debounce inside
    // ProjectService.autosave() prevents thrashing during continuous slider drags.
    drumEngine.onChanged = () =>
        projectService.autosave(rack, engine, transport, audioGraph, looperEngine);
    // Autosave after a recording pass completes or is cleared.  We use the
    // dedicated onDataChanged hook instead of addListener because the latter
    // fires on every bar-boundary tick during playback (every ~10 ms), which
    // would thrash the disk with unnecessary writes.
    looperEngine.onDataChanged = () =>
        projectService.autosave(rack, engine, transport, audioGraph, looperEngine);
    // Autosave whenever CC mappings change (add/remove/swap rewrite).
    // Read from the Provider directly — engine.ccMappingService is null at
    // this point (it is assigned later in RackScreen.initState).
    if (!mounted) return;
    context.read<CcMappingService>().mappingsNotifier.addListener(
      () => projectService.autosave(
          rack, engine, transport, audioGraph, looperEngine),
    );
    // Autosave when audio looper recording completes or a clip is cleared.
    context.read<AudioLooperEngine>().onDataChanged = () =>
        projectService.autosave(rack, engine, transport, audioGraph, looperEngine);

    // Re-load any persisted VST3 plugins into the native host so their
    // parameters are accessible immediately (they are not auto-loaded on restore).
    if (!mounted) return;
    debugPrint('SplashScreen: initializing VstHostService');
    final vstSvc = context.read<VstHostService>();
    if (vstSvc.isSupported) {
      debugPrint('SplashScreen: vstSvc.initialize()');
      await vstSvc.initialize();
      for (final plugin in rack.plugins) {
        if (plugin is! Vst3PluginInstance || plugin.path.isEmpty) continue;
        engine.initStatus.value = 'Loading ${plugin.pluginName}…';
        debugPrint('SplashScreen: Loading VST3 ${plugin.pluginName}');
        await vstSvc.loadPlugin(plugin.path, plugin.id);
      }
      // Always start the ALSA/CoreAudio thread so the GF Keyboard (FluidSynth)
      // can render audio even when no VST3 plugins are in the rack. On Linux
      // the keyboard's render block is registered inside startAudio() and only
      // produces sound once that thread is running.
      debugPrint('SplashScreen: vstSvc.startAudio()');
      vstSvc.startAudio();
      // Re-apply saved cable routing now that the JACK thread is live.
      // The syncAudioRouting calls that fire during project load (from
      // audioGraph.loadFromJson and _readGfFile) return early because _host
      // is still null at that point.  This call wires everything up: GFPA
      // insert chains, master renders, audio looper sources, and capture modes.
      vstSvc.syncAudioRouting(audioGraph, rack.plugins);
    }

    if (!mounted) return;
    debugPrint('SplashScreen: pushing RackScreen');
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const RackScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  /// Register all first-party GFPA plugins with [GFPluginRegistry].
  ///
  /// Called once after [AudioEngine.init] so that plugin implementations that
  /// hold an [AudioEngine] reference are initialised with the live engine.
  void _registerBuiltinGfpaPlugins(AudioEngine engine) {
    final registry = GFPluginRegistry.instance;
    registry.register(GFKeyboardPlugin(engine));
    registry.register(GFVocoderPlugin(engine));
    registry.register(GFJamModePlugin(engine));
    // Fun instruments — each is a pure-Dart GFPA shell that routes to
    // the FluidSynth channel assigned to its rack slot.
    registry.register(GFStyloPhonePlugin());
    registry.register(GFThereminPlugin());
  }

  String _getLocalizedStatus(BuildContext context, String status) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return status;
    switch (status) {
      case 'Starting audio engine...':
        return l10n.splashStartingEngine;
      case 'Loading preferences...':
        return l10n.splashLoadingPreferences;
      case 'Starting FluidSynth backend...':
        return l10n.splashStartingFluidSynth;
      case 'Restoring saved state...':
        return l10n.splashRestoringState;
      case 'Restoring rack state...':
        return l10n.splashRestoringRack;
      case 'Checking bundled soundfonts...':
        return l10n.splashCheckingSoundfonts;
      case 'Extracting default soundfont...':
        return l10n.splashExtractingSoundfont;
      case 'Ready':
        return l10n.splashReady;
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A24),
      body: Stack(
        children: [
          // Background Image (Fullscreen)
          Positioned.fill(
            child: Image.asset(
              'splashscreen.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                // Fallback in case the asset isn't bundled or registered correctly yet
                return Container(
                  color: const Color(0xFF1A1A24),
                  child: const Center(
                    child: Icon(Icons.piano, size: 150, color: Colors.white),
                  ),
                );
              },
            ),
          ),
          // Semi-transparent overlay at the bottom for readability
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.5),
                  ],
                ),
              ),
            ),
          ),
          // Dynamic Progress Area
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 64.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      color: Colors.white70,
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Consumer<AudioEngine>(
                    builder: (context, engine, child) {
                      return ValueListenableBuilder<String>(
                        valueListenable: engine.initStatus,
                        builder: (context, status, child) {
                          return Text(
                            _getLocalizedStatus(context, status),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w500,
                              shadows: [
                                Shadow(
                                  blurRadius: 8.0,
                                  color: Colors.black,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
