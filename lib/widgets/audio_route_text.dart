// Localized words for the audio route (speaker, wired, Bluetooth).
//
// The platform reports a route as a kind plus a label. A Bluetooth label is
// the headset's own name and is shown as is; the other labels are English
// words from the native side, so they are replaced here by translated ones.

import '../l10n/app_localizations.dart';
import '../services/audio_route_service.dart';

/// What to call [route] in a sentence such as "… has not been measured".
///
/// A Bluetooth headset keeps the name it advertises. A wired headset gets a
/// translated phrase instead of the platform's English "Wired".
String audioRouteName(AppLocalizations l10n, AudioRoute route) {
  if (route.kind == 'wired') return l10n.audioRouteWired;
  return route.label;
}

/// The instructions to show before a latency measurement on [route].
///
/// The measurement listens for its own sweeps through the microphone. On the
/// speaker that just works; on headphones the microphone cannot hear the
/// sweeps through the air, so the person has to hold an earcup against it.
/// [speakerText] is the screen's own text for the speaker case.
String calibrationHint(
  AppLocalizations l10n,
  AudioRoute route, {
  required String speakerText,
}) {
  if (route.isBluetooth) return l10n.rehearsalRouteBluetoothHint;
  if (route.kind == 'wired') return l10n.rehearsalRouteWiredHint;
  return speakerText;
}
