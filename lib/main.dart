import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/audio_engine.dart';
import 'services/cc_mapping_service.dart';
import 'services/midi_service.dart';
import 'services/locale_provider.dart';
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
      title:
          'GrooveForge Synthesizer', // Title needs AppLocalizations, but standard MaterialApp `title` is not localized without `onGenerateTitle`.
      // It's often fine to leave `title` dynamic by using `onGenerateTitle` instead if needed. For now, it's just the OS task switcher title.
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
