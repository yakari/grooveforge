import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';
import '../l10n/app_localizations.dart';

/// A modal dialog containing the comprehensive user guide for GrooveForge.
///
/// The guide is organized into distinct tabs: Features, MIDI Connectivity,
/// Soundfonts, Musical Tips, and Rack & Cables.
class UserGuideModal extends StatefulWidget {
  const UserGuideModal({super.key});

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
      length: 5,
      child: Dialog(
        backgroundColor: const Color(0xFF1A1A24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Expanded + FittedBox: the title is a translated string, so
                  // its width is not knowable here. "GUIDE DE L'UTILISATEUR"
                  // overflows the dialog by ~50 px at this size, and a longer
                  // translation would overflow further. Scaling down only when
                  // it does not fit keeps every language on one line without
                  // shrinking the languages that already fit.
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
              ),
              // Icon-only tabs.
              //
              // Five labels do not fit the dialog width: they were clipped to
              // "FEA", "MID", "SOU", ... which identifies nothing, and longer
              // translations clipped harder (the French set read "FON", "CON",
              // "SOU", "CON", "RAC" — two of them identical). Each icon keeps
              // its translated label as a tooltip, so the wording is still
              // reachable on long-press and still announced to screen readers.
              TabBar(
                tabs: [
                  Tab(
                    icon: Tooltip(
                      message: l10n.guideTabFeatures,
                      child: const Icon(Icons.auto_awesome),
                    ),
                  ),
                  Tab(
                    icon: Tooltip(
                      message: l10n.guideTabMidi,
                      child: const Icon(Icons.usb),
                    ),
                  ),
                  Tab(
                    icon: Tooltip(
                      message: l10n.guideTabSoundfonts,
                      child: const Icon(Icons.library_music),
                    ),
                  ),
                  Tab(
                    icon: Tooltip(
                      message: l10n.guideTabTips,
                      child: const Icon(Icons.music_note),
                    ),
                  ),
                  Tab(
                    icon: Tooltip(
                      message: l10n.guideTabPatch,
                      child: const Icon(Icons.cable_outlined),
                    ),
                  ),
                ],
                indicatorColor: Colors.blueAccent,
                labelColor: Colors.blueAccent,
                unselectedLabelColor: Colors.white54,
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _FeaturesTab(
                      version: _version,
                      latestChanges: _latestChanges,
                    ),
                    _MidiConnectivityTab(),
                    _SoundfontsTab(),
                    _MusicalTipsTab(),
                    _PatchViewTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays information about Jam Mode and the new Vocoder feature.
class _FeaturesTab extends StatelessWidget {
  final String version;
  final List<ChangelogEntry> latestChanges;
  const _FeaturesTab({required this.version, required this.latestChanges});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      children: [
        _buildWelcomeHeader(context, l10n, version, latestChanges),
        const SizedBox(height: 24),
        // Xen comes first: it is what the default rack ships with, and the
        // one a new reader will have on screen while reading this.
        _buildSectionTitle(l10n.guideXenTitle),
        _buildParagraph(l10n.guideXenBody),
        _buildSectionTitle(l10n.guideJamModeTitle),
        _buildParagraph(l10n.guideJamModeBody),
        const SizedBox(height: 20),
        _buildSectionTitle(l10n.guideVocoderTitle),
        _buildParagraph(l10n.guideVocoderBody),
        const SizedBox(height: 10),
        _buildInfoBox(
          l10n.guideVocoderBody.split('\n').last,
        ), // The latency warning
        // The remaining rack modules, in the order a player is most likely to
        // reach for them: instruments first, then the rhythm section, then the
        // loopers that layer on top, and finally the MIDI FX that reshape what
        // any of them receive.
        const SizedBox(height: 20),
        _buildSectionTitle(l10n.guideThereminTitle),
        _buildParagraph(l10n.guideThereminBody),
        const SizedBox(height: 20),
        _buildSectionTitle(l10n.guideDrumGeneratorTitle),
        _buildParagraph(l10n.guideDrumGeneratorBody),
        const SizedBox(height: 20),
        _buildSectionTitle(l10n.guideLoopersTitle),
        _buildParagraph(l10n.guideLoopersBody),
        const SizedBox(height: 20),
        _buildSectionTitle(l10n.guideMidiFxTitle),
        _buildParagraph(l10n.guideMidiFxBody),
      ],
    );
  }
}

/// Explains MIDI connection (USB/BLE) and CC/System action mapping.
class _MidiConnectivityTab extends StatelessWidget {
  const _MidiConnectivityTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      children: [
        _buildSectionTitle(l10n.guideMidiTitle),
        _buildParagraph(l10n.guideMidiBody),
        const SizedBox(height: 10),
        _buildSubTitle(l10n.guideMidiHardware),
        _buildStep(1, l10n.guideMidiHardwareStep1),
        _buildStep(2, l10n.guideMidiHardwareStep2),
        const SizedBox(height: 10),
        _buildSubTitle(l10n.guideMidiCcMappings),
        _buildParagraph(l10n.guideMidiCcMappingsBody),
        _buildFeatureItem(
          Icons.skip_next,
          l10n.guideMidiFeaturePatch,
          l10n.guideMidiFeaturePatchDesc,
        ),
        _buildFeatureItem(
          Icons.loop,
          l10n.guideMidiFeatureScales,
          l10n.guideMidiFeatureScalesDesc,
        ),
        _buildFeatureItem(
          Icons.lock,
          l10n.guideMidiFeatureJam,
          l10n.guideMidiFeatureJamDesc,
        ),
        const SizedBox(height: 24),
        _buildSectionTitle(l10n.guideMidiBestPracticeTitle),
        _buildParagraph(l10n.guideMidiBestPracticeBody),
        const SizedBox(height: 12),
        _buildInfoBox(l10n.guideMidiTipSplit),
        const SizedBox(height: 12),
        _buildInfoBox(l10n.guideAndroidUsbLimitation),
      ],
    );
  }
}

