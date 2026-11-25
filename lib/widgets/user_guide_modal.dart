import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';

/// The tabs of the user guide, in display order.
///
/// Exposed so a screen can open the guide on the page that concerns it: the
/// Rehearse tab opens it on [rehearsals], the rack on [start].
enum UserGuideTab { start, modules, cables, midi, rehearsals, tips }

/// A modal dialog holding the user guide.
///
/// The guide is organised by what the player wants to do, not by feature:
/// the first tab explains how sound moves between modules and lists short
/// recipes, each linking to a clip of the gesture on the website. The other
/// tabs are references for when a recipe is not enough.
class UserGuideModal extends StatefulWidget {
  const UserGuideModal({super.key, this.initialTab = UserGuideTab.start});

  /// The tab shown when the guide opens.
  final UserGuideTab initialTab;

  @override
  State<UserGuideModal> createState() => _UserGuideModalState();
}

class _UserGuideModalState extends State<UserGuideModal> {
  String _version = "...";
  List<ChangelogEntry> _latestChanges = [];

  @override
  void initState() {
    super.initState();
    _loadVersionData();
  }

  Future<void> _loadVersionData() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;

    setState(() {
      _version = info.version;
    });

    // Determine locale and changelog asset
    final locale = Localizations.localeOf(context).languageCode;
    final isFrench = locale == 'fr';
    final changelogAsset = isFrench ? 'CHANGELOG.fr.md' : 'CHANGELOG.md';

