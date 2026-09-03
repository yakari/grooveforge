import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

import '../../l10n/app_localizations.dart';
import '../../models/gfpa_plugin_instance.dart';
import '../../models/plugin_instance.dart';
import '../../plugins/gf_xen_plugin.dart';
import '../../services/audio_engine.dart';
import '../../services/custom_scale_library.dart';
import '../../services/rack_state.dart';
import 'xen_scale_editor_dialog.dart';

// ─── Design tokens ───────────────────────────────────────────────────────────
//
// Same RC-20 inspired hardware palette as the Jam Mode panel, so the two
// modules read as siblings in a rack. The one addition is the teal accent,
// which matches the colour of the `tuningOut` / `tuningIn` jacks on the back
// panel — the same signal wears the same colour on both faces of the module.

const _kPanelBg = Color(0xFF141414);
const _kPanelBorder = Color(0xFF2C2C2C);
const _kSeparator = Color(0xFF222222);

const _kLedOn = Color(0xFF00E56A);

/// Amber LCD, as on every other GrooveForge panel.
const _kLcdAmber = Color(0xFFFFAD2A);
const _kLcdBg = Color(0xFF080808);

/// Scale-lock accent — matches the purple `scaleOut` jack.
const _kLockColor = Color(0xFFAA44FF);

/// Retuning accent — matches the teal `tuningOut` jack.
const _kTuneColor = Color(0xFF00E5C0);

/// Highlight for the scale currently selected in the grid.
const _kSelected = Color(0xFFFFAD2A);

// ─── Root widget ─────────────────────────────────────────────────────────────

/// Rack slot body for a Xen module.
///
/// The panel is laid out in the order a player uses it:
///
///   1. the LCD, showing what is currently locked in;
///   2. the scale grid, tabbed by family — the thing you reach for mid-piece;
///   3. the tonic strip, for when you want to set a root without playing one;
///   4. the two target lists, which mirror the back-panel cables.
///
/// Stateful only for the selected family tab, which is pure view state and has
/// no business being persisted in the project file.
class GFpaXenSlotUI extends StatefulWidget {
  const GFpaXenSlotUI({super.key, required this.plugin});

  final GFpaPluginInstance plugin;

  @override
  State<GFpaXenSlotUI> createState() => _GFpaXenSlotUIState();
}

class _GFpaXenSlotUIState extends State<GFpaXenSlotUI> {
  GFScaleFamily _family = GFScaleFamily.western;

  @override
  void initState() {
    super.initState();
    // Open on the family of whatever scale is already loaded, so reopening a
    // project puts the player back where they left off rather than on the
    // Western tab.
    final rack = context.read<RackState>();
    final xen = rack.xenPluginFor(widget.plugin.id);
    if (xen != null) _family = xen.scale.family;
  }

  /// Whether the module is doing anything.
  ///
  /// Asked of [RackState] rather than read off the state map, because two
  /// switches can turn a slot off — the LED below and the generic bypass a
  /// mapped CC uses — and the panel must show the same answer the engine acts
  /// on.
  bool _isActive(RackState rack) => rack.isXenActive(widget.plugin.id);

  @override
  Widget build(BuildContext context) {
    final rack = context.watch<RackState>();
    final engine = context.read<AudioEngine>();
    final l10n = AppLocalizations.of(context)!;
    final xen = rack.xenPluginFor(widget.plugin.id);

    // The live plugin is created by RackState one frame after the slot is
    // added; render the empty shell rather than crashing in between.
    if (xen == null) {
      return const SizedBox(height: 8);
    }

    final enabled = _isActive(rack);

    final slots =
        rack.plugins
            .where((p) => p.midiChannel > 0 && p.id != widget.plugin.id)
            .toList();

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
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
            child: _HeaderRow(
              xen: xen,
              enabled: enabled,
              onToggleEnabled:
                  () => rack.setXenEnabled(widget.plugin.id, enabled: !enabled),
              onToggleSnap:
                  () => rack.setXenSnapEnabled(
                    widget.plugin.id,
                    enabled: !xen.snapEnabled,
                  ),
              onToggleTune:
                  () => rack.setXenTuneEnabled(
                    widget.plugin.id,
                    enabled: !xen.tuneEnabled,
                  ),
              l10n: l10n,
            ),
          ),