/// Explains Soundfont loading and management.
class _SoundfontsTab extends StatelessWidget {
  const _SoundfontsTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      children: [
        _buildSectionTitle(l10n.guideSoundfontsTitle),
        _buildParagraph(l10n.guideSoundfontsBody),
        _buildFeatureItem(
          Icons.folder_open,
          'Import SF2',
          'Add files from your local storage.',
        ),
        _buildFeatureItem(
          Icons.storage,
          'Permanent Cache',
          'Files are moved to app internal storage for stability.',
        ),
        const SizedBox(height: 20),
        _buildInfoBox(
          'Tip: High-quality soundfonts can be several hundred MBs. Ensure you have enough storage.',
        ),
      ],
    );
  }
}

/// Provides scale references and improvisation tips.
class _MusicalTipsTab extends StatelessWidget {
  const _MusicalTipsTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      children: [
        _buildSectionTitle(l10n.guideTipsTitle),
        _buildParagraph(l10n.guideTipsBody),
        const Divider(color: Colors.white24, height: 32),
        _buildSectionTitle(l10n.guideScalesTitle),
        _buildParagraph('Visual reference for common scales (Key of C):'),
        _buildScaleMemoItem('MAJOR / IONIAN', [0, 2, 4, 5, 7, 9, 11]),
        _buildScaleMemoItem('DORIAN', [0, 2, 3, 5, 7, 9, 10]),
        _buildScaleMemoItem('LYDIAN', [0, 2, 4, 6, 7, 9, 11]),
        _buildScaleMemoItem('MIXOLYDIAN', [0, 2, 4, 5, 7, 9, 10]),
        _buildScaleMemoItem('AEOLIAN (MINOR)', [0, 2, 3, 5, 7, 8, 10]),
        _buildScaleMemoItem('MAJOR PENTATONIC', [0, 2, 4, 7, 9]),
        _buildScaleMemoItem('MINOR PENTATONIC', [0, 3, 5, 7, 10]),
        _buildScaleMemoItem('MINOR BLUES', [0, 3, 5, 6, 7, 10]),
      ],
    );
  }
}

