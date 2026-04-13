// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'GrooveForge Synth';

  @override
  String get loadingText => 'Initializing Synth Engine...';

  @override
  String get preferencesTitle => 'Preferences';

  @override
  String get midiConnectionSection => 'MIDI Connection';

  @override
  String get connectMidiDevice => 'Connect MIDI Device';

  @override
  String get notConnected => 'Not connected';

  @override
  String get selectMidiDeviceDialogTitle => 'Select MIDI Device';

  @override
  String get midiNewDeviceDetected => 'New MIDI Device Detected';

  @override
  String midiConnectNewDevicePrompt(String deviceName) {
    return 'Connect to $deviceName?';
  }

  @override
  String get actionConnect => 'Connect';

  @override
  String get actionIgnore => 'Ignore';

  @override
  String get soundfontsSection => 'Soundfonts';

  @override
  String get loadSoundfont => 'Load Soundfont (.sf2)';

  @override
  String get noSoundfontsLoaded => 'No soundfonts loaded.';

  @override
  String get defaultSoundfont => 'Default soundfont';

  @override
  String get routingControlSection => 'Routing & Control';

  @override
  String get ccMappingPreferences => 'CC Mapping Preferences';

  @override
  String get ccMappingPreferencesSubtitle =>
      'Map hardware knobs to GM Effects and System Actions';

  @override
  String get keyGesturesSection => 'Key Gestures';

  @override
  String get verticalInteraction => 'Vertical Interaction (default)';

  @override
  String get verticalInteractionSubtitle =>
      'Swipe up/down on a key — overridable per slot';

  @override
  String get horizontalInteraction => 'Horizontal Interaction (default)';

  @override
  String get horizontalInteractionSubtitle =>
      'Slide left/right on a key — overridable per slot';

  @override
  String get actionSave => 'SAVE';

  @override
  String get actionDone => 'Done';

  @override
  String chNumber(int channel) {
    return 'CH $channel';
  }

  @override
  String get patchLoadSoundfont => 'Load a soundfont from preferences';

  @override
  String get patchDefaultSoundfont => 'Default soundfont';

  @override
  String get patchSoundfontNoneMidiOnly => 'None (MIDI only)';

  @override
  String get rackSlotKeyboardMidiOnlyShort => 'MIDI only';

  @override
  String patchUnknownProgram(int program) {
    return 'Unknown Program $program';
  }

  @override
  String patchBank(int bank) {
    return 'Bank $bank';
  }

  @override
  String get ccTitle => 'CC Mapping Preferences';

  @override
  String get ccActiveMappings => 'Active Mappings';

  @override
  String get ccAddMapping => 'Add Mapping';

  @override
  String get ccWaitingForEvents => 'Waiting for incoming MIDI events...';

  @override
  String ccLastEventCC(int cc, int val) {
    return 'Last Event: CC $cc (Value: $val)';
  }

  @override
  String ccLastEventNote(String type, int note, int velocity) {
    return 'Last Event: $type Note $note (Velocity: $velocity)';
  }

  @override
  String ccReceivedOnChannel(int channel) {
    return 'Received on Channel $channel';
  }

  @override
  String get ccInstructions =>
      'Move a slider or play a note on your MIDI hardware controller to instantly identify its internal event data here.';

  @override
  String get ccNoMappings =>
      'No custom mappings defined.\nClick below to add one.';

  @override
  String ccUnknownSequence(int cc) {
    return 'CC $cc';
  }

  @override
  String get ccRoutingAllChannels => 'All Channels';

  @override
  String get ccRoutingSameAsIncoming => 'Same as Incoming';

  @override
  String ccRoutingChannel(int channel) {
    return 'Channel $channel';
  }

  @override
  String ccMappingHardwareToTarget(int incoming, String targetName) {
    return 'Hardware CC $incoming ➔ Mapped to $targetName';
  }

  @override
  String ccMappingRouting(String channelStr) {
    return 'Routing: $channelStr';
  }

  @override
  String get ccNewMappingTitle => 'New CC Mapping';

  @override
  String get ccIncomingLabel => 'Incoming Hardware CC (e.g., 20)';

  @override
  String get ccTargetEffectLabel => 'Target GM Effect';

  @override
  String get ccTargetChannelLabel => 'Target Channel';

  @override
  String get ccSaveBinding => 'Save Binding';

  @override
  String get ccMuteChannelsLabel => 'Channels to mute/unmute';

  @override
  String ccMuteChannelsSummary(String channels) {
    return 'Channels: $channels';
  }

  @override
  String get ccMuteNoChannels => 'No channels selected';

  @override
  String ccTargetEffectFormat(String name, int cc) {
    return '$name (CC $cc)';
  }

  @override
  String get actionNone => 'None';

  @override
  String get actionPitchBend => 'Pitch Bend';

  @override
  String get actionVibrato => 'Vibrato';

  @override
  String get actionGlissando => 'Glissando';

  @override
  String get virtualPianoDisplaySection => 'Virtual Piano Display';

  @override
  String get visibleKeysTitle => 'Default Key Count';

  @override
  String get visibleKeysSubtitle =>
      'Number of white keys shown when no per-slot override is set';

  @override
  String get keys25 => '25 keys (15 white)';

  @override
  String get keys37 => '37 keys (22 white)';

  @override
  String get keys49 => '49 keys (29 white)';

  @override
  String get keys88 => '88 keys (52 white)';

  @override
  String get notationFormatTitle => 'Music Notation Format';

  @override
  String get notationFormatSubtitle => 'How chord names are displayed';

  @override
  String get notationStandard => 'Standard (C, D, E)';

  @override
  String get notationSolfege => 'Solfège (Do, Ré, Mi)';

  @override
  String get prefAboutMadeWith => 'Made with Flutter in Paris 🇫🇷';

  @override
  String get splashStartingEngine => 'Starting audio engine...';

  @override
  String get splashLoadingPreferences => 'Loading preferences...';

  @override
  String get splashStartingFluidSynth => 'Starting FluidSynth backend...';

  @override
  String get splashRestoringState => 'Restoring saved state...';

  @override
  String get splashCheckingSoundfonts => 'Checking bundled soundfonts...';

  @override
  String get splashExtractingSoundfont => 'Extracting default soundfont...';

  @override
  String get splashReady => 'Ready';

  @override
  String get synthTooltipUserGuide => 'User Guide';

  @override
  String get synthTooltipSettings => 'Settings & Setup';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get aftertouchEffectTitle => 'Aftertouch Effect (default)';

  @override
  String get aftertouchEffectSubtitle =>
      'Route keyboard pressure to this CC — overridable per slot';

  @override
  String get aboutSection => 'About';

  @override
  String get versionTitle => 'Version';

  @override
  String get viewChangelogTitle => 'View Changelog';

  @override
  String get viewChangelogSubtitle => 'History of changes and updates';

  @override
  String get changelogDialogTitle => 'Changelog';

  @override
  String get closeButton => 'Close';

  @override
  String get errorLoadingChangelog => 'Error loading changelog.';

  @override
  String get resetPreferencesButton => 'Reset All Preferences';

  @override
  String get resetPreferencesDialogTitle => 'Reset All Preferences?';

  @override
  String get resetPreferencesDialogBody =>
      'This will clear all your settings, loaded soundfonts, and custom assignments. This action cannot be undone.';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get confirmButton => 'OK';

  @override
  String get selectFile => 'Select File';

  @override
  String get selectDirectory => 'Select Directory';

  @override
  String get filePickerAllowedTypes => 'Allowed types';

  @override
  String get resetEverythingButton => 'Reset Everything';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSubtitle => 'App interface language';

  @override
  String get languageSystem => 'System Default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'French';

  @override
  String get guideTitle => 'User Guide';

  @override
  String get guideTabFeatures => 'Features';

  @override
  String get guideTabMidi => 'MIDI Connectivity';

  @override
  String get guideTabSoundfonts => 'Soundfonts';

  @override
  String get guideTabTips => 'Musical Tips';

  @override
  String get guideTabPatch => 'Rack & Cables';

  @override
  String get guidePatchRackTitle => 'The Rack';

  @override
  String get guidePatchRackBody =>
      'The rack is the heart of GrooveForge. Each row is a slot — an independent instrument or effect processor. Add slots with the + button, remove them with the trash icon, and reorder them by dragging the handle on the left side of each slot.';

  @override
  String get guidePatchSlotTypesTitle => 'Slot Types';

  @override
  String get guidePatchSlotKeyboard => 'Keyboard';

  @override
  String get guidePatchSlotKeyboardDesc =>
      'Built-in FluidSynth driven by a soundfont (.sf2). Play from the on-screen keyboard or external MIDI. Choose None as the soundfont to use the keyboard as a MIDI-only controller (MIDI OUT cables in patch view, no built-in synth).';

  @override
  String get guidePatchSlotVocoder => 'Vocoder';

  @override
  String get guidePatchSlotVocoderDesc =>
      'Processes microphone audio through a carrier wave for voice-synth effects.';

  @override
  String get guidePatchSlotJam => 'Jam Mode';

  @override
  String get guidePatchSlotJamDesc =>
      'Harmony engine that snaps incoming MIDI notes to a scale in real time. Receives chord information from a master keyboard slot.';

  @override
  String get guidePatchSlotVst3 => 'VST3 Plugin';

  @override
  String get guidePatchSlotVst3Desc =>
      'Load any third-party VST3 instrument or effect. Requires a compatible .vst3 bundle installed on your system.';

  @override
  String get guidePatchSlotVst3DesktopOnly =>
      'VST3 plugin slots are available on desktop platforms only (Linux, macOS, Windows). They are not available on Android or iOS.';

  @override
  String get guidePatchTitle => 'Cable Patching';

  @override
  String get guidePatchIntro =>
      'The patch view lets you see the back panel of every slot in your rack and draw virtual cables between jacks, just like on a real hardware rack. Tap the cable icon in the top app bar to toggle between the front view (playing) and the back view (patching).';

  @override
  String get guidePatchToggleTitle => 'Toggling Patch View';

  @override
  String get guidePatchToggleBody =>
      'Tap the cable icon (⊡) in the top-right of the rack screen to switch to the back panel view. Tap it again (or the agenda icon) to return to the front view. Slot reordering is disabled while in patch view.';

  @override
  String get guidePatchJacksTitle => 'Jack Types';

  @override
  String get guidePatchJacksBody =>
      'Each slot exposes a set of jacks grouped by signal family:\n• MIDI (yellow) — MIDI IN / MIDI OUT for note and CC messages.\n• Audio (red / white / orange) — AUDIO IN L, AUDIO IN R, AUDIO OUT L, AUDIO OUT R for stereo audio; SEND / RETURN for effects loops.\n• Data (purple) — CHORD OUT/IN and SCALE OUT/IN for Jam Mode harmony routing.';

  @override
  String get guidePatchDrawTitle => 'Drawing a Cable';

  @override
  String get guidePatchDrawBody =>
      'Long-press an output jack (●) to start dragging a cable. Compatible input jacks will pulse to show valid targets. Drag to a compatible input jack and release to connect. Dropping in empty space cancels the drag.\n\nCompatible pairs: MIDI OUT → MIDI IN, AUDIO OUT L → AUDIO IN L, AUDIO OUT R → AUDIO IN R, SEND → RETURN, CHORD OUT → CHORD IN, SCALE OUT → SCALE IN.';

  @override
  String get guidePatchDisconnectTitle => 'Disconnecting a Cable';

  @override
  String get guidePatchDisconnectBody =>
      'Each cable has a small ✕ badge at its midpoint. Tap the badge to bring up the Disconnect menu. The badge is also the cable\'s hit zone, so aim for the circle with the coloured ring.';

  @override
  String get guidePatchDataTitle => 'Data Cables (Jam Mode)';

  @override
  String get guidePatchDataBody =>
      'Purple data cables represent the Jam Mode harmony flow between slots. Drawing a CHORD OUT → CHORD IN cable is the same as selecting a Jam Mode master in the dropdown — both controls stay in sync. Similarly, a SCALE OUT → SCALE IN cable corresponds to a target follower slot.';

  @override
  String get guidePatchTip =>
      'Tip: Cables are saved as part of your project (.gf file). Open a saved project to restore all connections exactly as you left them.';

  @override
  String get guideJamModeTitle => 'Jam Mode (Auto-Harmony)';

  @override
  String get guideJamModeBody =>
      'Jam Mode allows you to play flawlessly by locking all keys to a specific scale. In Jam Mode, one channel acts as the \'Master\' (transmitting its scale/harmony) while other channels act as \'Slaves\'. Use the top controls to define the root note and scale type.';

  @override
  String get guideVocoderTitle => 'Vocoder (Voice Synth)';

  @override
  String get guideVocoderBody =>
      'The Vocoder uses your device microphone to modulate the synth sound. Access it by selecting the \'VOCODER\' preset in the soundfont dropdown. For best results:\n• Use wired headphones or speakers (latency over Bluetooth is too high).\n• Setup mic levels with the gain knobs.\n• Android Limitation: You cannot use separate USB devices for input and output. Use a single USB hub/interface that handles both, or the internal mic.\n• Experiment with different carrier waves (Saw, Pulse, Neutral).';

  @override
  String get guideMidiTitle => 'MIDI Connectivity';

  @override
  String get guideMidiBody =>
      'Connect hardware controllers via USB (OTG adapter) or BLE MIDI. Enable CC Mapping in preferences to bind physical knobs to internal effects or system actions like \'Next Patch\'.';

  @override
  String get guideMidiBestPracticeTitle => 'Hardware Recommendations';

  @override
  String get guideMidiBestPracticeBody =>
      'For an optimal experience, we recommend using a split MIDI keyboard or a dual-keyboard setup:\n• Channel 2 (Left Hand): Send notes here to control chords and harmony (Jam Master).\n• Channel 1 (Right Hand): Use this channel to improvise over the generated harmony with the current scale.';

  @override
  String get guideSoundfontsTitle => 'Soundfonts (SF2)';

  @override
  String get guideSoundfontsBody =>
      'Import high-quality instrument sounds (.sf2) in the Soundfont preferences. Once loaded, you can assign them to any MIDI channel via the patch selector.';

  @override
  String get guideTipsTitle => 'Musical Tips & Improvisation';

  @override
  String get guideTipsBody =>
      'New to improvisation? Try these tips:\n• Scale as Safe Zone: Every key in the selected scale will sound \'correct\' with the music.\n• The Root Note: Start or end your phrases on the root note (highlighted) to create a sense of resolution.\n• Rhythm first: Focus on simple rhythmic patterns rather than complex melodies.';

  @override
  String get guideScalesTitle => 'Available Scales';

  @override
  String guideWelcomeHeader(String version) {
    return 'Welcome to GrooveForge v$version';
  }

  @override
  String get guideWelcomeIntro =>
      'This update brings significant improvements to your workflow and creative tools:';

  @override
  String get guideChangelogExpand => 'See what\'s new in this version';

  @override
  String get guideMidiHardware => '1. Hardware Connection';

  @override
  String get guideMidiHardwareStep1 =>
      'Connect controller via USB (OTG) or power on BLE device.';

  @override
  String get guideMidiHardwareStep2 =>
      'Go to Settings > MIDI Input and select your device.';

  @override
  String get guideMidiCcMappings => '2. CC & System Mappings';

  @override
  String get guideMidiCcMappingsBody =>
      'Bind knobs to effects like Volume or System Actions:';

  @override
  String get guideMidiFeaturePatch => 'Patch Up/Down';

  @override
  String get guideMidiFeaturePatchDesc => 'Quickly switch instruments.';

  @override
  String get guideMidiFeatureScales => 'Cycle Scales';

  @override
  String get guideMidiFeatureScalesDesc => 'Change harmony on the fly.';

  @override
  String get guideMidiFeatureJam => 'Toggle Jam';

  @override
  String get guideMidiFeatureJamDesc => 'Force slaves to follow your lead.';

  @override
  String get guideMidiTipSplit =>
      'Tip: Most modern MIDI controllers allow splitting the keys into distinct zones/channels.';

  @override
  String get guideAndroidUsbLimitation =>
      'Important: On Android, using a USB hub with separate input and output devices can be unstable. Use an integrated USB Audio Interface for best results.';

  @override
  String get micSelectionTitle => 'Audio Input';

  @override
  String get micSelectionDevice => 'Microphone';

  @override
  String get micSelectionSensitivity => 'Sensitivity';

  @override
  String get micSelectionDefault => 'System Default';

  @override
  String get audioOutputTitle => 'Audio Output';

  @override
  String get audioOutputDevice => 'Output Device';

  @override
  String get audioOutputDefault => 'System Default';

  @override
  String get audioSettingsBarGain => 'Gain';

  @override
  String get audioSettingsBarMicSensitivity => 'Mic';

  @override
  String get audioSettingsBarMicDevice => 'Input';

  @override
  String get audioSettingsBarOutputDevice => 'Output';

  @override
  String get audioSettingsBarToggleTooltip => 'Show/hide audio settings bar';

  @override
  String get synthAutoScrollTitle => 'Auto-scroll to Active Channel';

  @override
  String get synthAutoScrollSubtitle =>
      'Automatically scroll the list when MIDI is received';

  @override
  String get rackTitle => 'Rack';

  @override
  String get rackAddPlugin => 'Add Plugin';

  @override
  String get rackAddGrooveForgeKeyboard => 'GrooveForge Keyboard';

  @override
  String get rackAddGrooveForgeKeyboardSubtitle =>
      'Soundfont synth or MIDI-only (None) for patch routing';

  @override
  String get rackAddVocoder => 'Vocoder';

  @override
  String get rackAddVocoderSubtitle => 'Mic-driven voice synthesizer (GFPA)';

  @override
  String get rackAddJamMode => 'Jam Mode';

  @override
  String get rackAddJamModeSubtitle =>
      'Scale-lock a keyboard slot to another\'s harmony';

  @override
  String get rackAddVst3 => 'Browse VST3 Plugin…';

  @override
  String get rackAddVst3Subtitle => 'Load an external .vst3 from disk';

  @override
  String get rackRemovePlugin => 'Remove Plugin';

  @override
  String get rackRemovePluginConfirm =>
      'Remove this plugin slot? All unsaved settings will be lost.';

  @override
  String get rackRemove => 'Remove';

  @override
  String get rackPluginUnavailableOnMobile =>
      'This VST3 plugin is not available on mobile.';

  @override
  String get rackMidiChannel => 'MIDI CH';

  @override
  String get rackMenuProject => 'Projects';

  @override
  String get rackOpenProject => 'Open Project';

  @override
  String get rackSaveProject => 'Save Project';

  @override
  String get rackSaveProjectAs => 'Save As…';

  @override
  String get rackNewProject => 'New Project';

  @override
  String get rackNewProjectConfirm =>
      'Start a new project? Unsaved changes will be lost.';

  @override
  String get rackNewProjectButton => 'New Project';

  @override
  String get rackProjectSaved => 'Project saved.';

  @override
  String get rackProjectOpened => 'Project opened.';

  @override
  String get rackAutosaveRestored => 'Session restored.';

  @override
  String get splashRestoringRack => 'Restoring rack state...';

  @override
  String get vst3LoadFailed =>
      'Failed to load VST3 plugin. Make sure you selected the .vst3 bundle folder.';

  @override
  String get vst3EditorOpenFailed =>
      'Could not open plugin editor. If the plugin uses OpenGL, try launching GrooveForge with LIBGL_ALWAYS_SOFTWARE=1 or in a pure X11 session (unset WAYLAND_DISPLAY).';

  @override
  String get vst3NotLoaded => 'Plugin not yet loaded.';

  @override
  String get vst3NotABundle =>
      'Selected folder is not a .vst3 bundle. Please select a folder that ends in .vst3.';

  @override
  String get vst3BrowseTitle => 'Browse for .vst3 folder…';

  @override
  String get vst3BrowseSubtitle =>
      'Select a .vst3 bundle directory from your filesystem.';

  @override
  String get vst3PickInstalledTitle => 'Pick from installed plugins';

  @override
  String get vst3PickInstalledSubtitle =>
      'Choose from plugins found in default system paths.';

  @override
  String get vst3ScanTitle => 'Scan for VST3 Plugins';

  @override
  String get vst3ScanSubtitle =>
      'Search default system paths for installed .vst3 plugins.';

  @override
  String get vst3Scanning => 'Scanning…';

  @override
  String vst3ScanFound(int count) {
    return '$count plugin(s) found.';
  }

  @override
  String get vst3ScanNoneFound => 'No .vst3 plugins found in default paths.';

  @override
  String vst3ScanError(String error) {
    return 'Scan failed: $error';
  }

  @override
  String get transportBpm => 'BPM';

  @override
  String get transportTapTempo => 'Tap';

  @override
  String get transportPlay => 'Play';

  @override
  String get transportStop => 'Stop';

  @override
  String get transportTimeSignature => 'Time Sig';

  @override
  String get transportMetronome => 'Metronome';

  @override
  String get transportTimeSigCustom => 'Custom';

  @override
  String get transportTimeSigNumerator => 'Beats / bar';

  @override
  String get transportTimeSigDenominator => 'Beat unit';

  @override
  String get patchViewToggleTooltip => 'Patch view';

  @override
  String get patchViewFrontButton => 'FRONT';

  @override
  String get disconnectCable => 'Disconnect';

  @override
  String get cableColour => 'Cable colour';

  @override
  String get connectionCycleError =>
      'Cycle detected: this connection would create a feedback loop';

  @override
  String get portMidiIn => 'MIDI IN';

  @override
  String get portMidiOut => 'MIDI OUT';

  @override
  String get portAudioInL => 'AUDIO IN L';

  @override
  String get portAudioInR => 'AUDIO IN R';

  @override
  String get portAudioOutL => 'AUDIO OUT L';

  @override
  String get portAudioOutR => 'AUDIO OUT R';

  @override
  String get portSendOut => 'SEND';

  @override
  String get portReturnIn => 'RETURN';

  @override
  String get portChordOut => 'CHORD OUT';

  @override
  String get portChordIn => 'CHORD IN';

  @override
  String get portScaleOut => 'SCALE OUT';

  @override
  String get portScaleIn => 'SCALE IN';

  @override
  String get looperSlotName => 'MIDI Looper';

  @override
  String get addLooper => 'MIDI Looper';

  @override
  String get addLooperSubtitle => 'Record and loop MIDI patterns with bar sync';

  @override
  String get rackAddAudioLooper => 'Audio Looper';

  @override
  String get rackAddAudioLooperSubtitle =>
      'Record and loop live audio (PCM) with bar sync, overdub, and reverse';

  @override
  String get audioLooperWaveformRecording => 'Recording…';

  @override
  String get audioLooperWaveformCableInstrument =>
      'Cable an instrument to Audio IN';

  @override
  String get audioLooperWaveformEmpty => 'No audio recorded';

  @override
  String get audioLooperTooltipStop => 'Stop';

  @override
  String get audioLooperTooltipReverse => 'Reverse';

  @override
  String get audioLooperTooltipBarSyncOn => 'Bar sync: ON';

  @override
  String get audioLooperTooltipBarSyncOff => 'Bar sync: OFF';

  @override
  String get audioLooperTooltipClear => 'Clear';

  @override
  String get audioLooperTooltipRecord => 'Record';

  @override
  String get audioLooperTooltipPlay => 'Play';

  @override
  String get audioLooperTooltipCancel => 'Cancel';

  @override
  String get audioLooperTooltipStopRecordingAndPlay => 'Stop recording & play';

  @override
  String get audioLooperTooltipPaddingToBar => 'Padding to bar…';

  @override
  String get audioLooperTooltipOverdub => 'Overdub';

  @override
  String get audioLooperTooltipStopOverdub => 'Stop overdub';

  @override
  String get audioLooperStatusIdle => 'IDLE';

  @override
  String get audioLooperStatusArmed => 'ARMED';

  @override
  String get audioLooperStatusRecording => 'REC';

  @override
  String get audioLooperStatusPlaying => 'PLAY';

  @override
  String get audioLooperStatusOverdubbing => 'ODUB';

  @override
  String get audioLooperStatusStopping => 'PAD';

  @override
  String get audioLooperSourceLabel => 'Source';

  @override
  String get audioLooperSourceTooltip =>
      'Pick which instrument feeds this looper';

  @override
  String get audioLooperSourceNone => 'None';

  @override
  String get audioLooperSourceUnknown => 'Unknown source';

  @override
  String audioLooperSourceMultiple(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Multiple ($count sources)',
      two: 'Multiple (2 sources)',
    );
    return '$_temp0';
  }

  @override
  String audioLooperMemoryCapWarning(String usedMb, int capMb) {
    return 'Audio looper memory: $usedMb MB / $capMb MB cap — consider clearing unused clips';
  }

  @override
  String get addLooperAlreadyExists =>
      'A MIDI Looper is already in the rack. Only one is allowed.';

  @override
  String get addJamModeAlreadyExists =>
      'A Jam Mode is already in the rack. Only one is allowed.';

  @override
  String get looperRecord => 'Record';

  @override
  String get looperPlay => 'Play';

  @override
  String get looperStop => 'Stop';

  @override
  String get looperClear => 'Clear';

  @override
  String get looperOverdub => 'Overdub';

  @override
  String get looperArmed => 'Armed — waiting for transport';

  @override
  String get looperWaitingForBar => 'Waiting for bar';

  @override
  String get looperWaitingForOverdub => 'Waiting for overdub';

  @override
  String looperTrack(int n) {
    return 'Track $n';
  }

  @override
  String get looperPinBelow => 'Pin below transport';

  @override
  String get jamModePinBelow => 'Pin below transport';

  @override
  String get looperHalfSpeed => '½×';

  @override
  String get looperNormalSpeed => '1×';

  @override
  String get looperDoubleSpeed => '2×';

  @override
  String get looperReverse => 'Reverse';

  @override
  String get looperMute => 'Mute';

  @override
  String looperBar(int n) {
    return 'Bar $n';
  }

  @override
  String get looperCcAssign => 'Assign CC';

  @override
  String get looperCcAssignTitle => 'Assign hardware CC to looper';

  @override
  String get looperCcRemove => 'Remove CC binding';

  @override
  String get looperCcLearn => 'Move a knob or fader…';

  @override
  String get looperActionLoop => 'Loop';

  @override
  String get looperActionStop => 'Stop';

  @override
  String get looperCcConflictTitle => 'CC already assigned';

  @override
  String looperCcConflictBody(int cc, String target) {
    return 'CC $cc is already mapped to $target. Overwrite?';
  }

  @override
  String get looperCcConflictOverwrite => 'Overwrite';

  @override
  String get looperVolume => 'Volume';

  @override
  String get looperQuantize => 'Quantize';

  @override
  String get kbConfigTitle => 'Keyboard Config';

  @override
  String kbConfigDefault(String value) {
    return 'Default ($value)';
  }

  @override
  String get kbConfigKeysToShow => 'Keys to show';

  @override
  String get kbConfigKeysToShowSubtitle =>
      'Number of visible keys (overrides default)';

  @override
  String kbConfigKeysDefault(int count) {
    return 'Default ($count keys)';
  }

  @override
  String get kbConfigKeyHeight => 'Key height';

  @override
  String get kbConfigKeyHeightSubtitle =>
      'Taller keys are easier to play on phones';

  @override
  String get kbConfigVertGesture => 'Vertical swipe';

  @override
  String get kbConfigVertGestureSubtitle => 'Swipe up/down on a key';

  @override
  String get kbConfigHorizGesture => 'Horizontal swipe';

  @override
  String get kbConfigHorizGestureSubtitle => 'Slide left/right across keys';

  @override
  String get kbConfigAftertouch => 'Aftertouch CC';

  @override
  String get kbConfigAftertouchSubtitle =>
      'Vertical pressure routes to this CC';

  @override
  String get kbConfigResetDefaults => 'Reset to defaults';

  @override
  String get keyHeightSmall => 'Small';

  @override
  String get keyHeightNormal => 'Normal';

  @override
  String get keyHeightLarge => 'Large';

  @override
  String get keyHeightExtraLarge => 'Extra Large';

  @override
  String get rackAddStylophone => 'Stylophone';

  @override
  String get rackAddStyloPhoneSubtitle =>
      'Monophonic metal-strip instrument (GFPA)';

  @override
  String get rackAddTheremin => 'Theremin';

  @override
  String get rackAddThereminSubtitle =>
      'Touch pad — vertical pitch, horizontal volume (GFPA)';

  @override
  String get thereminModePad => 'PAD';

  @override
  String get thereminModeCam => 'CAM';

  @override
  String get thereminCamHint =>
      'Move your hand towards or away from the camera to play';

  @override
  String get thereminCamErrUnsupported =>
      'Camera mode is not available on this platform.';

  @override
  String get thereminCamErrNoPermission =>
      'Camera permission denied. Switch to PAD mode to try again.';

  @override
  String get thereminCamErrNoCamera =>
      'No suitable camera found on this device.';

  @override
  String get thereminCamErrFixedFocus =>
      'This camera has fixed focus — hand tracking is not available.';

  @override
  String get thereminCamErrConfigError =>
      'Camera configuration error. Please switch to PAD mode.';

  @override
  String get styloWaveformSquare => 'SQR';

  @override
  String get styloWaveformSawtooth => 'SAW';

  @override
  String get styloWaveformSine => 'SIN';

  @override
  String get styloWaveformTriangle => 'TRI';

  @override
  String get thereminVibrato => 'VIB';

  @override
  String get thereminPadHeight => 'HEIGHT';

  @override
  String get midiMuteOwnSound => 'MUTE';

  @override
  String get vst3BrowseInstrumentTitle => 'Browse VST3 Instrument…';

  @override
  String get vst3BrowseInstrumentSubtitle =>
      'Load a synthesizer or sampler plugin (.vst3)';

  @override
  String get vst3BrowseEffectTitle => 'Browse VST3 Effect…';

  @override
  String get vst3BrowseEffectSubtitle => 'Load an audio effect plugin (.vst3)';

  @override
  String get vst3PickInstalledInstrumentTitle => 'Pick Installed Instrument';

  @override
  String get vst3PickInstalledEffectTitle => 'Pick Installed Effect';

  @override
  String get vst3EffectTypeReverb => 'Reverb';

  @override
  String get vst3EffectTypeCompressor => 'Compressor';

  @override
  String get vst3EffectTypeEq => 'EQ';

  @override
  String get vst3EffectTypeDelay => 'Delay';

  @override
  String get vst3EffectTypeModulation => 'Modulation';

  @override
  String get vst3EffectTypeDistortion => 'Distortion';

  @override
  String get vst3EffectTypeDynamics => 'Dynamics';

  @override
  String get vst3EffectTypeFx => 'FX';

  @override
  String get vst3FxInserts => 'FX';

  @override
  String get vst3FxAddEffect => 'Add effect';

  @override
  String get vst3FxNoEffects => 'No effects — connect via patch view';

  @override
  String get rackAddEffectsSectionLabel => 'Built-in Effects';

  @override
  String get rackAddVstSectionLabel => 'VST3 Plugins';

  @override
  String get rackAddReverb => 'Plate Reverb';

  @override
  String get rackAddReverbSubtitle => 'Lush stereo room reverb';

  @override
  String get rackAddDelay => 'Ping-Pong Delay';

  @override
  String get rackAddDelaySubtitle => 'Stereo delay with BPM sync';

  @override
  String get rackAddWah => 'Auto-Wah';

  @override
  String get rackAddWahSubtitle => 'Envelope / LFO wah filter with BPM sync';

  @override
  String get rackAddEq => '4-Band EQ';

  @override
  String get rackAddEqSubtitle => 'Low shelf, 2× peaking, high shelf';

  @override
  String get rackAddCompressor => 'Compressor';

  @override
  String get rackAddCompressorSubtitle => 'RMS compressor with soft knee';

  @override
  String get rackAddChorus => 'Chorus / Flanger';

  @override
  String get rackAddChorusSubtitle => 'Stereo chorus with BPM sync';

  @override
  String get rackAddAudioHarmonizer => 'Audio Harmonizer';

  @override
  String get rackAddAudioHarmonizerSubtitle =>
      'Up to 4 pitch-shifted harmony voices from any audio input';

  @override
  String get rackAddLoadGfpd => 'Load .gfpd from file…';

  @override
  String get rackAddLoadGfpdSubtitle =>
      'Import a custom GrooveForge plugin descriptor';

  @override
  String get rackAddMidiFxSectionLabel => 'Built-in MIDI FX';

  @override
  String get rackAddHarmonizer => 'Harmonizer';

  @override
  String get rackAddHarmonizerSubtitle =>
      'Add harmony voices to any MIDI input (MIDI FX)';

  @override
  String get rackAddChordExpand => 'Chord Expand';

  @override
  String get rackAddChordExpandSubtitle =>
      'Expand each note into a full chord voicing (MIDI FX)';

  @override
  String get rackAddArpeggiator => 'Arpeggiator';

  @override
  String get rackAddArpeggiatorSubtitle =>
      'Arpeggiate held notes in a rhythmic sequence (MIDI FX)';

  @override
  String get rackAddTransposer => 'Transposer';

  @override
  String get rackAddTransposerSubtitle =>
      'Shift all notes up or down by ±24 semitones (MIDI FX)';

  @override
  String get rackAddVelocityCurve => 'Velocity Curve';

  @override
  String get rackAddVelocityCurveSubtitle =>
      'Remap velocity with a power, sigmoid, or fixed curve (MIDI FX)';

  @override
  String get rackAddGate => 'Gate';

  @override
  String get rackAddGateSubtitle =>
      'Filter notes by velocity range and pitch range (MIDI FX)';

  @override
  String get midiFxBypass => 'Bypass';

  @override
  String get midiFxCcAssign => 'Assign CC to bypass';

  @override
  String get midiFxCcAssignTitle => 'Assign hardware CC to bypass';

  @override
  String get midiFxCcWaiting =>
      'Move a knob or button on your MIDI controller to assign it...';

  @override
  String midiFxCcAssigned(int cc) {
    return 'CC $cc assigned to bypass';
  }

  @override
  String get midiFxCcRemove => 'Remove CC binding';

  @override
  String get drumGeneratorAddTitle => 'Drum Generator';

  @override
  String get drumGeneratorAddSubtitle =>
      'Beat patterns from bossa nova to metal, with human feel';

  @override
  String get drumGeneratorActiveLabel => 'Active';

  @override
  String get drumGeneratorStyleLabel => 'Style';

  @override
  String get drumGeneratorSwingLabel => 'Swing';

  @override
  String get drumGeneratorSwingPattern => 'Pattern';

  @override
  String get drumGeneratorHumanizeLabel => 'Human feel';

  @override
  String get drumGeneratorHumanizeRobotic => 'Robotic';

  @override
  String get drumGeneratorHumanizeLive => 'Live drummer';

  @override
  String get drumGeneratorIntroLabel => 'Count-in';

  @override
  String get drumGeneratorFillLabel => 'Fill every';

  @override
  String get drumGeneratorSoundfontLabel => 'Soundfont';

  @override
  String get drumGeneratorLoadPattern => 'Load .gfdrum…';

  @override
  String get drumGeneratorFormatGuide => 'Format guide';

  @override
  String get drumGeneratorIntroNone => 'None';

  @override
  String get drumGeneratorIntroCountIn1 => '1 bar';

  @override
  String get drumGeneratorIntroCountIn2 => '2 bars';

  @override
  String get drumGeneratorIntroChopsticks => 'Chopsticks (4 hits)';

  @override
  String get drumGeneratorFillOff => 'Off';

  @override
  String get drumGeneratorFillEvery4 => 'Every 4 bars';

  @override
  String get drumGeneratorFillEvery8 => 'Every 8 bars';

  @override
  String get drumGeneratorFillEvery16 => 'Every 16 bars';

  @override
  String get drumGeneratorFillRandom => 'Random';

  @override
  String get drumGeneratorCrashAfterFill => 'Crash after fill';

  @override
  String get drumGeneratorDynamicBuild => 'Dynamic build';

  @override
  String get drumGeneratorDefaultSoundfont => 'Default soundfont';

  @override
  String get drumGeneratorFormatGuideTitle => 'Drum Pattern Format (.gfdrum)';

  @override
  String get drumGeneratorFormatGuideContent =>
      'A .gfdrum file is a YAML text file describing a drum pattern.\n\nStep grid notation:\nX = strong hit (~100)\nx = medium hit (~75)\no = soft hit (~55)\ng = ghost note (~28)\n. = rest\n\nVelocity fields: base_velocity, velocity_range\nTiming fields: timing_jitter, rush\nSections: groove, fill, break, crash, intro\nSection types: loop (random), sequence (ordered bars)\n\nSee bundled patterns in assets/drums/ for examples.';

  @override
  String get drumGeneratorNoPatternsFound => 'No patterns loaded';

  @override
  String get drumGeneratorFamilyRock => 'Rock';

  @override
  String get drumGeneratorFamilyJazz => 'Jazz';

  @override
  String get drumGeneratorFamilyFunk => 'Funk';

  @override
  String get drumGeneratorFamilyLatin => 'Latin';

  @override
  String get drumGeneratorFamilyCeltic => 'Celtic';

  @override
  String get drumGeneratorFamilyPop => 'Pop';

  @override
  String get drumGeneratorFamilyElectronic => 'Electronic';

  @override
  String get drumGeneratorFamilyWorld => 'World';

  @override
  String get drumGeneratorFamilyMetal => 'Metal';

  @override
  String get drumGeneratorFamilyCountry => 'Country';

  @override
  String get drumGeneratorFamilyFolk => 'Folk';

  @override
  String get drumGeneratorCustomPattern => 'Custom pattern';

  @override
  String get drumGeneratorNoSoundfonts =>
      'No soundfonts — add one in Preferences';

  @override
  String get audioDeviceDisconnectedInput =>
      'Audio input device disconnected — using default';

  @override
  String get audioDeviceDisconnectedOutput =>
      'Audio output device disconnected — using default';

  @override
  String get usbAudioDebugTitle => 'USB Audio Devices';

  @override
  String get usbAudioDebugSubtitle =>
      'Detailed device information for multi-USB investigation';

  @override
  String get usbAudioDebugNoDevices => 'No audio devices found';

  @override
  String get usbAudioDebugRefresh => 'Refresh';

  @override
  String get usbAudioDebugDeviceId => 'Device ID';

  @override
  String get usbAudioDebugDirection => 'Direction';

  @override
  String get usbAudioDebugInput => 'Input';

  @override
  String get usbAudioDebugOutput => 'Output';

  @override
  String get usbAudioDebugInputOutput => 'Input + Output';

  @override
  String get usbAudioDebugSampleRates => 'Sample rates';

  @override
  String get usbAudioDebugChannelCounts => 'Channel counts';

  @override
  String get usbAudioDebugEncodings => 'Encodings';

  @override
  String get usbAudioDebugAddress => 'Address';

  @override
  String get usbAudioDebugAny => 'Any';

  @override
  String get usbAudioDebugPlatformOnly =>
      'Android only — not available on this platform';

  @override
  String get ccCategoryTargetLabel => 'Target category';

  @override
  String get ccCategoryGmCc => 'Standard GM CC';

  @override
  String get ccCategoryInstruments => 'Instruments';

  @override
  String get ccCategoryAudioEffects => 'Audio Effects';

  @override
  String get ccCategoryMidiFx => 'MIDI FX';

  @override
  String get ccCategoryLooper => 'Looper';

  @override
  String get ccCategoryTransport => 'Transport';

  @override
  String get ccCategoryGlobal => 'Global';

  @override
  String get ccCategoryChannelSwap => 'Channel Swap';

  @override
  String get ccTransportPlayStop => 'Play / Stop';

  @override
  String get ccTransportTapTempo => 'Tap Tempo';

  @override
  String get ccTransportMetronomeToggle => 'Metronome Toggle';

  @override
  String get ccGlobalSystemVolume => 'System Volume';

  @override
  String get ccGlobalSystemVolumeHint =>
      'CC 0-127 → System media volume (0-100%)';

  @override
  String get ccSlotPickerLabel => 'Slot';

  @override
  String get ccParamPickerLabel => 'Parameter';

  @override
  String get ccActionPickerLabel => 'Action';

  @override
  String get ccNoSlotsOfType => 'No slots of this type in the rack.';

  @override
  String get ccSwapInstrumentA => 'Instrument A';

  @override
  String get ccSwapInstrumentB => 'Instrument B';

  @override
  String get ccSwapCablesLabel => 'Swap cables (effect chains, Jam Mode links)';

  @override
  String get ccSwapNeedTwoSlots =>
      'Need at least 2 instrument slots in the rack.';

  @override
  String ccSwapDisplayLabel(String slotA, String slotB) {
    return 'Swap: $slotA ↔ $slotB';
  }

  @override
  String get ccSwapCablesYes => 'with cables';

  @override
  String get ccSwapCablesNo => 'channels only';

  @override
  String toastSwapped(String slotA, String slotB) {
    return 'Swapped: $slotA ↔ $slotB';
  }

  @override
  String toastBypassOn(String slotName) {
    return '$slotName — bypassed';
  }

  @override
  String toastBypassOff(String slotName) {
    return '$slotName — active';
  }

  @override
  String toastSystemVolume(int percent) {
    return 'System volume: $percent%';
  }
}
