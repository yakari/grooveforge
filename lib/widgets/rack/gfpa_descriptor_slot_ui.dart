import 'package:flutter/material.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:grooveforge_plugin_ui/grooveforge_plugin_ui.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/gfpa_plugin_instance.dart';
import '../../services/rack_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Effect slot UI (type: effect / instrument)
// ─────────────────────────────────────────────────────────────────────────────

/// Rack slot UI for descriptor-backed GFPA effect plugins (`.gfpd`).
///
/// [RackState] now eagerly owns the per-slot [GFDescriptorPlugin] and its
/// native DSP handle — it creates them at project-load time (and on
/// [RackState.addPlugin] for runtime additions), so audio processing is
/// active regardless of whether this widget has ever been mounted.
///
/// This widget is therefore purely cosmetic: it reads the already-initialised
/// plugin + param notifier from [RackState] and renders
/// [GFDescriptorPluginUI]. It does NOT own the plugin lifetime, does NOT call
/// `initialize()` / `dispose()`, and does NOT `registerGfpaDsp` — all of that
/// happens in [RackState._initAudioEffectPlugin] /
/// [RackState._disposeAudioEffectPlugin], which are wired to the slot's
/// presence in the rack, not to widget mount/unmount.
class GFpaDescriptorSlotUI extends StatefulWidget {
  const GFpaDescriptorSlotUI({
    super.key,
    required this.instance,
    required this.descriptor,
  });

  /// The rack model — holds the persisted state map and plugin identity.
  final GFpaPluginInstance instance;

  /// The descriptor from the registry; used only for the loading placeholder
  /// if the eager init has not finished yet. The live plugin is fetched from
  /// [RackState.audioEffectInstanceForSlot].
  final GFPluginDescriptor descriptor;

  @override
  State<GFpaDescriptorSlotUI> createState() => _GFpaDescriptorSlotUIState();
}

class _GFpaDescriptorSlotUIState extends State<GFpaDescriptorSlotUI> {
  /// Per-widget VU meter controller — UI-local, not tied to audio lifetime.
  final GFVuMeterController _vuController = GFVuMeterController();

  @override
  void dispose() {
    _vuController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch RackState so the widget rebuilds once the eager init completes
    // (RackState calls notifyListeners() at the end of _initAudioEffectPlugin).
    final rack = context.watch<RackState>();
    final plugin = rack.audioEffectInstanceForSlot(widget.instance.id);
    final notifier = rack.audioEffectParamNotifierForSlot(widget.instance.id);

    if (plugin == null || notifier == null) {
      // The engine hasn't finished initialising this slot yet (either the
      // async init is still running, or registerGfpaDsp failed silently on
      // an outdated native .so). Show a spinner — the UI will rebuild once
      // notifyListeners fires.
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
        ),
      );
    }

    final bypassed = widget.instance.state['__bypass'] == true;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Bypass toggle (CC assign is in the slot header bar) ──────────
        _BypassHeader(
          bypassed: bypassed,
          l10n: l10n,
          onToggleBypass: () => rack.toggleEffectBypass(widget.instance.id),
        ),
        // ── Parameter controls ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: GFDescriptorPluginUI(
            plugin: plugin,
            paramNotifier: notifier,
            vuController: _vuController,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MIDI FX slot UI (type: midi_fx)
// ─────────────────────────────────────────────────────────────────────────────

/// Rack slot UI for descriptor-backed GFPA MIDI FX plugins (`.gfpd` with
/// `type: midi_fx`).
///
/// [RackState] now eagerly initialises the [GFMidiDescriptorPlugin] for every
/// MIDI FX slot at project load / slot add time, so MIDI routing is active even
/// when the slot widget is scrolled off-screen (lazy list rendering).
///
/// This widget is therefore purely cosmetic: it reads the already-initialised
/// plugin from [RackState.midiFxInstanceForSlot] and renders knobs / controls.
/// It does NOT own the plugin lifetime — that is managed by [RackState].
class GFpaMidiFxDescriptorSlotUI extends StatefulWidget {
  const GFpaMidiFxDescriptorSlotUI({
    super.key,
    required this.instance,
    required this.descriptor,
  });

  /// The rack model — holds persisted state and target slot IDs.
  final GFpaPluginInstance instance;