/// Explains the rack system, back-panel patch view, jack types, and cable
/// drawing/disconnecting workflow introduced in Phase 5.
class _PatchViewTab extends StatelessWidget {
  const _PatchViewTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      children: [
        // ── Rack intro ──────────────────────────────────────────────────────
        _buildSectionTitle(l10n.guidePatchRackTitle),
        _buildParagraph(l10n.guidePatchRackBody),
        const SizedBox(height: 8),
        _buildSubTitle(l10n.guidePatchSlotTypesTitle),
        _buildFeatureItem(Icons.piano, l10n.guidePatchSlotKeyboard, l10n.guidePatchSlotKeyboardDesc),
        _buildFeatureItem(Icons.mic, l10n.guidePatchSlotVocoder, l10n.guidePatchSlotVocoderDesc),
        _buildFeatureItem(Icons.auto_awesome, l10n.guidePatchSlotJam, l10n.guidePatchSlotJamDesc),
        _buildFeatureItem(Icons.extension, l10n.guidePatchSlotVst3, l10n.guidePatchSlotVst3Desc),
        const SizedBox(height: 4),
        _buildDesktopOnlyBox(l10n.guidePatchSlotVst3DesktopOnly),
        const Divider(color: Colors.white12, height: 40),
        // ── Patch view ──────────────────────────────────────────────────────
        _buildSectionTitle(l10n.guidePatchTitle),
        _buildParagraph(l10n.guidePatchIntro),
        const SizedBox(height: 20),
        _buildSubTitle(l10n.guidePatchToggleTitle),
        _buildParagraph(l10n.guidePatchToggleBody),
        const SizedBox(height: 20),
        _buildSubTitle(l10n.guidePatchJacksTitle),
        _buildParagraph(l10n.guidePatchJacksBody),
        _buildJackLegend(),
        const SizedBox(height: 20),
        _buildSubTitle(l10n.guidePatchDrawTitle),
        _buildParagraph(l10n.guidePatchDrawBody),
        const SizedBox(height: 20),
        _buildSubTitle(l10n.guidePatchDisconnectTitle),
        _buildParagraph(l10n.guidePatchDisconnectBody),
        const SizedBox(height: 20),
        _buildSubTitle(l10n.guidePatchDataTitle),
        _buildParagraph(l10n.guidePatchDataBody),
        const SizedBox(height: 20),
        _buildSubTitle(l10n.guidePatchSharedEffectTitle),
        _buildParagraph(l10n.guidePatchSharedEffectBody),
        const SizedBox(height: 8),
        _buildWarningBox(l10n.guidePatchSharedEffectWorkaround),
        const SizedBox(height: 12),
        _buildInfoBox(l10n.guidePatchTip),
      ],
    );
  }

  /// A warning-styled box used to flag routing constraints that will
  /// block a drag-drop attempt. Visually distinct from
  /// [_buildDesktopOnlyBox] (amber / desktop) and [_buildInfoBox]
  /// (neutral / info) so users recognise it as "this will produce a
  /// rejection toast if you try it".
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
          const Icon(Icons.warning_amber_outlined,
              color: Colors.redAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// An amber-tinted info box used to flag platform-specific limitations,
  /// such as VST3 support being desktop-only.
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
            child: Text(
              text,
              style: const TextStyle(color: Colors.amber, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// Visual legend showing each cable colour and the signal family it represents.
  Widget _buildJackLegend() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8, left: 8),
      child: Column(
        children: [
          _buildLegendRow(const Color(0xFFFFD700), 'MIDI', 'MIDI IN / OUT'),
          _buildLegendRow(const Color(0xFFFF4444), 'Audio L', 'AUDIO OUT L / AUDIO IN L'),
          _buildLegendRow(Colors.white70, 'Audio R', 'AUDIO OUT R / AUDIO IN R'),
          _buildLegendRow(const Color(0xFFFF8C00), 'Send/Return', 'SEND OUT / RETURN IN'),
          _buildLegendRow(const Color(0xFFAB47BC), 'Data', 'CHORD & SCALE (Jam Mode)'),
        ],
      ),
    );
  }

  /// A single row in the cable colour legend: a coloured swatch, a short
  /// family label, and a description of the ports it covers.
  Widget _buildLegendRow(Color color, String family, String ports) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 1),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(
              family,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              ports,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
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

Widget _buildScaleMemoItem(String name, List<int> intervals) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(4),
            ),
            child: CustomPaint(painter: _StaffPainter(intervals)),
          ),
        ),
      ],
    ),
  );
}

class _StaffPainter extends CustomPainter {
  final List<int> intervals;
  _StaffPainter(this.intervals);

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint =
        Paint()
          ..color = Colors.white24
          ..strokeWidth = 1;
    final notePaint =
        Paint()
          ..color = Colors.blueAccent
          ..style = PaintingStyle.fill;
    const double staffHeight = 30.0;
    final double startY = (size.height - staffHeight) / 2;
    final double lineSpacing = staffHeight / 4;

    final double gLineY = startY + 3 * lineSpacing;
    final TextPainter clefPainter = TextPainter(
      text: const TextSpan(
        text: '\uD834\uDD1E',
        style: TextStyle(color: Colors.white54, fontSize: 32, height: 1.0),
      ),
      textDirection: TextDirection.ltr,
    );
    clefPainter.layout();
    clefPainter.paint(canvas, Offset(8, gLineY - 20));

    for (int i = 0; i < 5; i++) {
      final y = startY + i * lineSpacing;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final Map<int, _ScaleNote> noteMap = {
      0: _ScaleNote(0, null),
      1: _ScaleNote(1, '\u266D'),
      2: _ScaleNote(1, null),
      3: _ScaleNote(2, '\u266D'),
      4: _ScaleNote(2, null),
      5: _ScaleNote(3, null),
      6: _ScaleNote(3, '\u266F'),
      7: _ScaleNote(4, null),
      8: _ScaleNote(5, '\u266D'),
      9: _ScaleNote(5, null),
      10: _ScaleNote(6, '\u266D'),
      11: _ScaleNote(6, null),
    };

    final double startX = 40;
    final double availableWidth = size.width - startX - 10;
    final double noteSpacing =
        availableWidth / (intervals.length == 1 ? 1 : intervals.length - 1 + 1);

    for (int i = 0; i < intervals.length; i++) {
      final interval = intervals[i] % 12;
      final x = startX + i * noteSpacing;
      final info = noteMap[interval]!;

      final line1Y = startY + 4 * lineSpacing;
      final y = line1Y - (info.step - 2) * (lineSpacing / 2);

      if (info.step == 0) {
        canvas.drawLine(Offset(x - 8, y), Offset(x + 8, y), linePaint);
      }

      if (info.accidental != null) {
        final TextPainter tp = TextPainter(
          text: TextSpan(
            text: info.accidental,
            style: const TextStyle(
              color: Colors.blueAccent,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        final double yOffset = info.accidental == '\u266D' ? -14 : -11;
        tp.paint(canvas, Offset(x - 16, y + yOffset));
      }

      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: 9, height: 7),
        notePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScaleNote {
  final int step;
  final String? accidental;
  _ScaleNote(this.step, this.accidental);
}
