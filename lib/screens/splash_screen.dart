import 'package:flutter/material.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:provider/provider.dart';
import '../models/vst3_plugin_instance.dart';
import '../plugins/gf_keyboard_plugin.dart';
import '../plugins/gf_jam_mode_plugin.dart';
import '../plugins/gf_vocoder_plugin.dart';
import '../services/audio_engine.dart';
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

    // Wait for the very first frame to finish before starting the heavy lifting.
    await Future.delayed(const Duration(milliseconds: 100));
    await engine.init();

    // Register built-in GFPA plugins so GFpaPluginInstance slots can resolve
    // their runtime implementations from GFPluginRegistry.
    _registerBuiltinGfpaPlugins(engine);

    if (!mounted) return;
    engine.initStatus.value = 'Restoring rack state...';
    final projectService = ProjectService();
    rack.onChanged = () => projectService.autosave(rack, engine, transport);
    debugPrint('SplashScreen: Calling loadOrInitDefault');
    await projectService.loadOrInitDefault(rack, engine, transport);
    debugPrint('SplashScreen: loadOrInitDefault returned');

    // Re-load any persisted VST3 plugins into the native host so their
    // parameters are accessible immediately (they are not auto-loaded on restore).
    if (!mounted) return;
    debugPrint('SplashScreen: initializing VstHostService');
    final vstSvc = context.read<VstHostService>();
    if (vstSvc.isSupported) {
      debugPrint('SplashScreen: vstSvc.initialize()');
      await vstSvc.initialize();
      bool anyVst3Loaded = false;
      for (final plugin in rack.plugins) {
        if (plugin is! Vst3PluginInstance || plugin.path.isEmpty) continue;
        engine.initStatus.value = 'Loading ${plugin.pluginName}…';
        debugPrint('SplashScreen: Loading VST3 ${plugin.pluginName}');
        final loaded = await vstSvc.loadPlugin(plugin.path, plugin.id);
        if (loaded != null) anyVst3Loaded = true;
      }
      if (anyVst3Loaded) {
        debugPrint('SplashScreen: vstSvc.startAudio()');
        vstSvc.startAudio();
      }
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
