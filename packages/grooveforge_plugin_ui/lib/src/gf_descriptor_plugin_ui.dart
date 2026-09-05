import 'package:flutter/material.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'rotary_knob.dart';
import 'gf_slider.dart';
import 'gf_vu_meter.dart';
import 'gf_toggle_button.dart';
import 'gf_option_selector.dart';
import 'gf_dropdown_selector.dart';
import 'gf_interval_bar.dart';

/// A parameter's value, prepared for display.
///
/// Three fields because a readout is read at three distances: [value] is the
/// number being adjusted and is always shown, [detail] is what it means and
/// may be elided when the column is narrow, and [tooltip] is the whole thing
/// spelled out for a long press.
class GFParamReadout {
  const GFParamReadout({required this.value, this.detail, this.tooltip});

  /// Primary text, e.g. `"+7 st"` or `"3"`. Never truncated.
  final String value;

  /// Secondary line, e.g. `"Perfect 5th"`. Null when the value speaks for
  /// itself.
  final String? detail;

  /// Long-press text carrying the full meaning.
  final String? tooltip;
}

/// Formats a parameter's current value for the readout beside its control.
///
/// Called only for parameters whose descriptor declares a [GFParamDisplay].
/// Returning null falls back to this package's own language-neutral
/// formatting, which is what a host without localisation gets. The hook
/// exists because interval names differ by locale — a perfect fifth is
/// "Perfect 5th" in English and "Quinte juste" in French — and this package
/// deliberately holds no translations of its own.
typedef GFParamValueFormatter = GFParamReadout? Function(
  GFDescriptorParameter param,
  double rawValue,
);

/// Auto-generates a plugin UI panel from a [GFPluginDescriptor].
///
/// Instead of building bespoke Flutter widgets for every GFPA plugin,
/// [GFDescriptorPluginUI] reads the `ui:` block from a `.gfpd` descriptor and
/// renders the declared controls (knobs, sliders, VU meters, toggles,
/// selectors) in the specified layout.
///
/// Each control is bound to a [GFAbstractDescriptorPlugin] instance (either a
/// [GFDescriptorPlugin] for audio effects or a [GFMidiDescriptorPlugin] for
/// MIDI FX). Parameter changes from the UI are propagated via
/// [GFAbstractDescriptorPlugin.setParameter]; the [ValueNotifier] passed in
/// notifies the widget to rebuild when parameter values change from the
/// engine side.
///
/// ## Usage
/// ```dart
/// GFDescriptorPluginUI(
///   plugin: myPlugin,
///   paramNotifier: myParamNotifier, // notified when any param changes
///   vuController: myVuController,   // optional — drives VU meter
/// )
/// ```
class GFDescriptorPluginUI extends StatelessWidget {
  const GFDescriptorPluginUI({
    super.key,
    required this.plugin,
    required this.paramNotifier,
    this.vuController,
    this.valueFormatter,
    this.laneEnabled,
  });

  /// The plugin whose parameters are controlled by this UI.
  ///
  /// Accepts both [GFDescriptorPlugin] (audio effects) and
  /// [GFMidiDescriptorPlugin] (MIDI FX) via [GFAbstractDescriptorPlugin].
  final GFAbstractDescriptorPlugin plugin;

  /// Notified whenever a parameter changes — triggers a rebuild.
  final ValueNotifier<int> paramNotifier;

  /// Optional VU meter controller. If provided, the [GFControlType.vumeter]
  /// control is rendered with live level data.
  final GFVuMeterController? vuController;

  /// Optional host hook for localising parameter readouts. See
  /// [GFParamValueFormatter].
  final GFParamValueFormatter? valueFormatter;

  /// Optional host veto on a lane being live, on top of the descriptor's own
  /// `activeWhen`.
  ///
  /// For things the descriptor cannot know: the Audio Harmonizer's voice
  /// lanes stop being editable when a chord is patched into it, because the
  /// chord is setting them. Leaving them lit would repeat the mistake the
  /// voice-count dimming fixed — controls that look live while something
  /// else decides their value.
  final bool Function(GFDescriptorControlGroup group)? laneEnabled;

  @override
  Widget build(BuildContext context) {
    final descriptor = plugin.descriptor;

    return ValueListenableBuilder<int>(
      valueListenable: paramNotifier,
      builder: (ctx, _, __) {
        // Phase 10: when the descriptor declares groups, use the responsive
        // grouped layout. Otherwise fall back to the legacy flat layout.
        if (descriptor.groups.isNotEmpty) {
          // Lanes are a vertical stack at every width — the whole point is
          // that the groups line up under each other, so there is nothing to
          // gain from collapsing them on a phone.
          if (descriptor.uiLayout == GFUiLayout.lanes) {
            return _buildLaneLayout(ctx, descriptor);
          }
          return LayoutBuilder(
            builder: (_, constraints) => constraints.maxWidth >= 600
                ? _buildWideGroupLayout(ctx, descriptor)
                : _buildNarrowGroupLayout(ctx, descriptor),
          );
        }
        return _buildFlatLayout(ctx, descriptor);
      },
    );
  }

