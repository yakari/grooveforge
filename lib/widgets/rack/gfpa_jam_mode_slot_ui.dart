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

/// Rack slot body for a standalone GFPA Jam Mode slot.
///
/// Adapts to the available width:
///   ≥ 500 px (desktop/tablet landscape) — two-column layout: routing on
///     the left, settings on the right.
///   < 500 px (phone/narrow) — stacked column layout.
class GFpaJamModeSlotUI extends StatelessWidget {
  const GFpaJamModeSlotUI({super.key, required this.plugin});

  final GFpaPluginInstance plugin;

  // ─── State helpers ────────────────────────────────────────────────────────

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

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
            final isWide = constraints.maxWidth >= 500;
            return Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: isWide
                  ? _WideLayout(
                      plugin: plugin,
                      rack: rack,
                      allSlots: allSlots,
                      enabled: _enabled,
                      detectionMode: _detectionMode,
                      bpmLockBeats: _bpmLockBeats,
                      scaleType: _scaleType,
                      onUpdate: _update,
                    )
                  : _NarrowLayout(
                      plugin: plugin,
                      rack: rack,
                      allSlots: allSlots,
                      enabled: _enabled,
                      detectionMode: _detectionMode,
                      bpmLockBeats: _bpmLockBeats,
                      scaleType: _scaleType,
                      onUpdate: _update,
                    ),
            );
          },
        );
      },
    );
  }
}

// ─── Shared layout data ───────────────────────────────────────────────────────

class _LayoutData {
  const _LayoutData({
    required this.plugin,
    required this.rack,
    required this.allSlots,
    required this.enabled,
    required this.detectionMode,
    required this.bpmLockBeats,
    required this.scaleType,
    required this.onUpdate,
  });

  final GFpaPluginInstance plugin;
  final RackState rack;
  final List<PluginInstance> allSlots;
  final bool enabled;
  final JamDetectionMode detectionMode;
  final int bpmLockBeats;
  final ScaleType scaleType;
  final void Function(RackState, Map<String, dynamic>) onUpdate;
}

// ─── Wide layout (desktop / tablet) ──────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.plugin,
    required this.rack,
    required this.allSlots,
    required this.enabled,
    required this.detectionMode,
    required this.bpmLockBeats,
    required this.scaleType,
    required this.onUpdate,
  });

  final GFpaPluginInstance plugin;
  final RackState rack;
  final List<PluginInstance> allSlots;
  final bool enabled;
  final JamDetectionMode detectionMode;
  final int bpmLockBeats;
  final ScaleType scaleType;
  final void Function(RackState, Map<String, dynamic>) onUpdate;

  @override
  Widget build(BuildContext context) {
    final d = _LayoutData(
      plugin: plugin,
      rack: rack,
      allSlots: allSlots,
      enabled: enabled,
      detectionMode: detectionMode,
      bpmLockBeats: bpmLockBeats,
      scaleType: scaleType,
      onUpdate: onUpdate,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Left: routing ─────────────────────────────────────────────
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MasterRow(d: d),
              const SizedBox(height: 6),
              _TargetChips(d: d),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // ── Right: enable + settings ──────────────────────────────────
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ScaleIndicator(plugin: plugin, allSlots: allSlots, d: d),
                const SizedBox(width: 8),
                const _VisualToggles(),
                const SizedBox(width: 8),
                _EnableButton(d: d),
              ],
            ),
            const SizedBox(height: 8),
            _DetectionRow(d: d),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ScaleButton(d: d),
                const SizedBox(width: 8),
                _BpmRow(d: d),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Narrow layout (phone) ───────────────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({
    required this.plugin,
    required this.rack,
    required this.allSlots,
    required this.enabled,
    required this.detectionMode,
    required this.bpmLockBeats,
    required this.scaleType,
    required this.onUpdate,
  });

  final GFpaPluginInstance plugin;
  final RackState rack;
  final List<PluginInstance> allSlots;
  final bool enabled;
  final JamDetectionMode detectionMode;
  final int bpmLockBeats;
  final ScaleType scaleType;
  final void Function(RackState, Map<String, dynamic>) onUpdate;

  @override
  Widget build(BuildContext context) {
    final d = _LayoutData(
      plugin: plugin,
      rack: rack,
      allSlots: allSlots,
      enabled: enabled,
      detectionMode: detectionMode,
      bpmLockBeats: bpmLockBeats,
      scaleType: scaleType,
      onUpdate: onUpdate,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _MasterRow(d: d)),
            const SizedBox(width: 8),
            _EnableButton(d: d),
          ],
        ),
        const SizedBox(height: 6),
        _ScaleIndicator(plugin: plugin, allSlots: allSlots, d: d),
        const SizedBox(height: 6),
        _TargetChips(d: d),
        const SizedBox(height: 8),
        _DetectionRow(d: d),
        const SizedBox(height: 6),
        Row(
          children: [
            _ScaleButton(d: d),
            const SizedBox(width: 8),
            Expanded(child: _BpmRow(d: d)),
            const SizedBox(width: 8),
            const _VisualToggles(),
          ],
        ),
      ],
    );
  }
}

