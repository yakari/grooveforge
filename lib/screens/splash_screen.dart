import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:provider/provider.dart';
import '../models/audio_looper_plugin_instance.dart';
import '../models/drum_generator_plugin_instance.dart';
import '../models/gfpa_plugin_instance.dart';
import '../models/looper_plugin_instance.dart';
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
import '../services/native_instrument_controller.dart';
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
    // Set the WAV importer + exporter for native platforms.
    // VstHostService conditionally exports the desktop implementation which
    // has access to `dart:ffi` for the raw PCM I/O — the web stub has no-op
    // versions so `dart2js` / `dart2wasm` don't pull `dart:ffi` into the
    // web build's import tree.
    if (!kIsWeb) {
      audioLooper.wavImporter = VstHostService.instance.importAudioLooperWavs;
      audioLooper.wavExporter = VstHostService.instance.exportAudioLooperWavs;
    }

    // Load the last autosave (or initialise defaults) BEFORE wiring up the
    // autosave callbacks.  This prevents spurious autosaves that would fire
    // mid-load (e.g. audioGraph.notifyListeners fires before looperEngine is
    // restored), which would overwrite persisted loop data with an empty state.
    debugPrint('SplashScreen: Calling loadOrInitDefault');
    await projectService.loadOrInitDefault(
        rack, engine, transport, audioGraph, looperEngine);
    debugPrint('SplashScreen: loadOrInitDefault returned');

    // ── Eager slot initialisation ───────────────────────────────────────
    //
    // The rack is a lazy ReorderableListView.builder — off-screen slot
    // widgets never mount, so any audio-critical work that used to live in
    // `initState()` (session registration, native resource allocation, DSP
    // wiring) would be silently skipped until the user scrolled to the slot.
    // That turned CC-triggered actions into no-ops for below-the-fold slots.
    //
    // Fix: walk the restored rack here and bring every module up to a fully
    // playable state BEFORE the first frame ever renders. Each slot UI then
    // becomes purely cosmetic — mounting or unmounting the widget never
    // affects audio.
    for (final plugin in rack.plugins) {
      if (plugin is DrumGeneratorPluginInstance) {
        drumEngine.ensureSession(plugin.id, plugin);
      } else if (plugin is LooperPluginInstance) {
        looperEngine.ensureSession(plugin.id);
      } else if (plugin is GFpaPluginInstance) {
        // Global-singleton monophonic instruments + vocoder must exist on
        // the native side as soon as the project is loaded — the rack is
        // a lazy list, so the slot widget's initState may never fire. See
        // [NativeInstrumentController] for the full rationale.
        //
        // For the vocoder on Android, this registers `vocoder_bus_render`
        // on Oboe slot 102 so GFPA effects and the audio looper can cable
        // into it. On desktop the call is a no-op because playback goes
        // through the VstHost master-render list instead.
        switch (plugin.pluginId) {
          case 'com.grooveforge.stylophone':
            NativeInstrumentController.instance.onStylophoneAdded(plugin);
          case 'com.grooveforge.theremin':
            NativeInstrumentController.instance.onThereminAdded(plugin);
          case 'com.grooveforge.vocoder':
            NativeInstrumentController.instance.onVocoderAdded();
        }
      }
    }
    // Audio looper: finalizeLoad() iterates every pending-load slot and
    // calls createClip on the native host, which is only valid after the
    // VstHostService is initialised. It runs later, right after vstSvc.startAudio().

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
    // Wire audio looper bar-sync to transport beats.
    transport.onBeatAudioLooper = audioLooper.onTransportBeat;
    // Autosave when audio looper recording completes or a clip is cleared.
    audioLooper.onDataChanged = () =>
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
      //
      // `keyboardSfIds` must be passed explicitly on Android — without it
      // the Android branch can't resolve keyboard slots to their Oboe bus IDs
      // and any cable from a keyboard to the audio looper records silence.
      vstSvc.syncAudioRouting(
        audioGraph,
        rack.plugins,
        keyboardSfIds: rack.buildKeyboardSfIds(),
      );

      // Audio looper: now that the JACK host is live we can materialise the
      // pending clips (metadata was parsed earlier from the .gf file but
      // creation was deferred because the native host wasn't ready).
      if (audioLooper.hasPendingLoad) {
        await audioLooper.finalizeLoad();
      }
      // Also cover the (rare) case where a brand-new audio looper slot was
      // added by initDefaults — it will have a plugin entry but no pending
      // load and no clip yet. Loop and create any missing clips.
      for (final plugin in rack.plugins) {
        if (plugin is AudioLooperPluginInstance &&
            !audioLooper.clips.containsKey(plugin.id)) {
          audioLooper.createClip(plugin.id);
        }
      }

      // Audio effect descriptor slots (reverb, delay, EQ, …): create the
      // per-slot Dart plugin, register its native DSP handle and seed every
      // parameter into the native state. Must happen AFTER startAudio() so
      // the VST host is live. See RackState.initializeAudioEffects for the
      // full rationale.
      await rack.initializeAudioEffects();

      // Re-sync routing now that all native DSP handles exist AND the audio
      // looper clips have been created by `finalizeLoad` / `createClip`.
      // Three reasons this second sync is load-bearing:
      //   1. GFPA audio-effect inserts need the DSP handles registered in
      //      step `initializeAudioEffects` above to be wired into their
      //      source's insert chain.
      //   2. Audio looper bus sources can only be registered now that the
      //      native clips exist — the first sync ran before `finalizeLoad`
      //      / `createClip` and saw an empty `audioLooperEngine.clips` map.
      //   3. The earlier startup sync (when `initAndroidKeyboardSlots`
      //      fires `syncAudioRouting` from `loadFromJson`) also saw empty
      //      clips, so this is the first call that can actually push bus
      //      sources to a freshly created audio looper.
      //
      // `keyboardSfIds` is built here — see comment on the earlier call.
      vstSvc.syncAudioRouting(
        audioGraph,
        rack.plugins,
        keyboardSfIds: rack.buildKeyboardSfIds(),
      );
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
