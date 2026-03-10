import 'package:flutter/material.dart';
import 'package:grooveforge/services/audio_engine.dart';

bool _isBlack(int note) {
  final n = note % 12;
  return n == 1 || n == 3 || n == 6 || n == 8 || n == 10;
}

String _noteName(int note) {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  return '${names[note % 12]}${(note ~/ 12) - 1}';
}

/// A fully interactive, responsive, multi-touch 88-key virtual piano.
///
/// Rendering uses a [CustomPainter] so active-note repaints are a single canvas
/// pass instead of rebuilding 100+ widgets, keeping glissando and UI smooth.
///
/// - Maps screen touches to MIDI notes accurately (black keys overlay white keys).
/// - Supports expressive gestures: Y-axis (Vibrato/Pitchbend) and X-axis (Glissando).
/// - Adapts to Jam Mode by snapping "wrong" keys to allowed [validPitchClasses].
/// - Auto-scrolls to ensure externally played notes remain visible.
class VirtualPiano extends StatefulWidget {
  final Set<int> activeNotes;
  final void Function(int note)? onNotePressed;
  final void Function(int note)? onNoteReleased;
  final GestureAction verticalAction;
  final GestureAction horizontalAction;
  final int keysToShow;
  final void Function(int value)? onPitchBend;
  final void Function(int cc, int value)? onControlChange;
  final void Function(bool interacting)? onInteractingChanged;
  final Set<int>? validPitchClasses;
  final int? rootPitchClass;
  final bool showJamModeBorders;
  final bool highlightWrongNotes;

  const VirtualPiano({
    super.key,
    required this.activeNotes,
    this.onNotePressed,
    this.onNoteReleased,
    this.verticalAction = GestureAction.vibrato,
    this.horizontalAction = GestureAction.glissando,
    this.keysToShow = 22,
    this.onPitchBend,
    this.onControlChange,
    this.onInteractingChanged,
    this.validPitchClasses,
    this.rootPitchClass,
    this.showJamModeBorders = true,
    this.highlightWrongNotes = true,
  });

  @override
  State<VirtualPiano> createState() => _VirtualPianoState();
}

class _VirtualPianoState extends State<VirtualPiano> {
  /// pointer id → physical note sent to audio engine
  final Map<int, int> _pointerNote = {};
  /// pointer id → visual note highlighted on screen (may differ from physical during glissando)
  final Map<int, int> _pointerVisual = {};
  /// pointer id → touch origin for expressive gesture delta calculation
  final Map<int, Offset> _pointerAnchor = {};

  final ScrollController _scrollCtrl = ScrollController();
  final ScrollController _scrollbarCtrl = ScrollController();

  // Cached layout values updated each build — used for auto-scroll outside build().
  double _wkw = 0;
  List<int> _wKeys = const [];
  List<int> _bKeys = const [];

