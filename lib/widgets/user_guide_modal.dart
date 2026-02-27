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
        _buildSubTitle('Master & Slaves'),
        _buildParagraph(
          '1. Define a Master Channel: Its played chords determine the system-wide mode.\n'
          '2. Assign Slave Channels: They will automatically "snap" their notes to a scale derived from the Master\'s chord.',
        ),
        const SizedBox(height: 10),
        _buildSubTitle('Dynamic Mode Calculation'),
        _buildParagraph(
          'GrooveForge analyzes complex chords in real-time. Playing a CM7 results in Ionian, '
          'while a Dm7 results in Dorian if "Standard" scale is selected. In "Jazz" mode, it '
          'recognizes Altered, Lydian Dominant, and more.',
        ),
        const SizedBox(height: 10),
        _buildSubTitle('Chord Stabilization (New!)'),
        _buildParagraph(
          'A 30ms "Wait-and-See" logic prevents identity flickering. When you lift your fingers, '
          'the engine preserves the "Peak Chord" so your slaves stay locked to the fullest harmony.',
        ),
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
