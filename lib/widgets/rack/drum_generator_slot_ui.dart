import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/drum_generator_plugin_instance.dart';
import '../../models/drum_pattern_data.dart';
import '../../services/audio_engine.dart';
import '../../services/drum_generator_engine.dart';
import '../../services/drum_pattern_parser.dart';
import '../../services/drum_pattern_registry.dart';
import '../../services/transport_engine.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────

const _kBg = Color(0xFF15151F);
const _kPanel = Color(0xFF1C1C2A);
const _kBorder = Color(0xFF2A2A3F);
const _kAccent = Colors.orangeAccent;

// ── Main widget ───────────────────────────────────────────────────────────────

/// Front-panel UI for a [DrumGeneratorPluginInstance] rack slot.
///
/// Provides controls for:
/// - Active toggle (starts/stops drum generation and transport).
/// - Style dropdown grouped by family.
/// - Soundfont selection.
/// - Swing slider (pattern default or override).
/// - Humanisation ("live drummer feel") slider.
/// - Count-in and fill-frequency dropdowns.
/// - Loading a custom `.gfdrum` file.
/// - Showing the `.gfdrum` format guide.
///
/// Responsive: at ≥ 500 px wide, controls lay out in two columns.
class DrumGeneratorSlotUI extends StatefulWidget {
  /// The plugin instance this UI controls.
  final DrumGeneratorPluginInstance plugin;

  const DrumGeneratorSlotUI({super.key, required this.plugin});

  @override
  State<DrumGeneratorSlotUI> createState() => _DrumGeneratorSlotUIState();
}

class _DrumGeneratorSlotUIState extends State<DrumGeneratorSlotUI> {
  @override
  void initState() {
    super.initState();
    // Ensure a session is registered for this slot when the UI first renders.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DrumGeneratorEngine>().ensureSession(
            widget.plugin.id,
            widget.plugin,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder ensures the entire slot body rebuilds whenever the
    // DrumGeneratorEngine notifies — this is what makes the active toggle,
    // style dropdown, and other state-driven widgets stay in sync after the
    // engine mutates the plugin instance (e.g. setActive, loadBuiltinPattern).
    return ListenableBuilder(
      listenable: context.read<DrumGeneratorEngine>(),
      builder: (context, _) => Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        decoration: BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 500;
              return isWide
                  ? _WideLayout(plugin: widget.plugin)
                  : _NarrowLayout(plugin: widget.plugin);
            },
          ),
        ),
      ),
    );
  }
}

// ── Wide layout (≥ 500 px) ────────────────────────────────────────────────────

/// Two-column layout for tablet/desktop form factors.
class _WideLayout extends StatelessWidget {
  final DrumGeneratorPluginInstance plugin;

  const _WideLayout({required this.plugin});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1: active toggle + style + soundfont.
        // Both dropdowns are wrapped in Expanded so the Row provides bounded
        // width constraints — required by DropdownButton(isExpanded: true).
        // Style gets 3 parts, soundfont 2 parts of the shared space.
        Row(
          children: [
            _ActiveToggle(plugin: plugin),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: _StyleDropdown(plugin: plugin)),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: _SoundfontDropdown(plugin: plugin)),
          ],
        ),
        const SizedBox(height: 8),
        // Row 2–3: sliders side by side
        Row(
          children: [
            Expanded(child: _SwingSlider(plugin: plugin)),
            const SizedBox(width: 12),
            Expanded(child: _HumanizeSlider(plugin: plugin)),
          ],
        ),
        const SizedBox(height: 8),
        // Row 4: count-in + fill dropdowns
        Row(
          children: [
            Expanded(child: _CountInDropdown(plugin: plugin)),
            const SizedBox(width: 8),
            Expanded(child: _FillDropdown(plugin: plugin)),
          ],
        ),
        const SizedBox(height: 8),
        // Row 5: load + format guide
        Row(
          children: [
            Expanded(child: _LoadPatternButton(plugin: plugin)),
            const SizedBox(width: 8),
            _FormatGuideButton(plugin: plugin),
          ],
        ),
      ],
    );
  }
}

// ── Narrow layout (< 500 px) ──────────────────────────────────────────────────

