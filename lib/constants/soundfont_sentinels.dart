// Special ChannelState.soundfontPath values that are not real `.sf2` files.
// Kept in one place so models and the audio engine share one literal.

/// On-screen keyboard and external MIDI on this channel route like a MIDI source
/// (MIDI OUT cables, loopers, scale lock) but **no** internal FluidSynth audio.
const String kMidiControllerOnlySoundfont = 'midiControllerOnly';