  /// The descriptor from the registry (used only for the UI; the live plugin
  /// instance is fetched from [RackState]).
  final GFPluginDescriptor descriptor;

  @override
  State<GFpaMidiFxDescriptorSlotUI> createState() =>
      _GFpaMidiFxDescriptorSlotUIState();
}

class _GFpaMidiFxDescriptorSlotUIState
    extends State<GFpaMidiFxDescriptorSlotUI> {
  /// Incremented by [GFDescriptorPluginUI] whenever a knob changes, triggering
  /// a rebuild and a state-persistence write via [_onParamChanged].
  late final ValueNotifier<int> _paramNotifier;

  @override
  void initState() {
    super.initState();
    _paramNotifier = ValueNotifier(0);
    _paramNotifier.addListener(_onParamChanged);
  }

  @override
  void dispose() {
    _paramNotifier.removeListener(_onParamChanged);
    _paramNotifier.dispose();
    super.dispose();
  }

  /// Persists the current plugin parameter values back to the rack model so
  /// they survive a project save / reload.
  ///
  /// The DSP plugin's [getState] only covers its declared parameters. The
  /// bypass toggle and CC assignment live outside that space under the `__`
  /// prefix, so we snapshot and restore them to avoid losing them on every
  /// knob turn.
  void _onParamChanged() {
    if (!mounted) return;
    final rack = context.read<RackState>();
    final plugin = rack.midiFxInstanceForSlot(widget.instance.id);
    if (plugin == null) return;
    // Snapshot meta-keys before the DSP state overwrites the whole map.
    final bypass = widget.instance.state['__bypass'];
    final bypassCc = widget.instance.state['__bypassCc'];
    widget.instance.state
      ..clear()
      ..addAll(plugin.getState());
    // Restore meta-keys that live outside the DSP parameter space.
    if (bypass != null) widget.instance.state['__bypass'] = bypass;
    if (bypassCc != null) widget.instance.state['__bypassCc'] = bypassCc;
    rack.markDirty();
  }

  /// Opens the per-slot CC assign dialog listing all CC-controllable
  /// parameters for this MIDI FX plugin.
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Watch RackState so this widget rebuilds once the plugin finishes its
    // async initialization (RackState calls notifyListeners after init).
    final rack = context.watch<RackState>();
    final plugin = rack.midiFxInstanceForSlot(widget.instance.id);

    if (plugin == null) {
      // Plugin is still initializing in the background — show a spinner.
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
        ),
      );
    }

    final bypassed = widget.instance.state['__bypass'] == true;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Bypass toggle (CC assign is in the slot header bar) ──────────
        _BypassHeader(
          bypassed: bypassed,
          l10n: l10n,
          onToggleBypass: () => rack.toggleMidiFxBypass(widget.instance.id),
        ),
        // ── Parameter controls ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: GFDescriptorPluginUI(
            plugin: plugin,
            paramNotifier: _paramNotifier,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bypass header widget
// ─────────────────────────────────────────────────────────────────────────────

/// A compact row rendered at the top of every MIDI FX slot that provides:
/// - An on/off power toggle (bypasses the plugin when off).
/// - A CC-assign button that opens a dialog to capture a hardware CC number.
///
/// Both controls write to [GFpaPluginInstance.state] via [RackState] so the
/// bypass state and CC assignment survive project saves.
/// Compact bypass toggle row shown inside effect and MIDI FX slot bodies.
///
/// The CC assign button has been moved to the slot header bar in
/// [RackSlotWidget] for a consistent UI across all module types.
class _BypassHeader extends StatelessWidget {
  const _BypassHeader({
    required this.bypassed,
    required this.l10n,
    required this.onToggleBypass,
  });

  /// Whether the effect is currently bypassed (off).
  final bool bypassed;
  final AppLocalizations l10n;
  final VoidCallback onToggleBypass;

  @override
  Widget build(BuildContext context) {
    final activeColor = Theme.of(context).colorScheme.primary;
    const inactiveColor = Colors.grey;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Tooltip(
            message: l10n.midiFxBypass,
            child: IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.power_settings_new,
                color: bypassed ? inactiveColor : activeColor,
              ),
              onPressed: onToggleBypass,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CC assign dialog
// ─────────────────────────────────────────────────────────────────────────────

/// Modal dialog that listens for incoming MIDI CC events and returns the first