          Container(height: 1, color: _kSeparator),

          // ── Scale grid ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: _ScaleGrid(
              xen: xen,
              family: _family,
              enabled: enabled,
              heldSources: _heldNoteSources(rack, engine),
              onFamily: (f) => setState(() => _family = f),
              onSelect: (id) => rack.selectXenScale(widget.plugin.id, id),
              onEditScale: (scale) => _openEditor(context, rack, scale),
              l10n: l10n,
            ),
          ),

          Container(height: 1, color: _kSeparator),

          // ── Tonic strip ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            child: _RootStrip(
              rootPc: xen.rootPc,
              enabled: enabled,
              onRoot: (pc) => rack.setXenRoot(widget.plugin.id, pc),
              onLatch: () => rack.latchXenRoot(widget.plugin.id),
              l10n: l10n,
            ),
          ),

          Container(height: 1, color: _kSeparator),

          // ── Targets: the two cables, shown as two lists ────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 9),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final lock = _TargetList(
                  label: l10n.xenTargetsLock,
                  accent: _kLockColor,
                  targetIds: widget.plugin.targetSlotIds,
                  allSlots: slots,
                  onAdd: (id) => rack.addXenTarget(widget.plugin.id, id),
                  onRemove: (id) => rack.removeXenTarget(widget.plugin.id, id),
                  l10n: l10n,
                );
                final tune = _TargetList(
                  label: l10n.xenTargetsTune,
                  accent: _kTuneColor,
                  targetIds: widget.plugin.tuningTargetSlotIds,
                  allSlots: slots,
                  onAdd: (id) => rack.addXenTuningTarget(widget.plugin.id, id),
                  onRemove:
                      (id) => rack.removeXenTuningTarget(widget.plugin.id, id),
                  l10n: l10n,
                );
                // Side by side once there is room; stacked on a phone, where
                // two columns of chips would each be too narrow to read.
                if (constraints.maxWidth < 480) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [lock, const SizedBox(height: 8), tune],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: lock),
                    const SizedBox(width: 12),
                    Expanded(child: tune),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the scale editor, and selects whatever comes back.
  ///
  /// Passing null starts a new scale; passing an existing custom scale edits
  /// it in place, keeping its id so any CC pad already bound to it still
  /// points at the right thing.
  Future<void> _openEditor(
    BuildContext context,
    RackState rack,
    GFScale? scale,
  ) async {
    final library = context.read<CustomScaleLibrary>();
    final saved = await showDialog<GFScale>(
      context: context,
      builder: (_) => XenScaleEditorDialog(library: library, initial: scale),
    );
    if (saved == null || !mounted) return;
    rack.selectXenScale(widget.plugin.id, saved.id);
    // Jump to the tab the new scale lives in, so it is visible straight away
    // rather than filed away behind a tab the player has to go find.
    setState(() => _family = saved.family);
  }

  /// The engine notifiers carrying the notes this module would latch from.
  ///
  /// Returned as live notifiers rather than a snapshot so the hint under the
  /// grid tracks the player's hands: it names the note that is about to become
  /// the tonic *before* the scale button is tapped, which is what makes the
  /// gesture learnable instead of something to discover afterwards.
  List<ValueListenable<Set<int>>> _heldNoteSources(
    RackState rack,
    AudioEngine engine,
  ) {
    final sources =
        widget.plugin.masterSlotId != null
            ? [widget.plugin.masterSlotId!]
            : widget.plugin.targetSlotIds;
    final notifiers = <ValueListenable<Set<int>>>[];
    for (final id in sources) {
      final slot = rack.plugins.where((p) => p.id == id).firstOrNull;
      if (slot == null) continue;
      final ch = slot.midiChannel - 1;
      if (ch < 0 || ch >= 16) continue;
      notifiers.add(engine.channels[ch].activeNotes);
    }
    return notifiers;
  }
}

