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
import '../l10n/app_localizations.dart';
import '../services/locale_provider.dart';
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
                        value: keysToShow,
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
                        value: format,
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
                return ValueListenableBuilder<ScaleLockMode>(
                  valueListenable: engine.lockModePreference,
                  builder: (context, lockMode, _) {
                    return _ResponsivePreferenceRow(
                      icon: const Icon(
                        Icons.lock_clock,
                        color: Colors.purpleAccent,
                      ),
                      title: loc.scaleLockModeTitle,
                      subtitle: loc.scaleLockModeSubtitle,
                      trailing: DropdownButton<ScaleLockMode>(
                        value: lockMode,
                        items: [
                          DropdownMenuItem(
                            value: ScaleLockMode.classic,
                            child: Text(loc.modeClassic),
                          ),
                          DropdownMenuItem(
                            value: ScaleLockMode.jam,
                            child: Text(loc.modeJam),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            engine.lockModePreference.value = val;
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
                  valueListenable: engine.showJamModeBorders,
                  builder: (context, showBorders, _) {
                    return _ResponsivePreferenceRow(
                      icon: const Icon(
                        Icons.border_outer,
                        color: Colors.blueAccent,
                      ),
                      title: loc.jamModeKeyGroupsTitle,
                      subtitle: loc.jamModeKeyGroupsSubtitle,
                      trailing: Switch(
                        value: showBorders,
                        onChanged: (val) {
                          engine.showJamModeBorders.value = val;
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
                return ValueListenableBuilder<bool>(
                  valueListenable: engine.highlightWrongNotes,
                  builder: (context, highlight, _) {
                    return _ResponsivePreferenceRow(
                      icon: const Icon(
                        Icons.error_outline,
                        color: Colors.redAccent,
                      ),
                      title: loc.highlightWrongNotesTitle,
                      subtitle: loc.highlightWrongNotesSubtitle,
                      trailing: Switch(
                        value: highlight,
                        onChanged: (val) {
                          engine.highlightWrongNotes.value = val;
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
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 40),

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