  static const int _minNote = 21; // A0
  static const int _maxNote = 108; // C8

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      if (_scrollbarCtrl.hasClients && _scrollbarCtrl.offset != _scrollCtrl.offset) {
        _scrollbarCtrl.jumpTo(_scrollCtrl.offset);
      }
    });
    _scrollbarCtrl.addListener(() {
      if (_scrollCtrl.hasClients && _scrollCtrl.offset != _scrollbarCtrl.offset) {
        _scrollCtrl.jumpTo(_scrollbarCtrl.offset);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToNote(60, center: true),
    );
  }

  @override
  void didUpdateWidget(covariant VirtualPiano old) {
    super.didUpdateWidget(old);
    if (widget.activeNotes.isNotEmpty && old.activeNotes != widget.activeNotes) {
      _scrollToNote(widget.activeNotes.last);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _scrollbarCtrl.dispose();
    super.dispose();
  }

  void _scrollToNote(int note, {bool center = false}) {
    if (!_scrollCtrl.hasClients || _wkw == 0) return;
    final bkw = _wkw * 0.6;
    final noteX = _noteVisualX(note, _wKeys, _bKeys, _wkw, bkw);
    final vp = _scrollCtrl.position.viewportDimension;
    final cur = _scrollCtrl.offset;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (center) {
      _scrollCtrl.jumpTo((noteX - vp / 2 + _wkw / 2).clamp(0.0, max));
    } else if (noteX < cur) {
      _scrollCtrl.animateTo(
        (noteX - vp * 0.2).clamp(0.0, max),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else if (noteX > cur + vp - _wkw) {
      _scrollCtrl.animateTo(
        (noteX - vp * 0.8).clamp(0.0, max),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  double _noteVisualX(int note, List<int> wk, List<int> bk, double wkw, double bkw) =>
      _isBlack(note)
          ? (wk.indexOf(note - 1) * wkw) + (wkw - bkw / 2)
          : wk.indexOf(note) * wkw;

  /// Accurate hit-test: black keys are checked first (they sit on top visually)
  /// in the upper 65% of key height; below that only white keys are hit.
  int? _hitTest(Offset pos, double h, double wkw, double bkw, List<int> wk, List<int> bk) {
    if (pos.dy < h * 0.65) {
      for (final b in bk) {
        final wi = wk.indexOf(b - 1);
        if (wi == -1) continue;
        final bx = wi * wkw + (wkw - bkw / 2);
        if (pos.dx >= bx && pos.dx <= bx + bkw) return b;
      }
    }
    final wi = (pos.dx / wkw).floor();
    return (wi >= 0 && wi < wk.length) ? wk[wi] : null;
  }

  /// Jam Mode snapping: returns the nearest valid pitch class note to [note].
  int _validTarget(int note) {
    if (widget.validPitchClasses == null) return note;
    if (widget.validPitchClasses!.contains(note % 12)) return note;
    int best = 999, bestKey = note;
    for (int d = 1; d <= 12; d++) {
      for (final k in [note - d, note + d]) {
        if (widget.validPitchClasses!.contains(k % 12) && d < best) {
          best = d;
          bestKey = k;
        }
      }
      if (best < 999) break;
    }
    return bestKey;
  }

  void _onDown(PointerEvent e, double h, double wkw, double bkw, List<int> wk, List<int> bk) {
    final note = _hitTest(e.localPosition, h, wkw, bkw, wk, bk);
    if (note == null) return;
    final wasEmpty = _pointerNote.isEmpty;
    _pointerNote[e.pointer] = note;
    _pointerVisual[e.pointer] = note;
    _pointerAnchor[e.pointer] = e.localPosition;
    widget.onNotePressed?.call(note);
    if (wasEmpty) widget.onInteractingChanged?.call(true);
    setState(() {});
  }

  void _onMove(PointerEvent e, double h, double wkw, double bkw, List<int> wk, List<int> bk) {
    final note = _hitTest(e.localPosition, h, wkw, bkw, wk, bk);
    final curActive = _pointerNote[e.pointer];
    final curVisual = _pointerVisual[e.pointer];

    if (note != curVisual && widget.horizontalAction == GestureAction.glissando) {
      note != null ? _pointerVisual[e.pointer] = note : _pointerVisual.remove(e.pointer);
      final logNew = note != null ? _validTarget(note) : null;
      final logCur = curActive != null ? _validTarget(curActive) : null;
      if (logNew != logCur) {
        if (curActive != null) widget.onNoteReleased?.call(curActive);
        if (note != null) {
          _pointerNote[e.pointer] = note;
          _pointerAnchor[e.pointer] = e.localPosition;
          widget.onNotePressed?.call(note);
        } else {
          _pointerNote.remove(e.pointer);
          _pointerAnchor.remove(e.pointer);
        }
      }
      setState(() {});
      return;
    }

    // Expressive gestures (pitchbend / vibrato) when not glissando-ing
    if (curActive != null) {
      final a = _pointerAnchor[e.pointer];
      if (a != null) {
        _applyGesture(widget.verticalAction, e.localPosition.dy - a.dy, vert: true);
        _applyGesture(widget.horizontalAction, e.localPosition.dx - a.dx, vert: false);
      }
    }
  }

  void _applyGesture(GestureAction action, double delta, {required bool vert}) {
    if (action == GestureAction.none || action == GestureAction.glissando) return;
    if (action == GestureAction.pitchBend && widget.onPitchBend != null) {
      final pb = (delta / (vert ? -100.0 : 100.0)).clamp(-1.0, 1.0);
      widget.onPitchBend!(8192 + (pb * 8191).toInt());
    } else if (action == GestureAction.vibrato && widget.onControlChange != null) {
      widget.onControlChange!(1, ((delta.abs() / 40.0).clamp(0.0, 1.0) * 127).toInt());
    }
  }

  void _onUp(PointerEvent e) {
    final note = _pointerNote.remove(e.pointer);
    _pointerVisual.remove(e.pointer);
    _pointerAnchor.remove(e.pointer);
    if (_pointerNote.isEmpty) widget.onInteractingChanged?.call(false);
    if (note != null) {
      widget.onNoteReleased?.call(note);
      if (widget.verticalAction == GestureAction.pitchBend ||
          widget.horizontalAction == GestureAction.pitchBend) {
        widget.onPitchBend?.call(8192);
      }
      if (widget.verticalAction == GestureAction.vibrato ||
          widget.horizontalAction == GestureAction.vibrato) {
        widget.onControlChange?.call(1, 0);
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Resolve which notes to display (visual note may differ from active note during glissando)
    Set<int> display = widget.activeNotes.toSet();
    for (final p in _pointerNote.keys) {
      final active = _pointerNote[p]!;
      final visual = _pointerVisual[p];
      if (display.contains(active) && visual != null) {
        display.remove(active);
        display.add(visual);
      }
    }

    Set<int> snapped = {}, wrong = {};
    if (widget.validPitchClasses != null) {
      for (final n in display) {
        final t = _validTarget(n);
        snapped.add(t);
        if (t != n) wrong.add(n);
      }
    } else {
      snapped = display;
    }

    final wKeys = <int>[], bKeys = <int>[];
    for (int i = _minNote; i <= _maxNote; i++) {
      (_isBlack(i) ? bKeys : wKeys).add(i);
    }

    return LayoutBuilder(builder: (context, constraints) {
      final show = widget.keysToShow <= 0 ? 88 : widget.keysToShow;
      final maxWK = show > wKeys.length ? wKeys.length : show;
      final wkw = constraints.maxWidth / maxWK;
      final bkw = wkw * 0.6;
      final totalH = constraints.maxHeight == double.infinity ? 100.0 : constraints.maxHeight;
      const sbPad = 16.0;
      final kh = totalH > sbPad ? totalH - sbPad : totalH;
      final totalW = wkw * wKeys.length;

      // Cache layout for auto-scroll calls outside build()
      _wkw = wkw;
      _wKeys = wKeys;
      _bKeys = bKeys;

      return Column(children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            scrollDirection: Axis.horizontal,
            physics: widget.horizontalAction == GestureAction.glissando
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            child: SizedBox(
              width: totalW,
              height: totalH,
              child: GestureDetector(
                onVerticalDragUpdate: (_) {},
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => _onDown(e, kh, wkw, bkw, wKeys, bKeys),
                  onPointerMove: (e) => _onMove(e, kh, wkw, bkw, wKeys, bKeys),
                  onPointerUp: _onUp,
                  onPointerCancel: _onUp,
                  child: Stack(children: [
                    // Single CustomPaint replaces ~104 widget objects
                    RepaintBoundary(
                      child: CustomPaint(
                        size: Size(totalW, kh),
                        painter: _PianoKeysPainter(
                          whiteKeys: wKeys,
                          blackKeys: bKeys,
                          wkw: wkw,
                          bkw: bkw,
                          keyHeight: kh,
                          snappedNotes: snapped,
                          wrongNotes: wrong,
                          validPitchClasses: widget.validPitchClasses,
                          rootPitchClass: widget.rootPitchClass,
                        ),
                      ),
                    ),
                    if (widget.validPitchClasses != null && widget.showJamModeBorders)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: ZoneBorderPainter(
                              validPitchClasses: widget.validPitchClasses!,
                              whiteKeys: wKeys,
                              blackKeys: bKeys,
                              whiteKeyWidth: wkw,
                              blackKeyWidth: bkw,
                              height: kh,
                              targetResolver: _validTarget,
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
        Container(
          height: 32.0,
          color: Colors.black26,
          child: RawScrollbar(
            controller: _scrollbarCtrl,
            thumbVisibility: true,
            interactive: true,
            thickness: 24.0,
            thumbColor: Colors.blueAccent.withValues(alpha: 0.8),
            radius: const Radius.circular(4),
            child: SingleChildScrollView(
              controller: _scrollbarCtrl,
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: totalW, height: 1),
            ),
          ),
        ),
      ]);
    });
  }
}

/// Paints all piano keys (white then black on top) onto a canvas.
///
/// Using a painter instead of a widget tree eliminates ~104 widget
/// instantiations per repaint, making rapid note changes (glissando) smooth.
class _PianoKeysPainter extends CustomPainter {
  final List<int> whiteKeys;
  final List<int> blackKeys;
  final double wkw;
  final double bkw;
  final double keyHeight;
  final Set<int> snappedNotes;
  final Set<int> wrongNotes;
  final Set<int>? validPitchClasses;
  final int? rootPitchClass;

  const _PianoKeysPainter({
    required this.whiteKeys,
    required this.blackKeys,
    required this.wkw,
    required this.bkw,
    required this.keyHeight,
    required this.snappedNotes,
    required this.wrongNotes,
    this.validPitchClasses,
    this.rootPitchClass,
  });

  Color _wFill(int note) {
    final valid = validPitchClasses == null || validPitchClasses!.contains(note % 12);
    final base = valid ? Colors.white : Colors.grey.shade400;
    if (snappedNotes.contains(note)) return Color.alphaBlend(Colors.blueAccent.withValues(alpha: 0.8), base);
    if (wrongNotes.contains(note)) return Color.alphaBlend(Colors.redAccent.withValues(alpha: 0.8), base);
    return base;
  }

  Color _bFill(int note) {
    final valid = validPitchClasses == null || validPitchClasses!.contains(note % 12);
    final base = valid ? Colors.black : Colors.grey.shade600;
    if (snappedNotes.contains(note)) return Color.alphaBlend(Colors.blueAccent.withValues(alpha: 0.8), base);
    if (wrongNotes.contains(note)) return Color.alphaBlend(Colors.redAccent.withValues(alpha: 0.8), base);
    return base;
  }

  void _label(Canvas canvas, String text, Color color, double fontSize, double cx, double bottomY) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, bottomY - tp.height - 4));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..style = PaintingStyle.fill;
    final whiteBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black87;
    final blackBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black;

    // White keys (base layer)
    for (int i = 0; i < whiteKeys.length; i++) {
      final note = whiteKeys[i];
      final x = i * wkw;
      fill.color = _wFill(note);
      final rr = RRect.fromRectAndCorners(
        Rect.fromLTWH(x + 0.5, 0.5, wkw - 1, keyHeight - 1),
        bottomLeft: const Radius.circular(4),
        bottomRight: const Radius.circular(4),
      );
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, whiteBorder);
      final isActive = snappedNotes.contains(note);
      final isRoot = rootPitchClass != null && note % 12 == rootPitchClass;
      if (isActive || isRoot) {
        _label(canvas, _noteName(note),
            isActive ? Colors.white : Colors.blueAccent,
            isActive ? 10 : 9,
            x + wkw / 2, keyHeight);
      }
    }

    // Black keys (top layer)
    for (final note in blackKeys) {
      final wi = whiteKeys.indexOf(note - 1);
      if (wi == -1) continue;
      final x = wi * wkw + (wkw - bkw / 2);
      final bh = keyHeight * 0.65;
      fill.color = _bFill(note);
      final rr = RRect.fromRectAndCorners(
        Rect.fromLTWH(x + 0.5, 0.5, bkw - 1, bh - 1),
        bottomLeft: const Radius.circular(3),
        bottomRight: const Radius.circular(3),
      );
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, blackBorder);
      final isActive = snappedNotes.contains(note);
      final isRoot = rootPitchClass != null && note % 12 == rootPitchClass;
      if (isActive || isRoot) {
        _label(canvas, _noteName(note),
            isActive ? Colors.white : Colors.blueAccent,
            8,
            x + bkw / 2, bh);
      }
    }
  }

  @override
  bool shouldRepaint(_PianoKeysPainter old) =>
      old.snappedNotes != snappedNotes ||
      old.wrongNotes != wrongNotes ||
      old.wkw != wkw ||
      old.keyHeight != keyHeight ||
      old.validPitchClasses != validPitchClasses ||
      old.rootPitchClass != rootPitchClass;
}

typedef TargetResolver = int Function(int note);

/// Outlines groups of physical keys that map to the same logical note in Jam Mode.
class ZoneBorderPainter extends CustomPainter {
  final Set<int> validPitchClasses;
  final List<int> whiteKeys;
  final List<int> blackKeys;
  final double whiteKeyWidth;
  final double blackKeyWidth;
  final double height;
  final TargetResolver targetResolver;

  ZoneBorderPainter({
    required this.validPitchClasses,
    required this.whiteKeys,
    required this.blackKeys,
    required this.whiteKeyWidth,
    required this.blackKeyWidth,
    required this.height,
    required this.targetResolver,
  });

  Path _blackKeyRect(int n) {
    final wi = whiteKeys.indexOf(n - 1);
    if (wi == -1) return Path();
    final x = wi * whiteKeyWidth + (whiteKeyWidth - blackKeyWidth / 2);
    return Path()..addRect(Rect.fromLTWH(x, 0, blackKeyWidth, height * 0.65));
  }

  Path _whiteKeyVisiblePath(int n) {
    final wi = whiteKeys.indexOf(n);
    if (wi == -1) return Path();
    Path p = Path()..addRect(Rect.fromLTWH(wi * whiteKeyWidth, 0, whiteKeyWidth, height));
    if (blackKeys.contains(n - 1)) {
      p = Path.combine(PathOperation.difference, p, _blackKeyRect(n - 1));
    }
    if (blackKeys.contains(n + 1)) {
      p = Path.combine(PathOperation.difference, p, _blackKeyRect(n + 1));
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (validPitchClasses.isEmpty) return;

    final Map<int, List<int>> groups = {};
    for (final w in whiteKeys) {
      groups.putIfAbsent(targetResolver(w), () => []).add(w);
    }
    for (final b in blackKeys) {
      groups.putIfAbsent(targetResolver(b), () => []).add(b);
    }

    final stroke = Paint()
      ..color = Colors.indigoAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round;
    final glow = Paint()
      ..color = Colors.indigoAccent.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.0);

    for (final entry in groups.entries) {
      Path zone = Path();
      bool first = true;
      for (final note in entry.value) {
        final part = blackKeys.contains(note) ? _blackKeyRect(note) : _whiteKeyVisiblePath(note);
        zone = first ? part : Path.combine(PathOperation.union, zone, part);
        first = false;
      }
      canvas.drawPath(zone, glow);
      canvas.drawPath(zone, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant ZoneBorderPainter old) =>
      old.validPitchClasses != validPitchClasses ||
      old.whiteKeyWidth != whiteKeyWidth ||
      old.blackKeyWidth != blackKeyWidth ||
      old.height != height;
}
