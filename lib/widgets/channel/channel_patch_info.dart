import 'dart:io';
import 'package:flutter/material.dart';
import 'package:grooveforge/l10n/app_localizations.dart';

import 'package:grooveforge/models/chord_detector.dart';
import 'package:grooveforge/models/gm_instruments.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/services/audio_input_ffi.dart';
import 'channel_scale_lock.dart';
import 'vocoder_level_meters.dart';
import '../rotary_knob.dart';

const String vocoderMode = 'vocoderMode';

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
                  value:
                      (state.soundfontPath == vocoderMode ||
                              engine.loadedSoundfonts.contains(
                                state.soundfontPath,
                              ))
                          ? state.soundfontPath
                          : engine.loadedSoundfonts.first,
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
                                          .split(Platform.pathSeparator)
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

                        // Add Vocoder Option at the top
                        // We do not add it to loadedSoundfonts so it doesn't try to parse it
                        // But we want it available in the UI
                        if (Platform.isLinux || Platform.isAndroid) {
                          items.insert(
                            0,
                            DropdownMenuItem<String>(
                              value: vocoderMode,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.mic,
                                    color: Colors.orange[300],
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Vocoder',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange[300],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return items;
                      })(),
                  onChanged: (newSf) {
                    if (newSf != null && newSf != state.soundfontPath) {
                      engine.assignSoundfontToChannel(channelIndex, newSf);
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
              state.soundfontPath == vocoderMode
                  ? 0
                  : (availablePrograms.contains(state.program)
                      ? state.program
                      : (availablePrograms.isNotEmpty
                          ? availablePrograms.first
                          : 0)),
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
          onChanged:
              state.soundfontPath == vocoderMode
                  ? null // Disable program picking in vocoder mode
                  : (newProg) {
                    if (newProg != null) {
                      engine.assignPatchToChannel(
                        channelIndex,
                        newProg,
                        bank: state.bank,
                      );
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
              state.soundfontPath == vocoderMode
                  ? 0
                  : (availableBanks.contains(state.bank)
                      ? state.bank
                      : (availableBanks.isNotEmpty ? availableBanks.first : 0)),
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
          onChanged:
              state.soundfontPath == vocoderMode
                  ? null // Disable bank picking in vocoder mode
                  : (newBank) {
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
                      engine.assignPatchToChannel(
                        channelIndex,
                        newProg,
                        bank: newBank,
                      );
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
              if (state.soundfontPath == vocoderMode) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: VocoderLevelMeters()),
                      const SizedBox(width: 8),
                      Container(
                        width: 1,
                        height: 48,
                        color: Colors.orange.withValues(alpha: 0.3),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: VocoderSliders(engine: engine)),
                      const SizedBox(width: 8),
                      Container(
                        width: 1,
                        height: 38,
                        color: Colors.orange.withValues(alpha: 0.3),
                      ),
                      const SizedBox(width: 8),
                      VocoderButtons(engine: engine),
                    ],
                  ),
                ),
              ],
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
              if (state.soundfontPath == vocoderMode) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: VocoderLevelMeters()),
                      const SizedBox(width: 8),
                      Container(
                        width: 1,
                        height: 48,
                        color: Colors.orange.withValues(alpha: 0.3),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: VocoderSliders(engine: engine)),
                      const SizedBox(width: 8),
                      Container(
                        width: 1,
                        height: 48,
                        color: Colors.orange.withValues(alpha: 0.3),
                      ),
                      const SizedBox(width: 8),
                      VocoderButtons(engine: engine),
                    ],
                  ),
                ),
              ],
            ],
          );
        }
      },
    );
  }
}

class VocoderSliders extends StatelessWidget {
  final AudioEngine engine;

  const VocoderSliders({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Noise Knob
          ValueListenableBuilder<double>(
            valueListenable: engine.vocoderNoiseMix,
            builder: (context, noise, _) {
              return RotaryKnob(
                value: noise,
                min: 0.0,
                max: 1.0,
                label: 'NOISE',
                size: 40,
                onChanged: (val) {
                  engine.vocoderNoiseMix.value = val;
                  engine.updateVocoderParameters();
                },
              );
            },
          ),

          // Speed Knob
          ValueListenableBuilder<double>(
            valueListenable: engine.vocoderEnvRelease,
            builder: (context, env, _) {
              return RotaryKnob(
                value: env,
                min: 0.0,
                max: 1.0,
                label: 'SPEED',
                size: 40,
                onChanged: (val) {
                  engine.vocoderEnvRelease.value = val;
                  engine.updateVocoderParameters();
                },
              );
            },
          ),

          // Bandwidth Knob
          ValueListenableBuilder<double>(
            valueListenable: engine.vocoderBandwidth,
            builder: (context, bw, _) {
              return RotaryKnob(
                value: bw,
                min: 0.0,
                max: 1.0,
                label: 'BANDWIDTH',
                size: 40,
                onChanged: (val) {
                  engine.vocoderBandwidth.value = val;
                  engine.updateVocoderParameters();
                },
              );
            },
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Waveform Toggle
        ValueListenableBuilder<int>(
          valueListenable: engine.vocoderWaveform,
          builder: (context, wave, _) {
            IconData getIcon() {
              if (wave == 0) return Icons.show_chart; // Sawtooth
              if (wave == 1) return Icons.water; // Square
              return Icons.record_voice_over; // Neutral (Sine)
            }

            String getLabel() {
              if (wave == 0) return 'Sawtooth';
              if (wave == 1) return 'Square';
              return 'Neutral';
            }

            return SizedBox(
              height: 22,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black45,
                  foregroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  side: const BorderSide(color: Colors.white12),
                ),
                onPressed: () {
                  engine.vocoderWaveform.value = (wave + 1) % 3;
                  engine.updateVocoderParameters();
                },
                icon: Icon(getIcon(), size: 12),
                label: Text(getLabel(), style: const TextStyle(fontSize: 10)),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        // Refresh Mic Button
        SizedBox(
          height: 22,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[800],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: () {
              AudioInputFFI().stopCapture();
              Future.delayed(const Duration(milliseconds: 100), () {
                AudioInputFFI().startCapture();
              });
            },
            icon: const Icon(Icons.refresh, size: 12),
            label: const Text('Refresh Mic', style: TextStyle(fontSize: 10)),
          ),
        ),
      ],
    );
  }
}
