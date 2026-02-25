import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'midi_service.dart';
import 'audio_engine.dart';
import 'cc_preferences.dart';
import 'cc_mapping_service.dart';

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  MidiDevice? _connectedDevice;

  @override
  void initState() {
    super.initState();
    _checkConnectedDevices();
  }

  void _checkConnectedDevices() {
    final midiService = context.read<MidiService>();
    Future.microtask(() async {
      final devs = await midiService.devices;
      if (!mounted) return;
      
      for (var device in devs) {
         if (device.connected) {
            setState(() {
               _connectedDevice = device;
            });
            break;
         }
      }
    });
  }

  void _showMidiDevicesDialog() async {
    final midiService = context.read<MidiService>();
    final devices = await midiService.devices;

    if (!mounted) return;

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

  Future<void> _loadSoundfont() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      if (file.path.endsWith('.sf2') || file.path.endsWith('.SF2')) {
         if (!mounted) return;
         await context.read<AudioEngine>().loadSoundfont(file);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferences'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text('MIDI Connection', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cable, color: Colors.blue),
              title: const Text('Connect MIDI Device'),
              subtitle: Text(_connectedDevice?.name ?? 'Not connected'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showMidiDevicesDialog,
            ),
          ),
          const SizedBox(height: 32),
          
          const Text('Soundfonts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurpleAccent)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.add, color: Colors.deepPurple),
                  title: const Text('Load Soundfont (.sf2)'),
                  onTap: _loadSoundfont,
                ),
                const Divider(height: 1),
                Consumer<AudioEngine>(
                  builder: (context, engine, child) {
                    return ValueListenableBuilder<int>(
                      valueListenable: engine.stateNotifier,
                      builder: (context, _, child) {
                        if (engine.loadedSoundfonts.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text('No soundfonts loaded.'),
                          );
                        }
                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: engine.loadedSoundfonts.length,
                          itemBuilder: (context, index) {
                            String path = engine.loadedSoundfonts[index];
                            String filename = path.split(Platform.pathSeparator).last;
                            return ListTile(
                              leading: const Icon(Icons.piano, color: Colors.grey),
                              title: Text(filename),
                              subtitle: Text(path, style: const TextStyle(fontSize: 10)),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent),
                                onPressed: () {
                                  engine.unloadSoundfont(path);
                                },
                              ),
                            );
                          },
                        );
                      },
                    );
                  }
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          
          const Text('Routing & Control', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune, color: Colors.teal),
              title: const Text('CC Mapping Preferences'),
              subtitle: const Text('Map hardware knobs to GM Effects and System Actions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CcPreferencesScreen()),
                );
              },
            ),
          ),
          const SizedBox(height: 32),
          
          const Text('Virtual Piano', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange)),
          const SizedBox(height: 8),
          Card(
            child: Consumer<AudioEngine>(
              builder: (context, engine, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: engine.dragToPlay,
                  builder: (context, isDragEnabled, _) {
                    return SwitchListTile(
                      secondary: const Icon(Icons.touch_app, color: Colors.orange),
                      title: const Text('Drag to Play (Glissando)'),
                      subtitle: const Text('Play notes smoothly by sliding your finger across the virtual piano keys'),
                      value: isDragEnabled,
                      activeThumbColor: Colors.orange,
                      onChanged: (val) {
                        engine.dragToPlay.value = val;
                        // Save triggers automatically when boolean toggles but for safety we can trigger internal save
                        engine.stateNotifier.value++; // forces _saveState downstream technically but we should invoke properly
                      },
                    );
                  }
                );
              }
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Consumer<AudioEngine>(
              builder: (context, engine, _) {
                return ValueListenableBuilder<int>(
                  valueListenable: engine.aftertouchDestCc,
                  builder: (context, destCc, _) {
                    final List<DropdownMenuItem<int>> ccItems = [];
                    for (int i = 0; i <= 127; i++) {
                      if (CcMappingService.standardGmCcs.containsKey(i)) {
                        String name = CcMappingService.standardGmCcs[i]!;
                        ccItems.add(DropdownMenuItem(value: i, child: Text('$name (CC $i)')));
                      }
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        children: [
                          const Icon(Icons.waves, color: Colors.teal),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Aftertouch Effect', style: TextStyle(fontSize: 16)),
                                Text('Route keyboard pressure to this CC', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                          DropdownButton<int>(
                            value: destCc,
                            items: ccItems,
                            menuMaxHeight: 300,
                            onChanged: (val) {
                              if (val != null) {
                                engine.aftertouchDestCc.value = val;
                                engine.stateNotifier.value++;
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  }
                );
              }
            ),
          ),
        ],
      ),
    );
  }
}
