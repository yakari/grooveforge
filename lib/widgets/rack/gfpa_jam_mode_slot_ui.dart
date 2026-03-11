import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chord_detector.dart';
import '../../models/gfpa_plugin_instance.dart';
import '../../models/grooveforge_keyboard_plugin.dart';
import '../../models/plugin_instance.dart';
import '../../plugins/gf_jam_mode_plugin.dart';
import '../../services/audio_engine.dart';
import '../../services/rack_state.dart';

// ─── Design tokens (RC-20 inspired hardware palette) ─────────────────────────

const _kPanelBg = Color(0xFF141414);
const _kPanelBorder = Color(0xFF2C2C2C);
const _kSeparator = Color(0xFF222222);

// LED status colours
const _kLedOn = Color(0xFF00E56A); // bright green

// Amber "LCD" display
const _kLcdAmber = Color(0xFFFFAD2A);
const _kLcdBg = Color(0xFF080808);

// Routing labels
const _kMasterColor = Color(0xFFD09030); // warm gold
const _kTargetColor = Color(0xFF25B8D8); // cyan

// Control accent colours
const _kModeChord = Color(0xFF8860E0); // purple
const _kModeBass = Color(0xFF20C0D0); // teal
const _kBpmColor = Color(0xFFE0A030); // amber
const _kVisualColor = Color(0xFF6090D0); // blue

// ─── Root widget ─────────────────────────────────────────────────────────────

/// Rack slot body for a GFPA Jam Mode plugin, styled as an RC-20 inspired
/// hardware panel with signal-flow routing and a glowing LED enable button.
class GFpaJamModeSlotUI extends StatelessWidget {
  const GFpaJamModeSlotUI({super.key, required this.plugin});

  final GFpaPluginInstance plugin;

  // ── State helpers ─────────────────────────────────────────────────────────

  bool get _enabled => plugin.state['enabled'] != false;

  JamDetectionMode get _detectionMode {
    final s = plugin.state['detectionMode'] as String?;
    return s == JamDetectionMode.bassNote.name
        ? JamDetectionMode.bassNote
        : JamDetectionMode.chord;
  }

  int get _bpmLockBeats =>
      (plugin.state['bpmLockBeats'] as num?)?.toInt().clamp(0, 4) ?? 0;

  ScaleType get _scaleType {
    final s = plugin.state['scaleType'] as String?;
    if (s == null) return ScaleType.standard;
    return ScaleType.values.firstWhere(
      (v) => v.name == s,
      orElse: () => ScaleType.standard,
    );
  }

