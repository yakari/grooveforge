import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/drum_generator_plugin_instance.dart';
import '../models/gfpa_plugin_instance.dart';
import '../models/keyboard_display_config.dart';
import '../models/audio_looper_plugin_instance.dart';
import '../models/looper_plugin_instance.dart';
import '../models/plugin_instance.dart';
import '../models/grooveforge_keyboard_plugin.dart';
import '../constants/soundfont_sentinels.dart';
import '../models/vst3_plugin_instance.dart';
import '../plugins/gf_vocoder_plugin.dart';
import 'audio_engine.dart';
import 'audio_graph.dart';
import 'cc_mapping_service.dart';
import 'cc_param_registry.dart';
import 'drum_pattern_registry.dart';
import 'native_instrument_controller.dart';
import 'transport_engine.dart';
import 'vst_host_service.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

/// Manages the ordered list of plugin slots in the GrooveForge rack.
///
/// Each [PluginInstance] in [plugins] corresponds to one synthesizer lane
/// with its own MIDI channel and sound source. Per-slot Jam Mode configuration
/// (enabled flag + chosen master slot) is stored on [GFpaPluginInstance]
/// and synced to [AudioEngine.jamFollowerMap] after every mutation.
///
/// When a slot is deleted, [RackState] also notifies [AudioGraph] so that any
/// dangling MIDI/Audio cables connected to the removed slot are cleaned up.
///
/// Persistence is handled externally by [ProjectService], which calls
/// [toJson] / [loadFromJson] and manages .gf file I/O. [RackState] itself
/// notifies an optional [onChanged] callback after every mutation so that
/// the project service can trigger an autosave.
class RackState extends ChangeNotifier {
  final AudioEngine _engine;
  final TransportEngine _transport;
  final AudioGraph _audioGraph;

  final List<PluginInstance> _plugins = [];

  /// Initialized [GFMidiDescriptorPlugin] instances keyed by rack slot ID.
  ///
  /// Populated by [GFpaDescriptorSlotUI] via [registerMidiFxPlugin] when a
  /// MIDI FX slot mounts, and cleared by [unregisterMidiFxPlugin] when it
  /// unmounts. The apply method [applyMidiFxForChannel] reads from this map
  /// to transform events before dispatch.
  final Map<String, GFMidiDescriptorPlugin> _midiFxInstances = {};

  /// Initialized [GFDescriptorPlugin] instances for descriptor-backed **audio
  /// effects** (reverb, delay, EQ, compressor, chorus, wah, …), keyed by rack
  /// slot ID.
  ///
  /// The rack is a lazy [ReorderableListView.builder] — off-screen slot
  /// widgets never mount, so any audio-critical work done in their
  /// `initState` (creating the Dart plugin, initialising the native DSP,
  /// syncing saved parameters) would silently skip. We therefore own the
  /// audio-effect plugin lifetime here in [RackState] and populate this map
  /// eagerly at project-load and add-plugin time.
  final Map<String, GFDescriptorPlugin> _audioEffectInstances = {};

  /// Param-change notifier per audio-effect slot.
  ///
  /// Shared ownership: [RackState] creates the notifier alongside the plugin
  /// and subscribes [_onAudioEffectParamChanged]; the slot widget reads it
  /// out and hands it to [GFDescriptorPluginUI] so knob turns increment it
  /// exactly as before. The listener writes `plugin.getState()` back into the
  /// model, pushes the changes to the native DSP, and schedules an autosave.
  final Map<String, ValueNotifier<int>> _audioEffectParamNotifiers = {};

  /// Called after every mutation; use to trigger autosave.
  VoidCallback? onChanged;

  // Tracks transport settings to detect user-driven changes and trigger
  // autosave (TransportEngine.notifyListeners is not otherwise wired into
  // RackState.onChanged).
  bool _lastMetronomeEnabled = false;
  double _lastBpm = 120.0;
  int _lastTimeSigNumerator = 4;
  int _lastTimeSigDenominator = 4;

  // Debounce timer for BPM saves — nudge fires every 80 ms so we wait until
  // the user stops adjusting before persisting.
  Timer? _bpmSaveDebounce;

  /// Periodic timer that drives arpeggiator ticks on all instrument channels.
  ///
  /// Arpeggiators generate notes autonomously based on wall-clock time, but
  /// [GFMidiGraph.processMidi] is only called when there are incoming user
  /// events. When the user holds a chord and no new events arrive, this timer
  /// fires every ~10 ms and injects an empty event list into each active
  /// MIDI-FX chain so that [ArpeggiateNode.tick()] is invoked, advancing the
  /// step sequence in real time.
  ///
  /// 10 ms corresponds to ±5 ms step-timing jitter — acceptable for musical
  /// use since even 1/32 at 240 BPM is ~31 ms.
  Timer? _midiFxTicker;

