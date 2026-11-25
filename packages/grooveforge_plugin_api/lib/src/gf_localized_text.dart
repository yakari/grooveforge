/// A piece of user-visible text written in several languages.
///
/// A `.gfpd` file may give any name, label or option either as a plain string
/// or as a map from language code to text:
///
/// ```yaml
/// label: {en: "Gate", fr: "Porte"}
/// ```
///
/// The loader keeps the map here so the plugin panel can show the text in the
/// player's language. A plain string never becomes a [GFLocalizedText]; the
/// descriptor keeps it as an ordinary `String` as before.
class GFLocalizedText {
  /// Creates a text from a map of language code (`en`, `fr`, `pt-BR`…) to
  /// the text in that language. The map should not be empty; an empty map
  /// resolves to an empty string.
  const GFLocalizedText(this.translations);

  /// Language code to text, in the order the `.gfpd` author wrote them.
  final Map<String, String> translations;

  /// The text shown when the requested language is missing: the English
  /// entry if there is one, else the first entry written.
  ///
  /// The descriptor's plain `String` fields (`name`, `label`, `options`) hold
  /// this value, so code that ignores languages still gets readable text.
  String get defaultText {
    final english = translations['en'];
    if (english != null) return english;
    return translations.isEmpty ? '' : translations.values.first;
  }

  /// The text for [languageCode], falling back to [defaultText].
  ///
  /// Accepts a full locale such as `pt_BR` or `pt-BR`: the exact entry wins,
  /// then the entry for the bare language (`pt`).
  String resolve(String languageCode) {
    final exact = translations[languageCode];
    if (exact != null) return exact;

    // `pt_BR` → `pt`: a regional locale still reads the plain language.
    final bare = languageCode.split(RegExp('[_-]')).first;
    return translations[bare] ?? defaultText;
  }

  @override
  String toString() => defaultText;
}
