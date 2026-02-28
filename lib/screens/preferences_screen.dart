import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:grooveforge/services/midi_service.dart';
import 'package:grooveforge/services/audio_engine.dart';
import '../screens/cc_preferences.dart';
import 'package:grooveforge/services/cc_mapping_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart' show rootBundle;

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  MidiDevice? _connectedDevice;
  String _appVersion = 'Loading...';

  @override
  void initState() {
    super.initState();
    _checkConnectedDevices();
    _loadVersionInfo();
  }

  Future<void> _loadVersionInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = '${info.version}+${info.buildNumber}';
      });
    }
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
      },
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

  void _showChangelogDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text('Changelog'),
            content: SizedBox(
              width: 600,
              height: 500,
              child: FutureBuilder<String>(
                future: rootBundle.loadString('CHANGELOG.md'),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text('Error loading changelog.'),
                    );
                  }
                  return Markdown(
                    data: snapshot.data ?? '',
                    styleSheet: MarkdownStyleSheet(
                      h1: const TextStyle(color: Colors.blueAccent),
                      h2: const TextStyle(color: Colors.blueAccent),
                      h3: const TextStyle(color: Colors.deepPurpleAccent),
                      p: const TextStyle(color: Colors.white70),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Preferences')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'MIDI Connection',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.blueAccent,
            ),
          ),
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

          const Text(
            'Soundfonts',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurpleAccent,
            ),
          ),
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
                        // Sort: Put default soundfont at the top
                        final sortedPaths = List<String>.from(
                          engine.loadedSoundfonts,
                        );
                        sortedPaths.sort((a, b) {
                          bool isADefault = a.endsWith('default_soundfont.sf2');
                          bool isBDefault = b.endsWith('default_soundfont.sf2');
                          if (isADefault && !isBDefault) return -1;
                          if (!isADefault && isBDefault) return 1;
                          return a.compareTo(b);
                        });

                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: sortedPaths.length,
                          itemBuilder: (context, index) {
                            String path = sortedPaths[index];
                            bool isDefault = path.endsWith(
                              'default_soundfont.sf2',
                            );
                            String filename =
                                isDefault
                                    ? 'Default soundfont'
                                    : path.split(Platform.pathSeparator).last;
                            return ListTile(
                              leading: Icon(
                                Icons.piano,
                                color: isDefault ? Colors.blue : Colors.grey,
                              ),
                              title: Text(
                                filename,
                                style: TextStyle(
                                  fontWeight:
                                      isDefault
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                path,
                                style: const TextStyle(fontSize: 10),
                              ),
                              trailing:
                                  isDefault
                                      ? null
                                      : IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.redAccent,
                                        ),
                                        onPressed: () {
                                          engine.unloadSoundfont(path);
                                        },
                                      ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          const Text(
            'Routing & Control',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune, color: Colors.teal),
              title: const Text('CC Mapping Preferences'),
              subtitle: const Text(
                'Map hardware knobs to GM Effects and System Actions',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CcPreferencesScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 32),

          const Text(
            'Key Gestures',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Consumer<AudioEngine>(
              builder: (context, engine, _) {
                return Column(
                  children: [
                    ValueListenableBuilder<GestureAction>(
                      valueListenable: engine.verticalGestureAction,
                      builder: (context, action, _) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.height, color: Colors.orange),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Vertical Interaction',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                    Text(
                                      'Swipe up/down on a key',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              DropdownButton<GestureAction>(
                                value: action,
                                items: const [
                                  DropdownMenuItem(
                                    value: GestureAction.none,
                                    child: Text('None'),
                                  ),
                                  DropdownMenuItem(
                                    value: GestureAction.pitchBend,
                                    child: Text('Pitch Bend'),
                                  ),
                                  DropdownMenuItem(
                                    value: GestureAction.vibrato,
                                    child: Text('Vibrato'),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    engine.verticalGestureAction.value = val;
                                    engine.stateNotifier.value++;
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ValueListenableBuilder<GestureAction>(
                      valueListenable: engine.horizontalGestureAction,
                      builder: (context, action, _) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.unfold_more, color: Colors.blue),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Horizontal Interaction',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                    Text(
                                      'Slide left/right on a key',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              DropdownButton<GestureAction>(
                                value: action,
                                items: const [
                                  DropdownMenuItem(
                                    value: GestureAction.none,
                                    child: Text('None'),
                                  ),
                                  DropdownMenuItem(
                                    value: GestureAction.pitchBend,
                                    child: Text('Pitch Bend'),
                                  ),
                                  DropdownMenuItem(
                                    value: GestureAction.vibrato,
                                    child: Text('Vibrato'),
                                  ),
                                  DropdownMenuItem(
                                    value: GestureAction.glissando,
                                    child: Text('Glissando'),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    engine.horizontalGestureAction.value = val;
                                    engine.stateNotifier.value++;
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 32),

          const Text(
            'Virtual Piano Display',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Consumer<AudioEngine>(
              builder: (context, engine, _) {
                return ValueListenableBuilder<int>(
                  valueListenable: engine.pianoKeysToShow,
                  builder: (context, keysToShow, _) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.piano, color: Colors.orange),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Visible Keys (Zoom)',
                                  style: TextStyle(fontSize: 16),
                                ),
                                Text(
                                  'Number of white keys to show at once',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DropdownButton<int>(
                            value: keysToShow,
                            items: const [
                              DropdownMenuItem(
                                value: 15,
                                child: Text('25 keys (15 white)'),
                              ),
                              DropdownMenuItem(
                                value: 22,
                                child: Text('37 keys (22 white)'),
                              ),
                              DropdownMenuItem(
                                value: 29,
                                child: Text('49 keys (29 white)'),
                              ),
                              DropdownMenuItem(
                                value: 52,
                                child: Text('88 keys (52 white)'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                engine.pianoKeysToShow.value = val;
                                engine.stateNotifier.value++;
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Consumer<AudioEngine>(
              builder: (context, engine, _) {
                return ValueListenableBuilder<String>(
                  valueListenable: engine.notationFormat,
                  builder: (context, format, _) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.music_note, color: Colors.blueGrey),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Music Notation Format',
                                  style: TextStyle(fontSize: 16),
                                ),
                                Text(
                                  'How chord names are displayed',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DropdownButton<String>(
                            value: format,
                            items: const [
                              DropdownMenuItem(
                                value: 'Standard',
                                child: Text('Standard (C, D, E)'),
                              ),
                              DropdownMenuItem(
                                value: 'Solfege',
                                child: Text('Solfège (Do, Ré, Mi)'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                engine.notationFormat.value = val;
                                // Forces _saveState
                                engine.stateNotifier.value++;
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Consumer<AudioEngine>(
              builder: (context, engine, _) {
                return ValueListenableBuilder<ScaleLockMode>(
                  valueListenable: engine.lockModePreference,
                  builder: (context, lockMode, _) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_clock,
                            color: Colors.purpleAccent,
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Scale Lock Mode',
                                  style: TextStyle(fontSize: 16),
                                ),
                                Text(
                                  'Classic (per channel) vs Jam (master-slave)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DropdownButton<ScaleLockMode>(
                            value: lockMode,
                            items: const [
                              DropdownMenuItem(
                                value: ScaleLockMode.classic,
                                child: Text('Classic Mode'),
                              ),
                              DropdownMenuItem(
                                value: ScaleLockMode.jam,
                                child: Text('Jam Mode'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                engine.lockModePreference.value = val;
                                engine.stateNotifier.value++;
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
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
                        ccItems.add(
                          DropdownMenuItem(
                            value: i,
                            child: Text('$name (CC $i)'),
                          ),
                        );
                      }
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.waves, color: Colors.teal),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Aftertouch Effect',
                                  style: TextStyle(fontSize: 16),
                                ),
                                Text(
                                  'Route keyboard pressure to this CC',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
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
                  },
                );
              },
            ),
          ),
          const Divider(height: 40),

          const Text(
            'About',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline, color: Colors.grey),
                  title: const Text('Version'),
                  trailing: Text(
                    _appVersion,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history, color: Colors.grey),
                  title: const Text('View Changelog'),
                  subtitle: const Text('History of changes and updates'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showChangelogDialog,
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          const Divider(height: 40),

          Consumer<AudioEngine>(
            builder: (context, engine, _) {
              return ElevatedButton.icon(
                onPressed: () => _showResetConfirmation(context, engine),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withValues(alpha: 0.1),
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.restore),
                label: const Text('Reset All Preferences'),
              );
            },
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _showResetConfirmation(BuildContext context, AudioEngine engine) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text('Reset All Preferences?'),
            content: const Text(
              'This will clear all your settings, loaded soundfonts, and custom assignments. This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await engine.resetAllPreferences();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                child: const Text('Reset Everything'),
              ),
            ],
          ),
    );
  }
}