// ─── Shared sub-widgets ───────────────────────────────────────────────────────

/// ♪ Drives harmony: [slot dropdown]
class _MasterRow extends StatelessWidget {
  const _MasterRow({required this.d});
  final _LayoutData d;

  @override
  Widget build(BuildContext context) {
    final available = d.allSlots;
    final current = available.cast<PluginInstance?>().firstWhere(
          (s) => s?.id == d.plugin.masterSlotId,
          orElse: () => null,
        );

    return Row(
      children: [
        const Icon(Icons.music_note, size: 13, color: Colors.deepPurpleAccent),
        const SizedBox(width: 5),
        const Text(
          'Master',
          style: TextStyle(fontSize: 11, color: Colors.white54),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: available.isEmpty
              ? const Text('No slots',
                  style: TextStyle(fontSize: 11, color: Colors.white24))
              : DropdownButton<String>(
                  value: current?.id,
                  hint: const Text('— pick —',
                      style: TextStyle(fontSize: 11, color: Colors.white38)),
                  isExpanded: true,
                  underline: Container(height: 1, color: Colors.white12),
                  dropdownColor: Colors.grey[850],
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('— none —',
                          style: TextStyle(
                              fontSize: 11, color: Colors.white38)),
                    ),
                    for (final s in available)
                      DropdownMenuItem(
                        value: s.id,
                        child: Text(
                          'CH ${s.midiChannel} — ${_shortName(s)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                  onChanged: (id) => d.rack.setJamModeMaster(d.plugin.id, id),
                ),
        ),
      ],
    );
  }
}

/// 🔒 Targets: [chip × chip × ...] [+ Add ▼]
class _TargetChips extends StatelessWidget {
  const _TargetChips({required this.d});
  final _LayoutData d;

