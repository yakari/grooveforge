import 'package:flutter/material.dart';

class UserGuideModal extends StatelessWidget {
  const UserGuideModal({super.key});

  @override
  Widget build(BuildContext context) {
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
                  const Text(
                    'GROOVEFORGE USER GUIDE',
                    style: TextStyle(
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
              const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.usb), text: 'CONNECTIVITY'),
                  Tab(icon: Icon(Icons.library_music), text: 'SOUNDS'),
                  Tab(
                    icon: Icon(Icons.settings_input_component),
                    text: 'CC MAPPING',
                  ),
                  Tab(icon: Icon(Icons.group_work), text: 'JAM MODE'),
                ],
                indicatorColor: Colors.blueAccent,
                labelColor: Colors.blueAccent,
                unselectedLabelColor: Colors.white54,
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    _ConnectivityTab(),
                    _SoundsTab(),
                    _CcMappingTab(),
                    _JamModeTab(),
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

class _ConnectivityTab extends StatelessWidget {
  const _ConnectivityTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      children: [
        _buildSectionTitle('Linking a MIDI Controller'),
        _buildParagraph(
          'GrooveForge supports USB MIDI and Bluetooth LE MIDI controllers out of the box. '
          'To connect your hardware:',
        ),
        _buildStep(
          1,
          'Connect your controller via USB or power on your BLE controller.',
        ),
        _buildStep(2, 'Navigate to the Settings (gear icon) in the top right.'),
        _buildStep(
          3,
          'Under "Internal MIDI Input", select your device from the list.',
        ),
        _buildStep(
          4,
          'The app will auto-connect. You will see a toast notification upon success.',
        ),
        const SizedBox(height: 20),
        _buildInfoBox(
          'Tip: If your device does not appear, ensure it is in a MIDI-compatible mode and try restarting the app.',
        ),
      ],
    );
  }
}

class _SoundsTab extends StatelessWidget {
  const _SoundsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      children: [
        _buildSectionTitle('Managing Soundfonts'),
        _buildParagraph(
          'GrooveForge comes with a "Default Soundfont", but you can load your own .sf2 files for high-quality instruments.',
        ),
        _buildStep(
          1,
          'In Settings, use the "IMPORT SF2" button to add files from your device.',
        ),
        _buildStep(
          2,
          'Imported soundfonts are securely moved to internal storage for consistent access.',
        ),
        _buildParagraph('On each Channel Card, you can customize:'),
        _buildFeatureItem(
          Icons.folder,
          'Soundfont',
          'Choose from your loaded library.',
        ),
        _buildFeatureItem(
          Icons.piano,
          'Patch',
          'Select the specific instrument preset.',
        ),
        _buildFeatureItem(
          Icons.layers,
          'Bank',
          'Switch between different sound banks within the SF2.',
        ),
        const SizedBox(height: 20),
        _buildInfoBox(
          'Note: Changing a soundfont on one channel does not affect others unless you manually assign them.',
        ),
      ],
    );
  }
}

class _CcMappingTab extends StatelessWidget {
  const _CcMappingTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      children: [
        _buildSectionTitle('MIDI CC Remapping'),
        _buildParagraph(
          'Remapping allows you to use your controller\'s knobs, sliders, and buttons to control app functions.',
        ),
        _buildStep(1, 'Go to Settings > CC MAPPINGS.'),
        _buildStep(
          2,
          'Select a slot and choose a Target function (e.g., Modulation, Volume, or System Actions).',
        ),
        _buildStep(
          3,
          'Use "LEARN" and move your physical control to auto-assign the CC number.',
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('System Actions (Exhaustive List)'),
        _buildParagraph(
          'Mapping to a Target CC above 1000 triggers application-level events. '
          'Note: Toggle and Cycle actions have a 250ms debounce to prevent "double-triggers" from sensitive pads.',
        ),
        _buildFeatureItem(
          Icons.lock,
          'Start/Stop Jam Mode (1007)',
          'Starts or stops the Jam Mode, which automatically locks selected channels scales based on the chords played on the master channel.',
        ),
        _buildFeatureItem(
          Icons.loop,
          'Cycle Scale Type (1008)',
          'Quickly cycle through scales: Standard, Jazz, Asiatic, etc.',
        ),
        _buildFeatureItem(
          Icons.skip_next,
          'Next/Prev Patch (1003/1004)',
          'Increment or decrement the current instrument patch.',
        ),
        _buildFeatureItem(
          Icons.library_music,
          'Next/Prev Soundfont (1001/1002)',
          'Switch the entire sound library for the channel.',
        ),
        _buildFeatureItem(
          Icons.linear_scale,
          'Absolute Patch Sweep (1005)',
          'Maps a knob/slider (0-127) directly to the instrument index.',
        ),
        _buildFeatureItem(
          Icons.layers,
          'Absolute Bank Sweep (1006)',
          'Maps a knob/slider directly to the Soundfont bank index.',
        ),
      ],
    );
  }
}

