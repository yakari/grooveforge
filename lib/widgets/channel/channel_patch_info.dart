import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:grooveforge/l10n/app_localizations.dart';

import 'package:grooveforge/constants/soundfont_sentinels.dart';
import 'package:grooveforge/models/chord_detector.dart';
import 'package:grooveforge/models/gm_instruments.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'channel_scale_lock.dart';
import '../rotary_knob.dart';

/// A widget that displays and allows configuration of the sound patch (Soundfont, Bank, Program)
/// and scale lock settings for a specific MIDI channel.
///
/// This widget adapts its layout based on the available width (wide vs. narrow) to ensure
/// the controls remain usable. It integrates with the `AudioEngine` to fetch available
/// soundfonts and their respective presets, and includes the `ChannelScaleLock` widget
/// to handle scale and chord locking configuration.
class ChannelPatchInfo extends StatelessWidget {
  final AudioEngine engine;
  final int channelIndex;
  final bool isDimmed;
  final bool isLocked;
  final ChordMatch? displayChord;
  final ChordMatch? referenceChord;
  final ScaleType currentScale;
  final String? descriptiveScaleName;
  final bool isJamSlave;
  final bool showLockControls;
  final VoidCallback? onLockToggled;
  final ValueChanged<ScaleType?> onScaleChanged;

  /// Optional: called when the user selects a program/bank in the rack slot.
  /// When provided, replaces the direct engine call so that the rack model
  /// can be updated (and autosaved). When null, the engine is called directly
  /// (legacy channel-card behaviour).
  final void Function(int program, int bank)? onPatchChanged;

  /// Optional: called when the user selects a soundfont in the rack slot.
  /// Same purpose as [onPatchChanged].
  final void Function(String soundfontPath)? onSoundfontChanged;

  /// When true, bank and program pickers are omitted (MIDI-only keyboard slot).
  final bool hideInstrumentPickers;

  const ChannelPatchInfo({
    super.key,
    required this.engine,
    required this.channelIndex,
    required this.isDimmed,
    required this.isLocked,
    this.displayChord,
    this.referenceChord,
    required this.currentScale,
    this.descriptiveScaleName,
    required this.isJamSlave,
    required this.showLockControls,
    this.onLockToggled,
    required this.onScaleChanged,
    this.onPatchChanged,
    this.onSoundfontChanged,
    this.hideInstrumentPickers = false,
  });

