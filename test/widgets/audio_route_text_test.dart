// Tests for the words shown about the audio route before a latency
// measurement. The measurement listens through the microphone, so the
// instructions have to change with what the person is listening on.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/l10n/app_localizations.dart';
import 'package:grooveforge/services/audio_route_service.dart';
import 'package:grooveforge/widgets/audio_route_text.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('fr'));
  const wired = AudioRoute(key: 'wired', label: 'Wired', kind: 'wired');
  const bt = AudioRoute(key: 'bt:WH-1000XM4', label: 'WH-1000XM4', kind: 'bluetooth');

  test('the speaker keeps the screen\'s own text', () {
    expect(
      calibrationHint(l10n, AudioRoute.unknown, speakerText: 'speaker'),
      'speaker',
    );
  });

  test('wired headphones get the earcup instructions, not "use the speaker"', () {
    expect(
      calibrationHint(l10n, wired, speakerText: 'speaker'),
      l10n.rehearsalRouteWiredHint,
    );
  });

  test('Bluetooth keeps its own instructions', () {
    expect(
      calibrationHint(l10n, bt, speakerText: 'speaker'),
      l10n.rehearsalRouteBluetoothHint,
    );
  });

  test('a wired headset is named in the user\'s language', () {
    expect(audioRouteName(l10n, wired), 'Votre casque filaire');
  });

  test('a Bluetooth headset keeps the name it advertises', () {
    expect(audioRouteName(l10n, bt), 'WH-1000XM4');
  });
}
