import 'package:flutter/material.dart';

class VirtualPiano extends StatelessWidget {
  final Set<int> activeNotes;
  final void Function(int note)? onNotePressed;
  final void Function(int note)? onNoteReleased;

  const VirtualPiano({
    super.key,
    required this.activeNotes,
    this.onNotePressed,
    this.onNoteReleased,
  });

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

  @override
  Widget build(BuildContext context) {
    // Default to displaying ~3 octaves starting from C3 (MIDI 48) if nothing is playing.
    int minNote = 48;
    int maxNote = 84; 
    
    // If notes are playing, attempt to pan the view if the note is outside our default bounds
    if (activeNotes.isNotEmpty) {
      int lowestActive = activeNotes.reduce((a, b) => a < b ? a : b);
      int highestActive = activeNotes.reduce((a, b) => a > b ? a : b);
      
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
        
        return SizedBox(
          height: currentHeight,
          child: Stack(
            children: [
              // Draw White Keys
              Row(
                children: whiteKeys.map((note) {
                  bool isActive = activeNotes.contains(note);
                  Widget keyWidget = Container(
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
                  
                  if (onNotePressed != null && onNoteReleased != null) {
                    return Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) => onNotePressed!(note),
                      onPointerUp: (_) => onNoteReleased!(note),
                      onPointerCancel: (_) => onNoteReleased!(note),
                      child: keyWidget,
                    );
                  }
                  
                  return keyWidget;
                }).toList(),
              ),
              // Draw Black Keys (overlayed)
              ...blackKeys.map((note) {
                bool isActive = activeNotes.contains(note);
                // Find index of the preceding white key to position the black key
                int precedingWhiteNote = note - 1;
                int whiteIndex = whiteKeys.indexOf(precedingWhiteNote);
                
                Widget keyWidget = Container(
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
                );
                
                if (onNotePressed != null && onNoteReleased != null) {
                   keyWidget = Listener(
                     behavior: HitTestBehavior.opaque,
                     onPointerDown: (_) => onNotePressed!(note),
                     onPointerUp: (_) => onNoteReleased!(note),
                     onPointerCancel: (_) => onNoteReleased!(note),
                     child: keyWidget,
                   );
                }

                return Positioned(
                  left: (whiteIndex * whiteKeyWidth) + (whiteKeyWidth - (blackKeyWidth / 2)),
                  child: keyWidget,
                );
              }),
            ],
          ),
        );
      }
    );
  }
}
