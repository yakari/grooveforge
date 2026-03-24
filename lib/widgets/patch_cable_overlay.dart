import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/audio_graph_connection.dart';
import '../models/audio_port_id.dart';
import '../models/gfpa_plugin_instance.dart';
import '../services/audio_graph.dart';
import '../services/patch_drag_controller.dart';
import '../services/rack_state.dart';

// ── Public overlay widgets ────────────────────────────────────────────────────

/// Overlay that renders all current MIDI, Audio, and Data connections as
/// bezier curves with plug-tip endpoints.
///
/// Positioned in a [Stack] above the rack list. Uses [GlobalKey]s passed by
/// [RackScreen] to locate each jack's screen position for cable routing.
///
/// **Interaction model**: only tiny circular tap-zones placed at each cable's
/// visual midpoint are interactive (32 dp hit area). The rest of the overlay
/// is wrapped in [IgnorePointer], so scroll events and jack interactions pass
/// through freely.
class PatchCableOverlay extends StatefulWidget {
  final AudioGraph graph;
  final RackState rack;
  final Map<String, GlobalKey> jackKeys;

  /// When provided, the cable painter uses this as its [CustomPainter.repaint]
  /// listenable so that static cables are redrawn whenever the rack list scrolls
  /// (jack positions change on screen during auto-scroll or manual scroll while
  /// a drag is active).
  final ScrollController? scrollController;

  const PatchCableOverlay({
    super.key,
    required this.graph,
    required this.rack,
    required this.jackKeys,
    this.scrollController,
  });

  @override
  State<PatchCableOverlay> createState() => PatchCableOverlayState();
}

class PatchCableOverlayState extends State<PatchCableOverlay> {
  /// Key on the [CustomPaint] so painters can find this overlay's [RenderBox]
  /// and map jack global positions to local canvas coordinates.
  final GlobalKey _painterKey = GlobalKey();

  /// Cable midpoints in overlay-local coordinates, updated after each paint.
  /// Used to position the per-cable disconnect tap zones.
  Map<String, Offset> _cableMidpoints = {};

  RenderBox? _getOverlayBox() =>
      _painterKey.currentContext?.findRenderObject() as RenderBox?;

  @override
  Widget build(BuildContext context) {
    const hitSize = 48.0;
    return Stack(
      children: [
        // Cable drawing — fully transparent to pointer events so scroll and
        // jack long-presses are never blocked.
        IgnorePointer(
          child: CustomPaint(
            key: _painterKey,
            painter: _CablePainter(
              connections: widget.graph.connections,
              dataCables: _deriveDataCables(),
              jackKeys: widget.jackKeys,
              overlayBoxGetter: _getOverlayBox,
              onMidpointsComputed: _onMidpointsComputed,
              repaint: widget.scrollController,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        // One small tap-zone per cable placed at its visual midpoint.
        // Only these tiny areas are interactive — everything else is transparent.
        ..._cableMidpoints.entries.map((entry) => Positioned(
              left: entry.value.dx - hitSize / 2,
              top: entry.value.dy - hitSize / 2,
              width: hitSize,
              height: hitSize,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _showDisconnectMenu(
                  context,
                  details.globalPosition,
                  entry.key,
                ),
                child: const SizedBox(width: hitSize, height: hitSize),
              ),
            )),
      ],
    );
  }

  // ── Cable midpoints ─────────────────────────────────────────────────────────

  /// Called by [_CablePainter] after each paint via [addPostFrameCallback].
  ///
  /// Updates [_cableMidpoints] and rebuilds so [Positioned] tap zones move to
  /// the new midpoint positions. Guarded against rebuilds that would trigger
  /// an infinite paint/callback loop: [_CablePainter.shouldRepaint] only
  /// returns true when connections change, not when midpoints change.
  void _onMidpointsComputed(Map<String, Offset> midpoints) {
    if (!mounted) return;
    setState(() => _cableMidpoints = Map.from(midpoints));
  }

  // ── Data cable derivation ───────────────────────────────────────────────────

  /// Derives virtual data cables from the Jam Mode routing fields.
  ///
  /// These are NOT stored in [AudioGraph]; they mirror [GFpaPluginInstance]
  /// `masterSlotId` / `targetSlotIds` and stay in sync with the Jam Mode
  /// dropdowns.
  List<_VirtualCable> _deriveDataCables() {
    final cables = <_VirtualCable>[];
    for (final plugin in widget.rack.plugins) {
      if (plugin is! GFpaPluginInstance) continue;
      if (plugin.pluginId != 'com.grooveforge.jammode') continue;

      final masterId = plugin.masterSlotId;
      if (masterId != null) {
        cables.add(_VirtualCable(
          id: '$masterId:chordOut>${plugin.id}:chordIn',
          fromSlotId: masterId,
          fromPort: AudioPortId.chordOut,
          toSlotId: plugin.id,
          toPort: AudioPortId.chordIn,
        ));
      }
      for (final targetId in plugin.targetSlotIds) {
        cables.add(_VirtualCable(
          id: '${plugin.id}:scaleOut>$targetId:scaleIn',
          fromSlotId: plugin.id,
          fromPort: AudioPortId.scaleOut,
          toSlotId: targetId,
          toPort: AudioPortId.scaleIn,
        ));
      }
    }
    return cables;
  }

  // ── Disconnect UI ───────────────────────────────────────────────────────────

  void _showDisconnectMenu(
    BuildContext context,
    Offset globalPos,
    String connectionId,
  ) {
    final label =
        AppLocalizations.of(context)?.disconnectCable ?? 'Disconnect';
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1),
      items: [
        PopupMenuItem<String>(
          value: 'disconnect',
          child: Row(children: [
            const Icon(Icons.link_off, size: 18),
            const SizedBox(width: 8),
            Text(label),
          ]),
        ),
      ],
    ).then((value) {
      if (value == 'disconnect') _disconnectCable(connectionId);
    });
  }