  void _update(RackState rack, Map<String, dynamic> delta) {
    rack.setGfpaPluginState(plugin.id, {...plugin.state, ...delta});
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    debugPrint('JamModeUI: build START');
    final rack = context.read<RackState>();
    final engine = context.read<AudioEngine>();

    return ListenableBuilder(
      listenable: engine.gfpaJamEntries,
      builder: (context, _) {
        final allSlots = rack.plugins
            .where((p) => p.midiChannel > 0 && p.id != plugin.id)
            .toList();

        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 480;

            return Container(
              margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              decoration: BoxDecoration(
                color: _kPanelBg,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: _kPanelBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Signal-flow routing row ──────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
                    child: isWide
                        ? _WideRoutingRow(
                            plugin: plugin,
                            rack: rack,
                            engine: engine,
                            allSlots: allSlots,
                            enabled: _enabled,
                            scaleType: _scaleType,
                            onUpdate: _update,
                          )
                        : _NarrowRoutingRows(
                            plugin: plugin,
                            rack: rack,
                            engine: engine,
                            allSlots: allSlots,
                            enabled: _enabled,
                            scaleType: _scaleType,
                            onUpdate: _update,
                          ),
                  ),

                  // ── Hairline separator ────────────────────────────────────
                  Container(height: 1, color: _kSeparator),

                  // ── Controls strip ────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                    child: _ControlsStrip(
                      plugin: plugin,
                      rack: rack,
                      engine: engine,
                      detectionMode: _detectionMode,
                      bpmLockBeats: _bpmLockBeats,
                      scaleType: _scaleType,
                      onUpdate: _update,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Wide routing row ─────────────────────────────────────────────────────────
//
//  [MASTER section] →→ [Scale LCD selector] →→ [Targets section ···] [LED button]

class _WideRoutingRow extends StatelessWidget {
  const _WideRoutingRow({
    required this.plugin,
    required this.rack,
    required this.engine,
    required this.allSlots,
    required this.enabled,
    required this.scaleType,
    required this.onUpdate,
  });

  final GFpaPluginInstance plugin;
  final RackState rack;
  final AudioEngine engine;
  final List<PluginInstance> allSlots;
  final bool enabled;
  final ScaleType scaleType;
  final void Function(RackState, Map<String, dynamic>) onUpdate;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── Master ──────────────────────────────────────────────────────────
        _MasterSection(plugin: plugin, allSlots: allSlots, rack: rack),

        // ── Flow arrow ──────────────────────────────────────────────────────
        _FlowArrow(enabled: enabled),

        // ── Scale LCD (also the scale-type selector) ─────────────────────────
        // Flexible so it claims remaining space between master and targets
        // without overflowing when the scale name is long.
        Flexible(
          child: _ScaleLcdSelector(
            plugin: plugin,
            allSlots: allSlots,
            engine: engine,
            scaleType: scaleType,
            enabled: enabled,
            rack: rack,
            onUpdate: onUpdate,
            showLabel: true,
          ),
        ),

        // ── Flow arrow ──────────────────────────────────────────────────────
        _FlowArrow(enabled: enabled),

        // ── Targets (takes remaining space) ─────────────────────────────────
        Expanded(
          child: _TargetsSection(plugin: plugin, allSlots: allSlots, rack: rack),
        ),

        const SizedBox(width: 12),

        // ── LED enable button ────────────────────────────────────────────────
        _LedButton(
          enabled: enabled,
          onTap: () =>
              rack.setJamModeEnabled(plugin.id, enabled: !enabled),
        ),
      ],
    );
  }
}

// ─── Narrow routing rows ──────────────────────────────────────────────────────

class _NarrowRoutingRows extends StatelessWidget {
  const _NarrowRoutingRows({
    required this.plugin,
    required this.rack,
    required this.engine,
    required this.allSlots,
    required this.enabled,
    required this.scaleType,
    required this.onUpdate,
  });

  final GFpaPluginInstance plugin;
  final RackState rack;
  final AudioEngine engine;
  final List<PluginInstance> allSlots;
  final bool enabled;
  final ScaleType scaleType;
  final void Function(RackState, Map<String, dynamic>) onUpdate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row: LED + Scale LCD
        Row(
          children: [
            _LedButton(
              enabled: enabled,
              onTap: () =>
                  rack.setJamModeEnabled(plugin.id, enabled: !enabled),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ScaleLcdSelector(
                plugin: plugin,
                allSlots: allSlots,
                engine: engine,
                scaleType: scaleType,
                enabled: enabled,
                rack: rack,
                onUpdate: onUpdate,
                showLabel: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Master
        _MasterSection(plugin: plugin, allSlots: allSlots, rack: rack),
        const SizedBox(height: 6),
        // Targets
        _TargetsSection(plugin: plugin, allSlots: allSlots, rack: rack),
      ],
    );
  }
}

// ─── LED enable button ────────────────────────────────────────────────────────

class _LedButton extends StatelessWidget {
  const _LedButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              enabled ? _kLedOn.withValues(alpha: 0.1) : const Color(0xFF1A1A1A),
          border: Border.all(
            color: enabled ? _kLedOn : Colors.white24,
            width: enabled ? 2.0 : 1.5,
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: _kLedOn.withValues(alpha: 0.45),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: _kLedOn.withValues(alpha: 0.15),
                    blurRadius: 22,
                    spreadRadius: 4,
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Inner LED dot
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled ? _kLedOn : const Color(0xFF3A3A3A),
                boxShadow: enabled
                    ? [BoxShadow(color: _kLedOn, blurRadius: 5)]
                    : [],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              enabled ? 'ON' : 'OFF',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w900,
                color: enabled ? _kLedOn : Colors.white30,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Scale LCD + type selector ────────────────────────────────────────────────

/// The amber LCD display that shows the active scale name AND doubles as the
/// scale-type selector: tap it to open the scale-type popup menu.
///
/// [showLabel] adds a "SCALE TYPE ▾" hint below the LCD (use on wide screens).
class _ScaleLcdSelector extends StatelessWidget {
  const _ScaleLcdSelector({
    required this.plugin,
    required this.allSlots,
    required this.engine,
    required this.scaleType,
    required this.enabled,
    required this.rack,
    required this.onUpdate,
    required this.showLabel,
  });

  final GFpaPluginInstance plugin;
  final List<PluginInstance> allSlots;
  final AudioEngine engine;
  final ScaleType scaleType;
  final bool enabled;
  final RackState rack;
  final void Function(RackState, Map<String, dynamic>) onUpdate;
  final bool showLabel;

  static const _scaleLabels = {
    ScaleType.standard: 'Standard',
    ScaleType.pentatonic: 'Pentatonic',
    ScaleType.blues: 'Blues',
    ScaleType.rock: 'Rock',
    ScaleType.jazz: 'Jazz',
    ScaleType.dorian: 'Dorian',
    ScaleType.mixolydian: 'Mixolydian',
    ScaleType.harmonicMinor: 'Harm. Minor',
    ScaleType.melodicMinor: 'Mel. Minor',
    ScaleType.classical: 'Classical',
    ScaleType.asiatic: 'Asiatic',
    ScaleType.oriental: 'Oriental',
    ScaleType.wholeTone: 'Whole Tone',
    ScaleType.diminished: 'Diminished',
  };

  @override
  Widget build(BuildContext context) {
    final masterSlot = allSlots.cast<PluginInstance?>().firstWhere(
          (s) => s?.id == plugin.masterSlotId,
          orElse: () => null,
        );

    // Build the live scale-name content for the LCD
    Widget lcdContent;
    if (masterSlot == null) {
      lcdContent = _buildLcd(context, '— NO MASTER —', showChevron: true);
    } else {
      final masterCh = masterSlot.midiChannel - 1;
      lcdContent = ListenableBuilder(
        listenable: Listenable.merge([
          engine.gfpaJamEntries,
          engine.channels[masterCh].lastChord,
          engine.channels[masterCh].activeNotes,
        ]),
        builder: (context, _) {
          final entry = engine.gfpaJamEntries.value
              .where((e) => e.masterCh == masterCh)
              .firstOrNull;

          String label;
          if (entry == null) {
            label = '— — —';
          } else {
            // These types don't appear in the descriptive scale name itself,
            // so the bracket tag adds useful context.  For all others (Blues,
            // Pentatonic, Rock, Dorian, etc.) the name already carries the info.
            const taggedTypes = {
              ScaleType.standard,
              ScaleType.jazz,
              ScaleType.classical,
              ScaleType.asiatic,
              ScaleType.oriental,
            };
            final rawTag = _scaleLabels[entry.scaleType] ?? entry.scaleType.name;
            final typeTag = taggedTypes.contains(entry.scaleType)
                ? ' [$rawTag]'
                : '';
                
            debugPrint('JamModeUI: entry.bassNoteMode = ${entry.bassNoteMode}');
            if (entry.bassNoteMode) {
              final active = engine.channels[masterCh].activeNotes.value;
              debugPrint('JamModeUI: active.isEmpty = ${active.isEmpty}');
              if (active.isNotEmpty) {
                final rootPc = active.reduce(min) % 12;
                final synth =
                    ChordMatch(_noteNameFromPc(rootPc), const {}, rootPc, false);
                final name =
                    engine.getDescriptiveScaleName(synth, entry.scaleType);
                label = '${_noteNameFromPc(rootPc)} $name$typeTag';
              } else {
                label =
                    '${engine.getDescriptiveScaleName(null, entry.scaleType)}$typeTag';
              }
            } else {
              final chord = engine.channels[masterCh].lastChord.value;
              final name =
                  engine.getDescriptiveScaleName(chord, entry.scaleType);
              final scalePart = chord != null
                  ? '${_noteNameFromPc(chord.rootPc)} $name'
                  : name;
              label = '$scalePart$typeTag';
            }
          }
          return _buildLcd(context, label, showChevron: true);
        },
      );
    }

    return Tooltip(
      message: 'Tap to change the scale type\nCurrent: ${_scaleLabels[scaleType] ?? scaleType.name}',
      child: PopupMenuButton<ScaleType>(
        color: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        onSelected: (s) => onUpdate(rack, {'scaleType': s.name}),
        itemBuilder: (_) => [
          for (final s in ScaleType.values)
            PopupMenuItem(
              value: s,
              height: 32,
              child: Row(
                children: [
                  if (s == scaleType)
                    const Icon(Icons.check, size: 11, color: _kLcdAmber)
                  else
                    const SizedBox(width: 11),
                  const SizedBox(width: 6),
                  Text(
                    _scaleLabels[s] ?? s.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: s == scaleType ? _kLcdAmber : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
        ],
        // CrossAxisAlignment.stretch propagates the width constraint that the
        // parent (Flexible in wide / Expanded in narrow) provides all the way
        // down to lcdContent, preventing horizontal overflow.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            lcdContent,
            if (showLabel) ...[
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'SCALE TYPE',
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.w800,
                      color: _kLcdAmber.withValues(alpha: 0.55),
                      letterSpacing: 1.3,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 10,
                    color: _kLcdAmber.withValues(alpha: 0.55),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLcd(BuildContext context, String scaleName,
      {required bool showChevron}) {
    return _LcdContainer(
      enabled: enabled,
      child: Row(
        // mainAxisSize.max fills the width provided by the stretched Column,
        // letting Flexible truncate long scale names with an ellipsis.
        children: [
          Flexible(
            child: Text(
              scaleName.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: enabled ? _kLcdAmber : _kLcdAmber.withValues(alpha: 0.25),
                letterSpacing: 1.2,
              ),
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.edit,
              size: 9,
              color: enabled
                  ? _kLcdAmber.withValues(alpha: 0.5)
                  : Colors.white12,
            ),
          ],
        ],
      ),
    );
  }
}

class _LcdContainer extends StatelessWidget {
  const _LcdContainer({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _kLcdBg,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: enabled
              ? _kLcdAmber.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.06),
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: _kLcdAmber.withValues(alpha: 0.07),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: child,
    );
  }
}

// ─── Flow arrow ───────────────────────────────────────────────────────────────

class _FlowArrow extends StatelessWidget {
  const _FlowArrow({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          Icons.arrow_forward,
          size: 14,
          color: enabled ? _kLcdAmber.withValues(alpha: 0.5) : Colors.white12,
        ),
      ),
    );
  }
}

// ─── Master section ───────────────────────────────────────────────────────────

class _MasterSection extends StatelessWidget {
  const _MasterSection({
    required this.plugin,
    required this.allSlots,
    required this.rack,
  });

  final GFpaPluginInstance plugin;
  final List<PluginInstance> allSlots;
  final RackState rack;

  @override
  Widget build(BuildContext context) {
    final current = allSlots.cast<PluginInstance?>().firstWhere(
          (s) => s?.id == plugin.masterSlotId,
          orElse: () => null,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label row
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _kMasterColor,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'MASTER',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: _kMasterColor,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        // Dropdown
        SizedBox(
          width: 130,
          child: DropdownButton<String>(
            value: current?.id,
            hint: const Text(
              '— pick —',
              style: TextStyle(fontSize: 11, color: Colors.white30),
            ),
            isExpanded: true,
            underline: Container(
              height: 1,
              color: _kMasterColor.withValues(alpha: 0.5),
            ),
            dropdownColor: const Color(0xFF1C1C1C),
            style: const TextStyle(fontSize: 11, color: Colors.white70),
            iconSize: 16,
            icon: Icon(Icons.arrow_drop_down,
                color: _kMasterColor.withValues(alpha: 0.7)),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('— none —',
                    style: TextStyle(fontSize: 11, color: Colors.white30)),
              ),
              for (final s in allSlots)
                DropdownMenuItem(
                  value: s.id,
                  child: Text(
                    'CH ${s.midiChannel} — ${_shortName(s)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
            onChanged: (id) => rack.setJamModeMaster(plugin.id, id),
          ),
        ),
      ],
    );
  }
}

// ─── Targets section ──────────────────────────────────────────────────────────

class _TargetsSection extends StatelessWidget {
  const _TargetsSection({
    required this.plugin,
    required this.allSlots,
    required this.rack,
  });

  final GFpaPluginInstance plugin;
  final List<PluginInstance> allSlots;
  final RackState rack;

  @override
  Widget build(BuildContext context) {
    final targetIds = plugin.targetSlotIds;
    final available = allSlots
        .where(
            (s) => s.id != plugin.masterSlotId && !targetIds.contains(s.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label row
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _kTargetColor,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'TARGETS',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: _kTargetColor,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        // Chips + add button
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final id in targetIds) _targetChip(context, id),
            if (available.isNotEmpty)
              _AddTargetButton(
                available: available,
                onAdd: (id) => rack.addJamModeTarget(plugin.id, id),
              ),
            if (targetIds.isEmpty && available.isEmpty)
              Text(
                'no slots',
                style: TextStyle(fontSize: 10, color: Colors.white24),
              ),
          ],
        ),
      ],
    );
  }

  Widget _targetChip(BuildContext context, String id) {
    final slot = allSlots.cast<PluginInstance?>().firstWhere(
          (s) => s?.id == id,
          orElse: () => null,
        );
    final label =
        slot != null ? 'CH ${slot.midiChannel} ${_shortName(slot)}' : '?';

    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 5, 3),
      decoration: BoxDecoration(
        color: _kTargetColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _kTargetColor.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _kTargetColor,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => rack.removeJamModeTarget(plugin.id, id),
            child: Icon(Icons.close, size: 10, color: _kTargetColor),
          ),
        ],
      ),
    );
  }
}

class _AddTargetButton extends StatelessWidget {
  const _AddTargetButton({required this.available, required this.onAdd});

  final List<PluginInstance> available;
  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      color: const Color(0xFF1C1C1C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      onSelected: onAdd,
      itemBuilder: (_) => [
        for (final s in available)
          PopupMenuItem(
            value: s.id,
            height: 34,
            child: Text(
              'CH ${s.midiChannel} — ${_shortName(s)}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 10, color: _kTargetColor),
            const SizedBox(width: 3),
            Text(
              'Add',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _kTargetColor),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Controls strip ───────────────────────────────────────────────────────────
//
//  DETECT [♪Chord | ♩Bass]   SYNC [Off][1][½][1bar]   · · ·   [□][□]

class _ControlsStrip extends StatelessWidget {
  const _ControlsStrip({
    required this.plugin,
    required this.rack,
    required this.engine,
    required this.detectionMode,
    required this.bpmLockBeats,
    required this.scaleType,
    required this.onUpdate,
  });

  final GFpaPluginInstance plugin;
  final RackState rack;
  final AudioEngine engine;
  final JamDetectionMode detectionMode;
  final int bpmLockBeats;
  final ScaleType scaleType;
  final void Function(RackState, Map<String, dynamic>) onUpdate;

  @override
  Widget build(BuildContext context) {
    // Wrap lets DETECT / SYNC / visual toggles reflow to a second line on
    // narrow screens instead of causing horizontal overflow.
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        // ── Detection mode ─────────────────────────────────────────────────
        _LabeledControl(
          label: 'DETECT',
          tooltip:
              '♪ Chord — detect the scale from all notes pressed simultaneously on the master channel.\n'
              '♩ Bass note — use only the lowest note (ideal for walking bass lines).',
          child: _ModeToggle(
              detectionMode: detectionMode, onUpdate: onUpdate, rack: rack),
        ),

        // ── BPM sync ───────────────────────────────────────────────────────
        _LabeledControl(
          label: 'SYNC',
          tooltip:
              'When to apply scale changes detected from the master channel.\n\n'
              'Off — apply immediately on each new note/chord\n'
              '1 beat — wait for the next beat\n'
              '½ bar — change every 2 beats\n'
              '1 bar — change every 4 beats',
          child: _BpmStrip(
              bpmLockBeats: bpmLockBeats, onUpdate: onUpdate, rack: rack),
        ),

        // ── Visual toggles ─────────────────────────────────────────────────
        _VisualToggles(engine: engine),
      ],
    );
  }
}

// ─── Labeled control helper ───────────────────────────────────────────────────

/// Wraps [child] with a small uppercase label + help icon above it.
/// The label row is itself a [Tooltip] trigger so hovering/long-pressing
/// reveals the explanation on any platform.
class _LabeledControl extends StatelessWidget {
  const _LabeledControl({
    required this.label,
    required this.tooltip,
    required this.child,
  });

  final String label;
  final String tooltip;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: tooltip,
          preferBelow: false,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w800,
                  color: Colors.white38,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(Icons.help_outline, size: 8, color: Colors.white30),
            ],
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

// ── Detection mode: [Chord] [Bass] ───────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.detectionMode,
    required this.onUpdate,
    required this.rack,
  });

  final JamDetectionMode detectionMode;
  final void Function(RackState, Map<String, dynamic>) onUpdate;
  final RackState rack;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeTab(
            label: 'Chord',
            icon: Icons.music_note,
            selected: detectionMode == JamDetectionMode.chord,
            color: _kModeChord,
            rounded: const BorderRadius.horizontal(left: Radius.circular(3)),
            onTap: () => onUpdate(rack, {'detectionMode': JamDetectionMode.chord.name}),
          ),
          Container(width: 1, height: 20, color: Colors.white10),
          _ModeTab(
            label: 'Bass',
            icon: Icons.piano,
            selected: detectionMode == JamDetectionMode.bassNote,
            color: _kModeBass,
            rounded: const BorderRadius.horizontal(right: Radius.circular(3)),
            onTap: () => onUpdate(rack, {'detectionMode': JamDetectionMode.bassNote.name}),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.rounded,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final BorderRadius rounded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: rounded,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: selected ? color : Colors.white30),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: selected ? color : Colors.white38,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── BPM lock strip: [Off] [1] [½] [1bar] ─────────────────────────────────────

class _BpmStrip extends StatelessWidget {
  const _BpmStrip({
    required this.bpmLockBeats,
    required this.onUpdate,
    required this.rack,
  });

  final int bpmLockBeats;
  final void Function(RackState, Map<String, dynamic>) onUpdate;
  final RackState rack;

  static const _options = [
    (val: 0, label: 'Off'),
    (val: 1, label: '1 beat'),
    (val: 2, label: '½ bar'),
    (val: 4, label: '1 bar'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: _options.map((opt) {
        final sel = bpmLockBeats == opt.val;
        return GestureDetector(
          onTap: () => onUpdate(rack, {'bpmLockBeats': opt.val}),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: sel ? _kBpmColor.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: sel ? _kBpmColor.withValues(alpha: 0.65) : Colors.white12,
              ),
            ),
            child: Text(
              opt.label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: sel ? _kBpmColor : Colors.white30,
                letterSpacing: 0.3,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Visual toggles: borders + highlight ──────────────────────────────────────

class _VisualToggles extends StatelessWidget {
  const _VisualToggles({required this.engine});
  final AudioEngine engine;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        engine.showJamModeBorders,
        engine.highlightWrongNotes,
      ]),
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _VisualToggle(
            icon: Icons.border_outer,
            tooltip: 'Show scale borders on keys',
            active: engine.showJamModeBorders.value,
            color: _kVisualColor,
            onToggle: () {
              engine.showJamModeBorders.value =
                  !engine.showJamModeBorders.value;
              engine.stateNotifier.value++;
            },
          ),
          const SizedBox(width: 4),
          _VisualToggle(
            icon: Icons.highlight_off,
            tooltip: 'Dim out-of-scale notes',
            active: engine.highlightWrongNotes.value,
            color: Colors.redAccent,
            onToggle: () {
              engine.highlightWrongNotes.value =
                  !engine.highlightWrongNotes.value;
              engine.stateNotifier.value++;
            },
          ),
        ],
      ),
    );
  }
}

class _VisualToggle extends StatelessWidget {
  const _VisualToggle({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.color,
    required this.onToggle,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final Color color;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: active ? color.withValues(alpha: 0.65) : Colors.white12,
            ),
          ),
          child: Icon(
            icon,
            size: 12,
            color: active ? color : Colors.white30,
          ),
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _noteNameFromPc(int pc) {
  const names = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
  return names[pc % 12];
}

String _shortName(PluginInstance s) {
  if (s is GrooveForgeKeyboardPlugin) {
    final sf = s.soundfontPath;
    if (sf == null) return s.displayName;
    final file = sf.split('/').last;
    return file.length > 12 ? '${file.substring(0, 12)}…' : file;
  }
  return s.displayName;
}