// ─── Header: LCD + stage toggles + enable LED ────────────────────────────────

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.xen,
    required this.enabled,
    required this.onToggleEnabled,
    required this.onToggleSnap,
    required this.onToggleTune,
    required this.l10n,
  });

  final GFXenPlugin xen;
  final bool enabled;
  final VoidCallback onToggleEnabled;
  final VoidCallback onToggleSnap;
  final VoidCallback onToggleTune;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            // Tapping the LCD explains the module, the way the Jam Mode LCD
            // opens its scale menu — a tappable display is already the idiom
            // on these panels, and it costs no room on a phone.
            onTap: () => _showAbout(context, l10n),
            child: _ScaleLcd(xen: xen, enabled: enabled, l10n: l10n),
          ),
        ),
        const SizedBox(width: 8),
        _StageToggle(
          label: l10n.xenSnap,
          accent: _kLockColor,
          on: xen.snapEnabled,
          enabled: enabled,
          onTap: onToggleSnap,
        ),
        const SizedBox(width: 6),
        _StageToggle(
          label: l10n.xenTune,
          accent: _kTuneColor,
          on: xen.tuneEnabled,
          enabled: enabled,
          onTap: onToggleTune,
        ),
        const SizedBox(width: 8),
        _LedButton(enabled: enabled, onTap: onToggleEnabled),
      ],
    );
  }
}

/// Explains what the module does, reached by tapping the LCD.
void _showAbout(BuildContext context, AppLocalizations l10n) {
  showDialog<void>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(
            l10n.rackAddXen,
            style: const TextStyle(
              color: _kLcdAmber,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: SingleChildScrollView(
            child: Text(
              l10n.xenAbout,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.closeButton),
            ),
          ],
        ),
  );
}

/// Amber LCD naming the scale, its tonic, and whether it retunes anything.
class _ScaleLcd extends StatelessWidget {
  const _ScaleLcd({
    required this.xen,
    required this.enabled,
    required this.l10n,
  });

  final GFXenPlugin xen;
  final bool enabled;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scale = xen.scale;
    final amber = enabled ? _kLcdAmber : Colors.white38;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _kLcdBg,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color:
              enabled
                  ? _kLcdAmber.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.06),
        ),
        boxShadow:
            enabled
                ? [
                  BoxShadow(
                    color: _kLcdAmber.withValues(alpha: 0.07),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ]
                : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                '${xenRootName(xen.rootPc)} ',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: amber,
                  letterSpacing: 0.5,
                ),
              ),
              Flexible(
                child: Text(
                  xenScaleLabel(l10n, scale),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: amber,
                  ),
                ),
              ),
              if (scale.isMicrotonal) ...[
                const SizedBox(width: 6),
                _CentsBadge(enabled: enabled, l10n: l10n),
              ],
            ],
          ),
          const SizedBox(height: 1),
          Text(
            // The provenance line is the module's teaching surface: it says
            // where these numbers come from, and admits when a tradition has
            // no single authoritative tuning.
            scale.provenance,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              color: enabled ? amber.withValues(alpha: 0.55) : Colors.white24,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The "¢" badge marking a scale that actually retunes keys.
///
/// Worth its own affordance because the distinction is easy to get wrong:
/// maqam Hijaz and maqam Rast sit side by side in the grid and only one of
/// them is microtonal.
class _CentsBadge extends StatelessWidget {
  const _CentsBadge({required this.enabled, required this.l10n});

  final bool enabled;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: l10n.xenMicrotonalTooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: _kTuneColor.withValues(alpha: enabled ? 0.15 : 0.05),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: _kTuneColor.withValues(alpha: enabled ? 0.6 : 0.2),
          ),
        ),
        child: Text(
          '¢',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: enabled ? _kTuneColor : Colors.white24,
          ),
        ),
      ),
    );
  }
}