    try {
      final content = await rootBundle.loadString(changelogAsset);
      final changes = parseLatestChangelogEntries(content);
      if (mounted) {
        setState(() {
          _latestChanges = changes;
        });
      }
    } catch (e) {
      debugPrint("Error loading changelog: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return DefaultTabController(
      length: UserGuideTab.values.length,
      initialIndex: widget.initialTab.index,
      child: Dialog(
        backgroundColor: const Color(0xFF1A1A24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildTitleBar(context, l10n),
              _buildTabBar(l10n),
              Expanded(
                child: TabBarView(
                  children: [
                    _StartTab(version: _version, latestChanges: _latestChanges),
                    const _ModulesTab(),
                    const _CablesTab(),
                    const _MidiTab(),
                    const _RehearsalsTab(),
                    const _TipsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The guide title and the close button.
  Widget _buildTitleBar(BuildContext context, AppLocalizations l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Expanded + FittedBox: the title is a translated string, so its
        // width is not knowable here. Scaling down only when it does not fit
        // keeps every language on one line without shrinking the ones that
        // already fit.
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.guideTitle.toUpperCase(),
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white54),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  /// Icon-only tabs.
  ///
  /// Six labels do not fit the dialog width: they were clipped to "FEA",
  /// "MID", "SOU", which identifies nothing. Each icon keeps its translated
  /// label as a tooltip, so the wording is still reachable on long-press and
  /// still announced to screen readers.
  Widget _buildTabBar(AppLocalizations l10n) {
    Tab tab(String label, IconData icon) =>
        Tab(icon: Tooltip(message: label, child: Icon(icon)));

    return TabBar(
      tabs: [
        tab(l10n.guideTabStart, Icons.play_circle_outline),
        tab(l10n.guideTabModules, Icons.view_agenda_outlined),
        tab(l10n.guideTabPatch, Icons.cable_outlined),
        tab(l10n.guideTabMidi, Icons.usb),
        // The same icon the Rehearse tab itself uses in the shell, so the
        // guide page and the thing it describes look alike.
        tab(l10n.guideTabRehearsals, Icons.groups_outlined),
        tab(l10n.guideTabTips, Icons.music_note),
      ],
      indicatorColor: Colors.blueAccent,
      labelColor: Colors.blueAccent,
      unselectedLabelColor: Colors.white54,
    );
  }
}

// ─── Website clips ──────────────────────────────────────────────────────────

/// The published website. Every recipe below has a section on its guide page
/// with a screen recording of the gesture, which the help cannot embed
/// without growing the app by several megabytes and adding a video player
/// that does not run on Linux or Windows.
const _kSiteBase = 'https://yakari.github.io/grooveforge/';

/// The guide page section for [anchor], in the reader's language when the
/// site has it (English and French).
String _guideUrl(BuildContext context, String anchor) {
  final french = Localizations.localeOf(context).languageCode == 'fr';
  return '$_kSiteBase${french ? 'fr/' : ''}guide/#$anchor';
}

/// One short how-to: a title, steps separated by newlines, an optional line
/// saying what the player should hear, and the anchor of its clip on the
/// website guide.
class _Recipe {
  const _Recipe(this.title, this.steps, this.result, this.anchor);

  final String title;
  final String steps;
  final String result;

  /// Section id on the website guide, e.g. `effect` for `guide/#effect`.
  /// The English and French pages use different ids, see [guideClipAnchors].
  final String anchor;
}

/// Section ids of the website guide that the help links to, English id to
/// French id: the French page translated its ids.
///
/// Public for the test that checks every one of them exists on both pages,
/// since renaming a section on the site would otherwise break these links
/// silently.
@visibleForTesting
const guideClipAnchors = {
  'scale': 'gamme',
  'effect': 'effet',
  'remove': 'retirer',
  'guitar': 'guitare',
  'amp': 'ampli',
  'controller': 'controleur',
  'learn': 'learn',
  'drums': 'batterie',
  'loop': 'boucle',
  'projects': 'projets',
  'rehearsal': 'repetition',
};

/// The recipes of the Start tab, in the order a new player needs them.
List<_Recipe> _recipes(AppLocalizations l10n) => [
      _Recipe(l10n.guideRecipeScaleTitle, l10n.guideRecipeScaleSteps,
          l10n.guideRecipeScaleResult, 'scale'),
      _Recipe(l10n.guideRecipeEffectTitle, l10n.guideRecipeEffectSteps,
          l10n.guideRecipeEffectResult, 'effect'),
      _Recipe(l10n.guideRecipeRemoveTitle, l10n.guideRecipeRemoveSteps,
          l10n.guideRecipeRemoveResult, 'remove'),
      _Recipe(l10n.guideRecipeGuitarTitle, l10n.guideRecipeGuitarSteps,
          l10n.guideRecipeGuitarResult, 'guitar'),
      _Recipe(l10n.guideRecipeAmpTitle, l10n.guideRecipeAmpSteps,
          l10n.guideRecipeAmpResult, 'amp'),
      _Recipe(l10n.guideRecipeControllerTitle, l10n.guideRecipeControllerSteps,
          l10n.guideRecipeControllerResult, 'controller'),
      _Recipe(l10n.guideRecipeLearnTitle, l10n.guideRecipeLearnSteps,
          l10n.guideRecipeLearnResult, 'learn'),
      _Recipe(l10n.guideRecipeDrumsTitle, l10n.guideRecipeDrumsSteps,
          l10n.guideRecipeDrumsResult, 'drums'),
      _Recipe(l10n.guideRecipeLoopTitle, l10n.guideRecipeLoopSteps,
          l10n.guideRecipeLoopResult, 'loop'),
      _Recipe(l10n.guideRecipeProjectsTitle, l10n.guideRecipeProjectsSteps,
          l10n.guideRecipeProjectsResult, 'projects'),
    ];

// ─── Tabs ───────────────────────────────────────────────────────────────────

/// The first page: what is new, how sound moves between modules, and the
/// recipes.
///
/// The three cabling rules come before anything else because they are what
/// readers were missing: a player who knew every module still did not know
/// that an instrument needs no cable to be heard, or which way an effect is
/// cabled.
class _StartTab extends StatelessWidget {
  const _StartTab({required this.version, required this.latestChanges});

  final String version;
  final List<ChangelogEntry> latestChanges;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      children: [
        _buildWelcomeHeader(context, l10n, version, latestChanges),
        const SizedBox(height: 24),
        _buildSectionTitle(l10n.guideRulesTitle),
        _buildParagraph(l10n.guideRulesIntro),
        _buildRule(_kJackMidi, l10n.guideRuleInstrument, outline: true),
        _buildRule(_kJackMidi, l10n.guideRuleColours),
        _buildRule(_kJackAudioL, l10n.guideRuleEffect),
        const SizedBox(height: 4),
        _buildParagraph(l10n.guideRuleDraw),
        const Divider(color: Colors.white12, height: 32),
        for (final recipe in _recipes(l10n)) ..._buildRecipe(context, l10n, recipe),
      ],
    );
  }

  /// One cabling rule, marked with the colour of the cable it is about.
  ///
  /// [outline] draws a hollow dot for the rule that needs no cable at all.
  Widget _buildRule(Color color, String text, {bool outline = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 5, right: 10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: outline ? Colors.transparent : color,
              border: Border.all(color: outline ? Colors.white54 : color, width: 2),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  /// A recipe: its title, numbered steps, the result, and the clip link.
  List<Widget> _buildRecipe(
    BuildContext context,
    AppLocalizations l10n,
    _Recipe recipe,
  ) {
    final steps = recipe.steps.split('\n').where((s) => s.trim().isNotEmpty);
    final french = Localizations.localeOf(context).languageCode == 'fr';
    final anchor = french ? (guideClipAnchors[recipe.anchor] ?? recipe.anchor) : recipe.anchor;
    return [
      _buildSubTitle(recipe.title),
      for (final (i, step) in steps.indexed) _buildStep(i + 1, step),
      if (recipe.result.isNotEmpty) _buildResult(recipe.result),
      _buildLink(l10n.guideWatchClip, _guideUrl(context, anchor)),
      const SizedBox(height: 20),
    ];
  }

  /// What the player should hear or see once the steps are done.
  Widget _buildResult(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 13,
          fontStyle: FontStyle.italic,
          height: 1.4,
        ),
      ),
    );
  }
}

/// Every module the "+" button offers, then a closer look at the ones that
/// need more than a line.
class _ModulesTab extends StatelessWidget {
  const _ModulesTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      children: [
        _buildSectionTitle(l10n.guideTabModules),
        _buildParagraph(l10n.guideModulesIntro),
        ..._slotTypeList(l10n),
        const SizedBox(height: 4),
        _buildDesktopOnlyBox(l10n.guidePatchSlotVst3DesktopOnly),
        const Divider(color: Colors.white12, height: 40),
        // Xen first: it is in every new rack, so it is the one a reader has
        // on screen while reading this.
        ..._detail(l10n.guideXenTitle, l10n.guideXenBody),
        ..._detail(l10n.guideRiffTitle, l10n.guideRiffBody),
        ..._detail(l10n.guideAmpTitle, l10n.guideAmpBody),
        _buildSubTitle(l10n.guideAmpIrSourcesTitle),
        _buildLink(l10n.guideIrSourceTone3000, _kIrSourceTone3000),
        _buildLink(l10n.guideIrSourceKalthallen, _kIrSourceKalthallen),
        _buildLink(l10n.guideIrSourceCelestion, _kIrSourceCelestion),
        const SizedBox(height: 10),
        _buildInfoBox(l10n.guideAmpIrSourcesNote),
        const SizedBox(height: 24),
        ..._detail(l10n.guideSoundfontsTitle, l10n.guideSoundfontsBody),
        ..._detail(l10n.guideDrumGeneratorTitle, l10n.guideDrumGeneratorBody),
        ..._detail(l10n.guideLoopersTitle, l10n.guideLoopersBody),
        ..._detail(l10n.guideMidiFxTitle, l10n.guideMidiFxBody),
        ..._detail(l10n.guideVocoderTitle, l10n.guideVocoderBody),
        _buildInfoBox(l10n.guideVocoderNote),
        const SizedBox(height: 24),
        ..._detail(l10n.guideThereminTitle, l10n.guideThereminBody),
        ..._detail(l10n.guideJamModeTitle, l10n.guideJamModeBody),
      ],
    );
  }

  /// A titled block of text about one module.
  List<Widget> _detail(String title, String body) => [
        _buildSectionTitle(title),
        _buildParagraph(body),
        const SizedBox(height: 12),
      ];

  /// Every module the "Add Plugin" sheet offers, in the same families and
  /// order, so the help keeps listing what the rack can actually hold. The
  /// entries reuse the sheet's own titles and subtitles, so renaming a module
  /// there renames it here too.
  List<Widget> _slotTypeList(AppLocalizations l10n) {
    return [
      _buildGroupLabel(l10n.guidePatchGroupInstruments),
      _buildFeatureItem(Icons.piano, l10n.guidePatchSlotKeyboard, l10n.guidePatchSlotKeyboardDesc),
      _buildFeatureItem(Icons.mic, l10n.guidePatchSlotVocoder, l10n.guidePatchSlotVocoderDesc),
      _buildFeatureItem(Icons.electric_bolt, l10n.rackAddRiff, l10n.rackAddRiffSubtitle),
      _buildFeatureItem(Icons.auto_awesome, l10n.guidePatchSlotJam, l10n.guidePatchSlotJamDesc),
      _buildFeatureItem(Icons.linear_scale, l10n.rackAddStylophone, l10n.rackAddStyloPhoneSubtitle),
      _buildFeatureItem(Icons.sensors, l10n.rackAddTheremin, l10n.rackAddThereminSubtitle),
      _buildGroupLabel(l10n.guidePatchGroupRhythm),
      _buildFeatureItem(Icons.album, l10n.drumGeneratorAddTitle, l10n.drumGeneratorAddSubtitle),
      _buildFeatureItem(Icons.loop, l10n.addLooper, l10n.addLooperSubtitle),
      _buildFeatureItem(Icons.radio_button_checked, l10n.rackAddAudioLooper, l10n.rackAddAudioLooperSubtitle),
      _buildGroupLabel(l10n.rackAddSourcesSectionLabel),
      _buildFeatureItem(Icons.mic, l10n.rackAddLiveInputSource, l10n.rackAddLiveInputSourceSubtitle),
      ..._audioEffectList(l10n),
      ..._midiFxList(l10n),
      _buildGroupLabel(l10n.guidePatchGroupCustom),
      _buildFeatureItem(Icons.file_open, l10n.rackAddLoadGfpd, l10n.rackAddLoadGfpdSubtitle),
      _buildFeatureItem(Icons.extension, l10n.guidePatchSlotVst3, l10n.guidePatchSlotVst3Desc),
    ];
  }

  /// The built-in audio effects, as listed in the "Add Plugin" sheet.
  List<Widget> _audioEffectList(AppLocalizations l10n) {
    return [
      _buildGroupLabel(l10n.rackAddEffectsSectionLabel),
      _buildFeatureItem(Icons.blur_on, l10n.rackAddReverb, l10n.rackAddReverbSubtitle),
      _buildFeatureItem(Icons.repeat, l10n.rackAddDelay, l10n.rackAddDelaySubtitle),
      _buildFeatureItem(Icons.graphic_eq, l10n.rackAddWah, l10n.rackAddWahSubtitle),
      _buildFeatureItem(Icons.equalizer, l10n.rackAddEq, l10n.rackAddEqSubtitle),
      _buildFeatureItem(Icons.compress, l10n.rackAddCompressor, l10n.rackAddCompressorSubtitle),
      _buildFeatureItem(Icons.waves, l10n.rackAddChorus, l10n.rackAddChorusSubtitle),
      _buildFeatureItem(Icons.queue_music, l10n.rackAddAudioHarmonizer, l10n.rackAddAudioHarmonizerSubtitle),
      _buildFeatureItem(Icons.record_voice_over, l10n.rackAddAutotune, l10n.rackAddAutotuneSubtitle),
      _buildFeatureItem(Icons.speaker, l10n.rackAddAmp, l10n.rackAddAmpSubtitle),
    ];
  }

  /// The built-in MIDI FX, as listed in the "Add Plugin" sheet.
  List<Widget> _midiFxList(AppLocalizations l10n) {
    return [
      _buildGroupLabel(l10n.rackAddMidiFxSectionLabel),
      _buildFeatureItem(Icons.music_note, l10n.rackAddHarmonizer, l10n.rackAddHarmonizerSubtitle),
      _buildFeatureItem(Icons.piano, l10n.rackAddChordExpand, l10n.rackAddChordExpandSubtitle),
      _buildFeatureItem(Icons.auto_awesome, l10n.rackAddArpeggiator, l10n.rackAddArpeggiatorSubtitle),
      _buildFeatureItem(Icons.swap_vert, l10n.rackAddTransposer, l10n.rackAddTransposerSubtitle),
      _buildFeatureItem(Icons.tune, l10n.rackAddVelocityCurve, l10n.rackAddVelocityCurveSubtitle),
      _buildFeatureItem(Icons.filter_alt, l10n.rackAddGate, l10n.rackAddGateSubtitle),
      _buildFeatureItem(Icons.graphic_eq, l10n.rackAddMicrotone, l10n.rackAddMicrotoneSubtitle),
      _buildFeatureItem(Icons.travel_explore, l10n.rackAddXen, l10n.rackAddXenSubtitle),
    ];
  }

  /// An amber-tinted box flagging a platform limit, such as VST3 being
  /// desktop-only.
  Widget _buildDesktopOnlyBox(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.desktop_windows_outlined, color: Colors.amber, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.amber, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// The back of the rack: socket colours, drawing and removing cables, and
/// the one rule that makes GrooveForge refuse a cable.
class _CablesTab extends StatelessWidget {
  const _CablesTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      children: [
        _buildSectionTitle(l10n.guidePatchTitle),
        _buildParagraph(l10n.guidePatchIntro),
        const SizedBox(height: 12),
        _buildSubTitle(l10n.guideJackLegendTitle),
        _buildJackLegend(l10n),
        const SizedBox(height: 20),
        _buildSubTitle(l10n.guidePatchDrawTitle),
        _buildParagraph(l10n.guidePatchDrawBody),
        const SizedBox(height: 12),
        _buildSubTitle(l10n.guidePatchDisconnectTitle),
        _buildParagraph(l10n.guidePatchDisconnectBody),
        const SizedBox(height: 12),
        _buildSubTitle(l10n.guidePatchDataTitle),
        _buildParagraph(l10n.guidePatchDataBody),
        const SizedBox(height: 12),
        _buildSubTitle(l10n.guidePatchSharedEffectTitle),
        _buildParagraph(l10n.guidePatchSharedEffectBody),
        const SizedBox(height: 8),
        _buildWarningBox(l10n.guidePatchSharedEffectWorkaround),
        const SizedBox(height: 12),
        _buildInfoBox(l10n.guidePatchTip),
      ],
    );
  }

  /// Socket colours: one row per family, with the socket names as printed on
  /// the back panels (left untranslated, like the panels) and what they carry.
  Widget _buildJackLegend(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8, left: 8),
      child: Column(
        children: [
          _buildLegendRow(_kJackMidi, 'MIDI IN / OUT', l10n.guideJackMidi),
          _buildLegendRow(_kJackAudioL, 'AUDIO IN / OUT L', l10n.guideJackAudioL),
          _buildLegendRow(_kJackAudioR, 'AUDIO IN / OUT R', l10n.guideJackAudioR),
          _buildLegendRow(_kJackSend, 'SEND / RETURN', l10n.guideJackSend),
          _buildLegendRow(_kJackData, 'CHORD / SCALE', l10n.guideJackData),
          _buildLegendRow(_kJackTune, 'TUNE IN / OUT', l10n.guideJackTune),
        ],
      ),
    );
  }