  @override
  Widget build(BuildContext context) {
    final state = engine.channels[channelIndex];

    // --- Data Preparation ---
    // If a custom soundfont (.sf2) is loaded and assigned to this channel,
    // we extract its specific available Banks and Programs.
    // Otherwise, we fall back to the standard General MIDI instrument list.
    Map<int, String>? bankPresets;
    List<int> availableBanks = [state.bank];

    if (state.soundfontPath != null &&
        engine.sf2Presets.containsKey(state.soundfontPath)) {
      final sfPresets = engine.sf2Presets[state.soundfontPath!];
      if (sfPresets != null) {
        availableBanks = sfPresets.keys.toList()..sort();
        if (sfPresets.containsKey(state.bank)) {
          bankPresets = sfPresets[state.bank];
        } else if (availableBanks.isNotEmpty) {
          bankPresets = sfPresets[availableBanks.first];
        }
      }
    } else {
      bankPresets = GmInstruments.list;
      availableBanks = [0];
    }

    if (bankPresets == null || bankPresets.isEmpty) {
      bankPresets = GmInstruments.list; // fallback
    }

    final availablePrograms = bankPresets.keys.toList()..sort();

    final Widget soundfontPicker = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black26,
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
      ),
      child:
          engine.loadedSoundfonts.isEmpty
              ? Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  AppLocalizations.of(context)!.patchLoadSoundfont,
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
              : DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  dropdownColor: Colors.grey[900],
                  value: () {
                    if (state.soundfontPath ==
                        kMidiControllerOnlySoundfont) {
                      return kMidiControllerOnlySoundfont;
                    }
                    if (engine.loadedSoundfonts.contains(state.soundfontPath)) {
                      return state.soundfontPath;
                    }
                    return engine.loadedSoundfonts.isNotEmpty
                        ? engine.loadedSoundfonts.first
                        : null;
                  }(),
                  icon: const Icon(
                    Icons.arrow_drop_down,
                    color: Colors.white54,
                    size: 20,
                  ),
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                  items:
                      (() {
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

                        final noneItem = DropdownMenuItem<String>(
                          value: kMidiControllerOnlySoundfont,
                          child: Text(
                            AppLocalizations.of(context)!
                                .patchSoundfontNoneMidiOnly,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                        List<DropdownMenuItem<String>> items =
                            sortedPaths.map((sfPath) {
                              bool isDefault = sfPath.endsWith(
                                'default_soundfont.sf2',
                              );
                              String name =
                                  isDefault
                                      ? AppLocalizations.of(
                                        context,
                                      )!.patchDefaultSoundfont
                                      : sfPath
                                          .split(kIsWeb ? '/' : Platform.pathSeparator)
                                          .last;
                              return DropdownMenuItem<String>(
                                value: sfPath,
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight:
                                        isDefault
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                    color: isDefault ? Colors.blue[300] : null,
                                  ),
                                ),
                              );
                            }).toList();

                        return [noneItem, ...items];
                      })(),
                  onChanged: (newSf) {
                    if (newSf != null && newSf != state.soundfontPath) {
                      if (onSoundfontChanged != null) {
                        onSoundfontChanged!(newSf);
                      } else {
                        engine.assignSoundfontToChannel(channelIndex, newSf);
                      }
                    }
                  },
                ),
              ),
    );

    final Widget programPicker = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black26,
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          dropdownColor: Colors.grey[900],
          value:
              availablePrograms.contains(state.program)
                  ? state.program
                  : (availablePrograms.isNotEmpty ? availablePrograms.first : 0),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
          items:
              availablePrograms.map((prog) {
                String pName =
                    bankPresets![prog] ??
                    AppLocalizations.of(context)!.patchUnknownProgram(prog);
                return DropdownMenuItem<int>(
                  value: prog,
                  child: Text(
                    '${prog.toString().padLeft(3, '0')} - $pName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
          onChanged: (newProg) {
                    if (newProg != null) {
                      if (onPatchChanged != null) {
                        onPatchChanged!(newProg, state.bank);
                      } else {
                        engine.assignPatchToChannel(
                          channelIndex,
                          newProg,
                          bank: state.bank,
                        );
                      }
                    }
                  },
        ),
      ),
    );

    final Widget bankPicker = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black26,
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          dropdownColor: Colors.grey[900],
          value:
              availableBanks.contains(state.bank)
                  ? state.bank
                  : (availableBanks.isNotEmpty ? availableBanks.first : 0),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
          items:
              availableBanks.map((b) {
                return DropdownMenuItem<int>(
                  value: b,
                  child: Text(AppLocalizations.of(context)!.patchBank(b)),
                );
              }).toList(),
          onChanged: (newBank) {
                    if (newBank != null && newBank != state.bank) {
                      int newProg = state.program;
                      if (state.soundfontPath != null &&
                          engine.sf2Presets.containsKey(state.soundfontPath)) {
                        if (engine.sf2Presets[state.soundfontPath]?[newBank]
                                ?.containsKey(newProg) !=
                            true) {
                          newProg =
                              engine
                                  .sf2Presets[state.soundfontPath]?[newBank]
                                  ?.keys
                                  .first ??
                              0;
                        }
                      }
                      if (onPatchChanged != null) {
                        onPatchChanged!(newProg, newBank);
                      } else {
                        engine.assignPatchToChannel(
                          channelIndex,
                          newProg,
                          bank: newBank,
                        );
                      }
                    }
                  },
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // --- Responsive Layout ---
        // Dynamically rearranges the soundfont, program, and bank dropdowns
        // alongside the scale lock button based on the available widget width.
        // This ensures usability on both tablets (wide) and phones (narrow).
        if (hideInstrumentPickers) {
          return Row(
            children: [
              Expanded(flex: 3, child: soundfontPicker),
              if (displayChord != null || referenceChord != null) ...[
                const SizedBox(width: 8),
                ChannelScaleLock(
                  engine: engine,
                  isDimmed: isDimmed,
                  isLocked: isLocked,
                  displayChord: displayChord,
                  referenceChord: referenceChord,
                  currentScale: currentScale,
                  descriptiveScaleName: descriptiveScaleName,
                  isJamSlave: isJamSlave,
                  showLockControls: showLockControls,
                  onLockToggled: onLockToggled,
                  onScaleChanged: onScaleChanged,
                ),
              ],
            ],
          );
        }

        if (constraints.maxWidth > 550) {
          // Wide layout
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(flex: 3, child: soundfontPicker),
                  const SizedBox(width: 8),
                  Expanded(flex: 4, child: programPicker),
                  const SizedBox(width: 8),
                  bankPicker,
                  if (displayChord != null || referenceChord != null) ...[
                    const SizedBox(width: 8),
                    ChannelScaleLock(
                      engine: engine,
                      isDimmed: isDimmed,
                      isLocked: isLocked,
                      displayChord: displayChord,
                      referenceChord: referenceChord,
                      currentScale: currentScale,
                      descriptiveScaleName: descriptiveScaleName,
                      isJamSlave: isJamSlave,
                      showLockControls: showLockControls,
                      onLockToggled: onLockToggled,
                      onScaleChanged: onScaleChanged,
                    ),
                  ],
                ],
              ),
            ],
          );
        } else {
          // Narrow layout
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: soundfontPicker),
                  if (displayChord != null || referenceChord != null) ...[
                    const SizedBox(width: 8),
                    ChannelScaleLock(
                      engine: engine,
                      isDimmed: isDimmed,
                      isLocked: isLocked,
                      displayChord: displayChord,
                      referenceChord: referenceChord,
                      currentScale: currentScale,
                      descriptiveScaleName: descriptiveScaleName,
                      isJamSlave: isJamSlave,
                      showLockControls: showLockControls,
                      onLockToggled: onLockToggled,
                      onScaleChanged: onScaleChanged,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: programPicker),
                  const SizedBox(width: 8),
                  bankPicker,
                ],
              ),
            ],
          );
        }
      },
    );
  }
}