/// A small labelled on/off button for one of the module's two stages.
class _StageToggle extends StatelessWidget {
  const _StageToggle({
    required this.label,
    required this.accent,
    required this.on,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final bool on;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final live = on && enabled;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color:
              live ? accent.withValues(alpha: 0.14) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: live ? accent.withValues(alpha: 0.8) : Colors.white12,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: live ? accent : const Color(0xFF3A3A3A),
                boxShadow:
                    live ? [BoxShadow(color: accent, blurRadius: 4)] : [],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: live ? accent : Colors.white38,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round enable LED, matching the Jam Mode panel's.
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
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              enabled
                  ? _kLedOn.withValues(alpha: 0.1)
                  : const Color(0xFF1A1A1A),
          border: Border.all(
            color: enabled ? _kLedOn : Colors.white24,
            width: enabled ? 2.0 : 1.5,
          ),
          boxShadow:
              enabled
                  ? [
                    BoxShadow(
                      color: _kLedOn.withValues(alpha: 0.45),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                  : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled ? _kLedOn : const Color(0xFF3A3A3A),
                boxShadow:
                    enabled ? [BoxShadow(color: _kLedOn, blurRadius: 5)] : [],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              enabled ? 'ON' : 'OFF',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: enabled ? _kLedOn : Colors.white54,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Scale grid ──────────────────────────────────────────────────────────────

/// Family tabs over a wrapping grid of scale buttons, plus the gesture hint.
class _ScaleGrid extends StatelessWidget {
  const _ScaleGrid({
    required this.xen,
    required this.family,
    required this.enabled,
    required this.heldSources,
    required this.onFamily,
    required this.onSelect,
    required this.onEditScale,
    required this.l10n,
  });

  final GFXenPlugin xen;
  final GFScaleFamily family;
  final bool enabled;
  final List<ValueListenable<Set<int>>> heldSources;
  final ValueChanged<GFScaleFamily> onFamily;
  final ValueChanged<String> onSelect;

  /// Opens the editor. Null means "start a new scale".
  final ValueChanged<GFScale?> onEditScale;

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Wrapped, not scrolled. A horizontal scroller clipped the last
        // family mid-word on a phone with nothing to say it could be
        // scrolled, so a third of the catalogue was effectively invisible.
        Wrap(
          spacing: 14,
          runSpacing: 2,
          children: [
            for (final f in GFScaleFamily.values)
              _FamilyTab(
                label: xenFamilyLabel(l10n, f),
                selected: f == family,
                enabled: enabled,
                onTap: () => onFamily(f),
              ),
          ],
        ),
        const SizedBox(height: 4),
        // Separates the two rows, which read as one wall of pills otherwise.
        Container(height: 1, color: Colors.white10),
        const SizedBox(height: 8),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final scale in GFScaleLibrary.byFamily(family))
              _ScaleButton(
                label: xenScaleLabel(l10n, scale),
                microtonal: scale.isMicrotonal,
                selected: scale.id == xen.scale.id,
                enabled: enabled,
                // A custom scale is the player's own, so it is editable in
                // place — long-press, the same gesture that edits elsewhere
                // in the rack.
                onLongPress:
                    scale.family == GFScaleFamily.custom
                        ? () => onEditScale(scale)
                        : null,
                onTap: () => onSelect(scale.id),
              ),
            // "New scale" lives in the custom tab, where its results appear.
            if (family == GFScaleFamily.custom)
              _NewScaleButton(
                enabled: enabled,
                onTap: () => onEditScale(null),
                l10n: l10n,
              ),
          ],
        ),
        const SizedBox(height: 6),
        // Scoped to the hint so a passing chord does not rebuild forty
        // scale buttons on every note-on.
        ListenableBuilder(
          listenable: Listenable.merge(heldSources),
          builder:
              (context, _) => _GestureHint(
                heldNotes: {for (final n in heldSources) ...n.value},
                enabled: enabled,
                l10n: l10n,
              ),
        ),
      ],
    );
  }
}