  /// A single legend row: a coloured dot, the socket names, and what they
  /// carry.
  Widget _buildLegendRow(Color color, String ports, String meaning) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 1),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$ports  ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(
                    text: meaning,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A red box for a rule that makes GrooveForge refuse a cable, so readers
  /// recognise it when the refusal message appears.
  Widget _buildWarningBox(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_outlined, color: Colors.redAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Hardware controllers: connecting one, which module it plays, and mapping
/// its knobs and pads.
class _MidiTab extends StatelessWidget {
  const _MidiTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      children: [
        _buildSectionTitle(l10n.guideMidiTitle),
        _buildParagraph(l10n.guideMidiBody),
        _buildStep(1, l10n.guideMidiHardwareStep1),
        _buildStep(2, l10n.guideMidiHardwareStep2),
        _buildStep(3, l10n.guideMidiHardwareStep3),
        const SizedBox(height: 20),
        _buildSubTitle(l10n.guideMidiCcMappings),
        _buildParagraph(l10n.guideMidiCcMappingsBody),
        const SizedBox(height: 20),
        _buildSubTitle(l10n.guideMidiBestPracticeTitle),
        _buildParagraph(l10n.guideMidiBestPracticeBody),
        _buildInfoBox(l10n.guideMidiTipSplit),
        const SizedBox(height: 12),
        _buildInfoBox(l10n.guideAndroidUsbLimitation),
      ],
    );
  }
}

