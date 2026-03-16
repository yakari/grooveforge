import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/gfpa_plugin_instance.dart';
import '../models/grooveforge_keyboard_plugin.dart';
import '../models/keyboard_display_config.dart';
import '../models/plugin_instance.dart';
import '../models/virtual_piano_plugin.dart';
import '../services/audio_engine.dart';
import '../services/cc_mapping_service.dart';
import '../services/rack_state.dart';

/// Returns true for plugins that support per-slot keyboard config.
///
/// Currently: [GrooveForgeKeyboardPlugin], [VirtualPianoPlugin], and the
/// GFPA Vocoder (which has an embedded virtual piano).
bool _supportsKeyboardConfig(PluginInstance plugin) {
  if (plugin is GrooveForgeKeyboardPlugin) return true;
  if (plugin is VirtualPianoPlugin) return true;
  if (plugin is GFpaPluginInstance &&
      plugin.pluginId == 'com.grooveforge.vocoder') {
    return true;
  }
  return false;
}

/// Returns the current [KeyboardDisplayConfig] for [plugin], or null.
KeyboardDisplayConfig? _configOf(PluginInstance plugin) {
  if (plugin is GrooveForgeKeyboardPlugin) return plugin.keyboardConfig;
  if (plugin is VirtualPianoPlugin) return plugin.keyboardConfig;
  if (plugin is GFpaPluginInstance) return plugin.keyboardConfig;
  return null;
}

/// Opens the per-slot keyboard configuration dialog for [plugin].
///
/// Valid for [GrooveForgeKeyboardPlugin], [VirtualPianoPlugin], and the
/// GFPA Vocoder. Calling with any other plugin type is a no-op.
///
/// The dialog lets the user override, per slot:
/// - Number of visible keys
/// - Key height (Compact / Normal / Large / Extra Large)
/// - Vertical swipe gesture action
/// - Horizontal swipe gesture action
/// - Aftertouch destination CC
///
/// Changes are applied immediately and persisted via [RackState.setKeyboardConfig].
void showKeyboardConfigDialog(BuildContext context, PluginInstance plugin) {
  if (!_supportsKeyboardConfig(plugin)) return;
  showDialog<void>(
    context: context,
    builder: (ctx) => _KeyboardConfigDialog(plugin: plugin),
  );
}

// ─── Dialog widget ────────────────────────────────────────────────────────────

/// The keyboard configuration [AlertDialog] for a single rack slot.
///
/// All fields are initialised from the slot's [KeyboardDisplayConfig] if
/// present, otherwise from the global [AudioEngine] defaults. Changes are
/// applied live via [RackState.setKeyboardConfig] so that the piano updates
/// in real time while the dialog is open.
class _KeyboardConfigDialog extends StatefulWidget {
  final PluginInstance plugin;

  const _KeyboardConfigDialog({required this.plugin});

  @override
  State<_KeyboardConfigDialog> createState() => _KeyboardConfigDialogState();
}

class _KeyboardConfigDialogState extends State<_KeyboardConfigDialog> {
  // ── Working copies of each override field ──────────────────────────────

  /// null means "use global default".
  int? _keysToShow;

  /// null means "use global default".
  GestureAction? _verticalAction;

  /// null means "use global default".
  GestureAction? _horizontalAction;

  /// null means "use global default".
  int? _aftertouchDestCc;

  /// Always explicit — no global default for key height.
  late KeyHeightOption _keyHeightOption;

  @override
  void initState() {
    super.initState();
    _loadFromPlugin();
  }

  /// Reads the current slot config (or leaves fields null for global fallback).
  void _loadFromPlugin() {
    final cfg = _pluginConfig;
    _keysToShow = cfg?.keysToShow;
    _verticalAction = cfg?.verticalGestureAction;
    _horizontalAction = cfg?.horizontalGestureAction;
    _aftertouchDestCc = cfg?.aftertouchDestCc;
    _keyHeightOption = cfg?.keyHeightOption ?? KeyHeightOption.normal;
  }

  KeyboardDisplayConfig? get _pluginConfig => _configOf(widget.plugin);

  // ── Persist current state ────────────────────────────────────────────────

  /// Builds a [KeyboardDisplayConfig] from the current working fields and
  /// persists it immediately so the piano updates in real time.
  ///
  /// Always stores an explicit config (never collapses to null here) so that
  /// the chosen key height is respected even when it is [KeyHeightOption.normal].
  /// The only way to revert to null (global defaults) is [_resetToDefaults].
  void _applyConfig(BuildContext ctx) {
    ctx.read<RackState>().setKeyboardConfig(
          widget.plugin.id,
          KeyboardDisplayConfig(
            keysToShow: _keysToShow,
            verticalGestureAction: _verticalAction,
            horizontalGestureAction: _horizontalAction,
            aftertouchDestCc: _aftertouchDestCc,
            keyHeightOption: _keyHeightOption,
          ),
        );
  }

