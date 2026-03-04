import 'package:flutter/material.dart';
import 'package:grooveforge/services/audio_engine.dart';

/// A fully interactive, responsive, multi-touch 88-key virtual piano.
///
/// **Features:**
/// - Maps screen touches to MIDI notes accurately (black keys overlay white keys).
/// - Supports advanced expressive gestures: Y-axis (Vibrato/Pitchbend) and X-axis (Glissando).
/// - Adapts to Jam Mode by visually snapping "wrong" keys to allowed [validPitchClasses].
/// - Auto-scrolls to ensure externally played notes remain visible on screen.
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
  // Track if this is the first layout pass
  bool _isInitialScroll = true;

  /// Maps hardware pointer ID -> the PHYSICAL key actually sent to AudioEngine.
  final Map<int, int> _pointerToActiveNote = {};

  /// Maps hardware pointer ID -> the PHYSICAL visual key currently highlighted by finger position under glissando.
  final Map<int, int> _pointerToVisualNote = {};

  /// Stores the exact (X,Y) screen coordinate where a finger first touched a key.
  /// Used as the origin point to calculate delta distances for expressive gestures (vibrato/pitchbend).
  final Map<int, Offset> _pointerToAnchor = {};

  // Controller for horizontal scrolling (master)
  final ScrollController _scrollController = ScrollController();
  // Dedicated controller for the scrollbar (slave)
  final ScrollController _scrollbarController = ScrollController();

  // Render constants
  final int _minMidiNote = 21; // A0
  final int _maxMidiNote = 108; // C8

  @override
  void initState() {
    super.initState();

    // Sync controllers
    _scrollController.addListener(() {
      if (_scrollbarController.hasClients &&
          _scrollbarController.offset != _scrollController.offset) {
        _scrollbarController.jumpTo(_scrollController.offset);
      }
    });
    _scrollbarController.addListener(() {
      if (_scrollController.hasClients &&
          _scrollController.offset != _scrollbarController.offset) {
        _scrollController.jumpTo(_scrollbarController.offset);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerOnNote(60); // Middle C
    });
  }

  @override
  void didUpdateWidget(covariant VirtualPiano oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeNotes.isNotEmpty &&
        oldWidget.activeNotes != widget.activeNotes) {
      // Find a newly played note if possible to center on
      int activeCopy =
          widget
              .activeNotes
              .last; // Set is unordered but typically holds the current playing
      _scrollToNoteIfNotVisible(activeCopy);
    }
  }

  void _centerOnNote(int note) {
    if (!_scrollController.hasClients) return;
    _scrollToNoteIfNotVisible(note, center: true);
  }

  double _getNoteVisualX(
    int note,
    List<int> whiteKeys,
    List<int> blackKeys,
    double whiteKeyWidth,
    double blackKeyWidth,
  ) {
    if (_isBlackKey(note)) {
      int precedingWhiteNote = note - 1;
      int whiteIndex = whiteKeys.indexOf(precedingWhiteNote);
      return (whiteIndex * whiteKeyWidth) +
          (whiteKeyWidth - (blackKeyWidth / 2));
    } else {
      int whiteIndex = whiteKeys.indexOf(note);
      return whiteIndex * whiteKeyWidth;
    }
  }

  void _scrollToNoteIfNotVisible(int note, {bool center = false}) {
    if (!_scrollController.hasClients) return;

    // We can't perfectly compute the X coordinate outside of build() easily
    // unless we know the total width. We rely on the layout parameters in build,
    // so this is a no-op until `build` calculates things.
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scrollbarController.dispose();
    super.dispose();
  }

  String _getNoteName(int midiNote) {
    final noteNames = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    int octave = (midiNote ~/ 12) - 1;
    String name = noteNames[midiNote % 12];
    return '$name$octave';
  }

  bool _isBlackKey(int midiNote) {
    int noteInOctave = midiNote % 12;
    return noteInOctave == 1 ||
        noteInOctave == 3 ||
        noteInOctave == 6 ||
        noteInOctave == 8 ||
        noteInOctave == 10;
  }

  /// Accurate hit-testing to determine which piano key exists at a given screen coordinate.
  ///
  /// The algorithm prioritizes Black Keys, which occupy the top 65% of the keyboard's height
  /// and sit horizontally between specific White Keys. If a touch falls in the bottom 35%,
  /// or misses a Black Key in the top section, it maps to the underlying White Key.
  int? _getNoteAtPosition(
    Offset localPosition,
    double containerHeight,
    double whiteKeyWidth,
    double blackKeyWidth,
    List<int> whiteKeys,
    List<int> blackKeys,
  ) {
    // 1. Check if we are interacting with the top half of the keyboard (where black keys are)
    if (localPosition.dy < containerHeight * 0.65) {
      // Check collision with black keys first since they are visually on top
      for (int blackNote in blackKeys) {
        int precedingWhiteNote = blackNote - 1;
        int whiteIndex = whiteKeys.indexOf(precedingWhiteNote);
        if (whiteIndex != -1) {
          double blackKeyStartX =
              (whiteIndex * whiteKeyWidth) +
              (whiteKeyWidth - (blackKeyWidth / 2));
          double blackKeyEndX = blackKeyStartX + blackKeyWidth;

          if (localPosition.dx >= blackKeyStartX &&
              localPosition.dx <= blackKeyEndX) {
            return blackNote;
          }
        }
      }
    }

    // 2. Fall back to white keys (the base layer)
    int whiteIndex = (localPosition.dx / whiteKeyWidth).floor();
    if (whiteIndex >= 0 && whiteIndex < whiteKeys.length) {
      return whiteKeys[whiteIndex];
    }

    return null;
  }

  /// Visual Snapping Algorithm (Jam Mode):
  /// If [validPitchClasses] are enforced, this calculates the new logical note
  /// that a prohibited physical key will trigger, searching bidirectionally to the nearest valid semitone.
  int _getValidTarget(int note) {
    if (widget.validPitchClasses == null) return note;
    if (widget.validPitchClasses!.contains(note % 12)) return note;
    int bestDistance = 999;
    int bestKey = note;
    for (int offset = 1; offset <= 12; offset++) {
      // Check downKey first to prefer snapping down (e.g., C# snaps to C)
      int downKey = note - offset;
      if (widget.validPitchClasses!.contains(downKey % 12)) {
        if (offset < bestDistance) {
          bestDistance = offset;
          bestKey = downKey;
        }
      }
      int upKey = note + offset;
      if (widget.validPitchClasses!.contains(upKey % 12)) {
        if (offset < bestDistance) {
          bestDistance = offset;
          bestKey = upKey;
        }
      }
      if (bestDistance < 999) break;
    }
    return bestKey;
  }

  void _handlePointerDown(
    PointerEvent event,
    double height,
    double wWidth,
    double bWidth,
    List<int> wKeys,
    List<int> bKeys,
  ) {
    int? note = _getNoteAtPosition(
      event.localPosition,
      height,
      wWidth,
      bWidth,
      wKeys,
      bKeys,
    );

    if (note != null) {
      bool wasEmpty = _pointerToActiveNote.isEmpty;
      _pointerToActiveNote[event.pointer] = note;
      _pointerToVisualNote[event.pointer] = note;
      _pointerToAnchor[event.pointer] = event.localPosition;
      widget.onNotePressed?.call(note);
      if (wasEmpty) {
        widget.onInteractingChanged?.call(true);
      }
      setState(() {});
    }
  }

  void _handlePointerMove(
    PointerEvent event,
    double height,
    double wWidth,
    double bWidth,
    List<int> wKeys,
    List<int> bKeys,
  ) {
    int? note = _getNoteAtPosition(
      event.localPosition,
      height,
      wWidth,
      bWidth,
      wKeys,
      bKeys,
    );

    int? currentActiveNote = _pointerToActiveNote[event.pointer];
    int? currentVisualNote = _pointerToVisualNote[event.pointer];

    if (note != currentVisualNote) {
      if (widget.horizontalAction == GestureAction.glissando) {
        if (note != null) {
          _pointerToVisualNote[event.pointer] = note;
        } else {
          _pointerToVisualNote.remove(event.pointer);
        }

        int? logicalNote = note != null ? _getValidTarget(note) : null;
        int? logicalCurrent =
            currentActiveNote != null
                ? _getValidTarget(currentActiveNote)
                : null;

        if (logicalNote != logicalCurrent) {
          if (currentActiveNote != null) {
            widget.onNoteReleased?.call(currentActiveNote);
          }
          if (note != null) {
            _pointerToActiveNote[event.pointer] = note;
            _pointerToAnchor[event.pointer] =
                event.localPosition; // Anchor resets on note change
            widget.onNotePressed?.call(note);
          } else {
            _pointerToActiveNote.remove(event.pointer);
            _pointerToAnchor.remove(event.pointer);
          }
        }
        setState(() {});
      }
    }

    // Always apply expressive gestures if the finger is moving over the same logical zone
    // or if glissando is OFF (meaning visual note does not change as you drag across keys).
    if (widget.horizontalAction != GestureAction.glissando ||
        note == currentVisualNote) {
      if (currentActiveNote != null) {
        final anchor = _pointerToAnchor[event.pointer];
        if (anchor != null) {
          double dx = event.localPosition.dx - anchor.dx;
          double dy = event.localPosition.dy - anchor.dy;
          _applyGesture(widget.verticalAction, dy, isVertical: true);
          _applyGesture(widget.horizontalAction, dx, isVertical: false);
        }
      }
    }
  }

  void _applyGesture(
    GestureAction action,
    double delta, {
    required bool isVertical,
  }) {
    if (action == GestureAction.none || action == GestureAction.glissando) {
      return;
    }

    if (action == GestureAction.pitchBend && widget.onPitchBend != null) {
      // Map deltas to PB. Vertical: -100px (up) -> max, +100px -> min.
      // Horizontal: +100px (right) -> max, -100px -> min.
      double factor = isVertical ? -100.0 : 100.0;
      double pbNormalized = (delta / factor).clamp(-1.0, 1.0);
      int pbValue = 8192 + (pbNormalized * 8191).toInt();
      widget.onPitchBend!(pbValue);
    } else if (action == GestureAction.vibrato &&
        widget.onControlChange != null) {
      // Sensitivity: 40px for full depth
      double modNormalized = (delta.abs() / 40.0).clamp(0.0, 1.0);
      int modValue = (modNormalized * 127).toInt();
      widget.onControlChange!(1, modValue);
    }
  }

  void _handlePointerUp(PointerEvent event) {
    int? activeNote = _pointerToActiveNote.remove(event.pointer);
    _pointerToVisualNote.remove(event.pointer);
    _pointerToAnchor.remove(event.pointer);

    if (_pointerToActiveNote.isEmpty) {
      widget.onInteractingChanged?.call(false);
    }

    if (activeNote != null) {
      widget.onNoteReleased?.call(activeNote);
      // Reset gestures when lift finger
      if (widget.verticalAction == GestureAction.pitchBend ||
          widget.horizontalAction == GestureAction.pitchBend) {
        widget.onPitchBend?.call(8192);
      }
      if (widget.verticalAction == GestureAction.vibrato ||
          widget.horizontalAction == GestureAction.vibrato) {
        widget.onControlChange?.call(1, 0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Set<int> displayActiveNotes = widget.activeNotes.toSet();
    for (int p in _pointerToActiveNote.keys) {
      int active = _pointerToActiveNote[p]!;
      int? visual = _pointerToVisualNote[p];
      if (displayActiveNotes.contains(active) && visual != null) {
        displayActiveNotes.remove(active);
        displayActiveNotes.add(visual);
      }
    }

    Set<int> snappedNotes = {};
    Set<int> wrongNotes = {};
    if (widget.validPitchClasses != null) {
      for (var note in displayActiveNotes) {
        int target = _getValidTarget(note);
        snappedNotes.add(target);
        if (target != note) {
          wrongNotes.add(note);
        }
      }
    } else {
      snappedNotes = displayActiveNotes.toSet();
    }

    // We always render the full 88 keys range
    int minNote = _minMidiNote;
    int maxNote = _maxMidiNote;

    List<int> whiteKeys = [];
    List<int> blackKeys = [];

    for (int i = minNote; i <= maxNote; i++) {
      if (_isBlackKey(i)) {
        blackKeys.add(i);
      } else {
        whiteKeys.add(i);
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Provide a default if showing 88 keys on a tiny screen
        int keysToShow = widget.keysToShow <= 0 ? 88 : widget.keysToShow;
        int maxWhiteKeys =
            keysToShow > whiteKeys.length ? whiteKeys.length : keysToShow;

        double whiteKeyWidth = constraints.maxWidth / maxWhiteKeys;
        double blackKeyWidth = whiteKeyWidth * 0.6;
        double currentHeight =
            constraints.maxHeight == double.infinity
                ? 100
                : constraints.maxHeight;
        double scrollbarPadding = 16.0;
        double keyHeight =
            currentHeight > scrollbarPadding
                ? currentHeight - scrollbarPadding
                : currentHeight;

        // Calculate total required width
        double totalWidth = whiteKeyWidth * whiteKeys.length;

        // Auto-panning & Initial scroll logic
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) return;

          int noteToScrollTo = -1;
          bool shouldCenter = false;

          if (_isInitialScroll) {
            noteToScrollTo = 60; // Middle C
            shouldCenter = true;
            _isInitialScroll = false;
          } else if (widget.activeNotes.isNotEmpty) {
            noteToScrollTo = widget.activeNotes.last;
            shouldCenter = false;
          }

          if (noteToScrollTo >= whiteKeys.first &&
              noteToScrollTo <= whiteKeys.last) {
            double noteVisualX = _getNoteVisualX(
              noteToScrollTo,
              whiteKeys,
              blackKeys,
              whiteKeyWidth,
              blackKeyWidth,
            );

            double viewportWidth = _scrollController.position.viewportDimension;
            double currentScrollOffset = _scrollController.offset;

            if (shouldCenter) {
              double targetOffset =
                  noteVisualX - (viewportWidth / 2) + (whiteKeyWidth / 2);
              targetOffset = targetOffset.clamp(
                0.0,
                _scrollController.position.maxScrollExtent,
              );
              _scrollController.jumpTo(targetOffset);
            } else {
              if (noteVisualX < currentScrollOffset) {
                // Note is to the left of viewport
                double targetOffset = noteVisualX - (viewportWidth * 0.2);
                targetOffset = targetOffset.clamp(
                  0.0,
                  _scrollController.position.maxScrollExtent,
                );
                _scrollController.animateTo(
                  targetOffset,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              } else if (noteVisualX >
                  (currentScrollOffset + viewportWidth - whiteKeyWidth)) {
                // Note is to the right of viewport
                double targetOffset = noteVisualX - (viewportWidth * 0.8);
                targetOffset = targetOffset.clamp(
                  0.0,
                  _scrollController.position.maxScrollExtent,
                );
                _scrollController.animateTo(
                  targetOffset,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            }
          }
        });

        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics:
                    (widget.horizontalAction == GestureAction.glissando)
                        ? const NeverScrollableScrollPhysics()
                        : const ClampingScrollPhysics(),
                child: SizedBox(
                  width: totalWidth,
                  height: currentHeight,
                  child: GestureDetector(
                    onVerticalDragUpdate: (_) {}, // Absorb vertical drags
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown:
                          (e) => _handlePointerDown(
                            e,
                            keyHeight,
                            whiteKeyWidth,
                            blackKeyWidth,
                            whiteKeys,
                            blackKeys,
                          ),
                      onPointerMove:
                          (e) => _handlePointerMove(
                            e,
                            keyHeight,
                            whiteKeyWidth,
                            blackKeyWidth,
                            whiteKeys,
                            blackKeys,
                          ),
                      onPointerUp: (e) => _handlePointerUp(e),
                      onPointerCancel: (e) => _handlePointerUp(e),
                      child: Stack(
                        children: [
                          // Draw White Keys
                          Row(
                            children:
                                whiteKeys.map((note) {
                                  bool isActive = false;
                                  bool isWrong = false;
                                  if (widget.validPitchClasses != null) {
                                    isActive = snappedNotes.contains(note);
                                    isWrong =
                                        widget.highlightWrongNotes &&
                                        wrongNotes.contains(note);
                                  } else {
                                    isActive = displayActiveNotes.contains(
                                      note,
                                    );
                                  }

                                  Color keyColor =
                                      (widget.validPitchClasses == null ||
                                              widget.validPitchClasses!
                                                  .contains(note % 12))
                                          ? Colors.white
                                          : Colors.grey[400]!;

                                  Color fillColor;
                                  if (isActive) {
                                    fillColor = Color.alphaBlend(
                                      Colors.blueAccent.withValues(alpha: 0.8),
                                      keyColor,
                                    );
                                  } else if (isWrong) {
                                    fillColor = Color.alphaBlend(
                                      Colors.redAccent.withValues(alpha: 0.8),
                                      keyColor,
                                    );
                                  } else {
                                    fillColor = keyColor;
                                  }

                                  return Container(
                                    width: whiteKeyWidth,
                                    height: keyHeight,
                                    decoration: BoxDecoration(
                                      color: fillColor,
                                      border: Border.all(
                                        color: Colors.black87,
                                        width: 1,
                                      ),
                                      borderRadius: const BorderRadius.only(
                                        bottomLeft: Radius.circular(4),
                                        bottomRight: Radius.circular(4),
                                      ),
                                    ),
                                    alignment: Alignment.bottomCenter,
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child:
                                        isActive ||
                                                (widget.rootPitchClass !=
                                                        null &&
                                                    note % 12 ==
                                                        widget.rootPitchClass)
                                            ? Text(
                                              _getNoteName(note),
                                              style: TextStyle(
                                                color:
                                                    isActive
                                                        ? Colors.white
                                                        : Colors.blueAccent,
                                                fontSize: isActive ? 10 : 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            )
                                            : const SizedBox(),
                                  );
                                }).toList(),
                          ),
                          // Draw Black Keys (overlayed)
                          ...blackKeys.map((note) {
                            bool isActive = false;
                            bool isWrong = false;
                            if (widget.validPitchClasses != null) {
                              isActive = snappedNotes.contains(note);
                              isWrong =
                                  widget.highlightWrongNotes &&
                                  wrongNotes.contains(note);
                            } else {
                              isActive = displayActiveNotes.contains(note);
                            }
                            int precedingWhiteNote = note - 1;
                            int whiteIndex = whiteKeys.indexOf(
                              precedingWhiteNote,
                            );

                            Color keyColor =
                                (widget.validPitchClasses == null ||
                                        widget.validPitchClasses!.contains(
                                          note % 12,
                                        ))
                                    ? Colors.black87
                                    : Colors.grey.shade600;

                            Color fillColor;
                            if (isActive) {
                              fillColor = Color.alphaBlend(
                                Colors.blueAccent.withValues(alpha: 0.8),
                                keyColor,
                              );
                            } else if (isWrong) {
                              fillColor = Color.alphaBlend(
                                Colors.redAccent.withValues(alpha: 0.8),
                                keyColor,
                              );
                            } else {
                              fillColor = keyColor;
                            }

                            return Positioned(
                              left:
                                  (whiteIndex * whiteKeyWidth) +
                                  (whiteKeyWidth - (blackKeyWidth / 2)),
                              child: Container(
                                width: blackKeyWidth,
                                height: keyHeight * 0.65,
                                decoration: BoxDecoration(
                                  color: fillColor,
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(3),
                                    bottomRight: Radius.circular(3),
                                  ),
                                ),
                                alignment: Alignment.bottomCenter,
                                padding: const EdgeInsets.only(bottom: 4),
                                child:
                                    isActive ||
                                            (widget.rootPitchClass != null &&
                                                note % 12 ==
                                                    widget.rootPitchClass)
                                        ? Text(
                                          _getNoteName(note),
                                          style: TextStyle(
                                            color:
                                                isActive
                                                    ? Colors.white
                                                    : Colors.blueAccent,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                        : const SizedBox(),
                              ),
                            );
                          }),
                          // Zone Borders Overlay
                          if (widget.validPitchClasses != null &&
                              widget.showJamModeBorders)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: ZoneBorderPainter(
                                    validPitchClasses:
                                        widget.validPitchClasses!,
                                    whiteKeys: whiteKeys,
                                    blackKeys: blackKeys,
                                    whiteKeyWidth: whiteKeyWidth,
                                    blackKeyWidth: blackKeyWidth,
                                    height: keyHeight,
                                    targetResolver: _getValidTarget,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Dedicated Scrollbar area at the bottom
            Container(
              height: 32.0, // Large touch area
              color: Colors.black26, // Distinct background for the track
              child: RawScrollbar(
                controller: _scrollbarController,
                thumbVisibility: true,
                interactive: true,
                thickness: 24.0, // Very visible and draggable
                thumbColor: Colors.blueAccent.withValues(alpha: 0.8),
                radius: const Radius.circular(4),
                child: SingleChildScrollView(
                  controller: _scrollbarController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: totalWidth,
                    height: 1, // Minimal height scrollable area
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

typedef TargetResolver = int Function(int note);

/// A custom canvas painter that outlines groups of physical keys that map to the same logical note.
///
/// In Jam Mode, playing a "wrong" note snaps to a "correct" note. This creates "zones" on the keyboard
/// (e.g., C, C#, and D might all snap to C). This painter dynamically calculates the complex, non-rectangular
/// polygon enveloping these adjacent physically-pressed keys and draws a glowing border to visualize the snap zone.
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

  Path _getBlackKeyRect(int n) {
    int precedingWhite = n - 1;
    int wIdx = whiteKeys.indexOf(precedingWhite);
    if (wIdx == -1) return Path();
    double startX =
        (wIdx * whiteKeyWidth) + (whiteKeyWidth - (blackKeyWidth / 2));
    return Path()
      ..addRect(Rect.fromLTWH(startX, 0, blackKeyWidth, height * 0.65));
  }

  Path _getWhiteKeyVisiblePath(int n) {
    int wIdx = whiteKeys.indexOf(n);
    if (wIdx == -1) return Path();
    Path p =
        Path()..addRect(
          Rect.fromLTWH(wIdx * whiteKeyWidth, 0, whiteKeyWidth, height),
        );

    // Subtract left black key portion
    if (blackKeys.contains(n - 1)) {
      p = Path.combine(PathOperation.difference, p, _getBlackKeyRect(n - 1));
    }
    // Subtract right black key portion
    if (blackKeys.contains(n + 1)) {
      p = Path.combine(PathOperation.difference, p, _getBlackKeyRect(n + 1));
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (validPitchClasses.isEmpty) return;

    Map<int, List<int>> targetGroups = {};
    for (int w in whiteKeys) {
      targetGroups.putIfAbsent(targetResolver(w), () => []).add(w);
    }
    for (int b in blackKeys) {
      targetGroups.putIfAbsent(targetResolver(b), () => []).add(b);
    }

    final strokePaint =
        Paint()
          ..color = Colors.indigoAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeJoin = StrokeJoin.round;

    final glowPaint =
        Paint()
          ..color = Colors.indigoAccent.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.0
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.0);

    for (final entry in targetGroups.entries) {
      Path zonePath = Path();
      bool first = true;
      for (int note in entry.value) {
        Path visiblePart =
            blackKeys.contains(note)
                ? _getBlackKeyRect(note)
                : _getWhiteKeyVisiblePath(note);
        if (first) {
          zonePath = visiblePart;
          first = false;
        } else {
          // Precise union of mutually exclusive bounds forms a contiguous outline without internal lines
          zonePath = Path.combine(PathOperation.union, zonePath, visiblePart);
        }
      }

      canvas.drawPath(zonePath, glowPaint);
      canvas.drawPath(zonePath, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant ZoneBorderPainter oldDelegate) {
    return oldDelegate.validPitchClasses != validPitchClasses ||
        oldDelegate.whiteKeyWidth != whiteKeyWidth ||
        oldDelegate.blackKeyWidth != blackKeyWidth ||
        oldDelegate.height != height;
  }
}