  /// Routes a disconnect request to [AudioGraph] (MIDI/Audio) or [RackState]
  /// (Data / Jam Mode) based on the encoded connection ID.
  void _disconnectCable(String connectionId) {
    // MIDI or Audio cable.
    final audioConn = widget.graph.connections
        .where((c) => c.id == connectionId)
        .firstOrNull;
    if (audioConn != null) {
      widget.graph.disconnect(connectionId);
      return;
    }

    // Data cable — parse "$fromSlotId:${fromPort.name}>$toSlotId:${toPort.name}"
    final parts = connectionId.split('>');
    if (parts.length != 2) return;
    final fromParts = parts[0].split(':');
    final toParts = parts[1].split(':');
    if (fromParts.length < 2 || toParts.length < 2) return;

    final fromPortName = fromParts.last;
    final toSlotId = toParts.first;

    if (fromPortName == AudioPortId.chordOut.name) {
      widget.rack.setJamModeMaster(toSlotId, null);
    } else if (fromPortName == AudioPortId.scaleOut.name) {
      widget.rack.removeJamModeTarget(fromParts.first, toSlotId);
    }
  }
}

// ── Drag cable overlay ────────────────────────────────────────────────────────

/// Overlay that draws the in-progress cable while a drag gesture is active.
///
/// Kept in the widget tree for the entire duration of the patch view so that
/// its [_painterKey]'s [RenderBox] is available as soon as dragging begins —
/// avoiding a one-frame coordinate miss on the very first drag event.
///
/// [ListenableBuilder] inside the state drives repaints on every pointer-move
/// without needing an outer [Consumer].
class DragCableOverlay extends StatefulWidget {
  final PatchDragController controller;
  final Map<String, GlobalKey> jackKeys;

  const DragCableOverlay({
    super.key,
    required this.controller,
    required this.jackKeys,
  });

  @override
  State<DragCableOverlay> createState() => _DragCableOverlayState();
}

class _DragCableOverlayState extends State<DragCableOverlay> {
  final GlobalKey _painterKey = GlobalKey();

