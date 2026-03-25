import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:provider/provider.dart';

import 'services/audio_engine.dart';
import 'services/audio_graph.dart';
import 'services/cc_mapping_service.dart';
import 'services/drum_generator_engine.dart';
import 'services/drum_pattern_parser.dart';
import 'services/drum_pattern_registry.dart';
import 'services/looper_engine.dart';
import 'services/midi_service.dart';
import 'services/locale_provider.dart';
import 'services/patch_drag_controller.dart';
import 'services/project_service.dart';
import 'services/rack_state.dart';
import 'services/transport_engine.dart';
import 'services/vst_host_service.dart';
import 'screens/splash_screen.dart';
import 'l10n/app_localizations.dart';

/// Asset paths for all bundled `.gfdrum` drum pattern files.
const _kBundledGfdrumAssets = [
  // Rock / Pop / Funk
  'assets/drums/rock_basic.gfdrum',
  'assets/drums/funk_tight.gfdrum',
  'assets/drums/disco.gfdrum',
  // Jazz
  'assets/drums/jazz_swing.gfdrum',
  'assets/drums/jazz_halftime_shuffle.gfdrum',
  'assets/drums/jazz_waltz.gfdrum',
  // Latin
  'assets/drums/latin_bossa_nova.gfdrum',
  'assets/drums/latin_salsa.gfdrum',
  'assets/drums/latin_cha_cha.gfdrum',
  'assets/drums/samba_groove.gfdrum',
  // World
  'assets/drums/batucada.gfdrum',
  'assets/drums/batucada_directed.gfdrum',
  'assets/drums/afrobeat.gfdrum',
  'assets/drums/second_line.gfdrum',
  // Metal
  'assets/drums/metal.gfdrum',
  // Country
  'assets/drums/country.gfdrum',
  // Folk / Celtic
  'assets/drums/celtic_irish_jig.gfdrum',
  'assets/drums/celtic_breton_an_dro.gfdrum',
  'assets/drums/celtic_scottish_reel.gfdrum',
  'assets/drums/celtic_plinn.gfdrum',
  'assets/drums/celtic_reel.gfdrum',
  // Fanfare / March
  'assets/drums/fanfare_march.gfdrum',
  'assets/drums/festive_fanfare.gfdrum',
];

/// Asset paths for all bundled `.gfpd` plugin descriptor files.
const _kBundledGfpdAssets = [
  // Audio effect plugins.
  'assets/plugins/reverb.gfpd',
  'assets/plugins/delay.gfpd',
  'assets/plugins/wah.gfpd',
  'assets/plugins/eq.gfpd',
  'assets/plugins/compressor.gfpd',
  'assets/plugins/chorus.gfpd',
  // MIDI FX plugins.
  'assets/plugins/harmonizer.gfpd',
  'assets/plugins/chord_expand.gfpd',
  'assets/plugins/arpeggiator.gfpd',
  'assets/plugins/transposer.gfpd',
  'assets/plugins/velocity_curve.gfpd',
  'assets/plugins/gate.gfpd',
];

/// Loads and registers all bundled `.gfdrum` patterns before the first frame.
///
/// Each asset is parsed by [DrumPatternParser.parse] and added to
/// [DrumPatternRegistry.instance].  Failed assets are logged and skipped so
/// one malformed file cannot block the entire startup.
Future<void> _loadBundledGfdrumPatterns() async {
  for (final assetPath in _kBundledGfdrumAssets) {
    try {
      final yaml = await rootBundle.loadString(assetPath);
      // Derive the pattern id from the filename stem (e.g. 'rock_basic').
      final stem =
          assetPath.split('/').last.replaceAll('.gfdrum', '');
      final pattern = DrumPatternParser.parse(yaml, id: stem);
      if (pattern != null) {
        DrumPatternRegistry.instance.register(pattern);
      } else {
        debugPrint('[main] Failed to parse $assetPath');
      }
    } catch (e) {
      debugPrint('[main] Failed to load $assetPath: $e');
    }
  }
}

/// Load and register all bundled `.gfpd` plugins before the first frame.
///
/// Each asset is parsed by [GFDescriptorLoader.loadAndRegister], which adds
/// the resulting plugin to [GFPluginRegistry]. Built-in DSP node factories
/// ([GFDspNodeRegistry]) and MIDI node factories ([GFMidiNodeRegistry]) are
/// registered first so every node type referenced in the descriptors resolves.
Future<void> _loadBundledGfpdPlugins() async {
  GFDescriptorLoader.registerBuiltinNodes();
  GFDescriptorLoader.registerBuiltinMidiNodes();
  for (final assetPath in _kBundledGfpdAssets) {
    try {
      final yaml = await rootBundle.loadString(assetPath);
      GFDescriptorLoader.loadAndRegister(yaml);
    } catch (e) {
      debugPrint('[main] Failed to load $assetPath: $e');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _loadBundledGfdrumPatterns();
  await _loadBundledGfpdPlugins();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
        Provider<CcMappingService>(create: (_) => CcMappingService()),
        Provider<MidiService>(create: (_) => MidiService()),
        ChangeNotifierProvider<AudioEngine>(create: (_) => AudioEngine()),
        ChangeNotifierProvider<TransportEngine>(create: (_) => TransportEngine()),
        // AudioGraph must be registered before RackState so that RackState can
        // call audioGraph.onSlotRemoved when a slot is deleted.
        ChangeNotifierProvider<AudioGraph>(create: (_) => AudioGraph()),
        ChangeNotifierProvider<PatchDragController>(
          create: (_) => PatchDragController(),
        ),
        // LooperEngine needs TransportEngine for beat-clock access.
        ChangeNotifierProxyProvider<TransportEngine, LooperEngine>(
          create: (ctx) => LooperEngine(ctx.read<TransportEngine>()),
          update: (ctx, transport, previous) =>
              previous ?? LooperEngine(transport),
        ),
        // DrumGeneratorEngine needs both TransportEngine and AudioEngine.
        ChangeNotifierProxyProvider2<TransportEngine, AudioEngine,
            DrumGeneratorEngine>(
          create: (ctx) => DrumGeneratorEngine(
            ctx.read<TransportEngine>(),
            ctx.read<AudioEngine>(),
          ),
          update: (ctx, transport, engine, previous) =>
              previous ?? DrumGeneratorEngine(transport, engine),
        ),
        ChangeNotifierProxyProvider3<AudioEngine, TransportEngine, AudioGraph,
            RackState>(
          create: (ctx) => RackState(
            ctx.read<AudioEngine>(),
            ctx.read<TransportEngine>(),
            ctx.read<AudioGraph>(),
          ),
          update: (ctx, engine, transport, graph, previous) =>
              previous ?? RackState(engine, transport, graph),
        ),
        ChangeNotifierProvider<ProjectService>(create: (_) => ProjectService()),
        Provider<VstHostService>(
          create: (_) => VstHostService.instance,
          dispose: (_, svc) => svc.dispose(),
        ),
      ],
      child: const GrooveForgeApp(),
    ),
  );
}

class GrooveForgeApp extends StatelessWidget {
  const GrooveForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context);

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      locale: localeProvider.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