  RackState(this._engine, this._transport, this._audioGraph) {
    _engine.bpmProvider = () => _transport.bpm;
    _engine.isPlayingProvider = () => _transport.isPlaying;
    _transport.onBeat = (bool isDownbeat) {
      if (_transport.metronomeEnabled) {
        _engine.playMetronomeClick(isDownbeat);
      }
    };
    _lastMetronomeEnabled = _transport.metronomeEnabled;
    _lastBpm = _transport.bpm;
    _lastTimeSigNumerator = _transport.timeSigNumerator;
    _lastTimeSigDenominator = _transport.timeSigDenominator;
    _transport.addListener(_onTransportChanged);
    // Phase 5.4: whenever the audio graph changes, push the new topological
    // order and routing rules to the native ALSA/CoreAudio processing loop.
    _audioGraph.addListener(_onAudioGraphChanged);

    // Drive arpeggiators with an independent 10 ms tick so they advance even
    // when the user is holding notes and no fresh MIDI events are arriving.
    _midiFxTicker = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => _tickMidiFx(),
    );
  }

  /// Builds a map of keyboard slot plugin ID → per-slot FluidSynth sfId for
  /// Android GFPA routing — maps rack slot ID → Oboe bus slot sfId.
  ///
  /// Each GF Keyboard slot gets its own FluidSynth instance on Android
  /// (provisioned by [initAndroidKeyboardSlots]).  This map tells
  /// [VstHostService] which bus slot sfId to register each GFPA insert under,
  /// so that an effect connected to keyboard A's output cannot affect keyboard
  /// B's audio path.
  ///
  /// **Drum generators** are also included: they render MIDI events through
  /// the FluidSynth instance associated with their MIDI channel (typically
  /// channel 10 = percussion slot), so the same `sfIdForChannel` lookup
  /// returns the right bus ID for "cable the drum generator to a looper" or
  /// "cable the drum generator to an effect chain".
  ///
  /// Returns an empty map on all non-Android platforms.
  ///
  /// Public alias: [buildKeyboardSfIds] — exposed so `SplashScreen` and any
  /// other external caller of [VstHostService.syncAudioRouting] can pass the
  /// correct map without reimplementing the channel → sfId lookup.
  Map<String, int> buildKeyboardSfIds() => _buildKeyboardSfIds();

  Map<String, int> _buildKeyboardSfIds() {
    final result = <String, int>{};
    for (final plugin in _plugins) {
      // Use the per-slot dedicated sfId (set by initAndroidKeyboardSlots).
      // If the dedicated synth has not been created yet, sfIdForChannel returns
      // -1 and this slot is omitted from the routing map — GFPA inserts simply
      // have no effect until the next syncAudioRouting after init completes.
      if (plugin is GrooveForgeKeyboardPlugin) {
        final sfId = _engine.sfIdForChannel(plugin.midiChannel - 1);
        if (sfId >= 1) result[plugin.id] = sfId;
      } else if (plugin is DrumGeneratorPluginInstance) {
        // Drum generator MIDI events feed the keyboard FluidSynth on their
        // channel — it rides the same AAudio bus slot.
        final sfId = _engine.sfIdForChannel(plugin.midiChannel - 1);
        if (sfId >= 1) result[plugin.id] = sfId;
      }
    }
    return result;
  }

  /// Creates a dedicated FluidSynth instance on the AAudio bus for every GF
  /// Keyboard slot in the current rack, on Android only.
  ///
  /// Must be called once after [loadFromJson] or [initDefaults], when the full
  /// plugin list is known.  After this completes, each keyboard slot has its
  /// own bus slot ID so GFPA effects can be applied per-slot without bleeding
  /// into adjacent keyboards that share the same soundfont file.
  ///
  /// No-op on iOS, desktop, and web.
  Future<void> initAndroidKeyboardSlots() async {
    if (kIsWeb || !Platform.isAndroid) return;
    for (final plugin in _plugins) {
      if (plugin is! GrooveForgeKeyboardPlugin) continue;
      final path = plugin.soundfontPath;
      if (path == null || path == kMidiControllerOnlySoundfont) continue;
      await _engine.createKeyboardSlotSynth(plugin.midiChannel - 1, path);
    }
    // Push updated sfId map to the native routing layer.
    VstHostService.instance.syncAudioRouting(
      _audioGraph,
      _plugins,
      keyboardSfIds: _buildKeyboardSfIds(),
    );
    // Restore bypass states from the project file so the native DSP layer
    // matches the persisted state after a fresh routing rebuild.
    _syncBypassStatesToNative();
  }

  /// Pushes the bypass state of every GFPA effect slot to the native DSP layer.
  ///
  /// Called after [syncAudioRouting] which clears and re-registers all inserts —
  /// the native handles are fresh and default to non-bypassed, so any slots that
  /// were bypassed in the project need their state re-applied.
  void _syncBypassStatesToNative() {
    for (final plugin in _plugins) {
      if (plugin is! GFpaPluginInstance) continue;
      if (plugin.state['__bypass'] == true) {
        VstHostService.instance.setGfpaDspBypass(plugin.id, true);
      }
    }
  }

  /// Called whenever the [AudioGraph] changes (connection added/removed).
  ///
  /// Pushes the updated topological processing order and routing table to the
  /// native audio loop so audio flows through the new cable configuration
  /// immediately without restarting the ALSA/CoreAudio thread.
  void _onAudioGraphChanged() {
    VstHostService.instance.syncAudioRouting(
      _audioGraph,
      _plugins,
      keyboardSfIds: _buildKeyboardSfIds(),
    );
    // Re-apply bypass states after a full routing rebuild (inserts are fresh).
    _syncBypassStatesToNative();
  }

  void _onTransportChanged() {
    bool saveNow = false;

    // Metronome toggle — save immediately.
    if (_transport.metronomeEnabled != _lastMetronomeEnabled) {
      _lastMetronomeEnabled = _transport.metronomeEnabled;
      saveNow = true;
    }

    // Time signature — save immediately.
    if (_transport.timeSigNumerator != _lastTimeSigNumerator ||
        _transport.timeSigDenominator != _lastTimeSigDenominator) {
      _lastTimeSigNumerator = _transport.timeSigNumerator;
      _lastTimeSigDenominator = _transport.timeSigDenominator;
      saveNow = true;
    }

    if (saveNow) Timer.run(() => onChanged?.call());

    // BPM — debounced: save 1.5 s after the user stops nudging/typing.
    if (_transport.bpm != _lastBpm) {
      _lastBpm = _transport.bpm;
      _bpmSaveDebounce?.cancel();
      _bpmSaveDebounce = Timer(
        const Duration(milliseconds: 1500),
        () => onChanged?.call(),
      );
    }
  }

  /// Called every ~10 ms to drive time-based MIDI FX nodes (e.g. arpeggiators).
  ///
  /// Pipes an empty event list through every registered MIDI FX plugin.
  /// [GFMidiGraph.processMidi] calls [GFMidiNode.tick()] before
  /// [GFMidiNode.processMidi], so arp nodes advance their step sequence and
  /// emit note events even when no user events arrive (e.g. while holding a
  /// chord with no new key presses).
  ///
  /// This covers both connection styles:
  /// - **MIDI cable**: arpeggiator slot reached from a keyboard via
  ///   `_applyMidiChain` in `rack_slot_widget.dart` (no `targetSlotIds` set).
  /// - **targetSlotIds**: arpeggiator configured with explicit target slots
  ///   (used by MIDI-controller-only channels without a cable).
  ///
  /// Arp-generated events carry the correct MIDI channel in their status byte
  /// (inherited from the original user note-on), so `e.midiChannel` is used
  /// directly to route them to the engine rather than looking up slot channels.
  void _tickMidiFx() {
    final transport = GFTransportContext(
      bpm: _transport.bpm,
      timeSigNumerator: _transport.timeSigNumerator,
      timeSigDenominator: _transport.timeSigDenominator,
      isPlaying: _transport.isPlaying,
      positionInBeats: _transport.positionInBeats,
    );

    // Tick every registered MIDI FX instance. For non-arp plugins (harmonizer,
    // chord expand) tick() returns [] and processMidi([]) returns [] — no cost.
    for (final entry in _midiFxInstances.entries) {
      // Skip bypassed slots so they don't generate arp output while inactive.
      final slot = _findGfpaById(entry.key);
      if (slot != null && slot.state['__bypass'] == true) continue;
      final plugin = entry.value;
      final events = plugin.processMidi(const [], transport);
      for (final e in events) {
        // e.midiChannel is the 0-based channel nibble from the status byte.
        final ch = e.midiChannel;
        if (e.isNoteOn) {
          _engine.playNote(channel: ch, key: e.data1, velocity: e.data2);
        } else if (e.isNoteOff) {
          _engine.stopNote(channel: ch, key: e.data1);
        }
      }
    }
  }

  @override
  void dispose() {
    _bpmSaveDebounce?.cancel();
    _midiFxTicker?.cancel();
    _transport.removeListener(_onTransportChanged);
    _audioGraph.removeListener(_onAudioGraphChanged);
    for (final plugin in _midiFxInstances.values) {
      plugin.dispose();
    }
    _midiFxInstances.clear();
    for (final slotId in _audioEffectInstances.keys.toList()) {
      _disposeAudioEffectPlugin(slotId);
    }
    super.dispose();
  }

  /// Read-only view of the current plugin list (in display order).
  List<PluginInstance> get plugins => List.unmodifiable(_plugins);

  int get pluginCount => _plugins.length;

  // ─── Initialisation ───────────────────────────────────────────────────────

  /// Populates the rack from a JSON list (e.g., loaded from a .gf file).
  void loadFromJson(List<dynamic> pluginsJson) {
    // Dispose any existing MIDI FX instances before loading new ones.
    for (final plugin in _midiFxInstances.values) {
      plugin.dispose();
    }
    _midiFxInstances.clear();
    // Dispose any existing audio-effect plugin instances too.
    for (final slotId in _audioEffectInstances.keys.toList()) {
      _disposeAudioEffectPlugin(slotId);
    }

    _plugins.clear();
    for (final entry in pluginsJson) {
      try {
        _plugins.add(PluginInstance.fromJson(entry as Map<String, dynamic>));
      } catch (e) {
        debugPrint('RackState: skipping unknown plugin entry — $e');
      }
    }
    // Fix keyboards with null soundfontPath — assign the default soundfont
    // so they aren't silent.  This handles corrupt/old .gf files.
    final defaultSf = _engine.loadedSoundfonts.isNotEmpty
        ? _engine.loadedSoundfonts.first
        : null;
    if (defaultSf != null) {
      for (final p in _plugins) {
        if (p is GrooveForgeKeyboardPlugin && p.soundfontPath == null) {
          p.soundfontPath = defaultSf;
        }
      }
    }

    _applyAllPluginsToEngine();
    _syncJamFollowerMapToEngine();

    // Eagerly initialise all MIDI FX slots so they are ready for routing even
    // when their slot widget is scrolled off screen (lazy list rendering).
    for (final plugin in _plugins) {
      if (plugin is GFpaPluginInstance) {
        _initMidiFxPlugin(plugin); // fire-and-forget; errors are caught inside
      }
    }

    notifyListeners();
    _notifyChanged();
  }

  /// Creates the factory defaults: two independent GrooveForge Keyboard slots
  /// (ch 1 = melody / right hand, ch 2 = harmony / left hand) plus a Jam Mode
  /// slot pre-configured with ch 2 as master and ch 1 as target, inactive by
  /// default so the user opts in by pressing the LED button.
  void initDefaults() {
    _plugins.clear();

    // Use the first loaded soundfont as the default for new keyboards.
    // Reading from _engine.channels[] is unreliable — the channel state may
    // be null if _restoreState hasn't populated it yet or if SharedPreferences
    // are missing.
    final defaultSf = _engine.loadedSoundfonts.isNotEmpty
        ? _engine.loadedSoundfonts.first
        : null;

    _plugins.add(
      GrooveForgeKeyboardPlugin(
        id: 'slot-0',
        midiChannel: 1,
        soundfontPath: defaultSf,
        bank: 0,
        program: 0,
      ),
    );

    _plugins.add(
      GrooveForgeKeyboardPlugin(
        id: 'slot-1',
        midiChannel: 2,
        soundfontPath: defaultSf,
        bank: 0,
        program: 0,
      ),
    );

    // Jam Mode slot: ch2 drives the harmony, ch1 follows.
    // Starts inactive so the user consciously enables it.
    _plugins.add(
      GFpaPluginInstance(
        id: 'slot-jam-0',
        pluginId: 'com.grooveforge.jammode',
        midiChannel: 0,
        masterSlotId: 'slot-1',
        targetSlotIds: ['slot-0'],
        state: {
          'enabled': false,
          'scaleType': 'standard',
          'detectionMode': 'chord',
          'bpmLockBeats': 0,
        },
      ),
    );

    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }

  // ─── Mutations ────────────────────────────────────────────────────────────

  void addPlugin(PluginInstance plugin) {
    _plugins.add(plugin);
    if (plugin is GrooveForgeKeyboardPlugin) {
      _applyPluginToEngine(plugin);
      // Ensure this slot has its own dedicated FluidSynth instance on Android.
      // Fire-and-forget: the synth is available before the user can connect a
      // GFPA cable (requires a separate user action), so the async delay is fine.
      if (!kIsWeb && Platform.isAndroid &&
          plugin.soundfontPath != null &&
          plugin.soundfontPath != kMidiControllerOnlySoundfont) {
        _engine
            .createKeyboardSlotSynth(
              plugin.midiChannel - 1,
              plugin.soundfontPath!,
            )
            .then((_) => VstHostService.instance.syncAudioRouting(
                  _audioGraph,
                  _plugins,
                  keyboardSfIds: _buildKeyboardSfIds(),
                ));
      }
    } else if (plugin is GFpaPluginInstance) {
      _applyGfpaPluginToEngine(plugin);
      // Eagerly init so the MIDI FX is available immediately, even before the
      // slot widget scrolls into view.
      _initMidiFxPlugin(plugin); // fire-and-forget; errors caught inside
      // Same rationale for descriptor-backed audio effects — see
      // [_initAudioEffectPlugin] for the full explanation.
      _initAudioEffectPlugin(plugin); // fire-and-forget
      // Global-singleton monophonic instruments (stylophone, theremin) and
      // the vocoder have their native lifetime managed by
      // [NativeInstrumentController] so the Oboe-bus registration stays
      // active while the slot is in the rack — independent of whether the
      // widget is currently mounted by the lazy list builder. On Android
      // this also lets the audio looper and GFPA effects cable into them.
      switch (plugin.pluginId) {
        case 'com.grooveforge.stylophone':
          NativeInstrumentController.instance.onStylophoneAdded(plugin);
        case 'com.grooveforge.theremin':
          NativeInstrumentController.instance.onThereminAdded(plugin);
        case 'com.grooveforge.vocoder':
          NativeInstrumentController.instance.onVocoderAdded();
      }
    }
    _syncJamFollowerMapToEngine();
    // Sync native routing: new slot may alter the topological sort order.
    VstHostService.instance.syncAudioRouting(
      _audioGraph,
      _plugins,
      keyboardSfIds: _buildKeyboardSfIds(),
    );
    notifyListeners();
    _notifyChanged();
  }

  void removePlugin(String id) {
    // Dispose and remove any eagerly-initialised MIDI FX plugin for this slot.
    _midiFxInstances.remove(id)?.dispose();
    // Same for eagerly-initialised audio-effect plugins (also unregisters
    // the native DSP handle).
    _disposeAudioEffectPlugin(id);
    // Global-singleton monophonic instruments — decrement ref count and, on
    // the last slot removed, stop the native oscillator and unregister the
    // Oboe bus source. See [NativeInstrumentController] for rationale.
    final removed = _findById(id);
    if (removed is GFpaPluginInstance) {
      switch (removed.pluginId) {
        case 'com.grooveforge.stylophone':
          NativeInstrumentController.instance.onStylophoneRemoved();
        case 'com.grooveforge.theremin':
          NativeInstrumentController.instance.onThereminRemoved();
        case 'com.grooveforge.vocoder':
          NativeInstrumentController.instance.onVocoderRemoved();
      }
    }

    // Clear references to the removed slot on all dependent plugins.
    for (final p in _plugins) {
      if (p is GFpaPluginInstance) {
        if (p.masterSlotId == id) p.masterSlotId = null;
        p.targetSlotIds.remove(id);
      }
    }
    _plugins.removeWhere((p) => p.id == id);
    // Inform the AudioGraph so any MIDI/Audio cables connected to the
    // removed slot are automatically cleaned up (fires _onAudioGraphChanged
    // if any connections were removed).
    _audioGraph.onSlotRemoved(id);
    // Remove any CC mappings that target the deleted slot (SlotParamTarget
    // or SwapTarget referencing this slot ID).
    _engine.ccMappingService?.removeOrphanedSlotMappings(id);
    _syncJamFollowerMapToEngine();
    // Sync native routing even if no cables pointed to the removed slot.
    VstHostService.instance.syncAudioRouting(
      _audioGraph,
      _plugins,
      keyboardSfIds: _buildKeyboardSfIds(),
    );
    notifyListeners();
    _notifyChanged();
  }

  /// Called by [ReorderableListView] — adjusts the index per Flutter's
  /// convention where the new index accounts for the removal of the old item.
  void reorderPlugins(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex--;
    final item = _plugins.removeAt(oldIndex);
    _plugins.insert(newIndex, item);
    notifyListeners();
    _notifyChanged();
  }

  /// Update the MIDI channel of a slot.
  ///
  /// Both [GrooveForgeKeyboardPlugin] and [GFpaPluginInstance] need their
  /// engine state re-applied after a channel change — otherwise the audio
  /// engine's per-channel mapping (`AudioEngine.channels[].soundfontPath`)
  /// stays pointed at the old channel and notes on the new channel fall
  /// through to whatever was there before. For the Vocoder plugin in
  /// particular this means notes get dispatched to FluidSynth instead of
  /// the vocoder DSP, which can sound like a stray piano voice on the new
  /// channel (because FluidSynth slot allocation collapses every odd-
  /// indexed channel into slot 0).
  void setPluginMidiChannel(String id, int midiChannel) {
    final plugin = _findById(id);
    if (plugin == null) return;
    final oldChannel = plugin.midiChannel;
    plugin.midiChannel = midiChannel;
    if (plugin is GrooveForgeKeyboardPlugin) {
      _applyPluginToEngine(plugin);
    } else if (plugin is GFpaPluginInstance) {
      // Clear the old channel's vocoderMode marker if this plugin owned it.
      // Without this, a vocoder that moved from channel A to channel B
      // would leave channel A's soundfontPath stuck at 'vocoderMode' and
      // any future plugin landing on channel A would see that stale state.
      if (plugin.pluginId == 'com.grooveforge.vocoder' &&
          oldChannel > 0 &&
          oldChannel <= _engine.channels.length) {
        final oldIdx = oldChannel - 1;
        if (_engine.channels[oldIdx].soundfontPath == vocoderMode) {
          _engine.channels[oldIdx].soundfontPath = null;
        }
      }
      _applyGfpaPluginToEngine(plugin);
    }
    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }

  /// Swaps two instrument slots' MIDI channels and optionally their entire
  /// signal chains (audio cables, Jam Mode references, CC mappings).
  ///
  /// **Channels-only** (`swapCables == false`):
  ///   1. Validate both slots exist and are instrument-type (midiChannel > 0).
  ///   2. Swap MIDI channels between the two plugins.
  ///   3. Re-apply keyboard engine state for both (re-routes FluidSynth).
  ///   4. Re-sync Jam Mode follower map.
  ///   5. Rebuild native audio routing.
  ///
  /// **Full swap** (`swapCables == true`): does everything above, plus:
  ///   6. Rewrites AudioGraph connections referencing either slot.
  ///   7. Swaps Jam Mode slot references (masterSlotId, targetSlotIds).
  ///   8. Rewrites CC mappings targeting either slot.
  void swapSlots(
    String slotIdA,
    String slotIdB, {
    bool swapCables = true,
  }) {
    final pluginA = _findById(slotIdA);
    final pluginB = _findById(slotIdB);
    if (pluginA == null || pluginB == null) return;

    // Both must be instrument-type slots (midiChannel > 0).
    if (pluginA.midiChannel <= 0 || pluginB.midiChannel <= 0) return;

    // 1–2. Swap MIDI channels on the plugin instances.
    final chA = pluginA.midiChannel - 1; // 0-based index into engine.channels
    final chB = pluginB.midiChannel - 1;
    final tmpChannel = pluginA.midiChannel;
    pluginA.midiChannel = pluginB.midiChannel;
    pluginB.midiChannel = tmpChannel;

    // 3. Swap the AudioEngine channel-level state (soundfontPath, program,
    // bank) so each MIDI channel retains the correct instrument config for
    // its new owner. Without this, a keyboard swapping with a vocoder would
    // leave the keyboard's soundfont on the vocoder's new channel.
    if (chA >= 0 && chA < 16 && chB >= 0 && chB < 16) {
      final stateA = _engine.channels[chA];
      final stateB = _engine.channels[chB];
      // Swap the serializable fields (soundfontPath, program, bank).
      final tmpPath = stateA.soundfontPath;
      final tmpProg = stateA.program;
      final tmpBank = stateA.bank;
      stateA.soundfontPath = stateB.soundfontPath;
      stateA.program = stateB.program;
      stateA.bank = stateB.bank;
      stateB.soundfontPath = tmpPath;
      stateB.program = tmpProg;
      stateB.bank = tmpBank;
    }

    // 4. Re-apply all keyboard engine states to push the swapped
    // soundfont/patch to FluidSynth on the correct channels.
    for (final p in _plugins) {
      if (p is GrooveForgeKeyboardPlugin) _applyPluginToEngine(p);
    }

    // 4–8. Full signal-chain swap.
    if (swapCables) {
      // 6. Rewire AudioGraph connections.
      _audioGraph.swapSlotReferences(slotIdA, slotIdB);

      // 7. Swap Jam Mode references on all GFPA plugins.
      for (final p in _plugins) {
        if (p is GFpaPluginInstance) {
          if (p.masterSlotId == slotIdA) {
            p.masterSlotId = slotIdB;
          } else if (p.masterSlotId == slotIdB) {
            p.masterSlotId = slotIdA;
          }
          _swapInList(p.targetSlotIds, slotIdA, slotIdB);
        }
      }

      // 8. Rewrite CC mappings targeting either slot.
      _engine.ccMappingService?.swapSlotReferences(slotIdA, slotIdB);
    }

    // Re-sync Jam Mode follower map (channels changed).
    _syncJamFollowerMapToEngine();

    // Rebuild native audio routing to reflect all changes.
    VstHostService.instance.syncAudioRouting(
      _audioGraph,
      _plugins,
      keyboardSfIds: _buildKeyboardSfIds(),
    );

    notifyListeners();
    _notifyChanged();
  }

  /// Swaps two values in a [List] in-place: every occurrence of [a] becomes
  /// [b] and vice versa. Used by [swapSlots] to rewrite Jam Mode target lists.
  static void _swapInList(List<String> list, String a, String b) {
    for (int i = 0; i < list.length; i++) {
      if (list[i] == a) {
        list[i] = b;
      } else if (list[i] == b) {
        list[i] = a;
      }
    }
  }

  /// Update the soundfont, bank, and patch for a GrooveForge Keyboard slot.
  void setPluginSoundfont(String id, String? soundfontPath) {
    final plugin = _findGKById(id);
    if (plugin == null) return;
    plugin.soundfontPath = soundfontPath;
    _applyPluginToEngine(plugin);
    notifyListeners();
    _notifyChanged();
  }

  void setPluginPatch(String id, int program, {int? bank}) {
    final plugin = _findGKById(id);
    if (plugin == null) return;
    plugin.program = program;
    if (bank != null) plugin.bank = bank;
    _engine.assignPatchToChannel(
      plugin.midiChannel - 1,
      program,
      bank: bank,
    );
    notifyListeners();
    _notifyChanged();
  }


  /// Update the per-slot keyboard display and expression config.
  ///
  /// Pass `null` as [config] to clear all overrides and revert to global prefs.
  /// Changes are persisted immediately via the autosave callback.
  void setKeyboardConfig(String id, KeyboardDisplayConfig? config) {
    final plugin = _findById(id);
    if (plugin is GrooveForgeKeyboardPlugin) {
      plugin.keyboardConfig = config;
    } else if (plugin is GFpaPluginInstance) {
      // Only vocoder GFPA slots have an embedded piano that can be configured.
      plugin.keyboardConfig = config;
    } else {
      return;
    }
    notifyListeners();
    _notifyChanged();
  }

  /// Persist a VST3 parameter value change in the rack model for .gf saving.
  void setVst3Parameter(String id, int paramId, double value) {
    final plugin = _findById(id);
    if (plugin is! Vst3PluginInstance) return;
    plugin.parameters[paramId] = value;
    _notifyChanged();
  }

  /// Snapshot the engine's current vocoder params into a GFPA vocoder slot's
  /// [GFpaPluginInstance.state] so they are persisted in .gf files.
  void snapshotGfpaVocoderParams(String id) {
    final plugin = _findGfpaById(id);
    if (plugin == null || plugin.pluginId != 'com.grooveforge.vocoder') return;
    final registry = GFPluginRegistry.instance;
    final gfPlugin = registry.findById('com.grooveforge.vocoder');
    if (gfPlugin is GFVocoderPlugin) {
      gfPlugin.snapshotFromEngine();
      plugin.state = gfPlugin.getState();
    } else {
      // Fallback: read directly from engine notifiers.
      plugin.state = {
        'waveform': _engine.vocoderWaveform.value,
        'noiseMix': _engine.vocoderNoiseMix.value,
        'envRelease': _engine.vocoderEnvRelease.value,
        'bandwidth': _engine.vocoderBandwidth.value,
        'gateThreshold': _engine.vocoderGateThreshold.value,
        'inputGain': _engine.vocoderInputGain.value,
      };
    }
  }

  /// Update the master slot for a Jam Mode GFPA slot.
  void setJamModeMaster(String id, String? masterSlotId) {
    final plugin = _findGfpaById(id);
    if (plugin == null || plugin.pluginId != 'com.grooveforge.jammode') return;
    plugin.masterSlotId = masterSlotId;
    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }

  /// Add a target slot to a Jam Mode GFPA slot (multi-target support).
  void addJamModeTarget(String id, String targetSlotId) {
    final plugin = _findGfpaById(id);
    if (plugin == null || plugin.pluginId != 'com.grooveforge.jammode') return;
    if (!plugin.targetSlotIds.contains(targetSlotId)) {
      plugin.targetSlotIds.add(targetSlotId);
    }
    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }

  /// Remove a target slot from a Jam Mode GFPA slot.
  void removeJamModeTarget(String id, String targetSlotId) {
    final plugin = _findGfpaById(id);
    if (plugin == null || plugin.pluginId != 'com.grooveforge.jammode') return;
    plugin.targetSlotIds.remove(targetSlotId);
    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }

  /// Toggles whether a [GFpaPluginInstance] Jam Mode slot is pinned below the
  /// transport bar for quick access.
  void toggleJamModePinned(String id) {
    final plugin = _findGfpaById(id);
    if (plugin == null || plugin.pluginId != 'com.grooveforge.jammode') return;
    plugin.pinned = !plugin.pinned;
    notifyListeners();
    _notifyChanged();
  }

  /// Toggles whether a [LooperPluginInstance] is pinned below the transport bar.
  void toggleLooperPinned(String id) {
    final plugin = plugins.whereType<LooperPluginInstance>().where((p) => p.id == id).firstOrNull;
    if (plugin == null) return;
    plugin.pinned = !plugin.pinned;
    notifyListeners();
    _notifyChanged();
  }

  void setJamModeEnabled(String id, {required bool enabled}) {
    final plugin = _findGfpaById(id);
    if (plugin == null || plugin.pluginId != 'com.grooveforge.jammode') return;
    plugin.state = {...plugin.state, 'enabled': enabled};
    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }


  /// Update the full state map of a GFPA plugin slot (triggers autosave).
  void setGfpaPluginState(String id, Map<String, dynamic> state) {
    final plugin = _findGfpaById(id);
    if (plugin == null) return;
    plugin.state = state;
    // Re-sync the engine immediately so scale/detection-mode changes take
    // effect without requiring a stop/restart of Jam Mode.
    if (plugin.pluginId == 'com.grooveforge.jammode') {
      _syncJamFollowerMapToEngine();
    }
    _notifyChanged();
  }

  // ─── Serialisation ────────────────────────────────────────────────────────

  List<Map<String, dynamic>> toJson() =>
      _plugins.map((p) => p.toJson()).toList();

  // ─── Engine sync ──────────────────────────────────────────────────────────

  /// Applies all loaded plugins to the audio engine.
  ///
  /// Called from [loadFromJson] which is followed by [initAndroidKeyboardSlots].
  /// We pass [skipAndroidSlotCreation] = true here because
  /// initAndroidKeyboardSlots will create the dedicated FluidSynth instances
  /// sequentially.  Without this flag, _applyPluginToEngine fires a concurrent
  /// fire-and-forget createKeyboardSlotSynth that races with the sequential
  /// one — producing two synths per channel and leaving the first one orphaned
  /// on the audio bus.
  void _applyAllPluginsToEngine() {
    for (final p in _plugins) {
      if (p is GrooveForgeKeyboardPlugin) {
        _applyPluginToEngine(p, skipAndroidSlotCreation: true);
      } else if (p is GFpaPluginInstance) {
        _applyGfpaPluginToEngine(p);
      }
    }
  }

  void _applyGfpaPluginToEngine(GFpaPluginInstance plugin) {
    switch (plugin.pluginId) {
      case 'com.grooveforge.vocoder':
        if (plugin.midiChannel > 0) {
          _engine.assignSoundfontToChannel(
            plugin.midiChannel - 1,
            vocoderMode,
          );
          // Restore saved params into the engine.
          final s = plugin.state;
          _engine.vocoderWaveform.value =
              (s['waveform'] as num?)?.toInt() ?? 0;
          _engine.vocoderNoiseMix.value =
              (s['noiseMix'] as num?)?.toDouble() ?? 0.05;
          _engine.vocoderEnvRelease.value =
              (s['envRelease'] as num?)?.toDouble() ?? 0.02;
          _engine.vocoderBandwidth.value =
              (s['bandwidth'] as num?)?.toDouble() ?? 0.2;
          _engine.vocoderGateThreshold.value =
              (s['gateThreshold'] as num?)?.toDouble() ?? 0.01;
          _engine.vocoderInputGain.value =
              (s['inputGain'] as num?)?.toDouble() ?? 1.0;
          _engine.updateVocoderParameters();
        }
    }
  }

  /// Applies a single keyboard plugin to the audio engine (channel assignment,
  /// program selection, and optionally dedicated FluidSynth creation on Android).
  ///
  /// [skipAndroidSlotCreation] — when true, skips the fire-and-forget
  /// `createKeyboardSlotSynth` call.  Used by [_applyAllPluginsToEngine] during
  /// project load, where [initAndroidKeyboardSlots] handles slot creation
  /// sequentially to avoid a race condition that produces duplicate synths.
  void _applyPluginToEngine(
    GrooveForgeKeyboardPlugin plugin, {
    bool skipAndroidSlotCreation = false,
  }) {
    final idx = plugin.midiChannel - 1;
    if (idx < 0 || idx > 15) return;

    if (plugin.soundfontPath == kMidiControllerOnlySoundfont) {
      _engine.assignSoundfontToChannel(idx, kMidiControllerOnlySoundfont);
    } else if (plugin.soundfontPath != null &&
        _engine.loadedSoundfonts.contains(plugin.soundfontPath)) {
      _engine.assignSoundfontToChannel(idx, plugin.soundfontPath!);

      // On Android each keyboard slot has a dedicated FluidSynth instance that
      // is bound to a single .sf2 file.  When the user switches soundfonts,
      // the old instance must be torn down and replaced so it actually plays
      // the new file.  createKeyboardSlotSynth is a no-op if the path hasn't
      // changed, so this is safe to call unconditionally.
      if (!skipAndroidSlotCreation && !kIsWeb && Platform.isAndroid) {
        _engine
            .createKeyboardSlotSynth(idx, plugin.soundfontPath!)
            .then((_) {
          // Re-apply instrument selection on the fresh synth so the correct
          // bank/program is active immediately.
          _engine.assignPatchToChannel(idx, plugin.program, bank: plugin.bank);
          // Push updated sfId map to native routing layer.
          VstHostService.instance.syncAudioRouting(
            _audioGraph,
            _plugins,
            keyboardSfIds: _buildKeyboardSfIds(),
          );
        });
        return;
      }
    }
    _engine.assignPatchToChannel(idx, plugin.program, bank: plugin.bank);
  }

  /// Syncs jam state to the engine.
  ///
  /// - Legacy [GrooveForgeKeyboardPlugin] slots → [AudioEngine.jamFollowerMap]
  ///   (controlled by the global [AudioEngine.jamEnabled] toggle).
  /// Syncs GFPA Jam Mode slots → [AudioEngine.gfpaJamEntries]
  /// (independent per-slot enable/disable, own scale and detection mode).
  void _syncJamFollowerMapToEngine() {
    final gfpaEntries = <GFpaJamEntry>[];

    for (final p in _plugins) {
      if (p is GFpaPluginInstance &&
          p.pluginId == 'com.grooveforge.jammode') {
        // Slot-level enabled flag (defaults to true when absent).
        if (p.state['enabled'] == false) continue;
        if (p.targetSlotIds.isEmpty || p.masterSlotId == null) continue;
        final master = _findById(p.masterSlotId!);
        if (master == null) continue;
        final masterCh = master.midiChannel - 1;
        if (masterCh < 0 || masterCh >= 16) continue;

        final scaleType = _parseScaleType(p.state['scaleType'] as String?);
        final bassNoteMode = p.state['detectionMode'] == 'bassNote';
        final bpmLockBeats =
            (p.state['bpmLockBeats'] as num?)?.toInt().clamp(0, 4) ?? 0;

        for (final targetId in p.targetSlotIds) {
          final target = _findById(targetId);
          if (target == null) continue;
          final followerCh = target.midiChannel - 1;
          if (followerCh < 0 || followerCh >= 16 || followerCh == masterCh) {
            continue;
          }
          gfpaEntries.add(
            GFpaJamEntry(
              masterCh: masterCh,
              followerCh: followerCh,
              scaleType: scaleType,
              bassNoteMode: bassNoteMode,
              bpmLockBeats: bpmLockBeats,
            ),
          );
        }
      }
    }

    _engine.gfpaJamEntries.value = gfpaEntries;
  }

  ScaleType _parseScaleType(String? s) {
    if (s == null) return ScaleType.standard;
    return ScaleType.values.firstWhere(
      (v) => v.name == s,
      orElse: () => ScaleType.standard,
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  PluginInstance? _findById(String id) {
    try {
      return _plugins.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  GrooveForgeKeyboardPlugin? _findGKById(String id) {
    final p = _findById(id);
    return p is GrooveForgeKeyboardPlugin ? p : null;
  }

  GFpaPluginInstance? _findGfpaById(String id) {
    final p = _findById(id);
    return p is GFpaPluginInstance ? p : null;
  }

  void _notifyChanged() {
    Timer.run(() => onChanged?.call());
  }

  /// Public helper for plugin slot widgets that need to trigger both a
  /// [notifyListeners] rebuild and an autosave without calling the protected
  /// [notifyListeners] directly from outside this class.
  void markDirty() {
    notifyListeners();
    _notifyChanged();
  }

  /// Flips the bypass toggle of the audio effect slot identified by [slotId].
  ///
  /// Pushes the new state to the native DSP layer so the insert callback
  /// skips processing on the audio thread (single atomic bool load, zero CPU).
  /// The state is persisted in `GFpaPluginInstance.state['__bypass']`.
  void toggleEffectBypass(String slotId) {
    final slot = _findGfpaById(slotId);
    if (slot == null) return;
    final bypassed = !(slot.state['__bypass'] == true);
    slot.state['__bypass'] = bypassed;
    VstHostService.instance.setGfpaDspBypass(slotId, bypassed);
    _engine.toastNotifier.value =
        '${slot.displayName} — ${bypassed ? 'bypassed' : 'active'}';
    notifyListeners();
    markDirty();
  }

  /// Sets the bypass state of the audio effect slot identified by [slotId].
  ///
  /// Unlike [toggleEffectBypass], this sets a specific value rather than toggling.
  void setEffectBypass(String slotId, bool bypassed) {
    final slot = _findGfpaById(slotId);
    if (slot == null) return;
    slot.state['__bypass'] = bypassed;
    VstHostService.instance.setGfpaDspBypass(slotId, bypassed);
    notifyListeners();
    markDirty();
  }

  /// Flips the bypass toggle of the MIDI FX slot identified by [slotId].
  ///
  /// When bypassed (`state['__bypass'] == true`) the slot is skipped in both
  /// [applyMidiFxForChannel] and [_tickMidiFx], so no MIDI events pass through
  /// it and arpeggiators stop generating notes.
  void toggleMidiFxBypass(String slotId) {
    final slot = _findGfpaById(slotId);
    if (slot == null) return;
    final bypassed = !(slot.state['__bypass'] == true);
    slot.state['__bypass'] = bypassed;
    _engine.toastNotifier.value =
        '${slot.displayName} — ${bypassed ? 'bypassed' : 'active'}';
    markDirty();
  }

  /// Assigns hardware CC [cc] to the bypass toggle of MIDI FX slot [slotId].
  ///
  /// Pass [cc] = null to remove the assignment. The stored value is the raw
  /// CC number (0–127) that hardware sends; it is matched in [handleBypassCcEvent].
  void setMidiFxBypassCc(String slotId, int? cc) {
    final slot = _findGfpaById(slotId);
    if (slot == null) return;
    if (cc == null) {
      slot.state.remove('__bypassCc');
    } else {
      slot.state['__bypassCc'] = cc;
    }
    markDirty();
  }

  /// Checks incoming hardware CC [ccNumber] against every MIDI FX slot's
  /// bypass assignment and toggles bypass for any match.
  ///
  /// Returns `true` if at least one slot was toggled (so the caller can skip
  /// further processing of that CC if desired).
  bool handleBypassCcEvent(int ccNumber) {
    var handled = false;
    for (final plugin in _plugins.whereType<GFpaPluginInstance>()) {
      if (plugin.state['__bypassCc'] == ccNumber) {
        plugin.state['__bypass'] = !(plugin.state['__bypass'] == true);
        handled = true;
      }
    }
    if (handled) markDirty();
    return handled;
  }

  // ─── Slot-addressed CC parameter dispatch ────────────────────────────────

  /// Debounce timestamps per (slotId, paramKey) to prevent rapid-fire toggles
  /// and cycles from a jittery CC knob.
  final Map<String, int> _ccDebounce = {};

  /// Handles an incoming CC event targeted at a specific slot parameter.
  ///
  /// Dispatches based on [mode]:
  /// - **absolute**: maps CC 0-127 to normalized [0.0, 1.0] and sets the GFPA
  ///   parameter via native DSP, or calls a special handler for non-GFPA params.
  /// - **toggle**: flips a boolean state (debounced 250ms).
  /// - **cycle**: advances a discrete parameter to the next option (debounced).
  ///
  /// No CC value gate — some controllers (e.g. Alesis Vortex Wireless 2)
  /// send value=0 on button press. The 250ms timestamp debounce prevents
  /// double-fire from press+release pairs that send two CC events.
  ///
  /// Called from [AudioEngine._dispatchCcMapping] via [onSlotParamCc].
  void handleSlotParamCc(
    String slotId,
    String paramKey,
    CcParamMode mode,
    int ccValue,
  ) {
    // ── Debounce for toggle and cycle modes ────────────────────────────
    if (mode == CcParamMode.toggle || mode == CcParamMode.cycle) {
      final key = '$slotId:$paramKey';
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = _ccDebounce[key] ?? 0;
      if (now - last < 250) return; // 250ms debounce.
      _ccDebounce[key] = now;
    }

    // ── Bypass (shared by all effect and MIDI FX slots) ────────────────
    if (paramKey == 'bypass') {
      _handleBypassCcToggle(slotId);
      return;
    }

    // ── GF Keyboard special params ─────────────────────────────────────
    final plugin = _findById(slotId);
    if (plugin is GrooveForgeKeyboardPlugin) {
      _handleKeyboardParamCc(plugin, paramKey, mode, ccValue);
      return;
    }

    // ── Drum Generator special params ──────────────────────────────────
    if (plugin is DrumGeneratorPluginInstance) {
      _handleDrumGeneratorParamCc(plugin, paramKey, ccValue);
      return;
    }

    // ── Looper special params ──────────────────────────────────────────
    if (plugin is LooperPluginInstance) {
      _handleLooperParamCc(slotId, paramKey);
      return;
    }

    // ── Audio Looper special params ────────────────────────────────────
    if (plugin is AudioLooperPluginInstance) {
      onAudioLooperParamCc?.call(slotId, paramKey);
      return;
    }

    // ── Vocoder special params ─────────────────────────────────────────
    if (plugin is GFpaPluginInstance &&
        plugin.pluginId == 'com.grooveforge.vocoder') {
      _handleVocoderParamCc(paramKey, mode, ccValue);
      return;
    }

    // ── Standard GFPA parameter (absolute or cycle via paramId) ────────
    if (plugin is GFpaPluginInstance) {
      final entry = CcParamRegistry.findParam(plugin.pluginId, paramKey);
      if (entry == null || entry.gfpaParamId == null) return;

      if (mode == CcParamMode.absolute) {
        _setGfpaParamFromCc(slotId, plugin, entry, ccValue);
      } else if (mode == CcParamMode.cycle && entry.cycleCount != null) {
        _cycleGfpaParam(slotId, plugin, entry);
      }
    }
  }

  /// Handles CC for Drum Generator params (swing, pattern cycling).
  void _handleDrumGeneratorParamCc(
    DrumGeneratorPluginInstance plugin,
    String paramKey,
    int ccValue,
  ) {
    switch (paramKey) {
      case 'toggle_active':
        plugin.isActive = !plugin.isActive;
        notifyListeners();
        markDirty();
      case 'swing':
        // CC 0-127 → swing ratio 0.5 (straight) to 0.75 (heavy).
        plugin.swingOverride = 0.5 + (ccValue / 127.0) * 0.25;
        notifyListeners();
        markDirty();
      case 'humanization':
        // CC 0-127 → humanization amount 0.0–1.0.
        plugin.humanizationAmount = ccValue / 127.0;
        notifyListeners();
        markDirty();
      case 'next_pattern':
        _cycleDrumPattern(plugin, 1);
      case 'prev_pattern':
        _cycleDrumPattern(plugin, -1);
    }
  }

  /// Cycles the drum generator's builtin pattern by [delta] (+1 or -1).
  void _cycleDrumPattern(DrumGeneratorPluginInstance plugin, int delta) {
    final all = DrumPatternRegistry.instance.all;
    if (all.isEmpty) return;
    final currentId = plugin.builtinPatternId;
    final currentIndex = currentId != null
        ? all.indexWhere((p) => p.id == currentId)
        : -1;
    var nextIndex = (currentIndex + delta) % all.length;
    if (nextIndex < 0) nextIndex = all.length - 1;
    // Fire through the engine callback so the transport time signature
    // is updated and the session resets cleanly.
    onDrumPatternCycle?.call(plugin.id, all[nextIndex].id);
  }

  /// Callback for drum pattern cycling. Wired by [RackScreen] to
  /// [DrumGeneratorEngine.loadBuiltinPattern].
  void Function(String slotId, String patternId)? onDrumPatternCycle;

  /// Callback for audio looper CC actions (slot-addressed loop button / stop).
  ///
  /// Wired by [RackScreen] to [AudioLooperEngine.looperButtonPress] and
  /// [AudioLooperEngine.stop].
  void Function(String slotId, String paramKey)? onAudioLooperParamCc;

  /// Handles CC for Looper slot-addressed params (loop button, stop).
  ///
  /// Routes through [AudioEngine.onLooperSystemAction] which is wired to
  /// [LooperEngine] by [RackScreen].
  void _handleLooperParamCc(String slotId, String paramKey) {
    switch (paramKey) {
      case 'loop_button':
        _engine.onLooperSystemAction?.call(1009, 127);
      case 'stop':
        _engine.onLooperSystemAction?.call(1012, 127);
    }
  }

  /// Toggles bypass on the given slot — works for both audio effects and MIDI FX.
  void _handleBypassCcToggle(String slotId) {
    final slot = _findGfpaById(slotId);
    if (slot == null) return;
    // Use the appropriate method based on whether this is an audio effect
    // (has a native DSP handle) or a MIDI FX.
    final isMidiFx = _midiFxInstances.containsKey(slotId);
    if (isMidiFx) {
      toggleMidiFxBypass(slotId);
    } else {
      toggleEffectBypass(slotId);
    }
  }

  /// Handles CC for GF Keyboard slot-addressed params.
  void _handleKeyboardParamCc(
    GrooveForgeKeyboardPlugin plugin,
    String paramKey,
    CcParamMode mode,
    int ccValue,
  ) {
    final ch = plugin.midiChannel - 1;
    if (ch < 0 || ch > 15) return;
    switch (paramKey) {
      case 'absolute_patch':
        // CC 0-127 maps directly to patch 0-127.
        _engine.assignPatchToChannel(ch, ccValue.clamp(0, 127));
      case 'next_patch':
        _engine.changePatchIndex(ch, 1);
      case 'prev_patch':
        _engine.changePatchIndex(ch, -1);
      case 'next_soundfont':
        _engine.cycleChannelSoundfont(ch, 1);
      case 'prev_soundfont':
        _engine.cycleChannelSoundfont(ch, -1);
      case 'volume':
        // CC 0-127 → gain 0.0–10.0 (FluidSynth range).
        _engine.fluidSynthGain.value = ccValue / 127.0 * 10.0;
    }
  }

  /// Handles CC for Vocoder params — all knobs are CC-assignable.
  void _handleVocoderParamCc(String paramKey, CcParamMode mode, int ccValue) {
    final norm = ccValue / 127.0;
    switch (paramKey) {
      case 'waveform':
        // Cycle through 4 waveforms: 0=saw, 1=square, 2=choral, 3=neutral.
        final current = _engine.vocoderWaveform.value;
        _engine.vocoderWaveform.value = (current + 1) % 4;
      case 'noise_mix':
        _engine.vocoderNoiseMix.value = norm;
      case 'env_release':
        // Range 0.005–0.5 seconds.
        _engine.vocoderEnvRelease.value = 0.005 + norm * 0.495;
      case 'bandwidth':
        // Range 0.05–1.0.
        _engine.vocoderBandwidth.value = 0.05 + norm * 0.95;
      case 'gate_threshold':
        // Range 0.0–0.1.
        _engine.vocoderGateThreshold.value = norm * 0.1;
      case 'input_gain':
        // Range 0.0–20.0.
        _engine.vocoderInputGain.value = norm * 20.0;
      case 'volume':
        // CC 0-127 → gain 0.0–10.0 (FluidSynth range).
        _engine.fluidSynthGain.value = norm * 10.0;
    }
  }

  /// Sets a standard GFPA parameter from a CC absolute value.
  ///
  /// Converts CC 0-127 to normalized [0.0, 1.0] and pushes to native DSP.
  void _setGfpaParamFromCc(
    String slotId,
    GFpaPluginInstance plugin,
    CcParamEntry entry,
    int ccValue,
  ) {
    final normalized = ccValue / 127.0;
    // Find the descriptor parameter for denormalization.
    final regPlugin = GFPluginRegistry.instance.findById(plugin.pluginId);
    if (regPlugin is! GFDescriptorPlugin) return;
    final descParam = regPlugin.descriptor.parameters
        .where((p) => p.paramId == entry.gfpaParamId)
        .firstOrNull;
    if (descParam == null) return;

    final physical = descParam.min + normalized * (descParam.max - descParam.min);
    VstHostService.instance.setGfpaDspParam(slotId, descParam.id, physical);
    // Also update the state map so the UI reflects the change.
    plugin.state[descParam.id] = normalized;
    notifyListeners();
  }

  /// Advances a discrete GFPA parameter to the next option.
  void _cycleGfpaParam(
    String slotId,
    GFpaPluginInstance plugin,
    CcParamEntry entry,
  ) {
    final count = entry.cycleCount!;
    final regPlugin = GFPluginRegistry.instance.findById(plugin.pluginId);
    if (regPlugin is! GFDescriptorPlugin) return;
    final descParam = regPlugin.descriptor.parameters
        .where((p) => p.paramId == entry.gfpaParamId)
        .firstOrNull;
    if (descParam == null) return;

    // Read current normalized value, compute current index, advance.
    final currentNorm = (plugin.state[descParam.id] as num?)?.toDouble() ?? 0.0;
    final currentIndex = (currentNorm * (count - 1)).round().clamp(0, count - 1);
    final nextIndex = (currentIndex + 1) % count;
    final maxIdx = (count - 1).clamp(1, count);
    final nextNorm = nextIndex / maxIdx;
    final physical = descParam.min + nextNorm * (descParam.max - descParam.min);
    VstHostService.instance.setGfpaDspParam(slotId, descParam.id, physical);
    plugin.state[descParam.id] = nextNorm;
    notifyListeners();
  }

  // ─── MIDI FX instance registry ──────────────────────────────────────────

  /// Eagerly initialise a [GFMidiDescriptorPlugin] for [instance] and store it
  /// in [_midiFxInstances] so it is available for MIDI routing even when the
  /// slot widget is off-screen (lazy list rendering never mounts it).
  ///
  /// Called by [addPlugin] and [loadFromJson] for every MIDI FX slot. The
  /// call is fire-and-forget; errors are caught and logged so a bad descriptor
  /// cannot break the rest of the rack.
  Future<void> _initMidiFxPlugin(GFpaPluginInstance instance) async {
    final registered = GFPluginRegistry.instance.findById(instance.pluginId);
    if (registered is! GFMidiDescriptorPlugin) return;

    // Create a fresh per-slot instance so two harmonizer slots don't share state.
    final plugin = GFMidiDescriptorPlugin(registered.descriptor);

    // Resolve the scale-provider channel from the master slot (for Jam Mode
    // scale snapping). Falls back to channel 0 when no master is configured.
    final masterSlotId = instance.masterSlotId;
    final masterSlot = masterSlotId != null
        ? _plugins
            .whereType<GFpaPluginInstance>()
            .where((p) => p.id == masterSlotId)
            .firstOrNull
        : null;
    final masterChannel = ((masterSlot?.midiChannel ?? 1) - 1).clamp(0, 15);

    final nodeContext = GFMidiNodeContext(
      sourceChannelIndex: _resolveSourceChannelForMidiFx(instance),
      scaleProvider: () =>
          _engine.channels[masterChannel].validPitchClasses.value,
    );

    try {
      await plugin.initialize(GFMidiPluginContext(
        sampleRate: 44100,
        maxFramesPerBlock: 512,
        midiNodeContext: nodeContext,
      ));
      // Restore previously saved parameter state (normalized 0–1 values).
      plugin.loadState(Map<String, dynamic>.from(instance.state));
      _midiFxInstances[instance.id] = plugin;
      notifyListeners(); // let the UI update if the slot just became visible
    } catch (e) {
      debugPrint('[RackState] MIDI FX init failed for ${instance.id}: $e');
    }
  }

  // ─── Audio effect instance registry ────────────────────────────────────

  /// Eagerly initialise every descriptor-backed **audio effect** slot that is
  /// currently in the rack.
  ///
  /// Must be called from the splash-screen startup sequence AFTER
  /// [VstHostService.startAudio] has brought the native host up — the
  /// `registerGfpaDsp` call inside [_initAudioEffectPlugin] will no-op
  /// silently while `_host` is still null.
  ///
  /// Idempotent: already-initialised slots are skipped.
  Future<void> initializeAudioEffects() async {
    for (final plugin in _plugins) {
      if (plugin is GFpaPluginInstance &&
          !_audioEffectInstances.containsKey(plugin.id)) {
        await _initAudioEffectPlugin(plugin);
      }
    }
  }

  /// Eagerly initialise a [GFDescriptorPlugin] for [instance], register its
  /// native DSP, and wire a listener that keeps the rack model, the native
  /// DSP and the autosave pipeline in sync on every knob change.
  ///
  /// Returns immediately for plugin IDs that are not audio-effect descriptors
  /// (e.g. MIDI FX, instruments, or unknown).
  ///
  /// This replaces the work that used to live in
  /// `GFpaDescriptorSlotUI._initPlugin()` inside the widget's `initState` —
  /// which was skipped whenever the slot was scrolled off-screen (lazy list).
  Future<void> _initAudioEffectPlugin(GFpaPluginInstance instance) async {
    final registered = GFPluginRegistry.instance.findById(instance.pluginId);
    if (registered is! GFDescriptorPlugin) return;

    // A fresh per-slot Dart plugin so two reverb slots never share knob state.
    final plugin = GFDescriptorPlugin(registered.descriptor);
    try {
      await plugin.initialize(
        const GFPluginContext(sampleRate: 44100, maxFramesPerBlock: 512),
      );
      plugin.loadState(Map<String, dynamic>.from(instance.state));
    } catch (e) {
      debugPrint('[RackState] audio effect init failed for ${instance.id}: $e');
      return;
    }

    _audioEffectInstances[instance.id] = plugin;

    // Register the matching native C++ DSP so the JACK/Oboe insert chain can
    // call into it. Guarded: if the symbol is missing (e.g. outdated .so) we
    // fall back to UI-only mode so the rest of the rack keeps producing sound.
    try {
      VstHostService.instance.registerGfpaDsp(instance.id, instance.pluginId);
      _syncAudioEffectParamsToNative(instance.id);
    } catch (e) {
      debugPrint('[RackState] registerGfpaDsp unavailable for ${instance.id} — $e');
    }

    // One param notifier per slot — the UI widget bumps this on every knob
    // turn. Listener below writes the state back and pushes to native.
    final notifier = ValueNotifier<int>(0);
    notifier.addListener(() => _onAudioEffectParamChanged(instance.id));
    _audioEffectParamNotifiers[instance.id] = notifier;

    notifyListeners();
  }

  /// Called by the slot UI whenever a knob moves (via the shared param
  /// notifier). Reads the full parameter map from the Dart plugin, writes it
  /// back into the rack-model state while preserving meta-keys (`__bypass`
  /// etc.), pushes every parameter to the native DSP, and marks the project
  /// dirty so the debounced autosave picks it up.
  void _onAudioEffectParamChanged(String slotId) {
    final plugin = _audioEffectInstances[slotId];
    if (plugin == null) return;
    final instance = _findById(slotId);
    if (instance is! GFpaPluginInstance) return;

    // Snapshot meta-keys that live outside the declared parameter space.
    final bypass = instance.state['__bypass'];
    instance.state
      ..clear()
      ..addAll(plugin.getState());
    if (bypass != null) instance.state['__bypass'] = bypass;

    _syncAudioEffectParamsToNative(slotId);
    markDirty();
  }

  /// Push every parameter on the audio-effect plugin for [slotId] to its
  /// native DSP counterpart.
  ///
  /// Each normalised `[0,1]` value is converted to the parameter's declared
  /// physical range before the FFI call, matching what the widget used to do.
  void _syncAudioEffectParamsToNative(String slotId) {
    final plugin = _audioEffectInstances[slotId];
    if (plugin == null) return;
    final vst = VstHostService.instance;
    for (final p in plugin.descriptor.parameters) {
      final norm = plugin.getParameter(p.paramId);
      final physical = p.min + norm * (p.max - p.min);
      vst.setGfpaDspParam(slotId, p.id, physical);
    }
  }

  /// Tear down the audio-effect plugin owned by [slotId] (if any): disposes
  /// the Dart plugin, unregisters the native DSP, and disposes the shared
  /// param notifier.
  void _disposeAudioEffectPlugin(String slotId) {
    _audioEffectParamNotifiers.remove(slotId)?.dispose();
    final plugin = _audioEffectInstances.remove(slotId);
    if (plugin != null) {
      try {
        plugin.dispose();
      } catch (_) {}
      VstHostService.instance.unregisterGfpaDsp(slotId);
    }
  }

  /// Returns the eagerly-initialised audio-effect plugin for [slotId], or
  /// null if this slot is not an audio effect or has not finished
  /// initialising yet.
  GFDescriptorPlugin? audioEffectInstanceForSlot(String slotId) =>
      _audioEffectInstances[slotId];

  /// Returns the shared param-change notifier for [slotId]. The slot UI
  /// widget hands this to [GFDescriptorPluginUI] so knob turns funnel back
  /// through [_onAudioEffectParamChanged].
  ValueNotifier<int>? audioEffectParamNotifierForSlot(String slotId) =>
      _audioEffectParamNotifiers[slotId];

  /// Returns the MIDI channel index (0-based) of the first configured target
  /// slot for [instance], or 0 if no target is set.
  ///
  /// Used to seed the [GFMidiNodeContext.sourceChannelIndex] so time-synced
  /// nodes (e.g., arpeggiators) can align to the correct channel's tempo grid.
  int _resolveSourceChannelForMidiFx(GFpaPluginInstance instance) {
    for (final targetId in instance.targetSlotIds) {
      final target = _findById(targetId);
      if (target != null && target.midiChannel > 0) {
        return target.midiChannel - 1;
      }
    }
    return 0;
  }

  /// Register an initialized [GFMidiDescriptorPlugin] for [slotId].
  ///
  /// Called by [GFpaMidiFxDescriptorSlotUI] to update the parameter state on a
  /// plugin that [RackState] may have already initialized eagerly. The widget's
  /// instance is preferred so knob changes are reflected immediately.
  void registerMidiFxPlugin(String slotId, GFMidiDescriptorPlugin plugin) {
    // Dispose the eagerly-created instance if the widget provides its own.
    _midiFxInstances[slotId]?.dispose();
    _midiFxInstances[slotId] = plugin;
  }

  /// Unregister the MIDI FX plugin for [slotId].
  ///
  /// Called by [GFpaMidiFxDescriptorSlotUI] on disposal. Does NOT dispose the
  /// plugin — [RackState] re-initialises it eagerly so it stays available for
  /// routing even when the slot scrolls off screen.
  void unregisterMidiFxPlugin(String slotId) {
    // Re-initialise from the slot instance so routing continues without the widget.
    final slot = _findById(slotId);
    if (slot is GFpaPluginInstance) {
      // Remove the widget-owned instance first to avoid disposing a live plugin.
      _midiFxInstances.remove(slotId);
      _initMidiFxPlugin(slot); // fire-and-forget
    }
  }

  /// Transform [events] through all active MIDI FX chains that target [midiChannel].
  ///
  /// Searches all [GFpaPluginInstance] MIDI FX slots. For each whose
  /// [GFpaPluginInstance.targetSlotIds] contains any slot with
  /// [PluginInstance.midiChannel] == [midiChannel], the events are piped
  /// through the registered [GFMidiDescriptorPlugin].
  ///
  /// If no MIDI FX slot targets [midiChannel] the original [events] list is
  /// returned unchanged.
  List<TimestampedMidiEvent> applyMidiFxForChannel(
    int midiChannel,
    List<TimestampedMidiEvent> events,
    GFTransportContext transport,
  ) {
    // Fast exit: no MIDI FX registered at all → nothing to process.
    if (_midiFxInstances.isEmpty) return events;

    // Collect slot IDs on this MIDI channel.
    final targetedSlotIds = _plugins
        .where((p) => p.midiChannel == midiChannel)
        .map((p) => p.id)
        .toSet();

    // Collect MIDI FX slot IDs applicable to this channel via two routing
    // styles so that both the explicit-config and visual-patch-cable workflows
    // work identically for hardware MIDI controller input.
    //
    // Style 1 — targetSlotIds: the MIDI FX instance explicitly names which
    //   keyboard/synth slot IDs it should process. Used when no patch cable is
    //   drawn and the user configured the target slot in the GFPA FX editor.
    //
    // Style 2 — MIDI cable: a patch cable runs from a keyboard slot's MIDI OUT
    //   jack to the MIDI FX slot's MIDI IN jack in the audio graph. This is the
    //   standard visual setup that also drives the on-screen keyboard path.
    //   Without this check, hardware MIDI controller input was silently bypassing
    //   cable-connected FX (harmonizer, transposer, …).
    final fxSlotIds = <String>{};

    for (final p in _plugins.whereType<GFpaPluginInstance>()) {
      // Style 1: the FX explicitly targets one of the active instrument slots.
      if (p.targetSlotIds.any(targetedSlotIds.contains)) {
        fxSlotIds.add(p.id);
        continue;
      }
      // Style 2: the FX is reachable from an instrument slot via a MIDI cable.
      // Use hasMidiOutTo to avoid allocating an intermediate List per slot.
      final reachableViaCable =
          targetedSlotIds.any((slotId) => _audioGraph.hasMidiOutTo(slotId, p.id));
      if (reachableViaCable) fxSlotIds.add(p.id);
    }

    if (fxSlotIds.isEmpty) return events;

    // Chain events through each applicable MIDI FX plugin in rack (display)
    // order so the processing sequence is deterministic and matches the visual
    // rack layout.
    var current = events;
    for (final p in _plugins.whereType<GFpaPluginInstance>()) {
      if (!fxSlotIds.contains(p.id)) continue;
      // Skip slots that the user has bypassed via the on/off toggle.
      if (p.state['__bypass'] == true) continue;
      final plugin = _midiFxInstances[p.id];
      if (plugin == null) continue;
      current = plugin.processMidi(current, transport);
    }
    return current;
  }

  /// `true` when at least one MIDI FX plugin is currently registered.
  ///
  /// Used by the MIDI hot path to skip the entire [applyMidiFxForChannel]
  /// pipeline (and avoid its allocations) when the rack has no MIDI FX slots.
  bool get hasMidiFxPlugins => _midiFxInstances.isNotEmpty;

  /// Return the [GFMidiDescriptorPlugin] registered for [slotId], or null.
  ///
  /// Used by [_PianoBody] to look up MIDI FX plugins connected via patch cable
  /// so on-screen keyboard notes can be routed through the MIDI FX chain.
  GFMidiDescriptorPlugin? midiFxInstanceForSlot(String slotId) =>
      _midiFxInstances[slotId];

  /// Returns `true` when the MIDI FX slot with [slotId] has been bypassed
  /// (its power toggle is off, i.e. `state['__bypass'] == true`).
  ///
  /// Used by [_PianoBody._applyMidiChain] to skip bypassed effects for
  /// on-screen keyboard input, mirroring the bypass check already present
  /// in [applyMidiFxForChannel] for hardware MIDI controller input.
  bool isMidiFxBypassed(String slotId) {
    for (final p in _plugins) {
      if (p.id == slotId && p is GFpaPluginInstance) {
        return p.state['__bypass'] == true;
      }
    }
    return false;
  }

  /// Trigger a native audio routing rebuild without modifying the rack.
  ///
  /// Used by GFPA descriptor slot widgets after registering or unregistering
  /// a native DSP instance so that [VstHostService] can wire the insert chain.
  void syncAudioRoutingIfNeeded() {
    VstHostService.instance.syncAudioRouting(
      _audioGraph,
      _plugins,
      keyboardSfIds: _buildKeyboardSfIds(),
    );
  }

  /// Returns the next unused MIDI channel (1–16), or -1 if all are taken.
  /// Slots with [midiChannel] == 0 (MIDI FX / pure effect) are not counted.
  int nextAvailableMidiChannel() {
    final used = _plugins
        .where((p) => p.midiChannel > 0)
        .map((p) => p.midiChannel)
        .toSet();
    for (int ch = 1; ch <= 16; ch++) {
      if (!used.contains(ch)) return ch;
    }
    return -1;
  }

  /// Generates a unique slot ID (e.g. "slot-3").
  String generateSlotId() {
    int n = _plugins.length;
    while (_plugins.any((p) => p.id == 'slot-$n')) {
      n++;
    }
    return 'slot-$n';
  }
}
