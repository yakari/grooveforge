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
  String get verticalInteraction => 'Vertical Interaction';

  @override
  String get verticalInteractionSubtitle => 'Swipe up/down on a key';

  @override
  String get horizontalInteraction => 'Horizontal Interaction';

  @override
  String get horizontalInteractionSubtitle => 'Slide left/right on a key';

  @override
  String get actionSave => 'SAVE';

  @override
  String chNumber(int channel) {
    return 'CH $channel';
  }

  @override
  String get patchLoadSoundfont => 'Load a soundfont from preferences';

  @override
  String get patchDefaultSoundfont => 'Default soundfont';

  @override
  String patchUnknownProgram(int program) {
    return 'Unknown Program $program';
  }

  @override
  String patchBank(int bank) {
    return 'Bank $bank';
  }

  @override
  String get jamStart => 'JAM';

  @override
  String get jamStop => 'STOP';

  @override
  String get jamMaster => 'Master';

  @override
  String get jamSlaves => 'Slaves';

  @override
  String get jamScale => 'Scale';

  @override
  String get jamSelectSlavesDialogTitle => 'Select Slave Channels';

  @override
  String jamModeToast(String status) {
    return 'Jam Mode: $status';
  }

  @override
  String get jamStarted => 'STARTED';

  @override
  String get jamStopped => 'STOPPED';

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
  String get visibleKeysTitle => 'Visible Keys (Zoom)';

  @override
  String get visibleKeysSubtitle => 'Number of white keys to show at once';

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
  String get synthVisibleChannelsTitle => 'Visible Channels';

  @override
  String synthChannelLabel(int channelIndex) {
    return 'Channel $channelIndex';
  }

  @override
  String get synthErrorAtLeastOneChannel =>
      'At least one channel must be visible';

  @override
  String get synthSaveFilters => 'Save Filters';

  @override
  String get synthTooltipUserGuide => 'User Guide';

  @override
  String get synthTooltipFilterChannels => 'Filter Visible Channels';

  @override
  String get synthTooltipSettings => 'Settings & Setup';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get scaleLockModeTitle => 'Scale Lock Mode';

  @override
  String get scaleLockModeSubtitle =>
      'Classic (per channel) vs Jam (master-slave)';

  @override
  String get modeClassic => 'Classic Mode';

  @override
  String get modeJam => 'Jam Mode';

  @override
  String get jamModeKeyGroupsTitle => 'Jam Mode Key Groups';

  @override
  String get jamModeKeyGroupsSubtitle =>
      'Visually group scale-mapped keys with borders';

  @override
  String get highlightWrongNotesTitle => 'Highlight Wrong Notes';

  @override
  String get highlightWrongNotesSubtitle =>
      'Color out-of-scale pressed keys in red';

  @override
  String get aftertouchEffectTitle => 'Aftertouch Effect';

  @override
  String get aftertouchEffectSubtitle => 'Route keyboard pressure to this CC';

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
  String get synthAutoScrollTitle => 'Auto-scroll to Active Channel';

  @override
  String get synthAutoScrollSubtitle =>
      'Automatically scroll the list when MIDI is received';

  @override
  String get vocoderWarningTitle => 'Feedback Warning';

  @override
  String get vocoderWarningBody =>
      'Using the internal microphone and speakers simultaneously can cause a loud feedback loop (Larsen effect). Please use external headphones, a separate microphone, or an external speaker for a safe experience.';

  @override
  String get vocoderWarningValidate => 'Enable Vocoder';

  @override
  String get vocoderWarningCancel => 'Cancel';

  @override
  String get rackTitle => 'Rack';

  @override
  String get rackAddPlugin => 'Add Plugin';

  @override
  String get rackAddGrooveForgeKeyboard => 'GrooveForge Keyboard';

  @override
  String get rackAddGrooveForgeKeyboardSubtitle => 'Built-in synth & vocoder';

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
  String get jamSlotOff => 'JAM OFF';

  @override
  String get jamSlotOn => 'JAM ON';

  @override
  String get jamSlotSelectMaster => 'Select Jam Master';

  @override
  String get jamSlotSelectMasterHint =>
      'Which slot will drive the harmony for this keyboard?';

  @override
  String get jamSlotChangeMaster => 'Change master…';

  @override
  String get jamSlotNoMasterSelected => 'Pick master';

  @override
  String get jamSlotNoOtherSlots => 'No other slots available to follow.';

  @override
  String get jamSlotClearMaster => 'Clear Jam master';

  @override
  String get vst3LoadFailed =>
      'Failed to load VST3 plugin. Make sure you selected the .vst3 bundle folder.';

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
}
