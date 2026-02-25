import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'midi_service.dart';
import 'audio_engine.dart';
import 'cc_mapping_service.dart';
import 'preferences_screen.dart';
import 'gm_instruments.dart';
import 'virtual_piano.dart';
import 'chord_detector.dart';

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

  // Track auto-scrolling
  final ScrollController _scrollController = ScrollController();
  int _lastAutoScrolledChannel = -1;
  DateTime _lastScrollTime = DateTime.fromMillisecondsSinceEpoch(0);

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

    // Listen to telemetry for auto-scrolling
    ccMappingService.lastEventNotifier.addListener(() {
       final event = ccMappingService.lastEventNotifier.value;
       if (event != null && mounted) {
          _handleAutoScroll(event.channel);
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

  void _handleAutoScroll(int channel) {
    if (!_scrollController.hasClients) return;
    
    // Prevent rapid scrolling if multiple notes hit at once
    final now = DateTime.now();
    if (now.difference(_lastScrollTime).inMilliseconds < 500 && channel == _lastAutoScrolledChannel) return;
    
    _lastAutoScrolledChannel = channel;
    _lastScrollTime = now;

    // We must find the visual index of this channel within the filtered list
    final audioEngine = context.read<AudioEngine>();
    int visualIndex = audioEngine.visibleChannels.value.indexOf(channel);
    
    // If the channel is hidden by the user's filter, we don't auto-scroll to it.
    if (visualIndex == -1) return;

    // The ListView viewport height exactly matches the constraints of our LayoutBuilder
    double viewportHeight = _scrollController.position.viewportDimension;
    double itemHeight = (viewportHeight - 16) / 2;
    double targetOffset = visualIndex * itemHeight;

    double currentPosition = _scrollController.offset;
    
    bool isAbove = targetOffset < currentPosition;
    bool isBelow = targetOffset + itemHeight > currentPosition + viewportHeight;

    if (isAbove) {
       _scrollController.animateTo(
         targetOffset, // Snap item to top of screen
         duration: const Duration(milliseconds: 300), 
         curve: Curves.easeOutCubic
       );
    } else if (isBelow) {
       _scrollController.animateTo(
         targetOffset - viewportHeight + itemHeight, // Snap item to bottom of screen
         duration: const Duration(milliseconds: 300), 
         curve: Curves.easeOutCubic
       );
    }
  }

  @override
  void dispose() {
    if (_toastListener != null) {
      context.read<AudioEngine>().toastNotifier.removeListener(_toastListener!);
    }
    _scrollController.dispose();
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
                    initialValue: engine.loadedSoundfonts.contains(selectedSf) ? selectedSf : engine.loadedSoundfonts.first,
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

  void _showChannelVisibilityDialog(BuildContext context) {
    final engine = context.read<AudioEngine>();
    // Clone the current set so we can modify it locally without triggering rebuilds yet
    List<int> tempVisible = List.from(engine.visibleChannels.value);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Visible Channels'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: 16,
                  itemBuilder: (context, index) {
                    final int channelIndex = index;
                    return CheckboxListTile(
                      title: Text('Channel ${channelIndex + 1}'),
                      value: tempVisible.contains(channelIndex),
                      onChanged: (bool? value) {
                        setDialogState(() {
                          if (value == true) {
                            if (!tempVisible.contains(channelIndex)) tempVisible.add(channelIndex);
                          } else {
                            tempVisible.remove(channelIndex);
                          }
                          tempVisible.sort();
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (tempVisible.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('At least one channel must be visible')));
                      return;
                    }
                    engine.visibleChannels.value = tempVisible;
                    // Trigger a save using the public save method equivalent;
                    engine.assignSoundfontToChannel(0, engine.channels[0].soundfontPath ?? engine.loadedSoundfonts.firstOrNull ?? '');
                    Navigator.pop(context);
                  },
                  child: const Text('Save Filters'),
                ),
              ],
            );
          },
        );
      },
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
            icon: const Icon(Icons.visibility),
            tooltip: 'Filter Visible Channels',
            onPressed: () => _showChannelVisibilityDialog(context),
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
                return LayoutBuilder(
                  builder: (context, constraints) {
                    // Force height of items to exactly half the available screen space (minus padding)
                    // so we always show strictly 2 items vertically at a time.
                    double itemHeight = (constraints.maxHeight - 16) / 2;
                    
                    return ValueListenableBuilder<List<int>>(
                      valueListenable: engine.visibleChannels,
                      builder: (context, visibleChannels, _) {
                        return ListView.builder(
                          controller: _scrollController,
                          itemCount: visibleChannels.length,
                          itemBuilder: (context, index) {
                            final channelIndex = visibleChannels[index];
                            final state = engine.channels[channelIndex];
                            String sfName = state.soundfontPath?.split(Platform.pathSeparator).last ?? 'No Soundfont';
                            String patchName = engine.getCustomPatchName(channelIndex) ?? GmInstruments.list[state.program] ?? 'Unknown Patch';
  
                            return SizedBox(
                              height: itemHeight,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: ValueListenableBuilder<Set<int>>(
                                  valueListenable: state.activeNotes,
                                  builder: (context, activeNotes, _) {
                                    bool isFlashing = activeNotes.isNotEmpty;
                                    
                                    return AnimatedContainer(
                                      duration: const Duration(milliseconds: 100),
                                      curve: Curves.easeInOut,
                                      decoration: BoxDecoration(
                                        color: isFlashing ? Colors.blueAccent.withValues(alpha: 0.2) : Theme.of(context).cardColor,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: isFlashing ? Colors.blueAccent : Colors.transparent,
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          if (isFlashing)
                                             BoxShadow(color: Colors.blueAccent.withValues(alpha: 0.3), blurRadius: 10, spreadRadius: 2)
                                        ]
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: () => _showChannelConfigDialog(channelIndex, engine),
                                        child: Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text('CH ${channelIndex + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blueAccent)),
                                                  Row(
                                                    children: [
                                                      if (isFlashing) const Icon(Icons.circle, color: Colors.greenAccent, size: 12),
                                                      const SizedBox(width: 8),
                                                      const Icon(Icons.piano, color: Colors.grey, size: 20),
                                                    ],
                                                  )
                                                ],
                                              ),
                                              const SizedBox(height: 12),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(sfName, style: const TextStyle(color: Colors.white70, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                        const SizedBox(height: 2),
                                                        Row(
                                                          children: [
                                                            Flexible(
                                                              child: Text(patchName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                            ),
                                                            const SizedBox(width: 12),
                                                              // Combine listeners to update UI on notes, last chord, or lock toggle
                                                              ValueListenableBuilder<Set<int>>(
                                                                valueListenable: state.activeNotes,
                                                                builder: (context, activeNotes, _) {
                                                                  return ValueListenableBuilder<ChordMatch?>(
                                                                    valueListenable: state.lastChord,
                                                                    builder: (context, lastChord, _) {
                                                                      return ValueListenableBuilder<bool>(
                                                                        valueListenable: state.isScaleLocked,
                                                                        builder: (context, isLocked, _) {
                                                                          // Don't show anything until a chord is played
                                                                          if (lastChord == null) return const SizedBox.shrink();

                                                                          // Dim if notes aren't actively held and scale isn't locked
                                                                          bool isDimmed = activeNotes.isEmpty && !isLocked;
                                                                          
                                                                          return Row(
                                                                            mainAxisSize: MainAxisSize.min,
                                                                            children: [
                                                                              InkWell(
                                                                                borderRadius: BorderRadius.circular(12),
                                                                                onTap: () {
                                                                                  state.isScaleLocked.value = !state.isScaleLocked.value;
                                                                                },
                                                                                child: AnimatedContainer(
                                                                                  duration: const Duration(milliseconds: 200),
                                                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                                                  decoration: BoxDecoration(
                                                                                    color: isLocked ? Colors.redAccent.withValues(alpha: 0.9) : Colors.amber.withValues(alpha: isDimmed ? 0.3 : 0.8),
                                                                                    borderRadius: BorderRadius.circular(12),
                                                                                  ),
                                                                                  child: Row(
                                                                                    mainAxisSize: MainAxisSize.min,
                                                                                    children: [
                                                                                      Text(
                                                                                        lastChord.name,
                                                                                        style: TextStyle(
                                                                                          color: isLocked ? Colors.white : Colors.black, 
                                                                                          fontWeight: FontWeight.bold, 
                                                                                          fontSize: 14,
                                                                                        ),
                                                                                      ),
                                                                                      if (isLocked) ...[
                                                                                        const SizedBox(width: 4),
                                                                                        const Icon(Icons.lock, size: 14, color: Colors.white),
                                                                                      ]
                                                                                    ],
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              if (isLocked) ...[
                                                                                const SizedBox(width: 8),
                                                                                ValueListenableBuilder<ScaleType>(
                                                                                  valueListenable: state.currentScaleType,
                                                                                  builder: (context, currentScale, _) {
                                                                                    return DropdownButtonHideUnderline(
                                                                                      child: DropdownButton<ScaleType>(
                                                                                        value: currentScale,
                                                                                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                                                                                        dropdownColor: Colors.grey[850],
                                                                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                                                                        onChanged: (ScaleType? newValue) {
                                                                                          if (newValue != null) {
                                                                                            state.currentScaleType.value = newValue;
                                                                                          }
                                                                                        },
                                                                                        items: ScaleType.values.map<DropdownMenuItem<ScaleType>>((ScaleType value) {
                                                                                          return DropdownMenuItem<ScaleType>(
                                                                                            value: value,
                                                                                            child: Text(value.name.replaceAllMapped(RegExp(r'[A-Z]'), (m) => ' ${m.group(0)}').toUpperCase()),
                                                                                          );
                                                                                        }).toList(),
                                                                                      ),
                                                                                    );
                                                                                  }
                                                                                ),
                                                                              ]
                                                                            ],
                                                                          );
                                                                        }
                                                                      );
                                                                    }
                                                                  );
                                                                }
                                                              ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.end,
                                                    children: [
                                                      Text('Prog: ${state.program}', style: const TextStyle(fontSize: 14)),
                                                      Text('Bank: ${state.bank}', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 16),
                                              // Native Live Virtual Piano
                                              Expanded(
                                                child: GestureDetector(
                                                  onTap: () {}, // Swallow taps so they don't trigger the InkWell
                                                  child: ValueListenableBuilder<bool>(
                                                    valueListenable: engine.dragToPlay,
                                                    builder: (context, dragToPlay, _) {
                                                      return VirtualPiano(
                                                        activeNotes: activeNotes,
                                                        dragToPlay: dragToPlay,
                                                        onNotePressed: (note) => engine.playNote(channel: channelIndex, key: note, velocity: 100),
                                                        onNoteReleased: (note) => engine.stopNote(channel: channelIndex, key: note),
                                                      );
                                                    }
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        );
                      },
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
