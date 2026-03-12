/// The functional category of a GFPA plugin.
enum GFPluginType {
  /// Generates audio from MIDI input (synthesizer, sampler, vocoder…).
  instrument,

  /// Processes an audio stream (reverb, EQ, compressor, delay…).
  effect,

  /// Transforms a MIDI event stream without producing audio
  /// (arpeggiator, scale-locker, chord generator…).
  midiFx,

  /// Consumes audio and exposes visual data only (spectrum analyser,
  /// oscilloscope…). Produces no audio output.
  analyzer,
}
