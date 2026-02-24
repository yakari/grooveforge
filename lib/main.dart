import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'midi_service.dart';
import 'audio_engine.dart';
import 'cc_mapping_service.dart';
import 'preferences_screen.dart';
import 'gm_instruments.dart';

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
  // Store listener reference so we can safely remove it on dispose
  void Function()? _toastListener;

  // Track the flashing state of channels
  final Map<int, bool> _channelFlashState = {};

  @override
  void initState() {
    super.initState();
    // Start listening to MIDI inputs and pass them to Audio Engine
    final midiService = context.read<MidiService>();
    final audioEngine = context.read<AudioEngine>();
    final ccMappingService = context.read<CcMappingService>();
    
    audioEngine.ccMappingService = ccMappingService;
    
    // Initialize the new persistent AudioEngine
    audioEngine.init();
    
    midiService.onMidiDataReceived = (packet) {
       audioEngine.processMidiPacket(packet);
    };

    // Listen to telemetry for flashing channels
    ccMappingService.lastEventNotifier.addListener(() {
       final event = ccMappingService.lastEventNotifier.value;
       if (event != null && mounted) {
          int ch = event.channel;
          setState(() { _channelFlashState[ch] = true; });
          Future.delayed(const Duration(milliseconds: 150), () {
             if (mounted) {
               setState(() { _channelFlashState[ch] = false; });
             }
          });
       }
    });

    // Listen for Audio Engine Toasts (Soundfont loaded, patch changed)
    _toastListener = () {
      final msg = audioEngine.toastNotifier.value;
      if (msg != null && mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
      }
    };
    audioEngine.toastNotifier.addListener(_toastListener!);
  }

  @override
  void dispose() {
    if (_toastListener != null) {
      context.read<AudioEngine>().toastNotifier.removeListener(_toastListener!);
    }
    super.dispose();
  }

  void _showChannelConfigDialog(int channelIndex, AudioEngine engine) {
    if (engine.loadedSoundfonts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please load a soundfont in Preferences first')));
      return;
    }

    String? selectedSf = engine.channels[channelIndex].soundfontPath ?? engine.loadedSoundfonts.first;
    int program = engine.channels[channelIndex].program;
    int bank = engine.channels[channelIndex].bank;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Configure Channel ${channelIndex + 1}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Soundfont'),
                    value: engine.loadedSoundfonts.contains(selectedSf) ? selectedSf : engine.loadedSoundfonts.first,
                    items: engine.loadedSoundfonts.map((sf) => DropdownMenuItem(
                      value: sf,
                      child: Text(sf.split(Platform.pathSeparator).last, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedSf = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: program.toString(),
                    decoration: const InputDecoration(labelText: 'Program / Patch (0-127)'),
                    keyboardType: TextInputType.number,
                    onChanged: (val) => program = int.tryParse(val) ?? 0,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: bank.toString(),
                    decoration: const InputDecoration(labelText: 'Bank Select (MSB)'),
                    keyboardType: TextInputType.number,
                    onChanged: (val) => bank = int.tryParse(val) ?? 0,
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    engine.assignSoundfontToChannel(channelIndex, selectedSf!);
                    engine.assignPatchToChannel(channelIndex, program, bank: bank);
                    Navigator.pop(ctx);
                  }, 
                  child: const Text('Save')
                ),
              ],
            );
          }
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
        title: const Text('Yakalive Synth'),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'MIDI CC Help',
            onPressed: _showCcHelpDialog,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings & Setup',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PreferencesScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Consumer<AudioEngine>(
          builder: (context, engine, child) {
            return ValueListenableBuilder<int>(
              valueListenable: engine.stateNotifier,
              builder: (context, _, child) {
                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 250,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: 16,
                  itemBuilder: (context, index) {
                    final state = engine.channels[index];
                    String sfName = state.soundfontPath?.split(Platform.pathSeparator).last ?? 'No Soundfont';
                    String patchName = GmInstruments.list[state.program] ?? 'Unknown Patch';
                    bool isFlashing = _channelFlashState[index] ?? false;

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        color: isFlashing ? Colors.blueAccent.withValues(alpha: 0.4) : Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isFlashing ? Colors.blueAccent : Colors.transparent,
                          width: 2,
                        ),
                        boxShadow: [
                          if (isFlashing)
                             BoxShadow(color: Colors.blueAccent.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)
                        ]
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showChannelConfigDialog(index, engine),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('CH ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blueAccent)),
                                  if (isFlashing) const Icon(Icons.circle, color: Colors.greenAccent, size: 12),
                                ],
                              ),
                              const Spacer(),
                              const Icon(Icons.piano, color: Colors.grey, size: 20),
                              const SizedBox(height: 4),
                              Text(sfName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(patchName, style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.music_note, color: Colors.grey, size: 16),
                                  const SizedBox(width: 4),
                                  Text('Prog: ${state.program}', style: const TextStyle(fontSize: 12)),
                                  const SizedBox(width: 8),
                                  Text('Bank: ${state.bank}', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
