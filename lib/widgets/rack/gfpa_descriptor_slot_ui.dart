import 'package:flutter/material.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:grooveforge_plugin_ui/grooveforge_plugin_ui.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/gfpa_plugin_instance.dart';
import '../../services/rack_state.dart';
import '../../services/vst_host_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Effect slot UI (type: effect / instrument)
// ─────────────────────────────────────────────────────────────────────────────

/// Rack slot UI for descriptor-backed GFPA effect plugins (`.gfpd`).
///
/// This widget bridges the rack model ([GFpaPluginInstance]) and the
/// auto-generated UI ([GFDescriptorPluginUI]):
///
/// 1. It creates a fresh [GFDescriptorPlugin] instance per slot (so two Reverb
///    slots don't share DSP state).
/// 2. It restores the parameter state from [GFpaPluginInstance.state] after
///    initialization.
/// 3. It syncs every parameter change back to [GFpaPluginInstance.state] and
///    notifies [RackState] so the project auto-saves.
class GFpaDescriptorSlotUI extends StatefulWidget {
  const GFpaDescriptorSlotUI({
    super.key,
    required this.instance,
    required this.descriptor,
  });

  /// The rack model — holds the persisted state map and plugin identity.
  final GFpaPluginInstance instance;

  /// The descriptor from the registry, used to create a fresh plugin instance.
  final GFPluginDescriptor descriptor;

  @override
  State<GFpaDescriptorSlotUI> createState() => _GFpaDescriptorSlotUIState();
}

class _GFpaDescriptorSlotUIState extends State<GFpaDescriptorSlotUI> {
  /// Per-slot plugin instance — owns its own DSP state, independent of the
  /// singleton template stored in [GFPluginRegistry].
  late final GFDescriptorPlugin _plugin;

  /// Incrementing counter that triggers a rebuild of [GFDescriptorPluginUI]
  /// whenever any parameter changes.
  late final ValueNotifier<int> _paramNotifier;

  /// Optional VU meter controller — wired to the plugin once it initialises.
  final GFVuMeterController _vuController = GFVuMeterController();

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _plugin = GFDescriptorPlugin(widget.descriptor);
    _paramNotifier = ValueNotifier(0);
    _initPlugin();
  }

  /// Asynchronously initialise the DSP plugin and restore saved state.
  Future<void> _initPlugin() async {
    // Use a standard audio context. The sample rate will be updated once the
    // native engine exposes it; 44100 Hz covers the vast majority of devices.
    await _plugin.initialize(
      const GFPluginContext(sampleRate: 44100, maxFramesPerBlock: 512),
    );
    // Restore the last-saved parameter state from the rack model.
    _plugin.loadState(Map<String, dynamic>.from(widget.instance.state));

    // Register this slot's native C++ DSP in the ALSA insert chain.
    // Must happen after initialize() so the descriptor is fully loaded.
    // Guarded by try/catch: if the native symbol is unavailable (e.g. an
    // older .so in the bundle before a rebuild), we fall back to UI-only
    // mode so the keyboard still produces sound through direct master render.
    if (mounted) {
      try {
        context.read<VstHostService>().registerGfpaDsp(
          widget.instance.id,
          widget.instance.pluginId,
        );
        // Seed initial parameter values into the native DSP from saved state.
        _syncAllParamsToNative();
      } catch (e) {
        debugPrint('GFpaDescriptorSlotUI: native DSP unavailable — $e');
      }
      // Always rebuild routing so the keyboard stays in masterRenders
      // regardless of whether native DSP registration succeeded.
      context.read<RackState>().syncAudioRoutingIfNeeded();
    }

    // Listen to param changes: sync back to the rack model for persistence.
    // Guard: widget may have been disposed during the preceding await.
    if (!mounted) return;
    _paramNotifier.addListener(_onParamChanged);

    if (mounted) setState(() => _initialized = true);
  }

  /// Called whenever a parameter changes in [GFDescriptorPluginUI].
  ///
  /// Writes the full parameter map back into [GFpaPluginInstance.state],
  /// forwards all parameter changes to the native C++ DSP engine, and asks
  /// [RackState] to schedule an auto-save.
  ///
  /// Preserves the `__bypass` meta-key which lives outside the DSP parameter
  /// space — [GFDescriptorPlugin.getState] only returns declared parameters.
  void _onParamChanged() {
    if (!mounted) return;
    final bypass = widget.instance.state['__bypass'];
    widget.instance.state
      ..clear()
      ..addAll(_plugin.getState());
    if (bypass != null) widget.instance.state['__bypass'] = bypass;
    _syncAllParamsToNative();
    // Use read() since we're in a listener, not a build method.
    // markDirty() triggers both a rebuild and an autosave without
    // calling the protected notifyListeners() from outside the class.
    context.read<RackState>().markDirty();
  }

  /// Push all current parameter values from the Dart plugin to the native DSP.
  ///
  /// Each normalised value [0,1] is converted to the parameter's physical
  /// range (min + norm*(max-min)) before calling [VstHostService.setGfpaDspParam].
  void _syncAllParamsToNative() {
    final vstService = context.read<VstHostService>();
    final params = _plugin.descriptor.parameters;
    for (final p in params) {
      final norm = _plugin.getParameter(p.paramId);
      final physical = p.min + norm * (p.max - p.min);
      vstService.setGfpaDspParam(widget.instance.id, p.id, physical);
    }
  }

  @override
  void dispose() {
    _paramNotifier.removeListener(_onParamChanged);
    _paramNotifier.dispose();
    _vuController.dispose();
    _plugin.dispose();
    // Unregister the native DSP instance so its memory is freed and the ALSA
    // insert chain no longer holds a dangling function pointer.
    // Use the singleton directly to avoid context.read() in dispose().
    VstHostService.instance.unregisterGfpaDsp(widget.instance.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      // Show a minimal loading indicator while the DSP initialises.
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
    final rack = context.read<RackState>();
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
            plugin: _plugin,
            paramNotifier: _paramNotifier,
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
