import 'gf_plugin.dart';
import 'gf_plugin_type.dart';
import 'gf_midi_event.dart';
import 'gf_transport_context.dart';

/// A GFPA plugin that transforms a MIDI event stream without producing audio.
///
/// Examples: arpeggiator, scale-locker (Jam Mode), chord generator,
/// velocity shaper, MIDI transpose.
///
/// In the audio graph (Phase 5+), a MIDI FX plugin sits on a MIDI cable
/// between an upstream MIDI source and a downstream instrument. In Phase 3
/// (pre-audio-graph), the host calls [processMidi] based on the slot's
/// [targetSlotId] connection stored in [GFpaPluginInstance].
abstract class GFMidiFxPlugin extends GFPlugin {
  @override
  GFPluginType get type => GFPluginType.midiFx;

  /// Receive [events] for the current processing block and return the
  /// transformed event list.
  ///
  /// Implementations may:
  ///   - Modify note pitches (scale locking, transposition)
  ///   - Generate new events (arpeggiator, chord)
  ///   - Filter events (velocity gate)
  ///   - Reorder events (within the block window)
  ///
  /// Must not block. Called on the audio thread or the UI thread depending
  /// on the host implementation.
  List<TimestampedMidiEvent> processMidi(
    List<TimestampedMidiEvent> events,
    GFTransportContext transport,
  );
}
