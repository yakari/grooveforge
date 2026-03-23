import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:provider/provider.dart';

import 'services/audio_engine.dart';
import 'services/audio_graph.dart';
import 'services/cc_mapping_service.dart';
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
];

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