/// Rehearsing as a band: recording a part, and getting the devices onto one
/// network.
///
/// The network section is the reason this tab exists. Everything else in the
/// feature is discoverable by poking at it, but "why can the others not see
/// me" has an answer that lives outside the app entirely (somebody has to
/// turn on a hotspot) and there is nowhere else to say so.
class _RehearsalsTab extends StatelessWidget {
  const _RehearsalsTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      children: [
        _buildSectionTitle(l10n.guideRehearsalIntroTitle),
        _buildParagraph(l10n.guideRehearsalIntroBody),
        _buildLink(
          l10n.guideWatchClip,
          _guideUrl(
            context,
            Localizations.localeOf(context).languageCode == 'fr'
                ? guideClipAnchors['rehearsal']!
                : 'rehearsal',
          ),
        ),
        const SizedBox(height: 20),
        _buildSectionTitle(l10n.guideRehearsalStartTitle),
        _buildParagraph(l10n.guideRehearsalStartBody),
        const SizedBox(height: 20),
        _buildSectionTitle(l10n.guideRehearsalRecordTitle),
        _buildParagraph(l10n.guideRehearsalRecordBody),
        const SizedBox(height: 10),
        _buildInfoBox(l10n.guideRehearsalMonitoringNote),
        const SizedBox(height: 20),
        _buildSectionTitle(l10n.guideRehearsalShareTitle),
        _buildParagraph(l10n.guideRehearsalShareBody),
        const SizedBox(height: 20),
        _buildSectionTitle(l10n.guideRehearsalHotspotTitle),
        _buildParagraph(l10n.guideRehearsalHotspotBody),
        const SizedBox(height: 10),
        _buildInfoBox(l10n.guideRehearsalHotspotNote),
      ],
    );
  }
}

