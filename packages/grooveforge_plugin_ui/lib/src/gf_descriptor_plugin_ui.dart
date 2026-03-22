import 'package:flutter/material.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'rotary_knob.dart';
import 'gf_slider.dart';
import 'gf_vu_meter.dart';
import 'gf_toggle_button.dart';
import 'gf_option_selector.dart';

/// Auto-generates a plugin UI panel from a [GFPluginDescriptor].
///
/// Instead of building bespoke Flutter widgets for every GFPA plugin,
/// [GFDescriptorPluginUI] reads the `ui:` block from a `.gfpd` descriptor and
/// renders the declared controls (knobs, sliders, VU meters, toggles,
/// selectors) in the specified layout.
///
/// Each control is bound to a [GFDescriptorPlugin] instance. Parameter changes
/// from the UI are propagated via [GFDescriptorPlugin.setParameter]; the
/// [ValueNotifier] passed in notifies the widget to rebuild when parameter
/// values change from the engine side.
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
  });

  /// The plugin whose parameters are controlled by this UI.
  final GFDescriptorPlugin plugin;

  /// Notified whenever a parameter changes — triggers a rebuild.
  final ValueNotifier<int> paramNotifier;

  /// Optional VU meter controller. If provided, the [GFControlType.vumeter]
  /// control is rendered with live level data.
  final GFVuMeterController? vuController;

  @override
  Widget build(BuildContext context) {
    final descriptor = plugin.descriptor;

    return ValueListenableBuilder<int>(
      valueListenable: paramNotifier,
      builder: (context, _, __) {
        final controls = descriptor.controls.map((ctrl) {
          return _buildControl(context, ctrl, descriptor);
        }).toList(growable: false);

        if (descriptor.uiLayout == GFUiLayout.grid) {
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: controls,
          );
        }
        // Default: row layout.
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
      },
    );
  }

  // ── Control factory ────────────────────────────────────────────────────────

  Widget _buildControl(
    BuildContext context,
    GFDescriptorControl ctrl,
    GFPluginDescriptor descriptor,
  ) {
    switch (ctrl.type) {
      case GFControlType.knob:
        return _buildKnob(ctrl, descriptor);
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
    }
  }

  // ── Knob ──────────────────────────────────────────────────────────────────

  Widget _buildKnob(GFDescriptorControl ctrl, GFPluginDescriptor descriptor) {
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
      size: size.toDouble(),
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

    return GFOptionSelector(
      options: options,
      selectedIndex: selectedIndex,
      label: label,
      onChanged: (i) {
        final norm = count <= 1 ? 0.0 : i / (count - 1).toDouble();
        plugin.setParameter(param.paramId, norm);
        paramNotifier.value++;
      },
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
