import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'midi_service.dart';
import 'audio_engine.dart';
import 'cc_mapping_service.dart';
import 'cc_preferences.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        Provider<CcMappingService>(create: (_) => CcMappingService()),
        Provider<MidiService>(create: (_) => MidiService()),
        Provider<AudioEngine>(create: (_) => AudioEngine()),
      ],
      child: const YakaliveApp(),
    ),
  );
}

class YakaliveApp extends StatelessWidget {
  const YakaliveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yakalive Synthesizer',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const SynthesizerScreen(),
    );
  }
}

class SynthesizerScreen extends StatefulWidget {
  const SynthesizerScreen({super.key});

  @override
  State<SynthesizerScreen> createState() => _SynthesizerScreenState();
}

class _SynthesizerScreenState extends State<SynthesizerScreen> {
  String? _soundfontName;
  MidiDevice? _connectedDevice;

  @override
  void initState() {
    super.initState();
    // Start listening to MIDI inputs and pass them to Audio Engine
    final midiService = context.read<MidiService>();
    final audioEngine = context.read<AudioEngine>();
    final ccMappingService = context.read<CcMappingService>();
    
    audioEngine.ccMappingService = ccMappingService;
    
    midiService.onMidiDataReceived = (packet) {
       audioEngine.processMidiPacket(packet);
    };
  }

  Future<void> _loadSoundfont() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      if (file.path.endsWith('.sf2') || file.path.endsWith('.SF2')) {
         if (!mounted) return;
         await context.read<AudioEngine>().init(file);
         if (!mounted) return;
         setState(() {
           _soundfontName = result.files.single.name;
         });
      }
    }
  }

  void _showMidiDevicesDialog() async {
    final midiService = context.read<MidiService>();
    final devices = await midiService.devices;

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select MIDI Device'),
          content: SizedBox(
            width: 300,
            height: 400,
            child: ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                return ListTile(
                  title: Text(device.name),
                  subtitle: Text(device.id),
                  onTap: () async {
                    if (_connectedDevice != null) {
                      midiService.disconnect(_connectedDevice!);
                    }
                    await midiService.connect(device);
                    if (!context.mounted) return;
                    setState(() {
                      _connectedDevice = device;
                    });
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        );
      }
    );
  }

  void _showCcHelpDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Standard MIDI CCs (General MIDI)'),
          content: SizedBox(
            width: 350,
            height: 450,
            child: ListView(
              children: const [
                ListTile(title: Text('CC 0'), subtitle: Text('Bank Select (MSB)')),
                ListTile(title: Text('CC 1'), subtitle: Text('Modulation Wheel (Vibrato)')),
                ListTile(title: Text('CC 2'), subtitle: Text('Breath Control')),
                ListTile(title: Text('CC 4'), subtitle: Text('Foot Pedal')),
                ListTile(title: Text('CC 5'), subtitle: Text('Portamento Time')),
                ListTile(title: Text('CC 7'), subtitle: Text('Main Volume')),
                ListTile(title: Text('CC 10'), subtitle: Text('Pan (Stereo)')),
                ListTile(title: Text('CC 11'), subtitle: Text('Expression (Sub-Volume)')),
                ListTile(title: Text('CC 64'), subtitle: Text('Sustain Pedal (On/Off)')),
                ListTile(title: Text('CC 65'), subtitle: Text('Portamento (On/Off)')),
                ListTile(title: Text('CC 71'), subtitle: Text('Resonance (Filter)')),
                ListTile(title: Text('CC 74'), subtitle: Text('Frequency Cutoff (Filter)')),
                ListTile(title: Text('CC 91'), subtitle: Text('Reverb Send Level')),
                ListTile(title: Text('CC 93'), subtitle: Text('Chorus Send Level')),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            )
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yakalive Soundfont Player'),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'MIDI CC Help',
            onPressed: _showCcHelpDialog,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const Icon(Icons.piano, size: 64, color: Colors.deepPurpleAccent),
                    const SizedBox(height: 16),
                    Text(
                      _soundfontName ?? 'No Soundfont Loaded (.sf2)',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _loadSoundfont,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Load Soundfont'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const Icon(Icons.cable, size: 64, color: Colors.blueAccent),
                    const SizedBox(height: 16),
                    Text(
                      _connectedDevice?.name ?? 'No MIDI Device Connected',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _showMidiDevicesDialog,
                      icon: const Icon(Icons.settings_input_component),
                      label: const Text('Connect MIDI Device'),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CcPreferencesScreen()),
                        );
                      },
                      icon: const Icon(Icons.tune),
                      label: const Text('CC Mapping Preferences'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
