import 'package:flutter/material.dart';

class VirtualPiano extends StatefulWidget {
  final Set<int> activeNotes;
  final void Function(int note)? onNotePressed;
  final void Function(int note)? onNoteReleased;
  final bool dragToPlay;

  const VirtualPiano({
    super.key,
    required this.activeNotes,
    this.onNotePressed,
    this.onNoteReleased,
    this.dragToPlay = false,
  });

  @override
  State<VirtualPiano> createState() => _VirtualPianoState();
}

class _VirtualPianoState extends State<VirtualPiano> {
  // Track continuous touches. Maps pointer ID -> MIDI Note currently depressed by that pointer
  final Map<int, int> _pointerToNote = {};

  String _getNoteName(int midiNote) {
    final noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
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

  int? _getNoteAtPosition(Offset localPosition, double containerHeight, double whiteKeyWidth, double blackKeyWidth, List<int> whiteKeys, List<int> blackKeys) {
    // 1. Check if we are interacting with the top half of the keyboard (where black keys are)
    if (localPosition.dy < containerHeight * 0.65) {
      // Check collision with black keys first since they are visually on top
      for (int blackNote in blackKeys) {
        int precedingWhiteNote = blackNote - 1;
        int whiteIndex = whiteKeys.indexOf(precedingWhiteNote);
        if (whiteIndex != -1) {
          double blackKeyStartX = (whiteIndex * whiteKeyWidth) + (whiteKeyWidth - (blackKeyWidth / 2));
          double blackKeyEndX = blackKeyStartX + blackKeyWidth;
          
          if (localPosition.dx >= blackKeyStartX && localPosition.dx <= blackKeyEndX) {
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

  void _handlePointerDown(PointerEvent event, double height, double wWidth, double bWidth, List<int> wKeys, List<int> bKeys) {
    int? note = _getNoteAtPosition(event.localPosition, height, wWidth, bWidth, wKeys, bKeys);
    if (note != null) {
      _pointerToNote[event.pointer] = note;
      widget.onNotePressed?.call(note);
    }
  }

  void _handlePointerMove(PointerEvent event, double height, double wWidth, double bWidth, List<int> wKeys, List<int> bKeys) {
    if (!widget.dragToPlay) return;

    int? newNote = _getNoteAtPosition(event.localPosition, height, wWidth, bWidth, wKeys, bKeys);
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
    // Default to displaying ~3 octaves starting from C3 (MIDI 48) if nothing is playing.
    int minNote = 48;
    int maxNote = 84; 
    
    // If notes are playing, attempt to pan the view if the note is outside our default bounds
    if (widget.activeNotes.isNotEmpty) {
      int lowestActive = widget.activeNotes.reduce((a, b) => a < b ? a : b);
      int highestActive = widget.activeNotes.reduce((a, b) => a > b ? a : b);
      
      // If we are playing way below the current view, shift down
      if (lowestActive < minNote) {
        minNote = lowestActive - 2;
        maxNote = minNote + 36; // Keep a 3-octave span
      }
      
      // If we are playing way above the current view, shift up
      if (highestActive > maxNote) {
        maxNote = highestActive + 2;
        minNote = maxNote - 36; 
      }
      
      // Failsafe bounds check
      if (minNote < 0) minNote = 0;
      if (maxNote > 127) maxNote = 127;
    }

    // Ensure we start on a C and end on a B for visual consistency
    minNote = (minNote - (minNote % 12)).clamp(0, 127);
    maxNote = (maxNote + (11 - (maxNote % 12))).clamp(0, 127);

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
        double whiteKeyWidth = constraints.maxWidth / whiteKeys.length;
        double blackKeyWidth = whiteKeyWidth * 0.6;
        double currentHeight = constraints.maxHeight == double.infinity ? 100 : constraints.maxHeight;
        
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _handlePointerDown(e, currentHeight, whiteKeyWidth, blackKeyWidth, whiteKeys, blackKeys),
          onPointerMove: (e) => _handlePointerMove(e, currentHeight, whiteKeyWidth, blackKeyWidth, whiteKeys, blackKeys),
          onPointerUp: (e) => _handlePointerUp(e),
          onPointerCancel: (e) => _handlePointerUp(e),
          child: SizedBox(
            height: currentHeight,
            child: Stack(
              children: [
                // Draw White Keys
                Row(
                  children: whiteKeys.map((note) {
                    bool isActive = widget.activeNotes.contains(note);
                    return Container(
                      width: whiteKeyWidth,
                      height: currentHeight,
                      decoration: BoxDecoration(
                        color: isActive ? Colors.blueAccent.withValues(alpha: 0.8) : Colors.white,
                        border: Border.all(color: Colors.black54, width: 0.5),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.only(bottom: 4),
                      child: isActive 
                          ? Text(_getNoteName(note), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))
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
                    left: (whiteIndex * whiteKeyWidth) + (whiteKeyWidth - (blackKeyWidth / 2)),
                    child: Container(
                      width: blackKeyWidth,
                      height: currentHeight * 0.65,
                      decoration: BoxDecoration(
                        color: isActive ? Colors.blueAccent : Colors.black87,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(3),
                          bottomRight: Radius.circular(3),
                        ),
                      ),
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.only(bottom: 4),
                      child: isActive 
                          ? Text(_getNoteName(note), style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))
                          : const SizedBox(),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      }
    );
  }
}
