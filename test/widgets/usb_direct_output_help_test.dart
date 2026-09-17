import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/l10n/app_localizations.dart';
import 'package:grooveforge/widgets/usb_direct_output_help.dart';

/// Opens the help the way Preferences does, at a given screen width and
/// language, and returns once it is on screen.
Future<void> _openHelp(WidgetTester tester, Size size, Locale locale) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showUsbDirectOutputHelp(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  const phone = Size(360, 740);
  const desktop = Size(1280, 800);

  testWidgets('phone: opens as a bottom sheet with every section', (tester) async {
    await _openHelp(tester, phone, const Locale('en'));

    expect(find.byType(BottomSheet), findsOneWidget);
    // Sections below the fold are built lazily; scrolling to each one also
    // proves the whole explanation is reachable on a small screen.
    for (final title in const [
      'The problem',
      'What this option does',
      'When it kicks in',
      'How to use it',
      'Good to know',
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('desktop: opens as a dialog and closes with "Got it"', (tester) async {
    await _openHelp(tester, desktop, const Locale('en'));

    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.byType(UsbDirectOutputHelp), findsNothing);
  });

  testWidgets('French phone layout renders without overflow', (tester) async {
    await _openHelp(tester, phone, const Locale('fr'));

    expect(find.text('Le problème'), findsOneWidget);
    expect(find.text('Compris'), findsOneWidget);
    // A RenderFlex overflow would have been reported as a test exception.
    expect(tester.takeException(), isNull);
  });
}
