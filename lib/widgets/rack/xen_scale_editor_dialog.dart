import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

import '../../l10n/app_localizations.dart';
import '../../services/custom_scale_library.dart';
import '../../services/file_picker_service.dart';
import 'gfpa_xen_slot_ui.dart' show xenRootName, xenScaleLabel;

// ─── Design tokens ───────────────────────────────────────────────────────────

const _kPanelBg = Color(0xFF141414);
const _kFieldBg = Color(0xFF1A1A1A);
const _kAmber = Color(0xFFFFAD2A);
const _kTuneColor = Color(0xFF00E5C0);
const _kMuted = Color(0xFF8A8A8A);

// ─── Editable row ────────────────────────────────────────────────────────────

/// One degree while it is being edited.
///
/// Mutable and text-backed, unlike the immutable [GFScaleDegree] it becomes on
/// save: a half-typed "-5" on the way to "-50" is not a valid degree, and
/// forcing it through the model on every keystroke would fight the player.
class _DegreeDraft {
  int semitone;
  final TextEditingController offset;
  bool active;

  _DegreeDraft({
    required this.semitone,
    required double cents,
    required this.active,
  }) : offset = TextEditingController(text: _formatCents(cents));

  double get cents => double.tryParse(offset.text.replaceAll(',', '.')) ?? 0.0;

  void dispose() => offset.dispose();

  static String _formatCents(double cents) {
    if (cents == cents.roundToDouble()) return cents.toStringAsFixed(0);
    return cents.toStringAsFixed(3);
  }
}

// ─── Dialog ──────────────────────────────────────────────────────────────────

/// Full-screen editor for a custom scale.
///
/// The list of degrees has no fixed length. That is deliberate and is what
/// makes the two shapes the player asked for both reachable:
///
///   - **A subset that fits the octave** — twelve degrees or fewer on the
///     keyboard layout, each on its own key, leaving the rest chromatic.
///   - **A division that spreads across the keyboard** — nineteen or more
///     degrees on the linear layout, where one octave costs nineteen keys.
///
/// And muting, which is neither adding nor removing: the degree keeps
/// sounding at its own tuning, but the snap stage stops treating it as a
/// destination. That is how a quarter-tone gets added to a blues scale as a
/// colour to lean on, without every nearby note being dragged onto it.
///
/// Returns the saved scale, or null when cancelled.
class XenScaleEditorDialog extends StatefulWidget {
  const XenScaleEditorDialog({
    super.key,
    required this.library,
    this.initial,
  });

  /// The player's scale library — saved scales go here and to the slot.
  final CustomScaleLibrary library;

  /// The scale being edited, or null to start a new one.
  final GFScale? initial;

  @override
  State<XenScaleEditorDialog> createState() => _XenScaleEditorDialogState();
}