  /// Resets all overrides and closes the dialog.
  void _resetToDefaults(BuildContext ctx) {
    ctx.read<RackState>().setKeyboardConfig(widget.plugin.id, null);
    Navigator.of(ctx).pop();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final engine = context.read<AudioEngine>();

    // The global default key count — shown in the "Default" dropdown item.
    final globalKeys = engine.pianoKeysToShow.value;
    final globalVAction = engine.verticalGestureAction.value;
    final globalHAction = engine.horizontalGestureAction.value;
    final globalCc = engine.aftertouchDestCc.value;

    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: Text(
        l10n.kbConfigTitle,
        style: const TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ConfigRow(
                icon: Icons.piano,
                iconColor: Colors.orange,
                title: l10n.kbConfigKeysToShow,
                subtitle: l10n.kbConfigKeysToShowSubtitle,
                trailing: _keysDropdown(l10n, globalKeys),
              ),
              const Divider(height: 1, color: Colors.white12),
              _ConfigRow(
                icon: Icons.height,
                iconColor: Colors.teal,
                title: l10n.kbConfigKeyHeight,
                subtitle: l10n.kbConfigKeyHeightSubtitle,
                trailing: _heightDropdown(l10n),
              ),
              const Divider(height: 1, color: Colors.white12),
              _ConfigRow(
                icon: Icons.swap_vert,
                iconColor: Colors.orange,
                title: l10n.kbConfigVertGesture,
                subtitle: l10n.kbConfigVertGestureSubtitle,
                trailing: _vertGestureDropdown(l10n, globalVAction),
              ),
              const Divider(height: 1, color: Colors.white12),
              _ConfigRow(
                icon: Icons.swap_horiz,
                iconColor: Colors.blue,
                title: l10n.kbConfigHorizGesture,
                subtitle: l10n.kbConfigHorizGestureSubtitle,
                trailing: _horizGestureDropdown(l10n, globalHAction),
              ),
              const Divider(height: 1, color: Colors.white12),
              _ConfigRow(
                icon: Icons.waves,
                iconColor: Colors.teal,
                title: l10n.kbConfigAftertouch,
                subtitle: l10n.kbConfigAftertouchSubtitle,
                trailing: _aftertouchDropdown(l10n, globalCc),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _resetToDefaults(context),
          child: Text(
            l10n.kbConfigResetDefaults,
            style: const TextStyle(color: Colors.red),
          ),
        ),
        TextButton(
          onPressed: () {
            _applyConfig(context);
            Navigator.of(context).pop();
          },
          child: Text(l10n.actionDone),
        ),
      ],
    );
  }

  // ── Dropdown builders ────────────────────────────────────────────────────

  /// Keys-to-show dropdown.
  ///
  /// First item is "Default (N keys)" which sets the override to null.
  /// The four explicit options mirror the global preference.
  Widget _keysDropdown(AppLocalizations l10n, int globalKeys) {
    // Map white-key counts to total-key display names.
    const keyOptions = {15: 25, 22: 37, 29: 49, 52: 88};
    final currentValue = _keysToShow;

    return DropdownButton<int?>(
      value: currentValue,
      dropdownColor: Colors.grey[850],
      style: const TextStyle(color: Colors.white, fontSize: 13),
      underline: const SizedBox.shrink(),
      items: [
        // "Default" — clears the override
        DropdownMenuItem<int?>(
          value: null,
          child: Text(
            l10n.kbConfigKeysDefault(
              keyOptions[globalKeys] ?? globalKeys,
            ),
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        for (final entry in keyOptions.entries)
          DropdownMenuItem<int?>(
            value: entry.key,
            child: Text('${entry.value} keys'),
          ),
      ],
      onChanged: (val) {
        setState(() => _keysToShow = val);
        _applyConfig(context);
      },
    );
  }

  /// Key-height dropdown with named options.
  Widget _heightDropdown(AppLocalizations l10n) {
    return DropdownButton<KeyHeightOption>(
      value: _keyHeightOption,
      dropdownColor: Colors.grey[850],
      style: const TextStyle(color: Colors.white, fontSize: 13),
      underline: const SizedBox.shrink(),
      items: [
        DropdownMenuItem(
          value: KeyHeightOption.small,
          child: Text(l10n.keyHeightSmall),
        ),
        DropdownMenuItem(
          value: KeyHeightOption.normal,
          child: Text(l10n.keyHeightNormal),
        ),
        DropdownMenuItem(
          value: KeyHeightOption.large,
          child: Text(l10n.keyHeightLarge),
        ),
        DropdownMenuItem(
          value: KeyHeightOption.extraLarge,
          child: Text(l10n.keyHeightExtraLarge),
        ),
      ],
      onChanged: (val) {
        if (val == null) return;
        setState(() => _keyHeightOption = val);
        _applyConfig(context);
      },
    );
  }

  /// Vertical gesture dropdown.
  ///
  /// First item is "Default (current global)" which clears the override.
  /// Note: glissando is excluded from vertical (it only makes sense horizontally).
  Widget _vertGestureDropdown(
    AppLocalizations l10n,
    GestureAction globalAction,
  ) {
    return DropdownButton<GestureAction?>(
      value: _verticalAction,
      dropdownColor: Colors.grey[850],
      style: const TextStyle(color: Colors.white, fontSize: 13),
      underline: const SizedBox.shrink(),
      items: [
        DropdownMenuItem<GestureAction?>(
          value: null,
          child: Text(
            l10n.kbConfigDefault(_actionLabel(l10n, globalAction)),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        DropdownMenuItem<GestureAction?>(
          value: GestureAction.none,
          child: Text(l10n.actionNone),
        ),
        DropdownMenuItem<GestureAction?>(
          value: GestureAction.pitchBend,
          child: Text(l10n.actionPitchBend),
        ),
        DropdownMenuItem<GestureAction?>(
          value: GestureAction.vibrato,
          child: Text(l10n.actionVibrato),
        ),
      ],
      onChanged: (val) {
        setState(() => _verticalAction = val);
        _applyConfig(context);
      },
    );
  }

  /// Horizontal gesture dropdown.
  ///
  /// First item is "Default (current global)" which clears the override.
  Widget _horizGestureDropdown(
    AppLocalizations l10n,
    GestureAction globalAction,
  ) {
    return DropdownButton<GestureAction?>(
      value: _horizontalAction,
      dropdownColor: Colors.grey[850],
      style: const TextStyle(color: Colors.white, fontSize: 13),
      underline: const SizedBox.shrink(),
      items: [
        DropdownMenuItem<GestureAction?>(
          value: null,
          child: Text(
            l10n.kbConfigDefault(_actionLabel(l10n, globalAction)),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        DropdownMenuItem<GestureAction?>(
          value: GestureAction.none,
          child: Text(l10n.actionNone),
        ),
        DropdownMenuItem<GestureAction?>(
          value: GestureAction.pitchBend,
          child: Text(l10n.actionPitchBend),
        ),
        DropdownMenuItem<GestureAction?>(
          value: GestureAction.vibrato,
          child: Text(l10n.actionVibrato),
        ),
        DropdownMenuItem<GestureAction?>(
          value: GestureAction.glissando,
          child: Text(l10n.actionGlissando),
        ),
      ],
      onChanged: (val) {
        setState(() => _horizontalAction = val);
        _applyConfig(context);
      },
    );
  }

  /// Aftertouch CC dropdown — only standard GM CCs (no system actions).
  ///
  /// First item is "Default (CC N)" which clears the override.
  Widget _aftertouchDropdown(AppLocalizations l10n, int globalCc) {
    // Build CC items — filter out system actions (values > 127).
    final ccItems = [
      for (final entry in CcMappingService.standardGmCcs.entries)
        if (entry.key <= 127)
          DropdownMenuItem<int?>(
            value: entry.key,
            child: Text('${entry.value} (CC ${entry.key})'),
          ),
    ];

    // Fallback: if the stored globalCc is not in the list, add it.
    final known = CcMappingService.standardGmCcs.keys.where((k) => k <= 127);
    final globalCcName = known.contains(globalCc)
        ? CcMappingService.standardGmCcs[globalCc]!
        : 'CC $globalCc';

    return DropdownButton<int?>(
      value: _aftertouchDestCc,
      dropdownColor: Colors.grey[850],
      menuMaxHeight: 300,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      underline: const SizedBox.shrink(),
      items: [
        DropdownMenuItem<int?>(
          value: null,
          child: Text(
            'Default ($globalCcName)',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        ...ccItems,
      ],
      onChanged: (val) {
        setState(() => _aftertouchDestCc = val);
        _applyConfig(context);
      },
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Returns the localised label for a [GestureAction].
  String _actionLabel(AppLocalizations l10n, GestureAction action) =>
      switch (action) {
        GestureAction.none => l10n.actionNone,
        GestureAction.pitchBend => l10n.actionPitchBend,
        GestureAction.vibrato => l10n.actionVibrato,
        GestureAction.glissando => l10n.actionGlissando,
      };
}

// ─── Config row helper ────────────────────────────────────────────────────────

/// A two-line label + icon row with a trailing control, matching the style of
/// the Preferences screen rows.
class _ConfigRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _ConfigRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}