class _FamilyTab extends StatelessWidget {
  const _FamilyTab({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Underlined text rather than a bordered pill. Families and scales were
    // drawn identically, so nothing said the first row picked a category and
    // the rows below picked a scale — the panel read as one undifferentiated
    // wall of buttons. Dropping nine borders is most of the legibility win.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        // Without this the underline's `double.infinity` width makes the whole
        // column claim the row, stacking the tabs one per line.
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  letterSpacing: 0.6,
                  color:
                      !enabled
                          ? Colors.white24
                          : selected
                          ? _kSelected
                          : Colors.white54,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                height: 2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  color: selected && enabled ? _kSelected : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One scale button. The teal underline marks a scale that retunes keys.
class _ScaleButton extends StatelessWidget {
  const _ScaleButton({
    required this.label,
    required this.microtonal,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool microtonal;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  /// Opens the editor for a player-made scale; null for built-ins.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.fromLTRB(9, 6, 9, 5),
        decoration: BoxDecoration(
          color:
              selected
                  ? _kSelected.withValues(alpha: 0.18)
                  : const Color(0xFF212121),
          borderRadius: BorderRadius.circular(4),
          // Only the selected chip is outlined. Outlining all forty put a box
          // around every word on screen, which is what made the grid look
          // cluttered rather than dense.
          border:
              selected
                  ? Border.all(color: _kSelected.withValues(alpha: 0.9))
                  : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color:
                    !enabled
                        ? Colors.white24
                        : selected
                        ? _kSelected
                        : Colors.white70,
              ),
            ),
            const SizedBox(height: 3),
            // A 2px rule rather than a badge: it distinguishes the microtonal
            // scales at a glance without adding clutter to forty buttons.
            Container(
              height: 2,
              width: 16,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                color:
                    microtonal && enabled
                        ? _kTuneColor.withValues(alpha: selected ? 0.95 : 0.5)
                        : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The button that opens an empty scale editor, shown in the custom tab.
class _NewScaleButton extends StatelessWidget {
  const _NewScaleButton({
    required this.enabled,
    required this.onTap,
    required this.l10n,
  });

  final bool enabled;
  final VoidCallback onTap;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 9, 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: enabled ? _kSelected.withValues(alpha: 0.5) : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add,
              size: 13,
              color: enabled ? _kSelected : Colors.white24,
            ),
            const SizedBox(width: 3),
            Text(
              l10n.xenEditorTitle,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: enabled ? _kSelected : Colors.white24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The line under the grid that explains — and previews — the gesture.
class _GestureHint extends StatelessWidget {
  const _GestureHint({
    required this.heldNotes,
    required this.enabled,
    required this.l10n,
  });

  final Set<int> heldNotes;
  final bool enabled;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    // With notes down, name the one that would become the tonic. Showing it
    // before the tap is what makes the gesture learnable.
    if (heldNotes.isNotEmpty) {
      final lowest = heldNotes.reduce((a, b) => a < b ? a : b);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _kLedOn,
              boxShadow: [BoxShadow(color: _kLedOn, blurRadius: 4)],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            l10n.xenHolding(xenNoteName(lowest)),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _kLedOn,
              letterSpacing: 0.3,
            ),
          ),
        ],
      );
    }

    return Text(
      l10n.xenHint,
      style: TextStyle(
        fontSize: 10,
        color: enabled ? Colors.white38 : Colors.white24,
        letterSpacing: 0.2,
      ),
    );
  }
}

// ─── Tonic strip ─────────────────────────────────────────────────────────────

/// Twelve chromatic buttons plus a LATCH button.
///
/// The strip is the fallback for setting a tonic with no keyboard patched (or
/// no free hand); LATCH re-runs the held-note gesture without changing scale.
class _RootStrip extends StatelessWidget {
  const _RootStrip({
    required this.rootPc,
    required this.enabled,
    required this.onRoot,
    required this.onLatch,
    required this.l10n,
  });

  final int rootPc;
  final bool enabled;
  final ValueChanged<int> onRoot;
  final VoidCallback onLatch;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      l10n.xenRoot,
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w900,
        color: Colors.white38,
        letterSpacing: 1.2,
      ),
    );