/// A few ideas for players who have never improvised.
class _TipsTab extends StatelessWidget {
  const _TipsTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      children: [
        _buildSectionTitle(l10n.guideTipsTitle),
        _buildParagraph(l10n.guideTipsBody),
      ],
    );
  }
}

// ─── Shared helpers ─────────────────────────────────────────────────────────

// Socket colours, matching the back panels of the rack.
const _kJackMidi = Color(0xFFFFD700);
const _kJackAudioL = Color(0xFFFF4444);
const _kJackAudioR = Colors.white70;
const _kJackSend = Color(0xFFFF8C00);
const _kJackData = Color(0xFFAB47BC);
const _kJackTune = Color(0xFF26A69A);

/// A small upper-case family label above a group of modules, styled like the
/// section labels of the "Add Plugin" sheet.
Widget _buildGroupLabel(String text) {
  return Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 2),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
      ),
    ),
  );
}

// Helper Widgets
Widget _buildWelcomeHeader(
  BuildContext context,
  AppLocalizations l10n,
  String version,
  List<ChangelogEntry> latestChanges,
) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.blueAccent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.guideWelcomeHeader(version),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.guideWelcomeIntro,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 12),
        // Nothing to show means show nothing. The two hard-coded English
        // bullets that used to stand in here were worse than an empty box:
        // they were untranslated, and they claimed a release had contents the
        // changelog did not list.
        if (latestChanges.isNotEmpty) ...[
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: false,
              title: Text(
                l10n.guideChangelogExpand,
                style: const TextStyle(
                  color: Colors.blueAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              iconColor: Colors.blueAccent,
              collapsedIconColor: Colors.blueAccent.withValues(alpha: 0.7),
              children: [
                for (final entry in latestChanges)
                  if (entry.isSection)
                    _buildChangelogSection(entry.text)
                  else
                    _buildBulletItem(entry.text),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

/// One line of the "what's new" list: either a section heading or a bullet.
///
/// A typed pair rather than magic-prefixed strings — the first attempt used an
/// invisible sentinel character, which is unreadable in a debugger and breaks
/// any tool that touches the text.
class ChangelogEntry {
  final String text;

  /// True for a section heading ("Fixed", "Corrigé"), false for a bullet.
  final bool isSection;

  const ChangelogEntry(this.text, {this.isSection = false});
}

/// Every bullet of the newest version block of [content], whichever section it
/// sits in, with the section headings interleaved.
///
/// This used to read only `### Added`, matched against a hard-coded English or
/// French heading. A release that changed and fixed things without adding any
/// therefore showed an empty "what's new" — which is what 2.17.2 did — and a
/// renamed or newly translated section would have emptied it just as silently.
///
/// Headings need no translation of their own: they come from the changelog the
/// app already picked for the current locale.
@visibleForTesting
List<ChangelogEntry> parseLatestChangelogEntries(String content) {
  final entries = <ChangelogEntry>[];
  var inLatestVersion = false;

  for (var line in content.split('\n')) {
    line = line.trim();

    if (line.startsWith('## [')) {
      if (inLatestVersion) break; // Reached the previous release.
      inLatestVersion = true;
      continue;
    }
    if (!inLatestVersion) continue;

    if (line.startsWith('### ')) {
      entries.add(ChangelogEntry(line.substring(4).trim(), isSection: true));
      continue;
    }
    if (line.startsWith('- ')) {
      entries.add(ChangelogEntry(
        line.substring(2).replaceAll('**', '').replaceAll('`', ''),
      ));
    }
  }

  // Headings with no bullets under them are not worth showing.
  if (entries.every((e) => e.isSection)) return const [];
  return entries;
}

/// A changelog section heading ("Fixed", "Corrigé") above its bullets.
///
/// Taken verbatim from the changelog, which the app already loaded in the
/// current language — so a fix is never presented as a new feature, and no
/// translation of these words is needed.
Widget _buildChangelogSection(String title) {
  return Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 2),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        color: Colors.blueAccent.withValues(alpha: 0.8),
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.8,
      ),
    ),
  );
}

