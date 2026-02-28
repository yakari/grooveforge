import 'dart:io';
import 'package:flutter/material.dart';

import 'package:grooveforge/models/chord_detector.dart';
import 'package:grooveforge/models/gm_instruments.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'channel_scale_lock.dart';

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

    // Parse patches based on loaded SF2 or fallback GM
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
              ? const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Load a soundfont from preferences',
                  style: TextStyle(
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
                      engine.loadedSoundfonts.contains(state.soundfontPath)
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

                        return sortedPaths.map((sfPath) {
                          bool isDefault = sfPath.endsWith(
                            'default_soundfont.sf2',
                          );
                          String name =
                              isDefault
                                  ? 'Default soundfont'
                                  : sfPath.split(Platform.pathSeparator).last;
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
              availablePrograms.contains(state.program)
                  ? state.program
                  : (availablePrograms.isNotEmpty
                      ? availablePrograms.first
                      : 0),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
          items:
              availablePrograms.map((prog) {
                String pName = bankPresets![prog] ?? 'Unknown Program $prog';
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
                return DropdownMenuItem<int>(value: b, child: Text('Bank $b'));
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
              engine.assignPatchToChannel(channelIndex, newProg, bank: newBank);
            }
          },
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 550) {
          // Wide layout
          return Row(
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