    // Wrapped rather than scrolled, for the same reason as the family tabs:
    // in portrait the strip was clipped after the seventh key, and the LATCH
    // button sat off screen entirely.
    final keys = Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (var pc = 0; pc < 12; pc++)
          _RootKey(
            label: xenRootName(pc),
            // Accidentals are drawn darker, so the strip reads like a
            // keyboard rather than twelve identical buttons.
            accidental: _isAccidental(pc),
            selected: pc == rootPc,
            enabled: enabled,
            onTap: () => onRoot(pc),
          ),
      ],
    );

    final latch = GestureDetector(
      onTap: enabled ? onLatch : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: enabled ? _kLcdAmber.withValues(alpha: 0.5) : Colors.white12,
          ),
        ),
        child: Text(
          l10n.xenLatch,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
            color: enabled ? _kLcdAmber : Colors.white24,
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Twelve keys plus a label plus LATCH do not fit one phone row.
        if (constraints.maxWidth < 400) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [label, latch],
              ),
              const SizedBox(height: 6),
              keys,
            ],
          );
        }
        return Row(
          children: [
            label,
            const SizedBox(width: 8),
            Expanded(child: keys),
            const SizedBox(width: 6),
            latch,
          ],
        );
      },
    );
  }

  /// True for the five black keys of an octave.
  static bool _isAccidental(int pc) => const {1, 3, 6, 8, 10}.contains(pc);
}

class _RootKey extends StatelessWidget {
  const _RootKey({
    required this.label,
    required this.accidental,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool accidental;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 26,
        padding: const EdgeInsets.symmetric(vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              selected
                  ? _kSelected.withValues(alpha: 0.2)
                  : accidental
                  ? const Color(0xFF101010)
                  : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color:
                selected ? _kSelected.withValues(alpha: 0.85) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
            color:
                !enabled
                    ? Colors.white24
                    : selected
                    ? _kSelected
                    : Colors.white60,
          ),
        ),
      ),
    );
  }
}

// ─── Target lists ────────────────────────────────────────────────────────────

/// One of the module's two target lists, mirroring a back-panel cable.
class _TargetList extends StatelessWidget {
  const _TargetList({
    required this.label,
    required this.accent,
    required this.targetIds,
    required this.allSlots,
    required this.onAdd,
    required this.onRemove,
    required this.l10n,
  });

  final String label;
  final Color accent;
  final List<String> targetIds;
  final List<PluginInstance> allSlots;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final available = allSlots.where((s) => !targetIds.contains(s.id)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: accent,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final id in targetIds) _chip(id),
            if (available.isNotEmpty)
              _AddTargetButton(available: available, onAdd: onAdd),
            if (targetIds.isEmpty)
              Text(
                available.isEmpty ? l10n.xenNoSlots : l10n.xenNoTargets,
                style: const TextStyle(fontSize: 10, color: Colors.white38),
              ),
          ],
        ),
      ],
    );
  }

  Widget _chip(String id) {
    final slot = allSlots.where((s) => s.id == id).firstOrNull;
    final label =
        slot != null ? 'CH ${slot.midiChannel} ${_shortName(slot)}' : '?';

    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 5, 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => onRemove(id),
            child: Icon(Icons.close, size: 10, color: accent),
          ),
        ],
      ),
    );
  }

  /// First word of a slot's name, so chips stay one line on a phone.
  static String _shortName(PluginInstance slot) {
    final name = slot.displayName;
    final space = name.indexOf(' ');
    return space > 0 ? name.substring(0, space) : name;
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
      tooltip: '',
      padding: EdgeInsets.zero,
      itemBuilder:
          (context) => [
            for (final slot in available)
              PopupMenuItem(
                value: slot.id,
                height: 34,
                child: Text(
                  'CH ${slot.midiChannel} · ${slot.displayName}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
          ],
      onSelected: onAdd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.white24),
        ),
        child: const Icon(Icons.add, size: 12, color: Colors.white54),
      ),
    );
  }
}