  // ── Flat layout (legacy — no groups) ──────────────────────────────────────

  Widget _buildFlatLayout(BuildContext context, GFPluginDescriptor descriptor) {
    final controls = descriptor.controls
        .map((ctrl) => _buildControl(context, ctrl, descriptor))
        .toList(growable: false);

    if (descriptor.uiLayout == GFUiLayout.grid) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: controls,
      );
    }
    // Default: horizontal row with scroll for overflow.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: controls
            .expand((w) => [w, const SizedBox(width: 10)])
            .toList()
          ..removeLast(),
      ),
    );
  }

  // ── Wide group layout (≥ 600 px) ──────────────────────────────────────────

  /// Renders all groups side-by-side with a labelled column per group.
  ///
  /// Each group column contains a small heading and a [Wrap] of its controls.
  /// Suitable for tablet landscape and desktop.
  Widget _buildWideGroupLayout(
    BuildContext context,
    GFPluginDescriptor descriptor,
  ) {
    final groupWidgets = descriptor.groups.map((group) {
      final controls = group.controls
          .map((ctrl) => _buildControl(context, ctrl, descriptor))
          .toList(growable: false);

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Group label heading.
            Text(
              group.label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 9,
                letterSpacing: 0.8,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: controls,
            ),
          ],
        ),
      );
    }).toList(growable: false);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: groupWidgets,
      ),
    );
  }

  // ── Narrow group layout (< 600 px) ────────────────────────────────────────

  /// Renders each group as a collapsible [ExpansionTile].
  ///
  /// On narrow phones the user taps a group header to expand/collapse it,
  /// keeping the UI usable without scrolling horizontally.
  Widget _buildNarrowGroupLayout(
    BuildContext context,
    GFPluginDescriptor descriptor,
  ) {
    final tiles = descriptor.groups.map((group) {
      final controls = group.controls
          .map((ctrl) => _buildControl(context, ctrl, descriptor))
          .toList(growable: false);

      return ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        title: Text(
          group.label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: controls,
          ),
        ],
      );
    }).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: tiles,
    );
  }

  // ── Lane layout (one row per group) ───────────────────────────────────────

  /// Renders every group as its own horizontal lane, stacked vertically.
  ///
  /// A lane is `[label] [controls…]`. Controls that can stretch — the
  /// interval bar — take the slack, so the ruler is as wide as the panel
  /// allows and the lanes share one scale. A group whose `activeWhen`
  /// condition is not met renders dimmed and refuses input.
  Widget _buildLaneLayout(
    BuildContext context,
    GFPluginDescriptor descriptor,
  ) {
    return LayoutBuilder(
      builder: (_, constraints) {
        // Under about a phone's width the fixed columns either side of the
        // track have to give way, or the ruler shrinks to a stub.
        final compact = constraints.maxWidth < 520;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: descriptor.groups
              .map((group) => _buildLane(context, group, descriptor, compact))
              .toList(growable: false),
        );
      },
    );
  }

  Widget _buildLane(
    BuildContext context,
    GFDescriptorControlGroup group,
    GFPluginDescriptor descriptor,
    bool compact,
  ) {
    final active = group.isActive((id) => _rawValueOf(id, descriptor)) &&
        (laneEnabled?.call(group) ?? true);

    // Only a control that fills the lane earns the leftover width; the rest
    // keep their natural size so knobs stay round and selectors stay tight.
    final children = <Widget>[];
    for (final ctrl in group.controls) {
      final widget = _buildControl(
        context,
        ctrl,
        descriptor,
        enabled: active,
        // Every control in a lane sits beside a 26 px track, so the roomy
        // label spacing a knob uses in a grid would stretch the whole row.
        dense: true,
        narrow: compact,
      );
      children.add(
        ctrl.type == GFControlType.interval ? Expanded(child: widget) : widget,
      );
      children.add(const SizedBox(width: 8));
    }
    if (children.isNotEmpty) children.removeLast();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: compact ? 30 : 46,
            child: Opacity(
              opacity: active ? 1.0 : 0.35,
              child: Text(
                group.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 9,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  /// Raw (un-normalised) value of the parameter [id], or null when the
  /// descriptor declares no such parameter.
  double? _rawValueOf(String id, GFPluginDescriptor descriptor) {
    final param = descriptor.paramById(id);
    if (param == null) return null;
    final norm = plugin.getParameter(param.paramId);
    return param.min + norm * (param.max - param.min);
  }

  // ── Control factory ────────────────────────────────────────────────────────

  Widget _buildControl(
    BuildContext context,
    GFDescriptorControl ctrl,
    GFPluginDescriptor descriptor, {
    bool enabled = true,
    bool dense = false,
    bool narrow = false,
  }) {
    switch (ctrl.type) {
      case GFControlType.knob:
        return _buildKnob(ctrl, descriptor, compact: dense);
      case GFControlType.slider:
        return _buildSlider(ctrl, descriptor);
      case GFControlType.toggle:
        return _buildToggle(ctrl, descriptor);
      case GFControlType.selector:
        return _buildSelector(ctrl, descriptor);
      case GFControlType.vumeter:
        return _buildVuMeter(ctrl);
      case GFControlType.button:
        return _buildButton(ctrl);
      case GFControlType.interval:
        return _buildIntervalBar(ctrl, descriptor, enabled, narrow);
    }
  }

  // ── Interval bar ──────────────────────────────────────────────────────────

  Widget _buildIntervalBar(
    GFDescriptorControl ctrl,
    GFPluginDescriptor descriptor,
    bool enabled,
    bool narrow,
  ) {
    final param = _resolveParam(ctrl, descriptor);
    if (param == null) return const SizedBox.shrink();

    final raw = plugin.getParameter(param.paramId) * (param.max - param.min) +
        param.min;

    final readout = _readoutFor(param, raw);

    return GFIntervalBar(
      value: raw,
      min: param.min,
      max: param.max,
      label: ctrl.label,
      valueLabel: readout?.value,
      detailLabel: readout?.detail,
      tooltip: readout?.tooltip,
      enabled: enabled,
      compact: narrow,
      onChanged: (newRaw) {
        final range = param.max - param.min;
        final norm =
            range == 0 ? 0.0 : ((newRaw - param.min) / range).clamp(0.0, 1.0);
        plugin.setParameter(param.paramId, norm);
        paramNotifier.value++;
      },
    );
  }

  // ── Knob ──────────────────────────────────────────────────────────────────

  Widget _buildKnob(
    GFDescriptorControl ctrl,
    GFPluginDescriptor descriptor, {
    bool compact = false,
  }) {
    final param = _resolveParam(ctrl, descriptor);
    if (param == null) return const SizedBox.shrink();

    final normValue = plugin.getParameter(param.paramId);
    final raw = normValue * (param.max - param.min) + param.min;
    final label = ctrl.label ?? param.name;
    final size = _sizeFor(ctrl.size, small: 36, medium: 50, large: 64);

    return RotaryKnob(
      value: raw,
      min: param.min,
      max: param.max,
      label: label,
      valueLabel: _readoutFor(param, raw)?.value,
      size: size.toDouble(),
      isCompact: compact,
      onChanged: (newRaw) {
        final range = param.max - param.min;
        final norm = range == 0 ? 0.0 : ((newRaw - param.min) / range).clamp(0.0, 1.0);
        plugin.setParameter(param.paramId, norm);
        paramNotifier.value++;
      },
    );
  }

  // ── Slider ────────────────────────────────────────────────────────────────

  Widget _buildSlider(GFDescriptorControl ctrl, GFPluginDescriptor descriptor) {
    final param = _resolveParam(ctrl, descriptor);
    if (param == null) return const SizedBox.shrink();

    final normValue = plugin.getParameter(param.paramId);
    final label = ctrl.label ?? param.name;
    final height = _sizeFor(ctrl.size, small: 60, medium: 90, large: 120);

    return GFSlider(
      normalizedValue: normValue,
      label: label,
      unit: param.unit,
      size: height.toDouble(),
      onChanged: (v) {
        plugin.setParameter(param.paramId, v);
        paramNotifier.value++;
      },
    );
  }

  // ── Toggle ────────────────────────────────────────────────────────────────

  Widget _buildToggle(GFDescriptorControl ctrl, GFPluginDescriptor descriptor) {
    final param = _resolveParam(ctrl, descriptor);
    if (param == null) return const SizedBox.shrink();

    final normValue = plugin.getParameter(param.paramId);
    final isOn = normValue >= 0.5;
    final label = ctrl.label ?? param.name;
    final size = _sizeFor(ctrl.size, small: 28, medium: 36, large: 44);

    return GFToggleButton(
      value: isOn,
      label: label,
      size: size.toDouble(),
      onChanged: (v) {
        plugin.setParameter(param.paramId, v ? 1.0 : 0.0);
        paramNotifier.value++;
      },
    );
  }

  // ── Selector ──────────────────────────────────────────────────────────────

  Widget _buildSelector(
    GFDescriptorControl ctrl,
    GFPluginDescriptor descriptor,
  ) {
    final param = _resolveParam(ctrl, descriptor);
    if (param == null) return const SizedBox.shrink();

    final normValue = plugin.getParameter(param.paramId);
    final options = param.options.isNotEmpty
        ? param.options
        : List.generate(
            (param.max - param.min + 1).round(),
            (i) => '${(param.min + i).toInt()}',
          );
    final count = options.length;
    final selectedIndex = (normValue * (count - 1)).round().clamp(0, count - 1);
    final label = ctrl.label ?? param.name;
    void onChanged(int i) {
      final norm = count <= 1 ? 0.0 : i / (count - 1).toDouble();
      plugin.setParameter(param.paramId, norm);
      paramNotifier.value++;
    }

    // Use a dropdown for large option sets — segmented rows become unreadable
    // beyond ~5 options (each segment would be too narrow to display its label).
    if (count > 5) {
      return GFDropdownSelector(
        options: options,
        selectedIndex: selectedIndex,
        label: label,
        onChanged: onChanged,
      );
    }

    return GFOptionSelector(
      options: options,
      selectedIndex: selectedIndex,
      label: label,
      onChanged: onChanged,
    );
  }

  // ── VU meter ──────────────────────────────────────────────────────────────

  Widget _buildVuMeter(GFDescriptorControl ctrl) {
    final height = _sizeFor(ctrl.size, small: 50, medium: 80, large: 110);
    return GFVuMeter(
      controller: vuController,
      height: height.toDouble(),
      width: 20.0,
    );
  }

  // ── Action button ─────────────────────────────────────────────────────────

  Widget _buildButton(GFDescriptorControl ctrl) {
    return _ActionButton(
      label: ctrl.label ?? ctrl.action ?? '?',
      onTap: () {
        // Action handling is extensible: the host can listen to a
        // notifier/stream; for now "reset" restores all defaults.
        if (ctrl.action == 'reset') _resetAllParams();
      },
    );
  }

  void _resetAllParams() {
    for (final p in plugin.descriptor.parameters) {
      final range = p.max - p.min;
      final norm = range == 0
          ? 0.0
          : ((p.defaultValue - p.min) / range).clamp(0.0, 1.0);
      plugin.setParameter(p.paramId, norm);
    }
    paramNotifier.value++;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// The readout to print beside a control, or null for the plain
  /// label-only look every undeclared parameter keeps.
  GFParamReadout? _readoutFor(GFDescriptorParameter param, double raw) {
    if (param.display == GFParamDisplay.none) return null;
    final hosted = valueFormatter?.call(param, raw);
    if (hosted != null) return hosted;
    return switch (param.display) {
      GFParamDisplay.integer => GFParamReadout(value: raw.round().toString()),
      // Without a host formatter there are no interval names to print, so
      // fall back to the signed semitone count on its own — still far more
      // use than a bare knob angle.
      GFParamDisplay.interval =>
        GFParamReadout(value: _signedSemitones(raw, param.unit)),
      GFParamDisplay.none => null,
    };
  }

  /// `+7 st` / `-5 st` — the sign is always explicit so a downward voice
  /// reads as one at a glance.
  static String _signedSemitones(double raw, String unit) {
    final semis = raw.round();
    final sign = semis > 0 ? '+' : '';
    return unit.isEmpty ? '$sign$semis' : '$sign$semis $unit';
  }

  GFDescriptorParameter? _resolveParam(
    GFDescriptorControl ctrl,
    GFPluginDescriptor descriptor,
  ) {
    if (ctrl.paramId == null) return null;
    return descriptor.paramById(ctrl.paramId!);
  }

  int _sizeFor(GFControlSize s, {required int small, required int medium, required int large}) =>
      switch (s) {
        GFControlSize.small => small,
        GFControlSize.large => large,
        _ => medium,
      };
}

// ── Simple push-button widget ─────────────────────────────────────────────────

/// A small rectangular push-button matching the dark plugin panel aesthetic.
class _ActionButton extends StatefulWidget {
  const _ActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _pressed
                ? [const Color(0xFF2A2A2A), const Color(0xFF1A1A1A)]
                : [const Color(0xFF444444), const Color(0xFF2E2E2E)],
          ),
          border: Border.all(
            color: Colors.orange.withValues(alpha: _pressed ? 0.6 : 0.3),
            width: 1,
          ),
          boxShadow: _pressed
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: _pressed ? Colors.orange : Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
