import 'package:flutter/material.dart';
import '../models/audio_port_id.dart';

/// Holds the transient state of a cable drag gesture in the patch view.
///
/// When the user long-presses an output jack, a drag starts: the source slot
/// and port are recorded here, and [pointerPosition] is updated as the finger
/// or cursor moves. The [PatchCableOverlay] reads this controller to draw the
/// in-progress "live" bezier cable following the pointer.
///
/// The drag ends when [endDrag] is called (typically from [RackScreen]'s
/// pointer-up handler), whether the drop landed on a compatible jack or not.
///
/// Fires [notifyListeners] on every position update so that the live-cable
/// overlay repaints smoothly.
class PatchDragController extends ChangeNotifier {
  /// The slot ID that owns the output jack where the drag started.
  /// Null when no drag is active.
  String? fromSlotId;

  /// The output port where the drag started.
  /// Null when no drag is active.
  AudioPortId? fromPort;

  /// Current pointer position in global (screen) coordinates.
  /// Null when no drag is active.
  Offset? pointerPosition;

  /// Whether a cable drag is currently in progress.
  bool get isDragging => fromSlotId != null;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Begins a drag from the given output port on [slotId] at [startPos].
  ///
  /// [startPos] should be the global centre of the jack widget, so the live
  /// cable originates exactly from the jack circle.
  void startDrag(String slotId, AudioPortId port, Offset startPos) {
    assert(port.isOutput, 'Only output jacks can start a drag');
    fromSlotId = slotId;
    fromPort = port;
    pointerPosition = startPos;
    notifyListeners();
  }

  /// Updates the live cable endpoint as the pointer moves.
  ///
  /// Called on every pointer-move event while [isDragging] is true.
  /// No-op when no drag is active.
  void updatePosition(Offset pos) {
    if (!isDragging) return;
    pointerPosition = pos;
    notifyListeners();
  }

  /// Clears all drag state, ending the in-progress cable gesture.
  ///
  /// Called after a successful drop (connection created) or an unsuccessful
  /// one (dropped on empty space / incompatible jack).
  void endDrag() {
    fromSlotId = null;
    fromPort = null;
    pointerPosition = null;
    notifyListeners();
  }
}
