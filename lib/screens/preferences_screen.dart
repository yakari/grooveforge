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
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../l10n/app_localizations.dart';
import '../services/locale_provider.dart';
import '../services/audio_input_ffi.dart';
import '../services/vst_host_service.dart';
import 'dart:async';

/// The main settings interface for GrooveForge.
///
/// Provides user controls for:
/// - MIDI device connection and disconnection.
/// - Soundfont (`.sf2`) loading, managing, and unloading.
/// - Core synthesizer preferences including scale lock modes (Classic vs Jam),
///   notation format, and piano key visibility.
/// - Interactive gesture mapping (e.g., assigning vertical swipes to Pitch Bend).
/// - Global app state reset.
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
        final loc = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(loc.selectMidiDeviceDialogTitle),
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
      builder: (context) {
        final loc = AppLocalizations.of(context)!;
        final isFrench = Localizations.localeOf(context).languageCode == 'fr';
        final changelogAsset = isFrench ? 'CHANGELOG.fr.md' : 'CHANGELOG.md';

        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(loc.changelogDialogTitle),
          content: SizedBox(
            width: 600,
            height: 500,
            child: FutureBuilder<String>(
              future: rootBundle.loadString(changelogAsset),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(loc.errorLoadingChangelog));
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
              child: Text(loc.closeButton),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(loc.preferencesTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // ======== LANGUAGE SECTION ========
          Text(
            loc.languageTitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.lightBlueAccent,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Consumer<LocaleProvider>(
              builder: (context, localeProvider, _) {
                return _ResponsivePreferenceRow(
                  icon: const Icon(
                    Icons.language,
                    color: Colors.lightBlueAccent,
                  ),
                  title: loc.languageTitle,
                  subtitle: loc.languageSubtitle,
                  trailing: DropdownButton<Locale?>(
                    value: localeProvider.locale,
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(loc.languageSystem),
                      ),
                      const DropdownMenuItem(
                        value: Locale('en'),
                        child: Text('English'),
                      ),
                      const DropdownMenuItem(
                        value: Locale('fr'),
                        child: Text('Français'),
                      ),
                    ],
                    onChanged: (val) {
                      localeProvider.setLocale(val);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 32),

          Text(
            loc.midiConnectionSection,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.blueAccent,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cable, color: Colors.blue),
              title: Text(loc.connectMidiDevice),
              subtitle: Text(_connectedDevice?.name ?? loc.notConnected),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showMidiDevicesDialog,
            ),
          ),
          const SizedBox(height: 32),

          Text(
            loc.soundfontsSection,
            style: const TextStyle(
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
                  title: Text(loc.loadSoundfont),
                  onTap: _loadSoundfont,
                ),
                const Divider(height: 1),
                Consumer<AudioEngine>(
                  builder: (context, engine, child) {
                    return ValueListenableBuilder<int>(
                      valueListenable: engine.stateNotifier,
                      builder: (context, _, child) {
                        if (engine.loadedSoundfonts.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(loc.noSoundfontsLoaded),
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
                                    ? loc.defaultSoundfont
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
          // ======== AUDIO INPUT SECTION ========
          Text(
            loc.micSelectionTitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.pinkAccent,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Consumer<AudioEngine>(
              builder: (context, engine, _) {
                return Column(
                  children: [
                    FutureBuilder<List<dynamic>>(
                      future:
                          Platform.isAndroid
                              ? engine.getAndroidInputDevices()
                              : engine.getAvailableMicrophones(),
                      builder: (context, snapshot) {
                        final List<dynamic> devices = snapshot.data ?? [];
                        return ValueListenableBuilder<int>(
                          valueListenable: engine.vocoderInputDeviceIndex,
                          builder: (context, deviceIndex, _) {
                            return ValueListenableBuilder<int>(
                              valueListenable:
                                  engine.vocoderInputAndroidDeviceId,
                              builder: (context, androidId, _) {
                                String currentName = loc.micSelectionDefault;
                                if (Platform.isAndroid) {
                                  final dev = devices
                                      .cast<dynamic>()
                                      .firstWhere(
                                        (d) => (d as Map)['id'] == androidId,
                                        orElse: () => null,
                                      );
                                  if (dev != null) {
                                    currentName = (dev as Map)['name'];
                                  }
                                } else if (deviceIndex >= 0 &&
                                    deviceIndex < devices.length) {
                                  currentName = devices[deviceIndex] as String;
                                }

                                final bool valueMissing =
                                    Platform.isAndroid
                                        ? (androidId != -1 &&
                                            !devices.any(
                                              (d) =>
                                                  (d as Map)['id'] == androidId,
                                            ))
                                        : (deviceIndex != -1 &&
                                            deviceIndex >= devices.length);

                                return _ResponsivePreferenceRow(
                                  icon: const Icon(
                                    Icons.mic,
                                    color: Colors.pinkAccent,
                                  ),
                                  title: loc.micSelectionDevice,
                                  subtitle:
                                      valueMissing
                                          ? "Disconnected (ID: ${Platform.isAndroid ? androidId : deviceIndex})"
                                          : currentName,
                                  trailing: DropdownButton<int>(
                                    value:
                                        Platform.isAndroid
                                            ? androidId
                                            : deviceIndex,
                                    items: [
                                      DropdownMenuItem(
                                        value: -1,
                                        child: Text(loc.micSelectionDefault),
                                      ),
                                      if (valueMissing)
                                        DropdownMenuItem(
                                          value:
                                              Platform.isAndroid
                                                  ? androidId
                                                  : deviceIndex,
                                          child: Text(
                                            "Disconnected (ID: ${Platform.isAndroid ? androidId : deviceIndex})",
                                          ),
                                        ),
                                      ...List.generate(devices.length, (i) {
                                        final device = devices[i];
                                        final int val =
                                            Platform.isAndroid
                                                ? (device as Map)['id']
                                                : i;
                                        final String name =
                                            Platform.isAndroid
                                                ? (device as Map)['name']
                                                : device as String;
                                        return DropdownMenuItem(
                                          value: val,
                                          child: Text(name),
                                        );
                                      }),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        if (Platform.isAndroid) {
                                          engine
                                              .vocoderInputAndroidDeviceId
                                              .value = val;
                                          final selected = devices
                                              .cast<dynamic>()
                                              .firstWhere(
                                                (d) => (d as Map)['id'] == val,
                                                orElse: () => null,
                                              );
                                          debugPrint(
                                            'GrooveForge: Selected device: ${selected?['name']} (ID: $val)',
                                          );
                                          if (selected != null &&
                                              (selected
                                                      as Map)['isBluetooth'] ==
                                                  true) {
                                            AudioEngine.audioConfigChannel
                                                .invokeMethod(
                                                  'startBluetoothSco',
                                                );
                                          } else {
                                            AudioEngine.audioConfigChannel
                                                .invokeMethod(
                                                  'stopBluetoothSco',
                                                );
                                          }
                                        } else {
                                          engine.vocoderInputDeviceIndex.value =
                                              val;
                                        }
                                        engine.stateNotifier.value++;
                                      }
                                    },
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.graphic_eq,
                                color: Colors.pinkAccent,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(loc.micSelectionSensitivity),
                            ],
                          ),
                          ValueListenableBuilder<double>(
                            valueListenable: engine.vocoderInputGain,
                            builder: (context, gain, _) {
                              return Slider(
                                value: gain,
                                min: 0.0,
                                max: 20.0,
                                onChanged: (val) {
                                  engine.vocoderInputGain.value = val;
                                  engine.stateNotifier.value++;
                                },
                              );
                            },
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: _MicLevelMeter(),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 32),
          // ======== AUDIO OUTPUT SECTION ========
          Text(
            loc.audioOutputTitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.pinkAccent,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Consumer<AudioEngine>(
              builder: (context, engine, _) {
                return FutureBuilder<List<Map<String, dynamic>>>(
                  future: engine.getAndroidOutputDevices(),
                  builder: (context, snapshot) {
                    final devices = snapshot.data ?? [];
                    return ValueListenableBuilder<int>(
                      valueListenable: engine.vocoderOutputAndroidDeviceId,
                      builder: (context, androidId, _) {
                        String currentName = loc.audioOutputDefault;
                        final dev = devices.firstWhere(
                          (d) => d['id'] == androidId,
                          orElse: () => <String, dynamic>{},
                        );
                        if (dev.isNotEmpty) {
                          currentName = dev['name'] as String;
                        }

                        final bool valueMissing =
                            androidId != -1 &&
                            !devices.any((d) => d['id'] == androidId);

                        return _ResponsivePreferenceRow(
                          icon: const Icon(
                            Icons.headset,
                            color: Colors.pinkAccent,
                          ),
                          title: loc.audioOutputDevice,
                          subtitle:
                              valueMissing
                                  ? "Disconnected (ID: $androidId)"
                                  : currentName,
                          trailing: DropdownButton<int>(
                            value: androidId,
                            items: [
                              DropdownMenuItem(
                                value: -1,
                                child: Text(loc.audioOutputDefault),
                              ),
                              if (valueMissing)
                                DropdownMenuItem(
                                  value: androidId,
                                  child: Text("Disconnected (ID: $androidId)"),
                                ),
                              ...devices.map((device) {
                                return DropdownMenuItem(
                                  value: device['id'] as int,
                                  child: Text(device['name'] as String),
                                );
                              }),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                engine.vocoderOutputAndroidDeviceId.value = val;
                                engine.stateNotifier.value++;
                              }
                            },
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 32),

          Text(
            loc.routingControlSection,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune, color: Colors.teal),
              title: Text(loc.ccMappingPreferences),
              subtitle: Text(loc.ccMappingPreferencesSubtitle),
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

          Text(
            loc.keyGesturesSection,
            style: const TextStyle(
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
                        return _ResponsivePreferenceRow(
                          icon: const Icon(Icons.height, color: Colors.orange),
                          title: loc.verticalInteraction,
                          subtitle: loc.verticalInteractionSubtitle,
                          trailing: DropdownButton<GestureAction>(
                            value: action,
                            items: [
                              DropdownMenuItem(
                                value: GestureAction.none,
                                child: Text(loc.actionNone),
                              ),
                              DropdownMenuItem(
                                value: GestureAction.pitchBend,
                                child: Text(loc.actionPitchBend),
                              ),
                              DropdownMenuItem(
                                value: GestureAction.vibrato,
                                child: Text(loc.actionVibrato),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                engine.verticalGestureAction.value = val;
                                engine.stateNotifier.value++;
                              }
                            },
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ValueListenableBuilder<GestureAction>(
                      valueListenable: engine.horizontalGestureAction,
                      builder: (context, action, _) {
                        return _ResponsivePreferenceRow(
                          icon: const Icon(
                            Icons.unfold_more,
                            color: Colors.blue,
                          ),
                          title: loc.horizontalInteraction,
                          subtitle: loc.horizontalInteractionSubtitle,
                          trailing: DropdownButton<GestureAction>(
                            value: action,
                            items: [
                              DropdownMenuItem(
                                value: GestureAction.none,
                                child: Text(loc.actionNone),
                              ),
                              DropdownMenuItem(
                                value: GestureAction.pitchBend,
                                child: Text(loc.actionPitchBend),
                              ),
                              DropdownMenuItem(
                                value: GestureAction.vibrato,
                                child: Text(loc.actionVibrato),
                              ),
                              DropdownMenuItem(
                                value: GestureAction.glissando,
                                child: Text(loc.actionGlissando),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                engine.horizontalGestureAction.value = val;
                                engine.stateNotifier.value++;
                              }
                            },
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

          Text(
            loc.virtualPianoDisplaySection,
            style: const TextStyle(
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
                    return _ResponsivePreferenceRow(
                      icon: const Icon(Icons.piano, color: Colors.orange),
                      title: loc.visibleKeysTitle,
                      subtitle: loc.visibleKeysSubtitle,
                      trailing: DropdownButton<int>(
                        value: [15, 22, 29, 52].contains(keysToShow) ? keysToShow : 22,
                        items: [
                          DropdownMenuItem(value: 15, child: Text(loc.keys25)),
                          DropdownMenuItem(value: 22, child: Text(loc.keys37)),
                          DropdownMenuItem(value: 29, child: Text(loc.keys49)),
                          DropdownMenuItem(value: 52, child: Text(loc.keys88)),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            engine.pianoKeysToShow.value = val;
                            engine.stateNotifier.value++;
                          }
                        },
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
                    return _ResponsivePreferenceRow(
                      icon: const Icon(
                        Icons.music_note,
                        color: Colors.blueGrey,
                      ),
                      title: loc.notationFormatTitle,
                      subtitle: loc.notationFormatSubtitle,
                      trailing: DropdownButton<String>(
                        value: ['Standard', 'Solfege'].contains(format) ? format : 'Standard',
                        items: [
                          DropdownMenuItem(
                            value: 'Standard',
                            child: Text(loc.notationStandard),
                          ),
                          DropdownMenuItem(
                            value: 'Solfege',
                            child: Text(loc.notationSolfege),
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
                return ValueListenableBuilder<bool>(
                  valueListenable: engine.autoScrollEnabled,
                  builder: (context, autoScroll, _) {
                    return _ResponsivePreferenceRow(
                      icon: const Icon(
                        Icons.unfold_more,
                        color: Colors.greenAccent,
                      ),
                      title: loc.synthAutoScrollTitle,
                      subtitle: loc.synthAutoScrollSubtitle,
                      trailing: Switch(
                        value: autoScroll,
                        onChanged: (val) {
                          engine.autoScrollEnabled.value = val;
                          engine.stateNotifier.value++;
                        },
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
                    return _ResponsivePreferenceRow(
                      icon: const Icon(Icons.waves, color: Colors.teal),
                      title: loc.aftertouchEffectTitle,
                      subtitle: loc.aftertouchEffectSubtitle,
                      trailing: DropdownButton<int>(
                        value: ccItems.any((item) => item.value == destCc) ? destCc : 1,
                        items: ccItems,
                        menuMaxHeight: 300,
                        onChanged: (val) {
                          if (val != null) {
                            engine.aftertouchDestCc.value = val;
                            engine.stateNotifier.value++;
                          }
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 40),

          // ======== VST3 SECTION (desktop only) ========
          if (!Platform.isAndroid && !Platform.isIOS) ...[
            Text(
              'VST3 Plugins',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.tealAccent,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: _Vst3ScanTile(),
            ),
            const Divider(height: 40),
          ],

          Text(
            loc.aboutSection,
            style: const TextStyle(
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
                  title: Text(loc.versionTitle),
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
                  title: Text(loc.viewChangelogTitle),
                  subtitle: Text(loc.viewChangelogSubtitle),
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
                label: Text(loc.resetPreferencesButton),
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
      builder: (context) {
        final loc = AppLocalizations.of(context)!;
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(loc.resetPreferencesDialogTitle),
          content: Text(loc.resetPreferencesDialogBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(loc.cancelButton),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await engine.resetAllPreferences();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              child: Text(loc.resetEverythingButton),
            ),
          ],
        );
      },
    );
  }
}

/// A reusable list item component specifically for preferences.
///
/// It intelligently adapts its layout based on screen width.
/// - On wider screens: Displays the icon, text, and control side-by-side [Row].
/// - On narrow screens (like unrotated smartphones): Stacks the control below the text [Column]
///   to prevent clipping and ensure touch targets remain large enough.
class _ResponsivePreferenceRow extends StatelessWidget {
  final Widget icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _ResponsivePreferenceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // threshold for switching to column
        bool isNarrow = constraints.maxWidth < 450;

        if (isNarrow) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    icon,
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontSize: 16)),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: DropdownButtonHideUnderline(child: trailing),
                ),
              ],
            ),
          );
        } else {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                icon,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16)),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing,
              ],
            ),
          );
        }
      },
    );
  }
}

class _MicLevelMeter extends StatefulWidget {
  const _MicLevelMeter();

  @override
  State<_MicLevelMeter> createState() => _MicLevelMeterState();
}

class _MicLevelMeterState extends State<_MicLevelMeter> {
  Timer? _timer;
  double _level = 0.0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (mounted) {
        final newLevel = AudioInputFFI().getInputPeakLevel();
        if ((newLevel - _level).abs() > 0.01 || newLevel == 0) {
          setState(() {
            _level = newLevel;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 8,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: _level.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.greenAccent,
                    Colors.yellowAccent,
                    if (_level > 0.8) Colors.redAccent else Colors.yellowAccent,
                  ],
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── VST3 Scanner tile ────────────────────────────────────────────────────────

class _Vst3ScanTile extends StatefulWidget {
  @override
  State<_Vst3ScanTile> createState() => _Vst3ScanTileState();
}

class _Vst3ScanTileState extends State<_Vst3ScanTile> {
  bool _scanning = false;
  String? _result;

  Future<void> _scan(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final vstSvc = context.read<VstHostService>();
    if (!vstSvc.isSupported) return;

    setState(() {
      _scanning = true;
      _result = null;
    });

    try {
      await vstSvc.initialize();
      final paths = await vstSvc.scanPluginPaths(VstHostService.defaultSearchPaths);
      setState(() {
        _result = paths.isEmpty
            ? l10n.vst3ScanNoneFound
            : l10n.vst3ScanFound(paths.length);
        _scanning = false;
      });
    } catch (e) {
      setState(() {
        _result = l10n.vst3ScanError(e.toString());
        _scanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vstSvc = context.read<VstHostService>();

    return ListTile(
      leading: const Icon(Icons.search, color: Colors.tealAccent),
      title: Text(l10n.vst3ScanTitle),
      subtitle: Text(_result ?? l10n.vst3ScanSubtitle),
      trailing: _scanning
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : vstSvc.isSupported
              ? const Icon(Icons.chevron_right)
              : const Icon(Icons.block, color: Colors.white38),
      onTap: vstSvc.isSupported && !_scanning ? () => _scan(context) : null,
    );
  }
}