/// Single-column stacked layout for phone form factors.
class _NarrowLayout extends StatelessWidget {
  final DrumGeneratorPluginInstance plugin;

  const _NarrowLayout({required this.plugin});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _ActiveToggle(plugin: plugin),
            const SizedBox(width: 8),
            Expanded(child: _StyleDropdown(plugin: plugin)),
          ],
        ),
        const SizedBox(height: 8),
        _SoundfontDropdown(plugin: plugin),
        const SizedBox(height: 8),
        _SwingSlider(plugin: plugin),
        const SizedBox(height: 4),
        _HumanizeSlider(plugin: plugin),
        const SizedBox(height: 8),
        _CountInDropdown(plugin: plugin),
        const SizedBox(height: 4),
        _FillDropdown(plugin: plugin),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _LoadPatternButton(plugin: plugin)),
            const SizedBox(width: 8),
            _FormatGuideButton(plugin: plugin),
          ],
        ),
      ],
    );
  }
}

// ── Active toggle ─────────────────────────────────────────────────────────────

/// Switch that activates or deactivates the drum generator for this slot.
///
/// When activating while the transport is stopped, also starts the transport.
class _ActiveToggle extends StatelessWidget {
  final DrumGeneratorPluginInstance plugin;

  const _ActiveToggle({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.drumGeneratorActiveLabel,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(width: 4),
        Switch(
          value: plugin.isActive,
          activeThumbColor: _kAccent,
          onChanged: (val) => _onChanged(context, val),
        ),
      ],
    );
  }

  void _onChanged(BuildContext context, bool val) {
    context.read<DrumGeneratorEngine>().setActive(plugin.id, val);
    if (val && !context.read<TransportEngine>().isPlaying) {
      context.read<TransportEngine>().play();
    }
  }
}

// ── Style dropdown ────────────────────────────────────────────────────────────

/// Grouped dropdown that lists all registered patterns by family.
class _StyleDropdown extends StatelessWidget {
  final DrumGeneratorPluginInstance plugin;

  const _StyleDropdown({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final registry = DrumPatternRegistry.instance;
    final patterns = registry.all;

    if (patterns.isEmpty) {
      return Text(
        l10n.drumGeneratorNoPatternsFound,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      );
    }

    // Determine the displayed value.
    final currentId = plugin.builtinPatternId;
    final isCustom = plugin.customPatternPath != null;
    final displayValue = isCustom ? '__custom__' : currentId;

    // Build items: group by family with dividers.
    final items = _buildDropdownItems(context, l10n, patterns, isCustom);

    return DropdownButton<String>(
      isExpanded: true,
      value: displayValue,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      dropdownColor: _kPanel,
      underline: Container(height: 1, color: _kBorder),
      hint: Text(
        l10n.drumGeneratorStyleLabel,
        style: const TextStyle(color: Colors.white54),
      ),
      items: items,
      onChanged: (id) => _onChanged(context, id),
    );
  }

  /// Builds the list of [DropdownMenuItem]s grouped by family.
  List<DropdownMenuItem<String>> _buildDropdownItems(
    BuildContext context,
    AppLocalizations l10n,
    List<DrumPatternData> patterns,
    bool isCustom,
  ) {
    final items = <DropdownMenuItem<String>>[];

    // Add custom-pattern item if one is loaded.
    if (isCustom) {
      items.add(DropdownMenuItem(
        value: '__custom__',
        child: Text(l10n.drumGeneratorCustomPattern),
      ));
    }

    // Group patterns by family.
    final families = DrumPatternRegistry.instance.families;
    for (final family in families) {
      final familyPatterns = patterns.where((p) => p.family == family).toList();
      for (final pattern in familyPatterns) {
        items.add(DropdownMenuItem(
          value: pattern.id,
          child: Text(
            '${_familyLabel(l10n, family)} — ${pattern.name}',
            overflow: TextOverflow.ellipsis,
          ),
        ));
      }
    }

    return items;
  }

  void _onChanged(BuildContext context, String? id) {
    if (id == null || id == '__custom__') return;
    context.read<DrumGeneratorEngine>().loadBuiltinPattern(plugin.id, id);
  }

  /// Returns a localised family label.
  String _familyLabel(AppLocalizations l10n, String family) {
    switch (family) {
      case 'rock':
        return l10n.drumGeneratorFamilyRock;
      case 'jazz':
        return l10n.drumGeneratorFamilyJazz;
      case 'funk':
        return l10n.drumGeneratorFamilyFunk;
      case 'latin':
        return l10n.drumGeneratorFamilyLatin;
      case 'celtic':
        return l10n.drumGeneratorFamilyCeltic;
      case 'pop':
        return l10n.drumGeneratorFamilyPop;
      case 'electronic':
        return l10n.drumGeneratorFamilyElectronic;
      case 'world':
        return l10n.drumGeneratorFamilyWorld;
      case 'metal':
        return l10n.drumGeneratorFamilyMetal;
      case 'country':
        return l10n.drumGeneratorFamilyCountry;
      case 'folk':
        return l10n.drumGeneratorFamilyFolk;
      default:
        return family;
    }
  }
}

// ── Soundfont dropdown ────────────────────────────────────────────────────────

/// Dropdown that lists all soundfonts already loaded in the app (same list
/// shown in the GF Keyboard slot) and lets the user pick one for this drum
/// slot.
///
/// The dropdown is driven by [AudioEngine.loadedSoundfonts] so it stays in
/// sync with any soundfonts added in Preferences without needing a file picker.
/// When no soundfonts are loaded at all, a short hint is shown instead.
class _SoundfontDropdown extends StatelessWidget {
  final DrumGeneratorPluginInstance plugin;

