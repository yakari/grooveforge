import 'package:flutter/material.dart';

class VirtualPiano extends StatefulWidget {
  final Set<int> activeNotes;
  final void Function(int note)? onNotePressed;
  final void Function(int note)? onNoteReleased;
  final bool dragToPlay;
  final int keysToShow;

  const VirtualPiano({
    super.key,
    required this.activeNotes,
    this.onNotePressed,
    this.onNoteReleased,
    this.dragToPlay = false,
    this.keysToShow = 88,
  });

  @override
  State<VirtualPiano> createState() => _VirtualPianoState();
}

class _VirtualPianoState extends State<VirtualPiano> {
  // Track if this is the first layout pass
  bool _isInitialScroll = true;

  // Track continuous touches. Maps pointer ID -> MIDI Note currently depressed by that pointer
  final Map<int, int> _pointerToNote = {};

  // Controller for horizontal scrolling
  final ScrollController _scrollController = ScrollController();

  // Render constants
  final int _minMidiNote = 21; // A0
  final int _maxMidiNote = 108; // C8

  @override
  void initState() {
    super.initState();
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
      int activeCopy = widget
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
      _pointerToNote[event.pointer] = note;
      widget.onNotePressed?.call(note);
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
    if (!widget.dragToPlay) return;

    int? newNote = _getNoteAtPosition(
      event.localPosition,
      height,
      wWidth,
      bWidth,
      wKeys,
      bKeys,
    );
    int? currentNote = _pointerToNote[event.pointer];

    if (newNote != currentNote) {
      if (currentNote != null) {
        widget.onNoteReleased?.call(currentNote);
      }
      if (newNote != null) {
        _pointerToNote[event.pointer] = newNote;
        widget.onNotePressed?.call(newNote);
      } else {
        _pointerToNote.remove(event.pointer);
      }
    }
  }

  void _handlePointerUp(PointerEvent event) {
    int? note = _pointerToNote.remove(event.pointer);
    if (note != null) {
      widget.onNoteReleased?.call(note);
    }
  }

  @override
  Widget build(BuildContext context) {
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
        int maxWhiteKeys = keysToShow > whiteKeys.length
            ? whiteKeys.length
            : keysToShow;

        double whiteKeyWidth = constraints.maxWidth / maxWhiteKeys;
        double blackKeyWidth = whiteKeyWidth * 0.6;
        double currentHeight = constraints.maxHeight == double.infinity
            ? 100
            : constraints.maxHeight;
        double scrollbarPadding = 16.0;
        double keyHeight = currentHeight > scrollbarPadding
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

        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true, // Always show the scrollbar for visibility
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(), // Prevent bouncy overscroll
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _handlePointerDown(
                e,
                keyHeight,
                whiteKeyWidth,
                blackKeyWidth,
                whiteKeys,
                blackKeys,
              ),
              onPointerMove: (e) => _handlePointerMove(
                e,
                keyHeight,
                whiteKeyWidth,
                blackKeyWidth,
                whiteKeys,
                blackKeys,
              ),
              onPointerUp: (e) => _handlePointerUp(e),
              onPointerCancel: (e) => _handlePointerUp(e),
              child: SizedBox(
                width: totalWidth,
                height: currentHeight,
                child: Stack(
                  children: [
                    // Draw White Keys
                    Row(
                      children: whiteKeys.map((note) {
                        bool isActive = widget.activeNotes.contains(note);
                        return Container(
                          width: whiteKeyWidth,
                          height: keyHeight,
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.blueAccent.withValues(alpha: 0.8)
                                : Colors.white,
                            border: Border.all(
                              color: Colors.black54,
                              width: 0.5,
                            ),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(4),
                              bottomRight: Radius.circular(4),
                            ),
                          ),
                          alignment: Alignment.bottomCenter,
                          padding: const EdgeInsets.only(bottom: 4),
                          child: isActive
                              ? Text(
                                  _getNoteName(note),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : const SizedBox(),
                        );
                      }).toList(),
                    ),
                    // Draw Black Keys (overlayed)
                    ...blackKeys.map((note) {
                      bool isActive = widget.activeNotes.contains(note);
                      // Find index of the preceding white key to position the black key
                      int precedingWhiteNote = note - 1;
                      int whiteIndex = whiteKeys.indexOf(precedingWhiteNote);

                      return Positioned(
                        left:
                            (whiteIndex * whiteKeyWidth) +
                            (whiteKeyWidth - (blackKeyWidth / 2)),
                        child: Container(
                          width: blackKeyWidth,
                          height: keyHeight * 0.65,
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.blueAccent.withValues(alpha: 0.8)
                                : Colors.black87,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(3),
                              bottomRight: Radius.circular(3),
                            ),
                          ),
                          alignment: Alignment.bottomCenter,
                          padding: const EdgeInsets.only(bottom: 4),
                          child: isActive
                              ? Text(
                                  _getNoteName(note),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : const SizedBox(),
                        ),
                      );
                    }), // Note the missing paren from mapping here
                  ],
                ),
              ),
            ),
          ), // Close SingleChildScrollView
        ); // Close Scrollbar
      },
    );
  }
}
