// ============================================================================
// AudioSourceDescriptor + AudioSourcePlugin mixin.
//
// Phase B of the audio routing redesign (see
// `docs/dev/AUDIO_ROUTING_REDESIGN.md`). This file moves the "what kind of
// audio source am I?" question from a hand-rolled `switch (plugin.runtimeType)`
// chain inside the routing service to a method implemented directly on every
// plugin class that can produce audio.
//
// ## Why this exists
//
// Before Phase B, adding a new audio source type meant editing five different
// files: the plugin model, the builder's `_isAudioSource`, the desktop
// resolver, the Android resolver, and usually a platform-specific FFI touch
// point. Every one of those edits was a pattern match on `plugin is
// SomeSpecificClass` — the plugin classes themselves stayed silent about
// their audio role, and the routing layer had to guess from runtime type.
//
// After Phase B, adding a new audio source type means:
//   1. `with AudioSourcePlugin` on the new plugin class.
//   2. Override `describeAudioSource()` to return the right descriptor.
//   3. Add one enum value to [AudioSourceKind] — the compiler forces you to
//      update the desktop and Android resolvers because the `switch`
//      statements there are exhaustive.
//
// That's a feature, not friction: the compiler is preventing you from
// shipping a new source type on Linux but forgetting Android.
//
// ## What this file does NOT do
//
//   - No FFI calls. Descriptors are pure data; the routing service layer
//     owns the mapping from `AudioSourceKind` to a native function pointer
//     or Oboe bus slot ID.
//   - No lifecycle management. When a source is added or removed from the
//     rack, [NativeInstrumentController] still handles the native
//     start/stop calls. The descriptor only answers "what kind of audio
//     source is this, *if* it is one at all?".
// ============================================================================

import 'package:flutter/foundation.dart' show immutable;

/// The kind of audio source a plugin represents.
///
/// Every value maps to exactly one native source type in the backend
/// resolver. The enum is deliberately flat rather than a sealed class
/// hierarchy — Dart 3 `switch` exhaustiveness over a flat enum is the
/// lightest-weight way to get compile-time coverage checking across
/// platform resolvers.
///
/// When adding a new value, update **both** `_resolveDesktopSource`
/// and `_resolveAndroidSource` in `lib/services/vst_host_service_desktop.dart`.
/// Missing a case will produce a Dart analyser error, not a runtime
/// regression.
enum AudioSourceKind {
  /// A GrooveForge Keyboard slot. The descriptor carries
  /// [AudioSourceDescriptor.midiChannel] so the backend resolver can
  /// compute the FluidSynth render slot index `(midiChannel - 1) % 2`
  /// on desktop or look up the per-soundfont Oboe bus slot on Android.
  gfKeyboard,

  /// A drum generator slot. Always plays through percussion slot 2 on
  /// desktop (the metronome / drum sink) and through the channel-10
  /// keyboard's FluidSynth bus slot on Android.
  drumGenerator,

  /// The theremin GFPA instrument (`com.grooveforge.theremin`).
  theremin,

  /// The stylophone GFPA instrument (`com.grooveforge.stylophone`).
  stylophone,

  /// The vocoder GFPA instrument (`com.grooveforge.vocoder`).
  vocoder,

  /// A live input source slot (hardware microphone / line in
  /// passthrough).
  liveInput,

  /// A VST3 plugin instrument. Desktop only — Android resolvers
  /// return `null` for this kind, and the plan builder silently
  /// drops VST3 sources when running under the Oboe capability profile.
  vst3Instrument,
}

/// Pure-data description of a plugin's audio-source role.
///
/// Produced by [AudioSourcePlugin.describeAudioSource] and consumed by
/// the backend resolvers in `VstHostService`. The resolvers read
/// [kind] to pick the right FFI call and read [midiChannel] when the
/// kind needs a channel-based lookup (keyboards, drum generator).
///
/// The type is deliberately value-semantic (`@immutable` + `==` /
/// `hashCode`) so that unit tests can assert on descriptors directly.
@immutable
class AudioSourceDescriptor {
  /// Discriminator identifying which concrete source this plugin
  /// represents. See [AudioSourceKind] for the full enum.
  final AudioSourceKind kind;

  /// MIDI channel (1–16) for kinds that need a per-channel lookup.
  /// Defaults to 0 and is ignored by kinds that don't care (theremin,
  /// stylophone, vocoder, live input, VST3).
  final int midiChannel;

  const AudioSourceDescriptor({
    required this.kind,
    this.midiChannel = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is AudioSourceDescriptor &&
      other.kind == kind &&
      other.midiChannel == midiChannel;

  @override
  int get hashCode => Object.hash(kind, midiChannel);

  @override
  String toString() =>
      'AudioSourceDescriptor(kind: $kind, midiChannel: $midiChannel)';
}

/// Mixin applied to every [PluginInstance] subclass that can produce
/// audio. Implementers return a descriptor for their audio role, or
/// `null` if the slot is not a source on this plugin (e.g. an audio
/// looper, a MIDI FX, or a VST3 effect plugin).
///
/// The method returns nullable rather than requiring a sentinel `none`
/// enum value so callers can use `describeAudioSource() == null` as a
/// clean "not a source" predicate — and so callers of the plan builder
/// can iterate `plugins.whereType<AudioSourcePlugin>()` to restrict to
/// candidates without pulling in every descriptor.
mixin AudioSourcePlugin {
  /// Returns a descriptor identifying this plugin as an audio source,
  /// or `null` if the plugin does not currently produce audio on its
  /// audio output jacks.
  ///
  /// Implementations must be pure (no FFI, no mutable state) so that
  /// the plan builder can call them from any thread without worrying
  /// about ordering relative to the audio callback.
  AudioSourceDescriptor? describeAudioSource();
}
