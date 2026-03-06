import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// A modal dialog containing the comprehensive user guide for GrooveForge.
///
/// The guide is organized into distinct tabs: Features, MIDI Connectivity,
/// Soundfonts, and Musical Tips.
class UserGuideModal extends StatelessWidget {
  const UserGuideModal({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return DefaultTabController(
      length: 4,
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
                  Text(
                    l10n.guideTitle.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              TabBar(
                tabs: [
                  Tab(
                    icon: const Icon(Icons.auto_awesome),
                    text: l10n.guideTabFeatures.toUpperCase(),
                  ),
                  Tab(
                    icon: const Icon(Icons.usb),
                    text: l10n.guideTabMidi.toUpperCase(),
                  ),
                  Tab(
                    icon: const Icon(Icons.library_music),
                    text: l10n.guideTabSoundfonts.toUpperCase(),
                  ),
                  Tab(
                    icon: const Icon(Icons.music_note),
                    text: l10n.guideTabTips.toUpperCase(),
                  ),
                ],
                indicatorColor: Colors.blueAccent,
                labelColor: Colors.blueAccent,
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    _FeaturesTab(),
                    _MidiConnectivityTab(),
                    _SoundfontsTab(),
                    _MusicalTipsTab(),
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
  const _FeaturesTab();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      children: [
        _buildWelcomeHeader(context, l10n),
        const SizedBox(height: 24),
        _buildSectionTitle(l10n.guideJamModeTitle),
        _buildParagraph(l10n.guideJamModeBody),
        const SizedBox(height: 20),
        _buildSectionTitle(l10n.guideVocoderTitle),
        _buildParagraph(l10n.guideVocoderBody),
        const SizedBox(height: 10),
        _buildInfoBox(
          l10n.guideVocoderBody.split('\n').last,
        ), // The latency warning
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
        _buildSubTitle('1. Hardware Connection'),
        _buildStep(
          1,
          'Connect controller via USB (OTG) or power on BLE device.',
        ),
        _buildStep(2, 'Go to Settings > MIDI Input and select your device.'),
        const SizedBox(height: 10),
        _buildSubTitle('2. CC & System Mappings'),
        _buildParagraph('Bind knobs to effects like Volume or System Actions:'),
        _buildFeatureItem(
          Icons.skip_next,
          'Patch Up/Down',
          'Quickly switch instruments.',
        ),
        _buildFeatureItem(
          Icons.loop,
          'Cycle Scales',
          'Change harmony on the fly.',
        ),
        _buildFeatureItem(
          Icons.lock,
          'Toggle Jam',
          'Force slaves to follow your lead.',
        ),
        const SizedBox(height: 24),
        _buildSectionTitle(l10n.guideMidiBestPracticeTitle),
        _buildParagraph(l10n.guideMidiBestPracticeBody),
        const SizedBox(height: 12),
        _buildInfoBox(
          'Tip: Most modern MIDI controllers allow splitting the keys into distinct zones/channels.',
        ),
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

// Helper Widgets
Widget _buildWelcomeHeader(BuildContext context, AppLocalizations l10n) {
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
          l10n.guideWelcomeHeader,
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
        _buildBulletItem(l10n.guideFeatureList1),
        _buildBulletItem(l10n.guideFeatureList2),
        _buildBulletItem(l10n.guideFeatureList3),
        _buildBulletItem(l10n.guideFeatureList4),
      ],
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