class _XenScaleEditorDialogState extends State<XenScaleEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _period;
  final List<_DegreeDraft> _degrees = [];
  GFScaleMapping _mapping = GFScaleMapping.pitchClass;

  /// Id of the scale under edit. Kept across saves so an edited scale replaces
  /// itself rather than accumulating copies — and so CC pad mappings pointing
  /// at it keep working.
  late String _id;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _period =
        TextEditingController(text: (initial?.periodCents ?? 1200.0).toString());
    _id = initial?.id ?? '';
    if (initial != null) {
      _mapping = initial.mapping;
      _degrees.addAll(initial.degrees.map(_draftOf));
    } else {
      _degrees.add(_DegreeDraft(semitone: 0, cents: 0, active: true));
    }
  }

  _DegreeDraft _draftOf(GFScaleDegree d) =>
      _DegreeDraft(semitone: d.semitone, cents: d.cents, active: d.active);

  @override
  void dispose() {
    _name.dispose();
    _period.dispose();
    for (final d in _degrees) {
      d.dispose();
    }
    super.dispose();
  }

  // ── Derived state ──────────────────────────────────────────────────────────

  int get _activeCount => _degrees.where((d) => d.active).length;

  /// True when two degrees claim the same key, which the keyboard layout
  /// cannot express.
  bool get _hasDuplicateKeys {
    if (_mapping != GFScaleMapping.pitchClass) return false;
    final keys = _degrees.map((d) => d.semitone).toList();
    return keys.toSet().length != keys.length;
  }

  double get _periodCents =>
      double.tryParse(_period.text.replaceAll(',', '.')) ?? 1200.0;

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      backgroundColor: _kPanelBg,
      insetPadding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _header(l10n),
                const Divider(height: 1, color: Color(0xFF2A2A2A)),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _identityRow(l10n, narrow),
                        const SizedBox(height: 12),
                        _layoutRow(l10n, narrow),
                        const SizedBox(height: 14),
                        _degreeList(l10n, narrow),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF2A2A2A)),
                _actions(l10n, narrow),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(AppLocalizations l10n) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Row(
          children: [
            const Icon(Icons.tune, size: 18, color: _kAmber),
            const SizedBox(width: 8),
            // Both labels are translated and neither has a bounded length, so
            // both must be able to give way rather than push the other off the
            // panel. The title yields first; the degree count is the piece a
            // player is actually reading while editing.
            Flexible(
              child: Text(
                l10n.xenEditorTitle,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _kAmber,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              flex: 0,
              child: Text(
                l10n.xenEditorDegreeCount(_degrees.length, _activeCount),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ],
        ),
      );

  // ── Name and seed ──────────────────────────────────────────────────────────

  Widget _identityRow(AppLocalizations l10n, bool narrow) {
    final name = TextField(
      controller: _name,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: _fieldDecoration(l10n.xenEditorName),
    );
    final seed = _SeedPicker(
      label: l10n.xenEditorSeed,
      onSeed: _seedFrom,
      l10n: l10n,
    );

    if (narrow) {
      return Column(children: [name, const SizedBox(height: 10), seed]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: name),
        const SizedBox(width: 10),
        seed,
      ],
    );
  }

  /// Replaces the current draft with a copy of [scale]'s degrees.
  ///
  /// The fastest route to both of the player's examples: seed from Blues and
  /// add a quarter-tone, or seed from 19-EDO and delete rows down to a subset.
  void _seedFrom(GFScale scale) {
    setState(() {
      for (final d in _degrees) {
        d.dispose();
      }
      _degrees
        ..clear()
        ..addAll(scale.degrees.map(_draftOf));
      _mapping = scale.mapping;
      _period.text = scale.periodCents.toString();
      if (_name.text.trim().isEmpty) _name.text = scale.name;
    });
  }

  // ── Layout and period ──────────────────────────────────────────────────────

  Widget _layoutRow(AppLocalizations l10n, bool narrow) {
    final toggle = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LayoutChip(
          label: l10n.xenEditorLayoutKeyboard,
          selected: _mapping == GFScaleMapping.pitchClass,
          onTap: () => setState(() => _mapping = GFScaleMapping.pitchClass),
        ),
        const SizedBox(width: 6),
        _LayoutChip(
          label: l10n.xenEditorLayoutLinear,
          selected: _mapping == GFScaleMapping.linear,
          onTap: () => setState(() => _mapping = GFScaleMapping.linear),
        ),
      ],
    );

    final period = SizedBox(
      width: 150,
      child: TextField(
        controller: _period,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        onChanged: (_) => setState(() {}),
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: _fieldDecoration(l10n.xenEditorPeriod),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.xenEditorLayout,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [toggle, const SizedBox(height: 10), period],
              )
            : Row(children: [toggle, const SizedBox(width: 14), period]),
        const SizedBox(height: 6),
        Text(
          _mapping == GFScaleMapping.pitchClass
              ? l10n.xenEditorLayoutKeyboardHint
              : l10n.xenEditorLayoutLinearHint(_degrees.length),
          style: const TextStyle(color: Colors.white38, fontSize: 10.5),
        ),
        if (_hasDuplicateKeys) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 14, color: _kAmber),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  l10n.xenEditorDuplicateKeys,
                  style: const TextStyle(color: _kAmber, fontSize: 10.5),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ── Degrees ────────────────────────────────────────────────────────────────

  Widget _degreeList(AppLocalizations l10n, bool narrow) {
    if (_degrees.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.xenEditorNoDegrees,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 10),
            _addButton(l10n),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _degrees.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _degreeRow(l10n, i, narrow),
          ),
        const SizedBox(height: 4),
        _addButton(l10n),
      ],
    );
  }

  Widget _degreeRow(AppLocalizations l10n, int index, bool narrow) {
    final draft = _degrees[index];
    // On the linear layout a degree's key IS its position, so the key picker
    // would be a control that cannot be used — show the resulting key instead.
    final keyLabel = _mapping == GFScaleMapping.pitchClass
        ? xenRootName(draft.semitone)
        : '#${index + 1}';
    final sounds = _mapping == GFScaleMapping.pitchClass
        ? draft.semitone * 100.0 + draft.cents
        : index * 100.0 + draft.cents;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        color: _kFieldBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: draft.active ? Colors.white12 : _kMuted.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          // Key
          if (_mapping == GFScaleMapping.pitchClass)
            _KeyPicker(
              semitone: draft.semitone,
              enabled: true,
              onChanged: (v) => setState(() => draft.semitone = v),
            )
          else
            SizedBox(
              width: 46,
              child: Text(
                keyLabel,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(width: 8),
          // Offset in cents
          SizedBox(
            width: narrow ? 74 : 96,
            child: TextField(
              controller: draft.offset,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
              ],
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                color: draft.active ? Colors.white : _kMuted,
                fontSize: 12,
              ),
              decoration: _fieldDecoration(l10n.xenEditorOffset, dense: true),
            ),
          ),
          const SizedBox(width: 8),
          // Resulting pitch — the value the player is actually reasoning about.
          Expanded(
            child: Text(
              l10n.xenEditorSounds(sounds.toStringAsFixed(
                sounds == sounds.roundToDouble() ? 0 : 2,
              )),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: draft.active
                    ? _kTuneColor.withValues(alpha: 0.85)
                    : _kMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Mute
          IconButton(
            tooltip: l10n.xenEditorMute,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              draft.active ? Icons.volume_up : Icons.volume_off,
              size: 17,
              color: draft.active ? Colors.white54 : _kMuted,
            ),
            onPressed: () => setState(() => draft.active = !draft.active),
          ),
          // Remove
          IconButton(
            tooltip: l10n.xenEditorRemoveDegree,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 16, color: Colors.white38),
            onPressed: () => setState(() {
              _degrees.removeAt(index).dispose();
            }),
          ),
        ],
      ),
    );
  }

  Widget _addButton(AppLocalizations l10n) => TextButton.icon(
        onPressed: _addDegree,
        icon: const Icon(Icons.add, size: 16),
        label: Text(l10n.xenEditorAddDegree),
        style: TextButton.styleFrom(foregroundColor: _kAmber),
      );

  /// Appends a degree just above the last one.
  ///
  /// Seeding it with the next free key rather than with zero saves a step in
  /// the common case of building a scale upwards.
  void _addDegree() {
    setState(() {
      final used = _degrees.map((d) => d.semitone).toSet();
      var next = _degrees.isEmpty ? 0 : _degrees.last.semitone + 1;
      while (used.contains(next) && next < 11) {
        next++;
      }
      _degrees.add(_DegreeDraft(
        semitone: next.clamp(0, 11),
        cents: 0,
        active: true,
      ));
    });
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Widget _actions(AppLocalizations l10n, bool narrow) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.file_download_outlined, size: 16),
              label: Text(l10n.xenEditorImport),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
            ),
            _ExportButton(
              label: l10n.xenEditorExport,
              onExport: _export,
              l10n: l10n,
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.xenEditorCancel),
            ),
            FilledButton(
              onPressed: _degrees.isEmpty ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: _kAmber),
              child: Text(
                l10n.xenEditorSave,
                style: const TextStyle(color: Colors.black),
              ),
            ),
          ],
        ),
      );

  /// Assembles the draft into a scale.
  ///
  /// Falls back to the linear layout when two degrees share a key — the
  /// warning above the list has already said so, and silently dropping one of
  /// them would be worse.
  GFScale _buildScale() {
    final name = _name.text.trim();
    final resolvedName = name.isEmpty
        ? AppLocalizations.of(context)!.xenEditorUnnamed
        : name;
    if (_id.isEmpty) _id = CustomScaleLibrary.generateId(resolvedName);

    final mapping = _hasDuplicateKeys ? GFScaleMapping.linear : _mapping;
    return GFScale(
      id: _id,
      name: resolvedName,
      family: GFScaleFamily.custom,
      provenance: 'Made in GrooveForge',
      mapping: mapping,
      periodCents: _periodCents <= 0 ? 1200.0 : _periodCents,
      degrees: [
        for (var i = 0; i < _degrees.length; i++)
          GFScaleDegree(
            mapping == GFScaleMapping.linear ? i : _degrees[i].semitone,
            _degrees[i].cents,
            _degrees[i].active,
          ),
      ],
    );
  }

  Future<void> _save() async {
    final scale = _buildScale();
    await widget.library.save(scale);
    if (!mounted) return;
    Navigator.of(context).pop(scale);
  }

  // ── Import / export ────────────────────────────────────────────────────────

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context)!;
    final path = await FilePickerService.pickFile(
      context: context,
      allowedExtensions: const ['scl', 'json'],
      dialogTitle: l10n.xenEditorImport,
    );
    if (path == null || !mounted) return;

    String contents;
    try {
      contents = await File(path).readAsString();
    } catch (e) {
      if (mounted) _toast(l10n.xenEditorImportFailed('$e'));
      return;
    }
    if (!mounted) return;

    final fileName = path.split(Platform.pathSeparator).last;
    // Route by extension: .scl is the interchange format, .json our own.
    final GFScale? imported;
    String? failure;
    if (fileName.toLowerCase().endsWith('.scl')) {
      final result = GFScalaFile.parse(
        contents,
        id: CustomScaleLibrary.generateId(fileName),
        fallbackName: fileName,
      );
      imported = result.scale;
      failure = result.error;
    } else {
      imported = CustomScaleLibrary.decodeExported(contents);
      failure = imported == null ? 'not a GrooveForge scale' : null;
    }

    if (imported == null) {
      _toast(l10n.xenEditorImportFailed(failure ?? '?'));
      return;
    }
    setState(() {
      _seedFrom(imported!);
      _name.text = imported.name;
      // A fresh id: importing makes a new scale rather than overwriting the
      // one currently open.
      _id = CustomScaleLibrary.generateId(imported.name);
    });
    _toast(l10n.xenEditorImported(imported.name));
  }

  Future<void> _export({required bool asScala}) async {
    final l10n = AppLocalizations.of(context)!;
    final scale = _buildScale();
    final contents = asScala
        ? GFScalaFile.export(scale)
        : CustomScaleLibrary.encodeForExport(scale);
    final extension = asScala ? 'scl' : 'json';

    final path = await FilePickerService.saveFile(
      context: context,
      dialogTitle: l10n.xenEditorExport,
      fileName: '${scale.id}.$extension',
      allowedExtensions: [extension],
    );
    if (path == null || !mounted) return;
    try {
      await File(path).writeAsString(contents);
      if (mounted) _toast(l10n.xenEditorExported(path));
    } catch (e) {
      if (mounted) _toast(l10n.xenEditorImportFailed('$e'));
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  // ── Shared decoration ──────────────────────────────────────────────────────

  InputDecoration _fieldDecoration(String label, {bool dense = false}) =>
      InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 11),
        isDense: dense,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: dense ? 8 : 12,
        ),
        filled: true,
        fillColor: _kFieldBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: _kAmber),
        ),
      );
}

