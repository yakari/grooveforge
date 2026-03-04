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
}
