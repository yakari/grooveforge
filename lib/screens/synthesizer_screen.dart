import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/services/cc_mapping_service.dart';
import 'package:grooveforge/services/midi_service.dart';
import 'package:grooveforge/screens/preferences_screen.dart';
import 'package:grooveforge/widgets/channel_card.dart';

class SynthesizerScreen extends StatefulWidget {
  const SynthesizerScreen({super.key});

  @override
  State<SynthesizerScreen> createState() => _SynthesizerScreenState();
}

class _SynthesizerScreenState extends State<SynthesizerScreen> {
  void Function()? _toastListener;
  final ScrollController _scrollController = ScrollController();
  int _lastAutoScrolledChannel = -1;
  DateTime _lastScrollTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    final midiService = context.read<MidiService>();
    final audioEngine = context.read<AudioEngine>();
    final ccMappingService = context.read<CcMappingService>();

    audioEngine.ccMappingService = ccMappingService;

    midiService.onMidiDataReceived = (packet) {
      audioEngine.processMidiPacket(packet);
    };

    ccMappingService.lastEventNotifier.addListener(() {
      final event = ccMappingService.lastEventNotifier.value;
      if (event != null && mounted) {
        _handleAutoScroll(event.channel);
      }
    });

    _toastListener = () {
      final msg = audioEngine.toastNotifier.value;
      if (msg != null && mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
        );
      }
    };
    audioEngine.toastNotifier.addListener(_toastListener!);
  }

  void _handleAutoScroll(int channel) {
    if (!_scrollController.hasClients) return;
    final now = DateTime.now();
    if (now.difference(_lastScrollTime).inMilliseconds < 500 &&
        channel == _lastAutoScrolledChannel) {
      return;
    }

    _lastAutoScrolledChannel = channel;
    _lastScrollTime = now;

    final audioEngine = context.read<AudioEngine>();
    int visualIndex = audioEngine.visibleChannels.value.indexOf(channel);

    if (visualIndex == -1) return;

    double viewportHeight = _scrollController.position.viewportDimension;
    double itemHeight = (viewportHeight - 16) / 2;
    double targetOffset = visualIndex * itemHeight;

    double currentPosition = _scrollController.offset;

    bool isAbove = targetOffset < currentPosition;
    bool isBelow = targetOffset + itemHeight > currentPosition + viewportHeight;

    if (isAbove) {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else if (isBelow) {
      _scrollController.animateTo(
        targetOffset - viewportHeight + itemHeight,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
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
                ListTile(
                  title: Text('CC 0'),
                  subtitle: Text('Bank Select (MSB)'),
                ),
                ListTile(
                  title: Text('CC 1'),
                  subtitle: Text('Modulation Wheel (Vibrato)'),
                ),
                ListTile(title: Text('CC 2'), subtitle: Text('Breath Control')),
                ListTile(title: Text('CC 4'), subtitle: Text('Foot Pedal')),
                ListTile(
                  title: Text('CC 5'),
                  subtitle: Text('Portamento Time'),
                ),
                ListTile(title: Text('CC 7'), subtitle: Text('Main Volume')),
                ListTile(title: Text('CC 10'), subtitle: Text('Pan (Stereo)')),
                ListTile(
                  title: Text('CC 11'),
                  subtitle: Text('Expression (Sub-Volume)'),
                ),
                ListTile(
                  title: Text('CC 64'),
                  subtitle: Text('Sustain Pedal (On/Off)'),
                ),
                ListTile(
                  title: Text('CC 65'),
                  subtitle: Text('Portamento (On/Off)'),
                ),
                ListTile(
                  title: Text('CC 71'),
                  subtitle: Text('Resonance (Filter)'),
                ),
                ListTile(
                  title: Text('CC 74'),
                  subtitle: Text('Frequency Cutoff (Filter)'),
                ),
                ListTile(
                  title: Text('CC 91'),
                  subtitle: Text('Reverb Send Level'),
                ),
                ListTile(
                  title: Text('CC 93'),
                  subtitle: Text('Chorus Send Level'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showChannelVisibilityDialog(BuildContext context) {
    final engine = context.read<AudioEngine>();
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
                            if (!tempVisible.contains(channelIndex)) {
                              tempVisible.add(channelIndex);
                            }
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('At least one channel must be visible'),
                        ),
                      );
                      return;
                    }
                    engine.visibleChannels.value = tempVisible;
                    engine.assignSoundfontToChannel(
                      0,
                      engine.channels[0].soundfontPath ??
                          engine.loadedSoundfonts.firstOrNull ??
                          '',
                    );
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
        title: const Text('GrooveForge Synth'),
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
                    double itemHeight = constraints.maxHeight < 400
                        ? constraints.maxHeight - 16
                        : (constraints.maxHeight - 16) / 2;

                    return ValueListenableBuilder<List<int>>(
                      valueListenable: engine.visibleChannels,
                      builder: (context, visibleChannels, _) {
                        return ListView.builder(
                          controller: _scrollController,
                          itemCount: visibleChannels.length,
                          itemBuilder: (context, index) {
                            final channelIndex = visibleChannels[index];

                            return ChannelCard(
                              channelIndex: channelIndex,
                              itemHeight: itemHeight,
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