class VocoderSliders extends StatelessWidget {
  final AudioEngine engine;
  final int channelIndex;
  final bool isNarrow;

  const VocoderSliders({
    super.key,
    required this.engine,
    required this.channelIndex,
    this.isNarrow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: isNarrow ? 2.0 : 8.0,
        horizontal: isNarrow ? 4.0 : 8.0,
      ),
      child: Row(
        key: ValueKey(
          'vocoder_row_${isNarrow ? "narrow" : "wide"}_$channelIndex',
        ),
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Noise Knob
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: engine.vocoderNoiseMix,
              builder: (context, val, _) {
                return RotaryKnob(
                  key: ValueKey('vocoder_noise_$channelIndex'),
                  value: val,
                  min: 0.0,
                  max: 1.0,
                  label: 'NOISE',
                  icon: Icons.grain,
                  size: isNarrow ? 28 : 40,
                  isCompact: isNarrow,
                  onChanged: (newVal) {
                    engine.vocoderNoiseMix.value = newVal;
                    engine.updateVocoderParameters();
                  },
                );
              },
            ),
          ),

          // Speed Knob
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: engine.vocoderEnvRelease,
              builder: (context, val, _) {
                return RotaryKnob(
                  key: ValueKey('vocoder_speed_$channelIndex'),
                  value: val,
                  min: 0.0,
                  max: 1.0,
                  label: 'SPEED',
                  icon: Icons.bolt,
                  size: isNarrow ? 28 : 40,
                  isCompact: isNarrow,
                  onChanged: (newVal) {
                    engine.vocoderEnvRelease.value = newVal;
                    engine.updateVocoderParameters();
                  },
                );
              },
            ),
          ),

          // Bandwidth Knob
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: engine.vocoderBandwidth,
              builder: (context, val, _) {
                return RotaryKnob(
                  key: ValueKey('vocoder_bandwidth_$channelIndex'),
                  value: val,
                  min: 0.0,
                  max: 1.0,
                  label: 'BW',
                  icon: Icons.width_full,
                  size: isNarrow ? 28 : 40,
                  isCompact: isNarrow,
                  onChanged: (newVal) {
                    engine.vocoderBandwidth.value = newVal;
                    engine.updateVocoderParameters();
                  },
                );
              },
            ),
          ),

          // Gate Knob
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: engine.vocoderGateThreshold,
              builder: (context, val, _) {
                return RotaryKnob(
                  key: ValueKey('vocoder_gate_$channelIndex'),
                  value: val,
                  min: 0.0,
                  max: 0.1,
                  label: 'GATE',
                  icon: Icons.noise_control_off,
                  size: isNarrow ? 28 : 40,
                  isCompact: isNarrow,
                  onChanged: (newVal) {
                    engine.vocoderGateThreshold.value = newVal;
                    engine.updateVocoderParameters();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class VocoderButtons extends StatelessWidget {
  final AudioEngine engine;

  const VocoderButtons({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    // 4 carrier modes laid out in a 2×2 grid
    const leftCol = [
      (label: 'Saw', icon: Icons.show_chart, index: 0),
      (label: 'Choral', icon: Icons.record_voice_over, index: 2),
    ];
    const rightCol = [
      (label: 'Square', icon: Icons.water, index: 1),
      (label: 'Natural', icon: Icons.mic, index: 3),
    ];

    Widget buildBtn(({int index, IconData icon, String label}) wf, int wave) =>
        SizedBox(
          height: 14,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  wave == wf.index ? Colors.orange[900] : Colors.black45,
              foregroundColor: wave == wf.index ? Colors.white : Colors.white38,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(
                color:
                    wave == wf.index
                        ? Colors.orange.withValues(alpha: 0.6)
                        : Colors.white12,
              ),
            ),
            onPressed: () {
              engine.vocoderWaveform.value = wf.index;
              engine.updateVocoderParameters();
            },
            icon: Icon(wf.icon, size: 9),
            label: Text(wf.label, style: const TextStyle(fontSize: 8)),
          ),
        );

    return ValueListenableBuilder<int>(
      valueListenable: engine.vocoderWaveform,
      builder: (context, wave, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 3,
          children: [
            // Left column: Saw / Choral
            Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 1,
              children: [for (final wf in leftCol) buildBtn(wf, wave)],
            ),
            // Right column: Square / Neutral
            Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 1,
              children: [for (final wf in rightCol) buildBtn(wf, wave)],
            ),
          ],
        );
      },
    );
  }
}