Widget _buildBulletItem(String text) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "\u2022 ",
          style: TextStyle(
            color: Colors.blueAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

Widget _buildSectionTitle(String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      title,
      style: const TextStyle(
        color: Colors.blueAccent,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

Widget _buildSubTitle(String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

Widget _buildParagraph(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
    ),
  );
}

Widget _buildStep(int number, String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$number. ',
          style: const TextStyle(
            color: Colors.blueAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(
          child: Text(text, style: const TextStyle(color: Colors.white70)),
        ),
      ],
    ),
  );
}

Widget _buildFeatureItem(IconData icon, String title, String description) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: ListTile(
      leading: Icon(icon, color: Colors.blueAccent, size: 20),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      subtitle: Text(
        description,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      contentPadding: EdgeInsets.zero,
      dense: true,
    ),
  );
}

// Where to find speaker-cabinet impulse responses for the Amp. Kept in step
// with the README and the website's Modules page. None of these files may be
// shipped with GrooveForge (their licences forbid redistribution), so the
// player downloads them from the source.
const _kIrSourceTone3000 = 'https://www.tone3000.com/search?format=ir';
const _kIrSourceKalthallen = 'https://cabs.kalthallen.de/';
const _kIrSourceCelestion = 'https://www.celestionplus.com/free-download/';

/// A tappable web link, opened in the system browser.
Widget _buildLink(String label, String url) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6, left: 8),
    child: InkWell(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Row(
        children: [
          const Icon(Icons.open_in_new, color: Colors.blueAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.blueAccent,
                fontSize: 14,
                decoration: TextDecoration.underline,
                decorationColor: Colors.blueAccent,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildInfoBox(String text) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.blueAccent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: Colors.blueAccent, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.blueAccent, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}
