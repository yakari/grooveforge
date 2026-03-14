import '../services/audio_engine.dart';

/// Determines the physical height of the on-screen piano keys for a slot.
///
/// Larger options make the keys taller and easier to tap on small screens
/// (phones, tablets in portrait mode). The default [normal] (150 px) gives
/// comfortable key targets on most devices.
enum KeyHeightOption {
  /// Small: 110 px — compact layout, fits more content on screen.
  small,

  /// Normal: 150 px — the default; comfortable on tablets and large phones.
  normal,

  /// Large: 175 px — recommended for phones or users who prefer bigger targets.
  large,

  /// Extra-large: 200 px — maximum height; ideal for small phones with fingers.
  extraLarge,
}

/// Extension providing the display pixel height for each [KeyHeightOption].
extension KeyHeightPixels on KeyHeightOption {
  /// The piano area height in logical pixels corresponding to this option.
  double get pianoPixelHeight => switch (this) {
        KeyHeightOption.small => 110.0,
        KeyHeightOption.normal => 150.0,
        KeyHeightOption.large => 175.0,
        KeyHeightOption.extraLarge => 200.0,
      };
}

/// Per-slot keyboard display and expression configuration.
///
/// Overrides the global Preferences values for a single rack slot. Any field
/// left as `null` falls back to the corresponding global setting from
/// [AudioEngine]. [keyHeightOption] always has an explicit value (defaulting
/// to [KeyHeightOption.normal]) because height is not part of global prefs.
///
/// Instances are immutable; use [copyWith] to produce modified copies, and
/// [toJson] / [fromJson] for project-file persistence.
class KeyboardDisplayConfig {
  /// Number of white keys to display at once. Null → use global pref.
  ///
  /// Valid values (white-key counts): 15, 22, 29, 52.
  final int? keysToShow;

  /// Vertical swipe gesture action for this slot. Null → use global pref.
  final GestureAction? verticalGestureAction;

  /// Horizontal swipe gesture action for this slot. Null → use global pref.
  final GestureAction? horizontalGestureAction;

  /// CC number to which vertical-gesture (vibrato-mode) pressure is routed.
  /// Null → use [AudioEngine.aftertouchDestCc].
  final int? aftertouchDestCc;

  /// Physical height of the piano keys area for this slot.
  ///
  /// Always explicit; there is no global default for key height, so this field
  /// defaults to [KeyHeightOption.normal] when not set by the user.
  final KeyHeightOption keyHeightOption;

  const KeyboardDisplayConfig({
    this.keysToShow,
    this.verticalGestureAction,
    this.horizontalGestureAction,
    this.aftertouchDestCc,
    this.keyHeightOption = KeyHeightOption.normal,
  });

  /// Returns true when every override field is null and key height is normal,
  /// meaning the slot behaves exactly like a fresh slot with no customisation.
  bool get isDefault =>
      keysToShow == null &&
      verticalGestureAction == null &&
      horizontalGestureAction == null &&
      aftertouchDestCc == null &&
      keyHeightOption == KeyHeightOption.normal;

  // ── Serialisation ────────────────────────────────────────────────────────

  /// Serialises this config to a JSON-compatible map for project persistence.
  Map<String, dynamic> toJson() => {
        if (keysToShow != null) 'keysToShow': keysToShow,
        if (verticalGestureAction != null)
          'verticalGestureAction': verticalGestureAction!.name,
        if (horizontalGestureAction != null)
          'horizontalGestureAction': horizontalGestureAction!.name,
        if (aftertouchDestCc != null) 'aftertouchDestCc': aftertouchDestCc,
        'keyHeightOption': keyHeightOption.name,
      };

  /// Deserialises a [KeyboardDisplayConfig] from a JSON map.
  ///
  /// Unknown or missing keys fall back to null / [KeyHeightOption.normal].
  factory KeyboardDisplayConfig.fromJson(Map<String, dynamic> json) {
    GestureAction? parseAction(String? name) {
      if (name == null) return null;
      return GestureAction.values.firstWhere(
        (e) => e.name == name,
        orElse: () => GestureAction.vibrato,
      );
    }

    final heightName = json['keyHeightOption'] as String?;
    final heightOption = heightName == null
        ? KeyHeightOption.normal
        : KeyHeightOption.values.firstWhere(
            (e) => e.name == heightName,
            orElse: () => KeyHeightOption.normal,
          );

    return KeyboardDisplayConfig(
      keysToShow: (json['keysToShow'] as num?)?.toInt(),
      verticalGestureAction:
          parseAction(json['verticalGestureAction'] as String?),
      horizontalGestureAction:
          parseAction(json['horizontalGestureAction'] as String?),
      aftertouchDestCc: (json['aftertouchDestCc'] as num?)?.toInt(),
      keyHeightOption: heightOption,
    );
  }

  // ── Mutation helper ──────────────────────────────────────────────────────

  /// Returns a copy of this config with the specified fields replaced.
  ///
  /// To clear an optional override (revert to global pref), pass the explicit
  /// sentinel value. Since Dart doesn't support null arguments for nullable
  /// fields in copyWith, use the dedicated `clear*` booleans.
  KeyboardDisplayConfig copyWith({
    int? keysToShow,
    bool clearKeysToShow = false,
    GestureAction? verticalGestureAction,
    bool clearVerticalGestureAction = false,
    GestureAction? horizontalGestureAction,
    bool clearHorizontalGestureAction = false,
    int? aftertouchDestCc,
    bool clearAftertouchDestCc = false,
    KeyHeightOption? keyHeightOption,
  }) =>
      KeyboardDisplayConfig(
        keysToShow:
            clearKeysToShow ? null : (keysToShow ?? this.keysToShow),
        verticalGestureAction: clearVerticalGestureAction
            ? null
            : (verticalGestureAction ?? this.verticalGestureAction),
        horizontalGestureAction: clearHorizontalGestureAction
            ? null
            : (horizontalGestureAction ?? this.horizontalGestureAction),
        aftertouchDestCc: clearAftertouchDestCc
            ? null
            : (aftertouchDestCc ?? this.aftertouchDestCc),
        keyHeightOption: keyHeightOption ?? this.keyHeightOption,
      );
}