// ─── Small controls ──────────────────────────────────────────────────────────

/// Chromatic key picker for a degree on the keyboard layout.
class _KeyPicker extends StatelessWidget {
  const _KeyPicker({
    required this.semitone,
    required this.enabled,
    required this.onChanged,
  });

  final int semitone;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      color: const Color(0xFF1C1C1C),
      tooltip: '',
      enabled: enabled,
      itemBuilder: (context) => [
        for (var pc = 0; pc < 12; pc++)
          PopupMenuItem(
            value: pc,
            height: 32,
            child: Text(
              xenRootName(pc),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
      ],
      onSelected: onChanged,
      child: Container(
        width: 46,
        padding: const EdgeInsets.symmetric(vertical: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF222222),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(
          xenRootName(semitone),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _LayoutChip extends StatelessWidget {
  const _LayoutChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _kAmber.withValues(alpha: 0.16) : _kFieldBg,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: selected ? _kAmber.withValues(alpha: 0.8) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _kAmber : Colors.white60,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// "Start from" — seeds the editor with an existing scale's degrees.
class _SeedPicker extends StatelessWidget {
  const _SeedPicker({
    required this.label,
    required this.onSeed,
    required this.l10n,
  });

  final String label;
  final ValueChanged<GFScale> onSeed;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<GFScale>(
      color: const Color(0xFF1C1C1C),
      tooltip: '',
      constraints: const BoxConstraints(maxHeight: 420, minWidth: 220),
      itemBuilder: (context) => [
        for (final scale in GFScaleLibrary.all)
          PopupMenuItem(
            value: scale,
            height: 34,
            child: Text(
              xenScaleLabel(l10n, scale),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
      ],
      onSelected: onSeed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: _kFieldBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.label,
    required this.onExport,
    required this.l10n,
  });

  final String label;
  final Future<void> Function({required bool asScala}) onExport;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<bool>(
      color: const Color(0xFF1C1C1C),
      tooltip: '',
      itemBuilder: (context) => [
        PopupMenuItem(
          value: false,
          height: 36,
          child: Text(
            l10n.xenEditorExportJson,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        PopupMenuItem(
          value: true,
          height: 36,
          child: Text(
            l10n.xenEditorExportScala,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
      onSelected: (asScala) => onExport(asScala: asScala),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.file_upload_outlined,
                size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