class _JamModeTab extends StatelessWidget {
  const _JamModeTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      children: [
        _buildSectionTitle('Smart Jam Mode (v1.3.0)'),
        _buildParagraph(
          'Jam Mode is the engine\'s most powerful feature, allowing intelligent scale synchronization across channels.',
        ),
        const SizedBox(height: 10),
        _buildSubTitle('1. Master & Slaves'),
        _buildParagraph(
          '• Define a Master Channel: Its played notes are analyzed to find the "best fit" chord identity.\n'
          '• Assign Slave Channels: They will automatically "snap" their played keys to the nearest note in the scale derived from the Master\'s chord.',
        ),
        const SizedBox(height: 10),
        _buildSubTitle('2. Scale Snapping Algorithm'),
        _buildParagraph(
          'When a slave note is played, the engine calculates the allowed pitch classes for the current scale. '
          'If the played key isn\'t in the scale, it immediately shifts (+/-) to the closest valid interval. '
          'This ensures your performance always stays perfectly in key with the harmony.',
        ),
        const SizedBox(height: 10),
        _buildSubTitle('3. Chord Stabilization'),
        _buildParagraph(
          'A 30ms "Wait-and-See" logic prevents identity flickering during fast finger movements. '
          'When you lift all fingers, the engine preserves the "Peak Chord" (the fullest version of the chord) '
          'so slaved channels stay locked to the harmony during silence.',
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('Scale Quick Memo'),
        _buildParagraph(
          'Here are the primary scales used in Jam Mode (shown in the key of C):',
        ),
        _buildScaleMemoItem('MAJOR / IONIAN', [0, 2, 4, 5, 7, 9, 11]),
        _buildScaleMemoItem('DORIAN', [0, 2, 3, 5, 7, 9, 10]),
        _buildScaleMemoItem('PHRYGIAN', [0, 1, 3, 5, 7, 8, 10]),
        _buildScaleMemoItem('LYDIAN', [0, 2, 4, 6, 7, 9, 11]),
        _buildScaleMemoItem('MIXOLYDIAN', [0, 2, 4, 5, 7, 9, 10]),
        _buildScaleMemoItem('AEOLIAN (MINOR)', [0, 2, 3, 5, 7, 8, 10]),
        _buildScaleMemoItem('LOCRIAN', [0, 1, 3, 5, 6, 8, 10]),
        const Divider(color: Colors.white24, height: 32),
        _buildScaleMemoItem('MAJOR PENTATONIC', [0, 2, 4, 7, 9]),
        _buildScaleMemoItem('MINOR PENTATONIC', [0, 3, 5, 7, 10]),
        _buildScaleMemoItem('MAJOR BLUES', [0, 2, 3, 4, 7, 9]),
        _buildScaleMemoItem('MINOR BLUES', [0, 3, 5, 6, 7, 10]),
        _buildScaleMemoItem('LYDIAN DOMINANT', [0, 2, 4, 6, 7, 9, 10]),
        _buildScaleMemoItem('ALTERED SCALE', [0, 1, 3, 4, 6, 8, 10]),
        _buildScaleMemoItem('HARMONIC MINOR', [0, 2, 3, 5, 7, 8, 11]),
        _buildScaleMemoItem('MELODIC MINOR', [0, 2, 3, 5, 7, 9, 11]),
        _buildScaleMemoItem('WHOLE TONE', [0, 2, 4, 6, 8, 10]),
        _buildScaleMemoItem('DIMINISHED', [0, 1, 3, 4, 6, 7, 9, 10]),
        const SizedBox(height: 20),
      ],
    );
  }
}

// Helper Widgets
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

    // Draw G-Clef (Unicode)
    final double gLineY = startY + 3 * lineSpacing;
    final TextPainter clefPainter = TextPainter(
      text: const TextSpan(
        text: '\uD834\uDD1E',
        style: TextStyle(color: Colors.white54, fontSize: 32, height: 1.0),
      ),
      textDirection: TextDirection.ltr,
    );
    clefPainter.layout();
    // Offset to center the G-loop on the G-line (empirical adjustment)
    clefPainter.paint(canvas, Offset(8, gLineY - 20));

    // Draw 5 lines
    for (int i = 0; i < 5; i++) {
      final y = startY + i * lineSpacing;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Map intervals to diatonic steps and accidentals
    // C=0, C#=1, D=2, D#=3, E=4, F=5, F#=6, G=7, G#=8, A=9, A#=10, B=11
    final Map<int, _ScaleNote> noteMap = {
      0: _ScaleNote(0, null),
      1: _ScaleNote(1, '\u266D'), // ♭
      2: _ScaleNote(1, null),
      3: _ScaleNote(2, '\u266D'), // ♭
      4: _ScaleNote(2, null),
      5: _ScaleNote(3, null),
      6: _ScaleNote(3, '\u266F'), // ♯
      7: _ScaleNote(4, null),
      8: _ScaleNote(5, '\u266D'), // ♭
      9: _ScaleNote(5, null),
      10: _ScaleNote(6, '\u266D'), // ♭
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

      // Line 1 (Bottom) is index 4 in our loop above (startY + 4*lineSpacing)
      final line1Y = startY + 4 * lineSpacing;
      // C4 (step 0) is 2 steps below Line 1 (E4)
      final y = line1Y - (info.step - 2) * (lineSpacing / 2);

      // Ledger line for C4 (step 0)
      if (info.step == 0) {
        canvas.drawLine(Offset(x - 8, y), Offset(x + 8, y), linePaint);
      }

      // Draw Accidental
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
  final int step; // Diatonic step (0=C, 1=D, etc.)
  final String? accidental;
  _ScaleNote(this.step, this.accidental);
}