  const _SoundfontDropdown({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final engine = context.read<AudioEngine>();

    // Rebuild this widget whenever the engine's loaded-soundfont list changes.
    return ValueListenableBuilder<int>(
      valueListenable: engine.stateNotifier,
      builder: (context, _, _) {
        final soundfonts = engine.loadedSoundfonts;

        // No soundfonts loaded yet — show an informational placeholder.
        if (soundfonts.isEmpty) {
          return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black26,
              border: Border.all(color: _kBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              l10n.drumGeneratorNoSoundfonts,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }

        // Sort: default soundfont (contains 'default_soundfont.sf2') first.
        final sorted = List<String>.from(soundfonts)
          ..sort((a, b) {
            final aIsDefault = a.endsWith('default_soundfont.sf2');
            final bIsDefault = b.endsWith('default_soundfont.sf2');
            if (aIsDefault && !bIsDefault) return -1;
            if (!aIsDefault && bIsDefault) return 1;
            return a.compareTo(b);
          });

        // Determine the currently selected value, falling back to the first
        // available soundfont if the stored path is no longer in the list.
        final currentPath = plugin.soundfontPath;
        final effectivePath = (currentPath != null &&
                soundfonts.contains(currentPath))
            ? currentPath
            : sorted.first;

        return Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.black26,
            border: Border.all(color: _kBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: _kPanel,
              value: effectivePath,
              icon: const Icon(
                Icons.arrow_drop_down,
                color: Colors.white54,
                size: 20,
              ),
              style:
                  const TextStyle(fontSize: 13, color: Colors.white70),
              items: sorted.map((path) {
                final isDefault = path.endsWith('default_soundfont.sf2');
                final name = isDefault
                    ? l10n.patchDefaultSoundfont
                    : path
                        .split(kIsWeb ? '/' : Platform.pathSeparator)
                        .last;
                return DropdownMenuItem<String>(
                  value: path,
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight:
                          isDefault ? FontWeight.bold : FontWeight.normal,
                      color: isDefault ? Colors.blue[300] : Colors.white70,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (path) {
                if (path == null) return;
                context
                    .read<DrumGeneratorEngine>()
                    .setSoundfont(plugin.id, path);
              },
            ),
          ),
        );
      },
    );
  }
}

// ── Swing slider ──────────────────────────────────────────────────────────────

/// Slider that overrides the pattern's swing ratio.
///
/// The leftmost position (0.5) is perfectly straight; the rightmost (0.75)
/// is heavy swing.  A null override defers to the pattern default.
class _SwingSlider extends StatelessWidget {
  final DrumGeneratorPluginInstance plugin;

  const _SwingSlider({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Show "Pattern default" when no override is set.
    final isDefault = plugin.swingOverride == null;
    final sliderValue = plugin.swingOverride ?? 0.5;
    final ratioLabel = isDefault
        ? l10n.drumGeneratorSwingPattern
        : sliderValue.toStringAsFixed(2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.drumGeneratorSwingLabel,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
            const Spacer(),
            Text(
              ratioLabel,
              style: const TextStyle(fontSize: 11, color: Colors.orangeAccent),
            ),
          ],
        ),
        Slider(
          value: sliderValue,
          min: 0.5,
          max: 0.75,
          divisions: 25,
          activeColor: _kAccent,
          onChanged: (v) => _onChanged(context, v),
          // Double-tap to reset to pattern default.
          onChangeEnd: (v) => _onChangeEnd(context, v),
        ),
      ],
    );
  }

  void _onChanged(BuildContext context, double v) {
    // Small deadband: if very close to 0.5, treat as "no override".
    plugin.swingOverride = (v - 0.5).abs() < 0.005 ? null : v;
    context.read<DrumGeneratorEngine>().markDirty();
  }

  void _onChangeEnd(BuildContext context, double v) {
    if ((v - 0.5).abs() < 0.005) {
      plugin.swingOverride = null;
      context.read<DrumGeneratorEngine>().markDirty();
    }
  }
}

// ── Humanize slider ───────────────────────────────────────────────────────────

/// Slider for the humanisation amount (0 = robotic, 1 = full live feel).
class _HumanizeSlider extends StatelessWidget {
  final DrumGeneratorPluginInstance plugin;