  @override
  Widget build(BuildContext context) {
    final targetIds = d.plugin.targetSlotIds;
    final available = d.allSlots
        .where((s) =>
            s.id != d.plugin.masterSlotId && !targetIds.contains(s.id))
        .toList();

    return Row(
      children: [
        const Icon(Icons.lock_outline, size: 13, color: Colors.orangeAccent),
        const SizedBox(width: 5),
        const Text(
          'Targets',
          style: TextStyle(fontSize: 11, color: Colors.white54),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Existing targets as removable chips
              for (final targetId in targetIds) ...[
                _buildTargetChip(context, targetId),
              ],
              // "+" add button — only if there are available slots
              if (available.isNotEmpty)
                _AddTargetButton(
                  available: available,
                  onAdd: (id) =>
                      d.rack.addJamModeTarget(d.plugin.id, id),
                ),
              if (targetIds.isEmpty && available.isEmpty)
                const Text(
                  'No slots available',
                  style: TextStyle(fontSize: 11, color: Colors.white24),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTargetChip(BuildContext context, String targetId) {
    final slot = d.allSlots.cast<PluginInstance?>().firstWhere(
          (s) => s?.id == targetId,
          orElse: () => null,
        );
    final label =
        slot != null ? 'CH ${slot.midiChannel} ${_shortName(slot)}' : '?';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
                fontSize: 11,
                color: Colors.orangeAccent,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => d.rack.removeJamModeTarget(d.plugin.id, targetId),
            child: const Icon(Icons.close, size: 10, color: Colors.orangeAccent),
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
      color: Colors.grey[850],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 11, color: Colors.white54),
            SizedBox(width: 3),
            Text('Add',
                style: TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}

/// [● START / ■ STOP] toggle button
class _EnableButton extends StatelessWidget {
  const _EnableButton({required this.d});
  final _LayoutData d;

  @override
  Widget build(BuildContext context) {
    final on = d.enabled;
    return GestureDetector(
      onTap: () => d.rack.setJamModeEnabled(d.plugin.id, enabled: !on),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on
              ? Colors.greenAccent.withValues(alpha: 0.15)
              : Colors.white10,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: on
                ? Colors.greenAccent.withValues(alpha: 0.7)
                : Colors.white24,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              on ? Icons.stop_circle_outlined : Icons.play_circle_outline,
              size: 14,
              color: on ? Colors.greenAccent : Colors.white38,
            ),
            const SizedBox(width: 5),
            Text(
              on ? 'Active' : 'Off',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: on ? Colors.greenAccent : Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [Chord] [Bass Note] detection mode chips
class _DetectionRow extends StatelessWidget {
  const _DetectionRow({required this.d});
  final _LayoutData d;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Chip(
          label: 'Chord',
          icon: Icons.music_note,
          selected: d.detectionMode == JamDetectionMode.chord,
          color: Colors.deepPurpleAccent,
          onTap: () => d.onUpdate(
              d.rack, {'detectionMode': JamDetectionMode.chord.name}),
        ),
        const SizedBox(width: 4),
        _Chip(
          label: 'Bass note',
          icon: Icons.piano,
          selected: d.detectionMode == JamDetectionMode.bassNote,
          color: Colors.cyanAccent,
          onTap: () => d.onUpdate(
              d.rack, {'detectionMode': JamDetectionMode.bassNote.name}),
        ),
      ],
    );
  }
}

/// Scale selector — a compact button that opens a popup menu
class _ScaleButton extends StatelessWidget {
  const _ScaleButton({required this.d});
  final _LayoutData d;

  static const _labels = {
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
    return PopupMenuButton<ScaleType>(
      color: Colors.grey[850],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: (s) => d.onUpdate(d.rack, {'scaleType': s.name}),
      itemBuilder: (_) => [
        for (final s in ScaleType.values)
          PopupMenuItem(
            value: s,
            height: 34,
            child: Row(
              children: [
                if (s == d.scaleType)
                  const Icon(Icons.check, size: 12, color: Colors.deepPurpleAccent)
                else
                  const SizedBox(width: 12),
                const SizedBox(width: 6),
                Text(
                  _labels[s] ?? s.name,
                  style: TextStyle(
                    fontSize: 12,
                    color: s == d.scaleType
                        ? Colors.deepPurpleAccent
                        : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.deepPurpleAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: Colors.deepPurpleAccent.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.piano, size: 11, color: Colors.deepPurpleAccent),
            const SizedBox(width: 4),
            Text(
              _labels[d.scaleType] ?? d.scaleType.name,
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.deepPurpleAccent,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.arrow_drop_down,
                size: 13, color: Colors.deepPurpleAccent),
          ],
        ),
      ),
    );
  }
}

/// BPM lock chip row: [Off] [1 beat] [½ bar] [1 bar]
class _BpmRow extends StatelessWidget {
  const _BpmRow({required this.d});
  final _LayoutData d;

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
        final sel = d.bpmLockBeats == opt.val;
        return GestureDetector(
          onTap: () =>
              d.onUpdate(d.rack, {'bpmLockBeats': opt.val}),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: sel
                  ? Colors.amberAccent.withValues(alpha: 0.15)
                  : Colors.white10,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: sel
                    ? Colors.amberAccent.withValues(alpha: 0.7)
                    : Colors.white24,
              ),
            ),
            child: Text(
              opt.label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: sel ? Colors.amberAccent : Colors.white38),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Active scale indicator ───────────────────────────────────────────────────

/// Shows the currently active scale with its root note (e.g. "C Major").
/// Updates live as the master plays new chords or bass notes.
class _ScaleIndicator extends StatelessWidget {
  const _ScaleIndicator({
    required this.plugin,
    required this.allSlots,
    required this.d,
  });

  final GFpaPluginInstance plugin;
  final List<PluginInstance> allSlots;
  final _LayoutData d;

  @override
  Widget build(BuildContext context) {
    final engine = context.read<AudioEngine>();
    final masterSlot = allSlots
        .cast<PluginInstance?>()
        .firstWhere((s) => s?.id == plugin.masterSlotId, orElse: () => null);
    if (masterSlot == null) return const SizedBox.shrink();

    final masterCh = masterSlot.midiChannel - 1;
    if (masterCh < 0 || masterCh >= 16) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: Listenable.merge([
        engine.gfpaJamEntries,
        engine.channels[masterCh].lastChord,
        engine.channels[masterCh].activeNotes,
      ]),
      builder: (context, _) {
        final entry = engine.gfpaJamEntries.value
            .where((e) => e.masterCh == masterCh)
            .firstOrNull;
        if (entry == null) return const SizedBox.shrink();

        // Build a display label: "C Minor Blues", "G Pentatonic", etc.
        // Always prefix with the root note name when it is known.
        String label;
        if (entry.bassNoteMode) {
          final active = engine.channels[masterCh].activeNotes.value;
          if (active.isNotEmpty) {
            final rootPc = active.reduce(min) % 12;
            final synth =
                ChordMatch(_noteNameFromPc(rootPc), const {}, rootPc, false);
            final scaleName =
                engine.getDescriptiveScaleName(synth, entry.scaleType);
            label = '${_noteNameFromPc(rootPc)} $scaleName';
          } else {
            label = engine.getDescriptiveScaleName(null, entry.scaleType);
          }
        } else {
          final chord = engine.channels[masterCh].lastChord.value;
          final scaleName =
              engine.getDescriptiveScaleName(chord, entry.scaleType);
          label = chord != null
              ? '${_noteNameFromPc(chord.rootPc)} $scaleName'
              : scaleName;
        }

        final on = d.enabled;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: on
                ? Colors.deepPurpleAccent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: on
                  ? Colors.deepPurpleAccent.withValues(alpha: 0.65)
                  : Colors.white12,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_note,
                size: 13,
                color: on ? Colors.deepPurpleAccent : Colors.white24,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: on ? Colors.white : Colors.white38,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Visual settings toggles ─────────────────────────────────────────────────

/// Two icon-toggle-buttons controlling the visual display of scale information
/// on the piano keys of target channels: [border] [highlight].
class _VisualToggles extends StatelessWidget {
  const _VisualToggles();

  @override
  Widget build(BuildContext context) {
    final engine = context.read<AudioEngine>();
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
            color: Colors.blueAccent,
            onToggle: () {
              engine.showJamModeBorders.value = !engine.showJamModeBorders.value;
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
              engine.highlightWrongNotes.value = !engine.highlightWrongNotes.value;
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
            color: active ? color.withValues(alpha: 0.15) : Colors.white10,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: active ? color.withValues(alpha: 0.7) : Colors.white24,
            ),
          ),
          child: Icon(icon, size: 13, color: active ? color : Colors.white38),
        ),
      ),
    );
  }
}

// ─── Generic chip ─────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : Colors.white10,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.8) : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: selected ? color : Colors.white38),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? color : Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _noteNameFromPc(int pc) {
  const names = [
    'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'
  ];
  return names[pc % 12];
}

String _shortName(PluginInstance s) {
  if (s is GrooveForgeKeyboardPlugin) {
    final sf = s.soundfontPath;
    if (sf == null || sf == 'vocoderMode') return s.displayName;
    final file = sf.split('/').last;
    return file.length > 12 ? '${file.substring(0, 12)}…' : file;
  }
  return s.displayName;
}
