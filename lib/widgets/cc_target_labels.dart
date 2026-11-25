// Names of rack slots and slot parameters, as CC mapping lists show them.
//
// A mapping stores a slot id and a parameter key ("slot-3", "palm_mute").
// Shown raw, they mean nothing to a player; these helpers turn them into the
// slot's name and the parameter's translated label.

import '../l10n/app_localizations.dart';
import '../models/gfpa_plugin_instance.dart';
import '../models/grooveforge_keyboard_plugin.dart';
import '../models/plugin_instance.dart';
import '../services/cc_labels.dart';
import '../services/cc_param_registry.dart';
import 'rack/gfpa_label.dart';

/// The slot [slotId] named for a mapping list: its name, its MIDI channel
/// when it has one, and its position in the rack ("Riff (Ch 2, #3)"), so two
/// slots of the same kind can be told apart. A slot that no longer exists is
/// shown by its id.
String ccSlotName(
  AppLocalizations l10n,
  List<PluginInstance> plugins,
  String slotId,
) {
  for (var i = 0; i < plugins.length; i++) {
    final p = plugins[i];
    if (p.id != slotId) continue;
    final ch = p.midiChannel > 0 ? l10n.ccSlotChannelShort(p.midiChannel) : null;
    final suffix = ch != null ? ' ($ch, #${i + 1})' : ' (#${i + 1})';
    return '${gfpaSlotHeaderName(l10n, p)}$suffix';
  }
  return slotId;
}

/// The registry entry for parameter [paramKey] of slot [slotId], or null
/// when the slot is gone or the parameter is not CC-controllable.
CcParamEntry? ccSlotParamEntry(
  List<PluginInstance> plugins,
  String slotId,
  String paramKey,
) {
  final plugin = plugins.where((p) => p.id == slotId).firstOrNull;
  final pluginId = switch (plugin) {
    GFpaPluginInstance(:final pluginId) => pluginId,
    GrooveForgeKeyboardPlugin() => '_gf_keyboard',
    _ => null,
  };
  if (pluginId == null) return null;
  return CcParamRegistry.findParam(pluginId, paramKey);
}

/// The translated label of parameter [paramKey] of slot [slotId] ("Palm
/// mute"), or the key itself when it cannot be resolved.
String ccSlotParamName(
  AppLocalizations l10n,
  List<PluginInstance> plugins,
  String slotId,
  String paramKey,
) {
  final entry = ccSlotParamEntry(plugins, slotId, paramKey);
  return entry == null ? paramKey : ccParamLabel(l10n, entry);
}
