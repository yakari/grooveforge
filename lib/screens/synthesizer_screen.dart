import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/services/cc_mapping_service.dart';
import 'package:grooveforge/services/midi_service.dart';
import 'package:grooveforge/screens/preferences_screen.dart';
import 'package:grooveforge/widgets/channel_card.dart';
import 'package:grooveforge/widgets/jam_session_widget.dart';
import 'package:grooveforge/widgets/user_guide_modal.dart';
import '../l10n/app_localizations.dart';

/// The primary user interface of GrooveForge.
///
/// This screen acts as the master container for the synthesizer. It organizes
/// [ChannelCard] widgets into a scrollable list, optionally displays the
/// [JamSessionWidget] if Jam Mode is enabled, and handles adaptive layouts
/// for different screen sizes (e.g., Mobile Landscape vs. Tablet/Desktop).
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

  /// Automatically scrolls the list of virtual keyboards so that a channel
  /// receiving external MIDI input (from a hardware controller) becomes visible.
  ///
  /// Uses a 500ms throttle to prevent the UI from "jumping" erratically if
  /// multiple channels trigger simultaneously or in rapid succession.
  void _handleAutoScroll(int channel) {
    if (!_scrollController.hasClients) return;

    // Throttle auto-scrolling to prevent jumpiness when many events arrive quickly
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

  void _showUserGuide() {
    showDialog(context: context, builder: (context) => const UserGuideModal());
  }

  /// Displays a dialog allowing the user to filter which of the 16 MIDI channels
  /// are currently rendered on screen, optimizing performance and reducing clutter.
  void _showChannelVisibilityDialog(BuildContext context) {
    final engine = context.read<AudioEngine>();
    List<int> tempVisible = List.from(engine.visibleChannels.value);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final l10n = AppLocalizations.of(context)!;
            return AlertDialog(
              title: Text(l10n.synthVisibleChannelsTitle),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: 16,
                  itemBuilder: (context, index) {
                    final int channelIndex = index;
                    return CheckboxListTile(
                      title: Text(l10n.synthChannelLabel(channelIndex + 1)),
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
                  child: Text(l10n.actionCancel),
                ),
                TextButton(
                  onPressed: () {
                    if (tempVisible.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.synthErrorAtLeastOneChannel),
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
                  child: Text(l10n.synthSaveFilters),
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
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: l10n.synthTooltipUserGuide,
            onPressed: _showUserGuide,
          ),
          IconButton(
            icon: const Icon(Icons.visibility),
            tooltip: l10n.synthTooltipFilterChannels,
            onPressed: () => _showChannelVisibilityDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l10n.synthTooltipSettings,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PreferencesScreen()),
              );
            },
          ),
        ],
      ),
      body: Consumer<AudioEngine>(
        builder: (context, engine, child) {
          return ValueListenableBuilder<ScaleLockMode>(
            valueListenable: engine.lockModePreference,
            builder: (context, lockMode, _) {
              return OrientationBuilder(
                builder: (context, orientation) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final isLandscape = orientation == Orientation.landscape;
                      // UNIFIED TRIGGER: If height is low in landscape, it's "Mobile Landscape"
                      // 480px is a standard height for many landscape phones.
                      final isMobileLandscape =
                          isLandscape && constraints.maxHeight < 480;

                      final showJamUI = lockMode == ScaleLockMode.jam;

                      // mainContent is the scrollable list of ChannelCards
                      Widget mainContent = ListenableBuilder(
                        // Listen to these states to rebuild the list
                        listenable: Listenable.merge([
                          engine.stateNotifier,
                          engine.visibleChannels,
                          engine.isGestureInProgress,
                        ]),
                        builder: (context, _) {
                          return LayoutBuilder(
                            builder: (context, innerConstraints) {
                              double itemHeight =
                                  isMobileLandscape
                                      ? innerConstraints.maxHeight - 16
                                      : (innerConstraints.maxHeight - 16) / 2;
                              final visibleChannels =
                                  engine.visibleChannels.value;
                              final interacting =
                                  engine.isGestureInProgress.value;

                              return ListView.builder(
                                controller: _scrollController,
                                physics:
                                    interacting
                                        ? const NeverScrollableScrollPhysics()
                                        : const AlwaysScrollableScrollPhysics(),
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

                      if (showJamUI) {
                        if (isMobileLandscape) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const JamSessionWidget(forceVertical: true),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: mainContent,
                                ),
                              ),
                            ],
                          );
                        } else {
                          return Padding(
                            padding: const EdgeInsets.all(2.0),
                            child: Column(
                              children: [
                                const JamSessionWidget(forceVertical: false),
                                const SizedBox(height: 2),
                                Expanded(child: mainContent),
                              ],
                            ),
                          );
                        }
                      }

                      return Padding(
                        padding: const EdgeInsets.all(2.0),
                        child: mainContent,
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