  const _HumanizeSlider({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.drumGeneratorHumanizeLabel,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
            const Spacer(),
            Text(
              '${(plugin.humanizationAmount * 100).round()} %',
              style: const TextStyle(fontSize: 11, color: Colors.orangeAccent),
            ),
          ],
        ),
        Row(
          children: [
            Text(
              l10n.drumGeneratorHumanizeRobotic,
              style: const TextStyle(fontSize: 10, color: Colors.white38),
            ),
            Expanded(
              child: Slider(
                value: plugin.humanizationAmount,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                activeColor: _kAccent,
                onChanged: (v) => _onChanged(context, v),
              ),
            ),
            Text(
              l10n.drumGeneratorHumanizeLive,
              style: const TextStyle(fontSize: 10, color: Colors.white38),
            ),
          ],
        ),
      ],
    );
  }

  void _onChanged(BuildContext context, double v) {
    plugin.humanizationAmount = v;
    context.read<DrumGeneratorEngine>().markDirty();
  }
}

// ── Count-in dropdown ─────────────────────────────────────────────────────────

/// Dropdown that selects the count-in style (none / 1 bar / 2 bars / chopsticks).
class _CountInDropdown extends StatelessWidget {
  final DrumGeneratorPluginInstance plugin;

  const _CountInDropdown({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.drumGeneratorIntroLabel,
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
        DropdownButton<DrumIntroType>(
          isExpanded: true,
          value: plugin.structureConfig.introType,
          dropdownColor: _kPanel,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          underline: Container(height: 1, color: _kBorder),
          items: [
            DropdownMenuItem(
              value: DrumIntroType.none,
              child: Text(l10n.drumGeneratorIntroNone),
            ),
            DropdownMenuItem(
              value: DrumIntroType.countIn1,
              child: Text(l10n.drumGeneratorIntroCountIn1),
            ),
            DropdownMenuItem(
              value: DrumIntroType.countIn2,
              child: Text(l10n.drumGeneratorIntroCountIn2),
            ),
            DropdownMenuItem(
              value: DrumIntroType.chopsticks,
              child: Text(l10n.drumGeneratorIntroChopsticks),
            ),
          ],
          onChanged: (val) => _onChanged(context, val),
        ),
      ],
    );
  }

  void _onChanged(BuildContext context, DrumIntroType? val) {
    if (val == null) return;
    plugin.structureConfig = DrumStructureConfig(
      introType: val,
      fillFrequency: plugin.structureConfig.fillFrequency,
      breakFrequency: plugin.structureConfig.breakFrequency,
      breakLengthBars: plugin.structureConfig.breakLengthBars,
      crashAfterFill: plugin.structureConfig.crashAfterFill,
      dynamicBuild: plugin.structureConfig.dynamicBuild,
    );
    context.read<DrumGeneratorEngine>().markDirty();
  }
}