// ─── Naming helpers ──────────────────────────────────────────────────────────

/// Localised label for [scale].
///
/// Only the generic Western names and the temperaments are translated. The
/// rest — Rast, Bhairav, Hirajoshi — are proper nouns of their traditions and
/// stay in their usual transliteration, which is also how a musician looking
/// them up will find them.
String xenScaleLabel(AppLocalizations l10n, GFScale scale) {
  switch (scale.id) {
    case 'major':
      return l10n.xenScaleMajor;
    case 'naturalMinor':
      return l10n.xenScaleNaturalMinor;
    case 'harmonicMinor':
      return l10n.xenScaleHarmonicMinor;
    case 'melodicMinor':
      return l10n.xenScaleMelodicMinor;
    case 'majorPentatonic':
      return l10n.xenScaleMajorPentatonic;
    case 'minorPentatonic':
      return l10n.xenScaleMinorPentatonic;
    case 'blues':
      return l10n.xenScaleBlues;
    case 'rock':
      return l10n.xenScaleRock;
    case 'dorian':
      return l10n.xenScaleDorian;
    case 'phrygian':
      return l10n.xenScalePhrygian;
    case 'lydian':
      return l10n.xenScaleLydian;
    case 'mixolydian':
      return l10n.xenScaleMixolydian;
    case 'locrian':
      return l10n.xenScaleLocrian;
    case 'phrygianDominant':
      return l10n.xenScalePhrygianDominant;
    case 'wholeTone':
      return l10n.xenScaleWholeTone;
    case 'diminished':
      return l10n.xenScaleDiminished;
    case 'justIntonation':
      return l10n.xenScaleJustIntonation;
    case 'pythagorean':
      return l10n.xenScalePythagorean;
    case 'meantone':
      return l10n.xenScaleMeantone;
    case 'werckmeisterIII':
      return l10n.xenScaleWerckmeisterIII;
    default:
      return scale.name;
  }
}

/// Localised tab label for a scale family.
String xenFamilyLabel(AppLocalizations l10n, GFScaleFamily family) {
  switch (family) {
    case GFScaleFamily.western:
      return l10n.xenFamilyWestern;
    case GFScaleFamily.maqam:
      return l10n.xenFamilyMaqam;
    case GFScaleFamily.raga:
      return l10n.xenFamilyRaga;
    case GFScaleFamily.farEast:
      return l10n.xenFamilyFarEast;
    case GFScaleFamily.celtic:
      return l10n.xenFamilyCeltic;
    case GFScaleFamily.gamelan:
      return l10n.xenFamilyGamelan;
    case GFScaleFamily.temperament:
      return l10n.xenFamilyTemperament;
    case GFScaleFamily.experimental:
      return l10n.xenFamilyExperimental;
    case GFScaleFamily.custom:
      return l10n.xenFamilyCustom;
  }
}

/// Note names for the twelve pitch classes.
///
/// Sharps throughout rather than context-sensitive spelling: a module whose
/// scales come from a dozen notational traditions has no single correct
/// enharmonic choice, and a stable strip is easier to aim at than one whose
/// labels change under the finger.
const List<String> _kPitchClassNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// Name of a pitch class, 0 = C … 11 = B. Not localised — note letters are
/// the same in every language GrooveForge ships.
String xenRootName(int pitchClass) => _kPitchClassNames[pitchClass % 12];

/// Name of a MIDI note including its octave, e.g. 60 → "C4".
String xenNoteName(int midiNote) =>
    '${xenRootName(midiNote)}${(midiNote ~/ 12) - 1}';
