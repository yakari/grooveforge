import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/audio_engine.dart';
import 'services/cc_mapping_service.dart';
import 'services/midi_service.dart';
import 'services/locale_provider.dart';
import 'services/project_service.dart';
import 'services/rack_state.dart';
import 'services/vst_host_service.dart';
import 'screens/splash_screen.dart';
import 'l10n/app_localizations.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
        Provider<CcMappingService>(create: (_) => CcMappingService()),
        Provider<MidiService>(create: (_) => MidiService()),
        ChangeNotifierProvider<AudioEngine>(create: (_) => AudioEngine()),
        ChangeNotifierProxyProvider<AudioEngine, RackState>(
          create: (ctx) => RackState(ctx.read<AudioEngine>()),
          update: (ctx, engine, previous) => previous ?? RackState(engine),
        ),
        Provider<ProjectService>(create: (_) => ProjectService()),
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