// ── Fill dropdown ─────────────────────────────────────────────────────────────

/// Dropdown that selects how often fill bars occur.
class _FillDropdown extends StatelessWidget {
  final DrumGeneratorPluginInstance plugin;

  const _FillDropdown({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.drumGeneratorFillLabel,
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
        DropdownButton<DrumFillFrequency>(
          isExpanded: true,
          value: plugin.structureConfig.fillFrequency,
          dropdownColor: _kPanel,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          underline: Container(height: 1, color: _kBorder),
          items: [
            DropdownMenuItem(
              value: DrumFillFrequency.off,
              child: Text(l10n.drumGeneratorFillOff),
            ),
            DropdownMenuItem(
              value: DrumFillFrequency.every4,
              child: Text(l10n.drumGeneratorFillEvery4),
            ),
            DropdownMenuItem(
              value: DrumFillFrequency.every8,
              child: Text(l10n.drumGeneratorFillEvery8),
            ),
            DropdownMenuItem(
              value: DrumFillFrequency.every16,
              child: Text(l10n.drumGeneratorFillEvery16),
            ),
            DropdownMenuItem(
              value: DrumFillFrequency.random,
              child: Text(l10n.drumGeneratorFillRandom),
            ),
          ],
          onChanged: (val) => _onChanged(context, val),
        ),
      ],
    );
  }

  void _onChanged(BuildContext context, DrumFillFrequency? val) {
    if (val == null) return;
    plugin.structureConfig = DrumStructureConfig(
      introType: plugin.structureConfig.introType,
      fillFrequency: val,
      breakFrequency: plugin.structureConfig.breakFrequency,
      breakLengthBars: plugin.structureConfig.breakLengthBars,
      crashAfterFill: plugin.structureConfig.crashAfterFill,
      dynamicBuild: plugin.structureConfig.dynamicBuild,
    );
    context.read<DrumGeneratorEngine>().markDirty();
  }
}

// ── Load .gfdrum button ───────────────────────────────────────────────────────

/// Button that opens a file picker for a custom `.gfdrum` pattern file.
class _LoadPatternButton extends StatelessWidget {
  final DrumGeneratorPluginInstance plugin;

  const _LoadPatternButton({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: _kAccent,
        side: const BorderSide(color: _kBorder),
      ),
      icon: const Icon(Icons.file_open, size: 16),
      label: Text(l10n.drumGeneratorLoadPattern),
      onPressed: () => _pickPattern(context),
    );
  }

  Future<void> _pickPattern(BuildContext context) async {
    if (kIsWeb) return; // File picker not available on web for this extension.

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gfdrum'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    try {
      final content = await File(path).readAsString();
      final stem = path.split('/').last.replaceAll('.gfdrum', '');
      final parsed = DrumPatternParser.parse(content, id: stem);
      if (parsed == null) return;
      if (context.mounted) {
        context.read<DrumGeneratorEngine>().loadCustomPattern(
              plugin.id,
              parsed,
              path,
            );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load .gfdrum: $e')),
        );
      }
    }
  }
}

// ── Format guide button ───────────────────────────────────────────────────────

/// Button that shows the `.gfdrum` format guide in an AlertDialog.
class _FormatGuideButton extends StatelessWidget {
  final DrumGeneratorPluginInstance plugin;

  const _FormatGuideButton({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return IconButton(
      icon: const Icon(Icons.help_outline, color: Colors.white38),
      tooltip: l10n.drumGeneratorFormatGuide,
      onPressed: () => _showGuide(context),
    );
  }

  void _showGuide(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C2A),
        title: Text(
          l10n.drumGeneratorFormatGuideTitle,
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Text(
            l10n.drumGeneratorFormatGuideContent,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.actionDone),
          ),
        ],
      ),
    );
  }
}
