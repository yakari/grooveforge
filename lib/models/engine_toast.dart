import '../l10n/app_localizations.dart';
import '../l10n/scale_names.dart';
import '../services/audio_engine.dart' show ScaleType;

/// A short notification the audio engine or the rack wants shown to the
/// player as a toast (a snackbar at the bottom of the rack screen).
///
/// Services such as `AudioEngine` and `RackState` have no `BuildContext`, so
/// they cannot pick the player's language themselves. They publish one of
/// these typed messages on `AudioEngine.toastNotifier` instead, carrying only
/// the raw arguments; the rack screen turns it into text with [localize].
///
/// Constructors are deliberately not `const`: const instances are
/// canonicalized, and `ValueNotifier` only notifies when the new value is a
/// different object. A fresh instance per event makes the same message
/// raised twice in a row (two loads of the same soundfont) show twice.
sealed class EngineToast {
  /// Base constructor for the concrete toast kinds.
  EngineToast();

  /// Returns the toast text in the language described by [l10n].
  String localize(AppLocalizations l10n);
}

/// A message that is already localized by the code that raised it.
///
/// Used by widgets (which do have a `BuildContext`) that share the engine's
/// toast channel, e.g. the system-volume or slot-swap feedback.
class LocalizedTextToast extends EngineToast {
  /// The final, already-translated text.
  final String text;

  /// Wraps already-translated [text].
  LocalizedTextToast(this.text);

  @override
  String localize(AppLocalizations l10n) => text;
}

/// The chosen audio output device was unplugged; playback fell back to the
/// system default output.
class OutputDeviceDisconnectedToast extends EngineToast {
  /// Creates the toast; it carries no arguments.
  OutputDeviceDisconnectedToast();

  @override
  String localize(AppLocalizations l10n) => l10n.toastOutputDeviceDisconnected;
}

/// A soundfont (.sf2) finished loading.
class SoundfontLoadedToast extends EngineToast {
  /// File name of the soundfont, shown as-is.
  final String fileName;

  /// Reports that [fileName] is now loaded.
  SoundfontLoadedToast(this.fileName);

  @override
  String localize(AppLocalizations l10n) =>
      l10n.toastSoundfontLoaded(fileName);
}

/// A soundfont could not be loaded.
class SoundfontLoadErrorToast extends EngineToast {
  /// Technical error description from the loader, shown verbatim.
  final String error;

  /// Reports a failed load with the underlying [error].
  SoundfontLoadErrorToast(this.error);

  @override
  String localize(AppLocalizations l10n) =>
      l10n.toastSoundfontLoadError(error);
}

/// A soundfont was removed from the loaded list.
class SoundfontUnloadedToast extends EngineToast {
  /// Creates the toast; it carries no arguments.
  SoundfontUnloadedToast();

  @override
  String localize(AppLocalizations l10n) => l10n.toastSoundfontUnloaded;
}

/// A MIDI controller button toggled scale lock on a channel.
class ScaleLockToggledToast extends EngineToast {
  /// MIDI channel as the player counts it, 1 to 16.
  final int channel;

  /// Whether scale lock is now on.
  final bool locked;

  /// Reports that scale lock on [channel] is now [locked].
  ScaleLockToggledToast({required this.channel, required this.locked});

  @override
  String localize(AppLocalizations l10n) => locked
      ? l10n.toastScaleLockOn(channel)
      : l10n.toastScaleLockOff(channel);
}

/// A MIDI controller button cycled the scale type of a channel.
class ScaleTypeChangedToast extends EngineToast {
  /// MIDI channel as the player counts it, 1 to 16.
  final int channel;

  /// The scale type the channel switched to.
  final ScaleType scaleType;

  /// Reports that [channel] now uses [scaleType].
  ScaleTypeChangedToast({required this.channel, required this.scaleType});

  /// Named as in the channel's scale menu, so the toast and the menu agree.
  @override
  String localize(AppLocalizations l10n) => l10n.toastScaleTypeChanged(
        scaleTypeLabel(l10n, scaleType).toUpperCase(),
        channel,
      );
}

/// A MIDI controller knob swept the program (the sound) of a channel.
class PatchSweepToast extends EngineToast {
  /// MIDI channel as the player counts it, 1 to 16.
  final int channel;

  /// The MIDI program number now selected, 0 to 127.
  final int program;

  /// Reports that [channel] switched to [program].
  PatchSweepToast({required this.channel, required this.program});

  @override
  String localize(AppLocalizations l10n) =>
      l10n.toastPatchSweep(program, channel);
}

/// A MIDI controller knob swept the sound bank of a channel.
class BankSweepToast extends EngineToast {
  /// MIDI channel as the player counts it, 1 to 16.
  final int channel;

  /// The bank number now selected.
  final int bank;

  /// Reports that [channel] switched to [bank].
  BankSweepToast({required this.channel, required this.bank});

  @override
  String localize(AppLocalizations l10n) => l10n.toastBankSweep(bank, channel);
}

/// Every preference was reset to its default value.
class PreferencesResetToast extends EngineToast {
  /// Creates the toast; it carries no arguments.
  PreferencesResetToast();

  @override
  String localize(AppLocalizations l10n) => l10n.toastPreferencesReset;
}

/// An effect slot was bypassed (skipped) or made active again.
class SlotBypassToast extends EngineToast {
  /// Display name of the slot, shown as-is.
  final String slotName;

  /// True when the slot is now bypassed, false when it is active again.
  final bool bypassed;

  /// Reports that [slotName] is now [bypassed] or active.
  SlotBypassToast({required this.slotName, required this.bypassed});

  @override
  String localize(AppLocalizations l10n) => bypassed
      ? l10n.toastBypassOn(slotName)
      : l10n.toastBypassOff(slotName);
}