  RenderBox? _getOverlayBox() =>
      _painterKey.currentContext?.findRenderObject() as RenderBox?;

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder repaints on every PatchDragController.notifyListeners()
    // (position updates and start/end of drag) without rebuilding the full Stack.
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => IgnorePointer(
        child: CustomPaint(
          key: _painterKey,
          painter: _DragCablePainter(
            controller: widget.controller,
            jackKeys: widget.jackKeys,
            overlayBoxGetter: _getOverlayBox,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

// ── Internal data ─────────────────────────────────────────────────────────────

/// Transient representation of a Jam Mode data cable derived from
/// [RackState]'s `masterSlotId` / `targetSlotIds` fields.
class _VirtualCable {
  final String id;
  final String fromSlotId;
  final AudioPortId fromPort;
  final String toSlotId;
  final AudioPortId toPort;

  const _VirtualCable({
    required this.id,
    required this.fromSlotId,
    required this.fromPort,
    required this.toSlotId,
    required this.toPort,
  });

  Color get color => fromPort.color;
}

// ── Bezier geometry helpers ───────────────────────────────────────────────────

/// Computes cubic bezier control points with a natural downward sag.
///
/// Sag = `clamp(|dy| × 0.4 + 40, 40, 120)` dp, simulating cable gravity.
({Offset p1, Offset p2}) _controlPoints(Offset p0, Offset p3) {
  final dy = (p3.dy - p0.dy).abs();
  final sag = (dy * 0.4 + 40.0).clamp(40.0, 120.0);
  final midX = (p0.dx + p3.dx) / 2;
  return (
    p1: Offset(midX, p0.dy + sag),
    p2: Offset(midX, p3.dy + sag),
  );
}

/// Point at parameter [t] on a cubic bezier — used for midpoint hit-zones.
Offset _bezierPoint(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  final mt = 1 - t;
  return p0 * (mt * mt * mt) +
      p1 * (3 * mt * mt * t) +
      p2 * (3 * mt * t * t) +
      p3 * (t * t * t);
}

/// Returns the centre of [jackKey]'s widget in [overlayBox]-local coordinates.
///
/// Jack centres are first computed in global screen coords via
/// [RenderBox.localToGlobal], then mapped to the overlay's local canvas space
/// with [RenderBox.globalToLocal].  Returns null if the key is not yet
/// attached or [overlayBox] is not ready (first frame after entering patch view).
Offset? _jackCenter(GlobalKey jackKey, RenderBox? overlayBox) {
  final ctx = jackKey.currentContext;
  if (ctx == null) return null;
  final box = ctx.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  final globalCenter = box.localToGlobal(box.size.center(Offset.zero));
  if (overlayBox == null) return globalCenter;
  return overlayBox.globalToLocal(globalCenter);
}

// ── CustomPainters ────────────────────────────────────────────────────────────

/// Draws all MIDI/Audio and Data cables as bezier curves with plug endpoints.
class _CablePainter extends CustomPainter {
  final List<AudioGraphConnection> connections;
  final List<_VirtualCable> dataCables;
  final Map<String, GlobalKey> jackKeys;
  final RenderBox? Function() overlayBoxGetter;
  final void Function(Map<String, Offset>) onMidpointsComputed;

  _CablePainter({
    required this.connections,
    required this.dataCables,
    required this.jackKeys,
    required this.overlayBoxGetter,
    required this.onMidpointsComputed,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final overlayBox = overlayBoxGetter();
    final midpoints = <String, Offset>{};

    for (final conn in connections) {
      _drawCable(
        canvas: canvas,
        overlayBox: overlayBox,
        fromKey: jackKeys['${conn.fromSlotId}:${conn.fromPort.name}'],
        toKey: jackKeys['${conn.toSlotId}:${conn.toPort.name}'],
        color: conn.cableColorOverride ?? conn.fromPort.color,
        id: conn.id,
        midpoints: midpoints,
      );
    }
    for (final cable in dataCables) {
      _drawCable(
        canvas: canvas,
        overlayBox: overlayBox,
        fromKey: jackKeys['${cable.fromSlotId}:${cable.fromPort.name}'],
        toKey: jackKeys['${cable.toSlotId}:${cable.toPort.name}'],
        color: cable.color,
        id: cable.id,
        midpoints: midpoints,
      );
    }

    // Defer midpoint update to after the current frame so setState (called
    // in _onMidpointsComputed) doesn't fire mid-paint.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => onMidpointsComputed(midpoints));
  }

  void _drawCable({
    required Canvas canvas,
    required RenderBox? overlayBox,
    required GlobalKey? fromKey,
    required GlobalKey? toKey,
    required Color color,
    required String id,
    required Map<String, Offset> midpoints,
  }) {
    if (fromKey == null || toKey == null) return;
    final p0 = _jackCenter(fromKey, overlayBox);
    final p3 = _jackCenter(toKey, overlayBox);
    if (p0 == null || p3 == null) return;

    final (:p1, :p2) = _controlPoints(p0, p3);
    final path = Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);

    // Shadow pass for visual depth.
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..strokeWidth = 6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Cable body.
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Plug endpoints.
    _drawPlug(canvas, p0, color);
    _drawPlug(canvas, p3, color);

    // Disconnect badge — drawn last so it sits on top of the cable.
    final mid = _bezierPoint(p0, p1, p2, p3, 0.5);
    _drawDisconnectBadge(canvas, mid, color);
    midpoints[id] = mid;
  }

  @override
  bool shouldRepaint(_CablePainter old) =>
      old.connections != connections ||
      old.dataCables != dataCables ||
      old.jackKeys != jackKeys;
}

/// Draws the live drag cable from the source jack to the pointer position.
/// No-op when [PatchDragController.isDragging] is false.
class _DragCablePainter extends CustomPainter {
  final PatchDragController controller;
  final Map<String, GlobalKey> jackKeys;
  final RenderBox? Function() overlayBoxGetter;

  _DragCablePainter({
    required this.controller,
    required this.jackKeys,
    required this.overlayBoxGetter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.isDragging || controller.pointerPosition == null) return;

    final fromKey =
        jackKeys['${controller.fromSlotId}:${controller.fromPort!.name}'];
    if (fromKey == null) return;

    final overlayBox = overlayBoxGetter();
    final p0 = _jackCenter(fromKey, overlayBox);
    if (p0 == null) return;

    // Convert pointer position (global) to overlay-local canvas space.
    final p3 = overlayBox != null
        ? overlayBox.globalToLocal(controller.pointerPosition!)
        : controller.pointerPosition!;

    final (:p1, :p2) = _controlPoints(p0, p3);
    final path = Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);

    // Semi-transparent stroke shows the cable is not yet connected.
    canvas.drawPath(
      path,
      Paint()
        ..color = controller.fromPort!.color.withValues(alpha: 0.75)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Plug tip on the source jack only (free end trails the pointer).
    _drawPlug(canvas, p0, controller.fromPort!.color);
  }

  @override
  bool shouldRepaint(_DragCablePainter old) =>
      old.controller.pointerPosition != controller.pointerPosition ||
      old.controller.isDragging != controller.isDragging;
}

// ── Shared drawing helpers ────────────────────────────────────────────────────

/// Draws a small circular disconnect badge at [center].
///
/// The badge is a dark filled circle with a coloured ring and a white × symbol,
/// giving users a clear tap target to disconnect the cable. Rendered on top of
/// the cable body so it is always visible against any background colour.
void _drawDisconnectBadge(Canvas canvas, Offset center, Color cableColor) {
  const r = 9.0; // badge radius in logical pixels

  // Dark background so the badge is legible over any cable colour.
  canvas.drawCircle(
    center, r,
    Paint()
      ..color = const Color(0xDD1A1A2E)
      ..style = PaintingStyle.fill,
  );

  // Coloured ring that matches the cable family.
  canvas.drawCircle(
    center, r,
    Paint()
      ..color = cableColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );

  // White × drawn as two crossing lines.
  final xPaint = Paint()
    ..color = Colors.white
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round;
  const d = r * 0.45;
  canvas.drawLine(
    Offset(center.dx - d, center.dy - d),
    Offset(center.dx + d, center.dy + d),
    xPaint,
  );
  canvas.drawLine(
    Offset(center.dx + d, center.dy - d),
    Offset(center.dx - d, center.dy + d),
    xPaint,
  );
}

/// Draws a filled plug-tip circle at [center].
///
/// Outer disc: cable colour. Inner pin dot: dark, mimicking a TRS connector.
void _drawPlug(Canvas canvas, Offset center, Color color) {
  canvas.drawCircle(
    center,
    6.0,
    Paint()
      ..color = color
      ..style = PaintingStyle.fill,
  );
  canvas.drawCircle(
    center,
    2.5,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill,
  );
}
