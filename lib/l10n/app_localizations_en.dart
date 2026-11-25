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
  String get pianoVelocityTitle => 'Key velocity';

  @override
  String get pianoVelocitySubtitle =>
      'How hard the on-screen keys play. By touch: the closer to the front edge of the key, the louder.';

  @override
  String get pianoVelocityTouch => 'By touch';

  @override
  String get pianoVelocitySoft => 'Soft';

  @override
  String get pianoVelocityMedium => 'Medium';

  @override
  String get pianoVelocityLoud => 'Loud';

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
  String get prefAboutMadeWith => 'Made with Flutter in Paris';

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
  String get guideTabMidi => 'MIDI controllers';

  @override
  String get guideTabTips => 'Playing tips';

  @override
  String get guideTabPatch => 'Cables';

  @override
  String get guidePatchGroupInstruments => 'Instruments';

  @override
  String get guidePatchGroupRhythm => 'Drums & loopers';

  @override
  String get guidePatchGroupCustom => 'Your own plugins';

  @override
  String get guidePatchSlotKeyboard => 'Keyboard';

  @override
  String get guidePatchSlotKeyboardDesc =>
      'Plays a piano or any sound from a soundfont (.sf2). Set it to None (MIDI only) to use it only to send notes to other modules. A key touched near its front edge plays louder than near the back; Preferences > Key velocity can fix one strength instead.';

  @override
  String get guidePatchSlotVocoder => 'Vocoder';

  @override
  String get guidePatchSlotVocoderDesc =>
      'Your voice through the microphone becomes a synth that plays the notes you hold.';

  @override
  String get guidePatchSlotJam => 'Jam Mode';

  @override
  String get guidePatchSlotJamDesc =>
      'Keeps one keyboard in the scale of the chords another keyboard plays.';

  @override
  String get guidePatchSlotVst3 => 'VST3 Plugin';

  @override
  String get guidePatchSlotVst3Desc =>
      'Loads a VST3 instrument or effect installed on your computer.';

  @override
  String get guidePatchSlotVst3DesktopOnly =>
      'VST3 plugins work on Linux, macOS and Windows only, not on Android or in the web demo.';

  @override
  String get guidePatchTitle => 'The cable view';

  @override
  String get guidePatchIntro =>
      'Tap the cable icon at the top of the rack to see the back of every module. Tap the back arrow to return. Modules cannot be moved in this view.';

  @override
  String get guidePatchDrawTitle => 'Drawing a cable';

  @override
  String get guidePatchDrawBody =>
      'Long-press an output socket and drag. Sockets that accept the cable light up. Release on one to connect, anywhere else to cancel. An output only connects to an input of the same colour.';

  @override
  String get guidePatchDisconnectTitle => 'Removing a cable';

  @override
  String get guidePatchDisconnectBody =>
      'Tap the small ✕ in the middle of a cable, then Disconnect. Removing a module removes its cables too.';

  @override
  String get guidePatchDataTitle => 'Scale and tuning cables';

  @override
  String get guidePatchDataBody =>
      'Purple cables carry harmony. CHORD OUT into CHORD IN tells Jam Mode or Xen which keyboard\'s chords to follow. SCALE OUT into SCALE IN adds a keyboard that follows the scale. The cables and the menus in the panels always agree.\nTeal TUNE OUT into TUNE IN carries a Xen scale\'s tuning to an instrument. It is separate from the scale cable, so you can keep a keyboard in a scale without retuning it, or the other way round.';

  @override
  String get guidePatchSharedEffectTitle => 'One effect, one signal';

  @override
  String get guidePatchSharedEffectBody =>
      'An effect remembers the sound passing through it (a reverb tail, a delay line), so it can only process one signal. Two keyboards cabled straight into the same reverb is fine: they are mixed first. One keyboard straight into a reverb and another through a harmonizer into the same reverb is two different signals, and GrooveForge refuses the cable.';

  @override
  String get guidePatchSharedEffectWorkaround =>
      'If a cable is refused for this reason, add a second copy of the effect and cable the other signal into it.';

  @override
  String get guidePatchTip => 'Cables are saved with the project.';

  @override
  String get guideXenTitle => 'Xen: scales and tunings';

  @override
  String get guideXenBody =>
      'Xen keeps every note you play inside a scale. Hold a key and tap a scale: the key you hold becomes the root note, until you do it again. Picking a scale also switches Xen on.\nSNAP moves notes that are outside the scale to the nearest one that fits; the piano greys them out. TUNE plays the scale\'s own tuning, for scales whose notes fall between the piano keys: those keys get a teal band and their offset in cents. SNAP and TUNE switch on and off separately.\nThe Family menu has Western modes, Arabic and Turkish maqamat, Indian ragas, Chinese, Japanese and Korean scales, gamelan tunings, historical temperaments and more. My Scales holds the scales you build or import from Scala (.scl) files.';

  @override
  String get guideJamModeTitle => 'Jam Mode';

  @override
  String get guideJamModeBody =>
      'Jam Mode is for two keyboards: one plays chords, the other improvises. In its panel, MASTER is the keyboard whose chords set the scale, and TARGETS are the keyboards that follow. Every note a target plays moves into that scale. You can also draw the link in the cable view: CHORD OUT into CHORD IN, SCALE OUT into SCALE IN.';

  @override
  String get guideVocoderTitle => 'Vocoder';

  @override
  String get guideVocoderBody =>
      'Tap + and pick Vocoder. Sing or talk into the microphone while you hold notes: your voice shapes a synth that plays them. Set the microphone level with the gain knobs. Try the carrier waves (Saw, Square, Choral), or Harmony, which drops the synth and moves your own voice onto the keys you hold.';

  @override
  String get guideThereminTitle => 'Theremin and Stylophone';

  @override
  String get guideThereminBody =>
      'The Theremin has two modes. PAD is a touch pad: slide up and down for pitch, left and right for volume. CAM (Android, iOS and macOS) uses the front camera to sense how far your hand is: closer plays higher, far enough away is silent, and volume stays full. BASE sets the lowest note, RANGE the span in octaves, VIB the vibrato and HEIGHT the size of the pad.\nThe Stylophone is a 25-key strip you play by touching or sliding along it. It plays one note at a time, like the original, and glides between keys without a click. SQR, SAW, SIN and TRI pick the waveform.';

  @override
  String get guideDrumGeneratorTitle => 'Drum Generator';

  @override
  String get guideDrumGeneratorBody =>
      'Plays a drum pattern at the transport tempo, from bossa nova to metal. Swing pushes the off-beats late. Human feel goes from a strict grid to a drummer who breathes. Count-in plays a few hits before the pattern starts, and Fill every adds a fill every few bars.\nPatterns are .gfdrum files, so you can add your own.';

  @override
  String get guideLoopersTitle => 'Loopers';

  @override
  String get guideLoopersBody =>
      'The MIDI Looper records the notes you play and loops them. The Audio Looper records sound, and can also overdub and reverse.\nBoth wait for the next bar to start recording and round the loop to whole bars, so loops stay in time with each other.\nThe Audio Looper records what is cabled into its AUDIO IN: cable an instrument or a Live Input into it first.';

  @override
  String get guideMidiFxTitle => 'MIDI FX';

  @override
  String get guideMidiFxBody =>
      'MIDI FX change the notes on their way from a keyboard to its sound. Harmonizer adds up to four voices to what you play; with Scale Lock on, they stay in the current scale. Chord Expand turns one note into a chord. Arpeggiator plays held notes one after another, in time. Transposer shifts everything by up to two octaves. Velocity Curve changes how loud soft and hard notes come out. Gate lets through only notes within a velocity or pitch range. Microtone merges held notes into one microtonal pitch.';

  @override
  String get guideMidiTitle => 'Connect a controller';

  @override
  String get guideMidiBody =>
      'GrooveForge works with USB MIDI keyboards and pads (through an OTG adapter on a phone) and with Bluetooth MIDI devices.';

  @override
  String get guideMidiBestPracticeTitle => 'One keyboard or two?';

  @override
  String get guideMidiBestPracticeBody =>
      'One keyboard is enough: a new project pairs a GrooveForge Keyboard with a Xen module. Xen starts off and switches on when you pick a scale: hold a note and tap a scale button.\nA second keyboard, or a controller split in two, is useful for Jam Mode: one hand plays the chords that set the scale, the other improvises over them.';

  @override
  String get guideSoundfontsTitle => 'Sounds (soundfonts)';

  @override
  String get guideSoundfontsBody =>
      'The keyboard plays its sounds from soundfont files (.sf2). To add one, open Preferences, then under Soundfonts tap Load Soundfont (.sf2). It then appears in the sound menu of every keyboard. A good soundfont can take several hundred MB.';

  @override
  String get guideTipsTitle => 'Improvising';

  @override
  String get guideTipsBody =>
      'New to improvising? A few ideas:\n• In a scale, every key fits the music. There are no wrong notes, only surprising ones.\n• Start or end your phrases on the root note: it sounds like coming home.\n• Rhythm first. A simple idea played in time beats a fast run.\n• Leave space. Short phrases with rests between them sound more musical than a stream of notes.';

  @override
  String guideWelcomeHeader(String version) {
    return 'Welcome to GrooveForge v$version';
  }

  @override
  String get guideWelcomeIntro =>
      'Short recipes to get going. Each one links to a clip of the gesture on the website.';

  @override
  String get guideChangelogExpand => 'What\'s new in this version';

  @override
  String get guideMidiHardwareStep1 =>
      'Plug the controller in, or switch on the Bluetooth one.';

  @override
  String get guideMidiHardwareStep2 =>
      'Open Preferences with the gear icon. Under MIDI Connection, tap Connect MIDI Device and pick it.';

  @override
  String get guideMidiCcMappings => 'Map knobs and pads';

  @override
  String get guideMidiCcMappingsBody =>
      'For a module\'s controls: tap the sliders icon at the top of the module, tap Learn next to a control, then move a knob or press a pad.\nFor actions that concern the whole app (looper, transport, channel swap and more): open Preferences, then CC Mapping Preferences, then Add Mapping.';

  @override
  String get guideMidiTipSplit =>
      'Many controllers can split their keys into two zones on different MIDI channels, for example bass in the left hand and melody in the right.';

  @override
  String get guideAndroidUsbLimitation =>
      'Android keeps only one USB audio device at a time. If plugging in a USB microphone silences your USB headphones or sound card, turn on Direct USB output in Preferences, under Audio Output.';

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
  String get usbDirectOutputTitle => 'Direct USB output';

  @override
  String get usbDirectOutputSubtitle =>
      'For a USB mic and a USB sound card (DAC) used together: Android only keeps one of them. Tap ? to learn more.';

  @override
  String get usbDirectOutputUnknownDevice => 'USB DAC';

  @override
  String get usbDirectOutputStatusNoDevice =>
      'Waiting: no compatible USB DAC is plugged in.';

  @override
  String get usbDirectOutputStatusAndroidRoutes =>
      'Not needed right now: Android already plays through your USB device.';

  @override
  String usbDirectOutputStatusPermission(String device) {
    return 'Android is asking for access to $device: tap Allow.';
  }

  @override
  String usbDirectOutputStatusDenied(String device) {
    return 'USB access to $device was declined. Replug it, or turn this off and on, to be asked again.';
  }

  @override
  String usbDirectOutputStatusActive(String device, int rate, int bits) {
    return 'Playing through $device ($rate Hz, $bits-bit). Set the volume in GrooveForge or on your speaker: the phone\'s volume keys don\'t reach this output.';
  }

  @override
  String usbDirectOutputStatusUnsupported(String device) {
    return '$device can\'t be used: only simple USB DACs (USB Audio Class 1) are supported.';
  }

  @override
  String usbDirectOutputStatusError(String device) {
    return '$device stopped. Unplug and replug it to try again.';
  }

  @override
  String get usbDirectOutputHelpTooltip => 'How does it work?';

  @override
  String get usbDirectOutputHelpProblemTitle => 'The problem';

  @override
  String get usbDirectOutputHelpProblemBody =>
      'Android can only use one USB audio device at a time. Plug in a USB microphone (a wireless mic receiver, for example) and a USB sound card (such as the headphone jack of a USB-C hub), and Android keeps the one it detected last and quietly ignores the other. Your music then comes out of the phone\'s speaker instead of your headphones or speakers.';

  @override
  String get usbDirectOutputHelpSolutionTitle => 'What this option does';

  @override
  String get usbDirectOutputHelpSolutionBody =>
      'GrooveForge sends its sound straight to the sound card Android ignored, over USB, without going through Android\'s audio system. Your microphone keeps working normally.';

  @override
  String get usbDirectOutputHelpWhenTitle => 'When it kicks in';

  @override
  String get usbDirectOutputHelpWhenBody =>
      'Only when it is needed: a compatible USB sound card is plugged in and Android is not already playing through a USB device. The rest of the time nothing changes, so you can leave it on.';

  @override
  String get usbDirectOutputHelpStepsTitle => 'How to use it';

  @override
  String get usbDirectOutputHelpStep1 => 'Turn the option on.';

  @override
  String get usbDirectOutputHelpStep2 =>
      'Plug in your sound card and your USB microphone.';

  @override
  String get usbDirectOutputHelpStep3 =>
      'When Android asks for access to the sound card, tap Allow.';

  @override
  String get usbDirectOutputHelpStep4 =>
      'The line under the switch shows \"Playing through…\": you\'re set.';

  @override
  String get usbDirectOutputHelpTipsTitle => 'Good to know';

  @override
  String get usbDirectOutputHelpTipVolume =>
      'The phone\'s volume keys don\'t change this output. Use GrooveForge\'s gain and your speaker\'s volume.';

  @override
  String get usbDirectOutputHelpTipCompat =>
      'Works with simple USB sound cards (USB Audio Class 1), which covers most USB-C hubs and jack adapters. High-end USB interfaces are shown as not supported.';

  @override
  String get usbDirectOutputHelpTipOtherApps =>
      'Only GrooveForge plays through the sound card this way. Notifications and other apps still use the phone.';

  @override
  String get usbDirectOutputHelpTipGiveBack =>
      'After turning the option off, unplug and replug the sound card so Android can use it again.';

  @override
  String get usbDirectOutputHelpTipCharger =>
      'Plug the charger into the hub before connecting the hub to the phone. Adding power while playing makes the phone reconnect every USB device, which cuts the sound and can even restart some phones.';

  @override
  String get usbDirectOutputHelpClose => 'Got it';

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
  String connectionSharedEffectError(String effectName) {
    return '$effectName is already cabled from another signal path. Duplicate the effect slot so each path has its own instance.';
  }

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
  String get portTuningOut => 'TUNE OUT';

  @override
  String get portTuningIn => 'TUNE IN';

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
  String get rackAddSourcesSectionLabel => 'Audio Sources';

  @override
  String get rackAddLiveInputSource => 'Live Input';

  @override
  String get rackAddLiveInputSourceSubtitle =>
      'Route a microphone or line-in into any effect (harmonizer, vocoder, reverb…)';

  @override
  String get liveInputNoDevice => 'No input device detected';

  @override
  String get liveInputDeviceHint =>
      'Change the input in Preferences › Audio Input';

  @override
  String get liveInputDisconnected =>
      'Microphone unplugged: input stopped. Plug it back in or choose another input in Preferences.';

  @override
  String get liveInputFeedbackMuted =>
      'Muted: the phone\'s mic would feed back through its speaker.';

  @override
  String get liveInputFeedbackUnmute => 'Unmute anyway';

  @override
  String get audioDeviceDisconnected => 'Disconnected';

  @override
  String get micDisconnectedToast =>
      'Microphone unplugged: input stopped instead of switching to the phone mic';

  @override
  String get liveInputGainLabel => 'Gain';

  @override
  String get liveInputMonitorMute => 'Mute local monitor (still feeds effects)';

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
  String get chiptuneDuty => 'DUTY';

  @override
  String get chiptuneNoise => 'NOISE';

  @override
  String get chiptuneCrush => 'CRUSH';

  @override
  String get chiptuneSub => 'SUB';

  @override
  String get chiptuneOff => 'OFF';

  @override
  String get chiptuneArp => 'ARP';

  @override
  String get chiptuneChord => 'CHORD';

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
  String get rackAddNativeOnlyBadge => 'Apps only';

  @override
  String get rackAddNativeOnlyTooltip =>
      'Available in the GrooveForge apps for Android, Linux, macOS and Windows, not in this web demo.';

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
  String get rackAddWah => 'Wah';

  @override
  String get rackAddWahSubtitle =>
      'Wah filter: LFO sweep with BPM sync, or played from a pedal / CC knob';

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
  String get rackAddAutotune => 'Autotune';

  @override
  String get rackAddRiff => 'Riff';

  @override
  String get rackAddRiffSubtitle =>
      'Modelled electric guitar, string by string; cable it into the Amp';

  @override
  String get rackAddAmp => 'Amp';

  @override
  String get rackAddAmpSubtitle =>
      'Guitar amp: drive pedal, amp tone stack and speaker cabinet';

  @override
  String get ampIrNone => 'Cabinet IR: none loaded';

  @override
  String ampIrLoaded(String name) {
    return 'Cabinet IR: $name';
  }

  @override
  String get ampIrLoad => 'Load IR';

  @override
  String get ampIrRemove => 'Remove the IR';

  @override
  String get ampIrPickTitle => 'Choose a cabinet impulse response (.wav)';

  @override
  String get ampIrNotWav => 'This file is not a WAV file.';

  @override
  String get ampIrUnsupported =>
      'This WAV uses a compressed format. Export it as a PCM or float WAV.';

  @override
  String get ampIrEmpty => 'This file contains no sound.';

  @override
  String get ampIrUnreadable => 'Could not read this file.';

  @override
  String get ampIrRejected => 'The amp could not use this IR.';

  @override
  String get guideRiffTitle => 'Riff, the modelled guitar';

  @override
  String get guideRiffBody =>
      'Riff is an electric guitar modelled string by string. It has no keys: cable a keyboard\'s MIDI OUT into its MIDI IN, or play it from a controller on its MIDI channel.\nClose notes go to separate strings, so they ring together. With Legato on, a note close to the previous one hammers on or pulls off on the same string. Overlap does the same only when you press a key before letting go of the last one.\nThe pitch wheel bends, the mod wheel adds vibrato, the sustain pedal lets strings ring. Feedback makes held strings bloom into a harmonic, like in front of an amp.\nPalm mute, Pick position, Tone and the pickup selector change strings that are already ringing: map them to a pedal or a knob with Learn and play them like a guitarist\'s hands. For crunch and distortion, cable Riff into the Amp.';

  @override
  String get guideAmpTitle => 'Amp and cabinet IRs';

  @override
  String get guideAmpBody =>
      'The Amp has three sections you can switch on and off, by hand or with a footswitch: a Drive pedal (Overdrive or Distortion), the amp itself (Gain, Bass, Middle, Treble) and the speaker cabinet.\nThe cabinet shapes most of a guitar sound. Besides the three built-in ones, the Amp can play an impulse response (IR), a recording of a real cabinet: tap Load IR under the Amp and pick a .wav file. It is saved in your project; the cross next to its name removes it.';

  @override
  String get guideAmpIrSourcesTitle => 'Where to find free cabinet IRs';

  @override
  String get guideAmpIrSourcesNote =>
      'Each pack comes with its own licence: free to play through, but usually not to share. Download them yourself from these sites.';

  @override
  String get guideIrSourceTone3000 =>
      'TONE3000: a community library with thousands of free IRs';

  @override
  String get guideIrSourceKalthallen =>
      'Kalthallen Cabs: free and paid packs of classic cabinets';

  @override
  String get guideIrSourceCelestion =>
      'Celestion: a free IR from the speaker maker';

  @override
  String get rackAddAutotuneSubtitle =>
      'Snaps your voice onto the notes of a scale, from subtle to robot';

  @override
  String get autotuneListening => 'Sing something…';

  @override
  String autotuneCents(String cents) {
    return '$cents ¢';
  }

  @override
  String get autotuneDisplayTooltip =>
      'Left: the note you are singing and how far off it is. Right: the note it is being tuned to.';

  @override
  String get autotuneScalePatched => 'Following the patched scale';

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
  String get rackAddMicrotone => 'Microtone';

  @override
  String get rackAddMicrotoneSubtitle =>
      'Combine held notes into a single microtonal pitch via pitch-bend (MIDI FX)';

  @override
  String get rackAddXen => 'Xen';

  @override
  String get rackAddXenSubtitle =>
      'Lock the keyboard to a scale and retune it — maqam, raga, gamelan, historical temperaments (MIDI FX)';

  @override
  String get xenAbout =>
      'Hold a note, tap a scale: that note becomes the tonic, and the keyboard locks to the scale around it. Scales that are not equal-tempered — an Arabic maqam, an Indian raga, a Highland pipe chanter — also retune the keys they use, so the intervals sound as the tradition intends rather than as a piano approximates them. Unlike the Microtone module, which bends pitch one note at a time, Xen retunes each key independently: a whole chord can hold its own intonation.';

  @override
  String get xenSnap => 'SNAP';

  @override
  String get xenTune => 'TUNE';

  @override
  String get xenRoot => 'ROOT';

  @override
  String get xenFamily => 'FAMILY';

  @override
  String get xenScale => 'SCALE';

  @override
  String get xenLatch => 'LATCH';

  @override
  String get xenTargetsLock => 'SCALE LOCK';

  @override
  String get xenTargetsTune => 'RETUNE';

  @override
  String get xenHint => 'Hold a note, then tap a scale';

  @override
  String xenHolding(String note) {
    return 'Holding $note';
  }

  @override
  String get xenNoSlots => 'no slots';

  @override
  String get xenNoTargets => 'not patched';

  @override
  String get xenMicrotonalTooltip => 'Retunes the keys it uses';

  @override
  String get xenTemperedTooltip => 'Equal-tempered — key layout only';

  @override
  String get xenFamilyWestern => 'Western';

  @override
  String get xenFamilyMaqam => 'Maqam';

  @override
  String get xenFamilyRaga => 'Raga';

  @override
  String get xenFamilyFarEast => 'Far East';

  @override
  String get xenFamilyPersian => 'Persian';

  @override
  String get xenFamilySoutheastAsia => 'SE Asia';

  @override
  String get xenFamilyAfrica => 'Africa';

  @override
  String get xenFamilyEurope => 'Europe';

  @override
  String get xenFamilyGamelan => 'Gamelan';

  @override
  String get xenFamilyTemperament => 'Temperaments';

  @override
  String get xenFamilyExperimental => 'Experimental';

  @override
  String get xenFamilyCustom => 'My Scales';

  @override
  String get xenEditorTitle => 'Scale editor';

  @override
  String get xenEditorName => 'Name';

  @override
  String get xenEditorLayout => 'Layout';

  @override
  String get xenEditorLayoutKeyboard => 'Keyboard';

  @override
  String get xenEditorLayoutLinear => 'Linear';

  @override
  String get xenEditorLayoutKeyboardHint =>
      'Each degree keeps its own key; the pattern repeats every octave.';

  @override
  String xenEditorLayoutLinearHint(int count) {
    return 'Degrees take successive keys; one period spans $count keys.';
  }

  @override
  String get xenEditorPeriod => 'Period (cents)';

  @override
  String get xenEditorKey => 'Key';

  @override
  String get xenEditorOffset => 'Offset';

  @override
  String xenEditorSounds(String cents) {
    return 'sounds $cents¢';
  }

  @override
  String get xenEditorAddDegree => 'Add degree';

  @override
  String get xenEditorRemoveDegree => 'Remove';

  @override
  String get xenEditorMute =>
      'Mute — playable and tuned, but the snap ignores it';

  @override
  String get xenEditorSeed => 'Start from';

  @override
  String get xenEditorSeedNone => 'Empty';

  @override
  String get xenEditorSave => 'Save';

  @override
  String get xenEditorCancel => 'Cancel';

  @override
  String get xenEditorImport => 'Import';

  @override
  String get xenEditorExport => 'Export';

  @override
  String get xenEditorExportJson => 'GrooveForge scale (.json)';

  @override
  String get xenEditorExportScala => 'Scala tuning (.scl)';

  @override
  String xenEditorDegreeCount(int count, int active) {
    return '$count degrees, $active active';
  }

  @override
  String get xenEditorNoDegrees =>
      'No degrees yet — add one, or start from an existing scale.';

  @override
  String get xenEditorDuplicateKeys =>
      'Two degrees share a key; the scale will use the linear layout.';

  @override
  String xenEditorImportFailed(String reason) {
    return 'Could not read that file: $reason';
  }

  @override
  String xenEditorImported(String name) {
    return 'Imported “$name”';
  }

  @override
  String xenEditorExported(String path) {
    return 'Exported to $path';
  }

  @override
  String get xenEditorDelete => 'Delete scale';

  @override
  String get xenEditorUnnamed => 'Untitled scale';

  @override
  String get xenScaleMajor => 'Major';

  @override
  String get xenScaleNaturalMinor => 'Natural Minor';

  @override
  String get xenScaleHarmonicMinor => 'Harmonic Minor';

  @override
  String get xenScaleMelodicMinor => 'Melodic Minor';

  @override
  String get xenScaleMajorPentatonic => 'Major Pentatonic';

  @override
  String get xenScaleMinorPentatonic => 'Minor Pentatonic';

  @override
  String get xenScaleBlues => 'Blues';

  @override
  String get xenScaleRock => 'Rock';

  @override
  String get xenScaleDorian => 'Dorian';

  @override
  String get xenScalePhrygian => 'Phrygian';

  @override
  String get xenScaleLydian => 'Lydian';

  @override
  String get xenScaleMixolydian => 'Mixolydian';

  @override
  String get xenScaleLocrian => 'Locrian';

  @override
  String get xenScalePhrygianDominant => 'Phrygian Dominant';

  @override
  String get xenScaleWholeTone => 'Whole Tone';

  @override
  String get xenScaleDiminished => 'Diminished';

  @override
  String get xenScaleJustIntonation => 'Just Intonation';

  @override
  String get xenScalePythagorean => 'Pythagorean';

  @override
  String get xenScaleMeantone => 'Quarter-comma Meantone';

  @override
  String get xenScaleWerckmeisterIII => 'Werckmeister III';

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
  String get drumGeneratorLoadFailed =>
      'That file is not a valid .gfdrum pattern.';

  @override
  String get drumGeneratorFormatGuide => 'Format guide';

  @override
  String get drumGeneratorIntroNone => 'None';

  @override
  String get drumGeneratorIntroCountIn1 => '1 bar';

  @override
  String get drumGeneratorIntroCountIn2 => '2 bars';

  @override
  String drumGeneratorIntroChopsticks(int hits) {
    return 'Chopsticks ($hits hits)';
  }

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
  String get drumGeneratorBreakLabel => 'Breaks';

  @override
  String get drumGeneratorBreakNone => 'None';

  @override
  String get drumGeneratorBreakRare => 'Rare';

  @override
  String get drumGeneratorBreakOccasional => 'Now and then';

  @override
  String get drumGeneratorBreakFrequent => 'Often';

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
      'A .gfdrum file is a YAML text file describing a drum pattern.\n\nStep grid notation:\nX = strong hit (~100)\nx = medium hit (~75)\no = soft hit (~55)\ng = ghost note (~28)\n. = rest\n\nVelocity fields: base_velocity, velocity_range\nTiming fields: timing_jitter, rush (in beats; negative plays ahead of the beat)\nSections: groove, fill, break, crash, intro\nSection types: loop (one variation per phrase), sequence (bars in order)\n\nThe full format is described on the website, under .gfdrum.';

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
  String get drumGeneratorFamilyMarch => 'March';

  @override
  String get drumGeneratorFamilyReggae => 'Reggae';

  @override
  String get drumGeneratorFamilyRnb => 'R&B';

  @override
  String get drumGeneratorFamilyArabic => 'Arabic';

  @override
  String get drumGeneratorFamilyTurkish => 'Turkish';

  @override
  String get drumGeneratorFamilyPersian => 'Persian';

  @override
  String get drumGeneratorFamilyIndian => 'Indian';

  @override
  String get drumGeneratorFamilyFarEast => 'Far East';

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
  String get ccDirectValueLabel => 'Value to recall';

  @override
  String get ccAssignAddValue => 'Assign a value…';

  @override
  String get ccAssignNoValues => 'Nothing assigned yet';

  @override
  String get ccAssignMoveKnobOrButton => 'Move a CC knob or press button…';

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

  @override
  String get intervalNameUnison => 'Unison';

  @override
  String get intervalNameMinor2 => 'Minor 2nd';

  @override
  String get intervalNameMajor2 => 'Major 2nd';

  @override
  String get intervalNameMinor3 => 'Minor 3rd';

  @override
  String get intervalNameMajor3 => 'Major 3rd';

  @override
  String get intervalNamePerfect4 => 'Perfect 4th';

  @override
  String get intervalNameTritone => 'Tritone';

  @override
  String get intervalNamePerfect5 => 'Perfect 5th';

  @override
  String get intervalNameMinor6 => 'Minor 6th';

  @override
  String get intervalNameMajor6 => 'Major 6th';

  @override
  String get intervalNameMinor7 => 'Minor 7th';

  @override
  String get intervalNameMajor7 => 'Major 7th';

  @override
  String get intervalNameOctave => 'Octave';

  @override
  String intervalNameOctaves(int count) {
    return '$count octaves';
  }

  @override
  String intervalNameCompound(String base, int octaves) {
    return '$base +$octaves oct';
  }

  @override
  String intervalSemitones(String semitones) {
    return '$semitones st';
  }

  @override
  String intervalTooltipAbove(String name, int semitones) {
    return '$name, $semitones semitones above the played note';
  }

  @override
  String intervalTooltipBelow(String name, int semitones) {
    return '$name, $semitones semitones below the played note';
  }

  @override
  String get intervalTooltipUnison =>
      'Unison — the same pitch as the played note';

  @override
  String get vocoderWaveSaw => 'Saw';

  @override
  String get vocoderWaveSquare => 'Square';

  @override
  String get vocoderWaveChoral => 'Choral';

  @override
  String get vocoderWaveHarmony => 'Harmony';

  @override
  String get latencyProbeTitle => 'Overdub latency';

  @override
  String get latencyProbeSubtitle =>
      'Measure how late the mic hears what the app plays';

  @override
  String get latencyProbeExplain =>
      'Plays six short sweeps through the speaker and listens for them on the microphone. Use the speaker: a microphone cannot hear headphones, and the measurement will correctly report that it found nothing.';

  @override
  String get latencyProbeStart => 'Measure';

  @override
  String get latencyProbeMeasuring => 'Measuring…';

  @override
  String get latencyProbeRoundTrip => 'Round trip';

  @override
  String get latencyProbeJitter => 'Jitter';

  @override
  String get latencyProbeConfidence => 'Confidence';

  @override
  String get latencyProbeShots => 'Usable sweeps';

  @override
  String get latencyProbeDrift => 'Clock drift';

  @override
  String get latencyProbeSkew => 'Counter skew';

  @override
  String latencyProbeDriftOverTake(String ms) {
    return 'A 4-minute take would slide $ms ms';
  }

  @override
  String latencyProbeShotsValue(int found, int total) {
    return '$found of $total';
  }

  @override
  String latencyProbeMs(String value) {
    return '$value ms';
  }

  @override
  String latencyProbeFramesSuffix(int frames) {
    return '$frames frames';
  }

  @override
  String latencyProbePpm(String value) {
    return '$value ppm';
  }

  @override
  String get latencyProbeFailed => 'No usable measurement';

  @override
  String get latencyProbeSilentInput =>
      'The microphone heard nothing. Check the microphone permission, and play through the speaker rather than headphones.';

  @override
  String get latencyProbeNeedsAudio =>
      'Audio capture is not running. Open a live input or the vocoder first.';

  @override
  String get latencyProbeHint =>
      'Keep the room quiet and hold the phone so the speaker faces the mic.';

  @override
  String get rackTabLabel => 'Rack';

  @override
  String get rehearsalsTabLabel => 'Rehearse';

  @override
  String get rehearsalsTitle => 'Rehearsals';

  @override
  String get rehearsalsEmpty => 'No rehearsals yet';

  @override
  String get rehearsalsEmptyHint =>
      'Start a tune, set the tempo, and record your part. The rest of the band can join later.';

  @override
  String get rehearsalsNew => 'Start a tune';

  @override
  String get rehearsalCreateTitle => 'New rehearsal';

  @override
  String get rehearsalFieldTitle => 'Tune';

  @override
  String get rehearsalFieldTitleHint => 'Autumn Leaves';

  @override
  String get rehearsalFieldYourName => 'Your name';

  @override
  String get rehearsalFieldInstrument => 'Your instrument';

  @override
  String get rehearsalFieldTempo => 'Tempo';

  @override
  String get rehearsalFieldTimeSignature => 'Time signature';

  @override
  String get rehearsalFieldCountIn => 'Count-in';

  @override
  String rehearsalCountInBars(int bars) {
    String _temp0 = intl.Intl.pluralLogic(
      bars,
      locale: localeName,
      other: '$bars bars',
      one: '$bars bar',
    );
    return '$_temp0';
  }

  @override
  String get rehearsalCountInNone => 'None';

  @override
  String get rehearsalCreate => 'Create';

  @override
  String get rehearsalCancel => 'Cancel';

  @override
  String rehearsalPartsProgress(int done, int total) {
    return '$done of $total parts recorded';
  }

  @override
  String rehearsalBpmValue(String bpm) {
    return '$bpm BPM';
  }

  @override
  String rehearsalMeter(int num, int den) {
    return '$num/$den';
  }

  @override
  String get rehearsalDelete => 'Delete';

  @override
  String rehearsalDeleteConfirm(String title) {
    return 'Delete \"$title\" and every recording in it?';
  }

  @override
  String get rehearsalAddPart => 'Add a part';

  @override
  String get rehearsalNotRecorded => 'Not recorded yet';

  @override
  String rehearsalTakeLength(String seconds) {
    return '${seconds}s';
  }

  @override
  String get rehearsalMetronome => 'Metronome';

  @override
  String get rehearsalPlay => 'Play';

  @override
  String get rehearsalStop => 'Stop';

  @override
  String get rehearsalRecord => 'Record';

  @override
  String get rehearsalRerecord => 'Record again';

  @override
  String get rehearsalCountingIn => 'Counting in';

  @override
  String rehearsalBarBeat(int bar, int beat) {
    return 'Bar $bar  ·  beat $beat';
  }

  @override
  String get rehearsalMute => 'Mute';

  @override
  String get rehearsalGridFrozen =>
      'Once a part is recorded, the tempo can no longer be set here: every take is aligned to it. You can still move the first beat.';

  @override
  String get rehearsalNoCompensation =>
      'Latency has not been measured on this device, so a new take may sit behind the beat.';

  @override
  String get instrumentVocals => 'Vocals';

  @override
  String get instrumentGuitar => 'Acoustic guitar';

  @override
  String get instrumentElectricGuitar => 'Electric guitar';

  @override
  String get instrumentBassGuitar => 'Bass';

  @override
  String get instrumentDrums => 'Drums';

  @override
  String get instrumentKeyboard => 'Keyboard';

  @override
  String get instrumentSynth => 'Synth';

  @override
  String get instrumentViolin => 'Violin';

  @override
  String get instrumentSaxophone => 'Saxophone';

  @override
  String get instrumentTrumpet => 'Trumpet';

  @override
  String get instrumentPercussion => 'Percussion';

  @override
  String get instrumentOther => 'Other';

  @override
  String get masterImport => 'Play along to a recording';

  @override
  String get masterImporting => 'Importing…';

  @override
  String masterImportFailed(String formats) {
    return 'That file could not be read. These formats work: $formats.';
  }

  @override
  String get masterTitle => 'Recording';

  @override
  String get masterRemove => 'Remove the recording';

  @override
  String masterRemoveConfirm(String name) {
    return 'Remove \"$name\" from this rehearsal?';
  }

  @override
  String get masterAlign => 'Set the first downbeat';

  @override
  String get masterAlignTitle => 'Align the grid';

  @override
  String get masterAlignHint =>
      'Play the recording and tap along on the beat to set the tempo, then drag the marker to the first downbeat.';

  @override
  String get masterTapTempo => 'Tap the beat';

  @override
  String get masterTapMore => 'Keep tapping…';

  @override
  String masterDownbeatAt(String time) {
    return 'First downbeat at $time';
  }

  @override
  String get masterNudgeBack => '10 ms earlier';

  @override
  String get masterNudgeForward => '10 ms later';

  @override
  String get masterCheck => 'Check two bars';

  @override
  String get masterDone => 'Done';

  @override
  String get masterVideoAudioOnly =>
      'Video files are imported for their audio only.';

  @override
  String get masterMetronomeOff =>
      'The click is off: the recording is the timing reference now.';

  @override
  String get nearbyTitle => 'Nearby';

  @override
  String get nearbyShare => 'Share this rehearsal';

  @override
  String get nearbyHint =>
      'Have the others scan this, or send them the link below.';

  @override
  String get nearbyStop => 'Stop sharing';

  @override
  String get nearbyStart => 'Start sharing';

  @override
  String get nearbyNoNetwork =>
      'This device is not on a network. Join the same Wi-Fi as the others, or turn on a hotspot.';

  @override
  String get nearbyWaiting => 'Waiting for someone to join…';

  @override
  String nearbyPeers(int count) {
    return '$count connected';
  }

  @override
  String get nearbyJoin => 'Join a rehearsal';

  @override
  String get nearbyScan => 'Scan the code';

  @override
  String get nearbyConnecting => 'Connecting…';

  @override
  String get nearbySyncing => 'Syncing…';

  @override
  String get nearbySynced => 'Up to date';

  @override
  String nearbySyncedWith(int takes) {
    return 'Received $takes parts';
  }

  @override
  String nearbyFailed(String reason) {
    return 'Could not sync: $reason';
  }

  @override
  String get nearbyWrongCode => 'That code does not match this rehearsal.';

  @override
  String get nearbyScanUnsupported =>
      'This device has no scanner. Type the code from the other device instead.';

  @override
  String nearbyHostAddress(String host, int port) {
    return '$host · port $port';
  }

  @override
  String get syncStepHandshake => 'Saying hello';

  @override
  String get syncStepManifest => 'Comparing';

  @override
  String get syncStepSending => 'Sending';

  @override
  String get syncStepReceiving => 'Receiving';

  @override
  String get syncStepDone => 'Done';

  @override
  String get nearbyLink => 'Link';

  @override
  String get nearbyCopyLink => 'Copy the link';

  @override
  String get nearbyCopied => 'Copied';

  @override
  String get nearbyLinkHint =>
      'No camera on the other device? Copy this link and send it to them — they paste it into Join.';

  @override
  String get nearbyPasteLink => 'Paste the link from the other device';

  @override
  String get nearbyPasteFromClipboard => 'Paste';

  @override
  String get nearbyLooksLikeCode =>
      'That is the short code, which is not enough on its own. Copy the whole link from the other device.';

  @override
  String get nearbyNotALink => 'That is not a GrooveForge rehearsal link.';

  @override
  String get nearbyScanTitle => 'Point the camera at the code';

  @override
  String get nearbyScanHint =>
      'Hold it steady over the code on the other device.';

  @override
  String get nearbyScanPermission =>
      'GrooveForge needs the camera to read the code. You can type the link instead.';

  @override
  String get nearbyScanOr => 'or';

  @override
  String get nearbyScanOpen => 'Scan a code';

  @override
  String get joinIdentityTitle => 'Who are you?';

  @override
  String get joinIdentityHint => 'The others will see this name on your part.';

  @override
  String get joinIdentityConfirm => 'Join';

  @override
  String get rehearsalDeleteTake => 'Delete this recording';

  @override
  String rehearsalTakeDropped(int ms) {
    return 'This take lost $ms ms of audio and will not line up with the click. Record it again.';
  }

  @override
  String get rehearsalCleanTake => 'Remove the speaker bleed';

  @override
  String get rehearsalCleaning => 'Removing the speaker…';

  @override
  String get rehearsalCleanDone =>
      'Speaker bleed removed. The original is kept beside it.';

  @override
  String get rehearsalCleanFailed =>
      'Could not remove the speaker from this take.';

  @override
  String rehearsalDeleteTakeConfirm(String instrument) {
    return 'Delete your recording of $instrument? The others will lose it too, next time you sync.';
  }

  @override
  String rehearsalOthersPart(String name) {
    return '$name\'s part';
  }

  @override
  String get rehearsalYourPart => 'Your part';

  @override
  String get liveConnected => 'Connected — parts appear as they are recorded';

  @override
  String get liveRefresh => 'Sync now';

  @override
  String get rehearsalRemovePart => 'Remove this part';

  @override
  String rehearsalRemovePartConfirm(String instrument) {
    return 'Remove your $instrument part? It disappears for everyone, along with anything recorded on it.';
  }

  @override
  String get rehearsalRecordFromRack => 'Record from the rack';

  @override
  String get rehearsalInputRack => 'Rack';

  @override
  String get rehearsalPartActions => 'More';

  @override
  String get rehearsalMemberHere => 'Here now';

  @override
  String get rehearsalMemberAway => 'Not connected';

  @override
  String get rehearsalsJoin => 'Join a tune';

  @override
  String get guideTabRehearsals => 'Rehearsals';

  @override
  String get guideRehearsalIntroTitle => 'Rehearsing together';

  @override
  String get guideRehearsalIntroBody =>
      'The Rehearse tab is for a band learning a tune. Everyone records their own part over a shared click, on their own device, and every device ends up with all the parts.\n\nNothing is uploaded anywhere. The devices talk straight to each other, so a rehearsal works in a room with no internet at all.';

  @override
  String get guideRehearsalStartTitle => 'Starting a tune';

  @override
  String get guideRehearsalStartBody =>
      'Start a tune, give it a name, and say what you play. Set the tempo and the time signature, or tap the beat if you would rather feel it than count it.\n\nTo play along to a recording, import it as the master track: MP3, FLAC and WAV everywhere, and on Android also M4A, AAC and the sound of a video. Then tap along to the beat and drag the marker onto the first downbeat, so the bars line up with the music. The click then switches off: the recording sets the tempo.';

  @override
  String get guideRehearsalRecordTitle => 'Recording your part';

  @override
  String get guideRehearsalRecordBody =>
      'Add a part for your instrument and press record. A count-in plays first, two bars by default, and recording starts on the downbeat.\n\nEvery device takes a moment to play sound and another to record it, which would put your take late against the others. The app measures that delay on your device and moves your take back by it, so what you played on the beat lands on the beat. Measure it once with Calibrate in the tune, or from Preferences, and again when you change headphones or switch to a Bluetooth speaker: the delay belongs to the gear, not to the tune.\n\nYou record your own parts and nobody else\'s. Yours can be re-recorded or deleted as often as you like.';

  @override
  String get guideRehearsalMonitoringNote =>
      'Record with headphones, or with an external microphone kept away from the speaker. Through the built-in speaker, the microphone hears the click and the parts already recorded, and they all end up in your take.';

  @override
  String get guideRehearsalShareTitle => 'Getting the band together';

  @override
  String get guideRehearsalShareBody =>
      'The first time, one person opens the tune and taps the share icon; the others join from the Rehearse tab, with Join a tune: on a phone they scan the code, on a computer they paste the link. After that, the devices know each other: opening the same tune is enough, and they find each other within a few seconds.\n\nA dot next to each part shows whether its player is connected. What you record reaches everyone in the room as soon as you stop, and what you missed while away arrives the next time you are all together.';

  @override
  String get guideRehearsalHotspotTitle => 'When there is no Wi-Fi';

  @override
  String get guideRehearsalHotspotBody =>
      'Everyone has to be on the same network. Phones on mobile data cannot see each other, and rehearsal rooms rarely have usable Wi-Fi, so one person makes the network:\n\n1. One phone turns on its personal hotspot, in the phone\'s own settings (usually under Connections or Network).\n2. Everyone else joins that hotspot from their Wi-Fi settings, like any network.\n3. Everyone opens the tune. The devices find each other within a few seconds.\n\nIt does not have to be the same person every time: if the usual host is away, anybody else turns theirs on and the rest join it. There is nothing to scan again.';

  @override
  String get guideRehearsalHotspotNote =>
      'Sharing parts uses no mobile data: it never leaves the room. Some phones ask to turn mobile data on before sharing a hotspot, but the rehearsal itself does not use any.';

  @override
  String get rehearsalTakePending => 'Not sent yet';

  @override
  String get rehearsalSyncIncomplete =>
      'Stay connected: not everyone has the latest takes yet.';

  @override
  String get rehearsalTakeAwaitingAudio => 'Waiting for audio';

  @override
  String get rehearsalTempoTitle => 'Tempo';

  @override
  String get rehearsalTuneTempo => 'Tune tempo';

  @override
  String get rehearsalTuneTempoHint =>
      'Shared with the band. Recordings are re-rendered to match.';

  @override
  String get rehearsalPracticeSpeed => 'Practice speed';

  @override
  String get rehearsalPracticeSpeedHint =>
      'Only on this device. Slow a passage down without changing pitch.';

  @override
  String rehearsalPracticeSpeedValue(int percent) {
    return '$percent%';
  }

  @override
  String get rehearsalRendering => 'Adjusting the recordings…';

  @override
  String get rehearsalMeterFrozen =>
      'Metre locked: a part is already recorded against it.';

  @override
  String get rehearsalCalibrate => 'Calibrate';

  @override
  String get rehearsalCalibrateTitle => 'Measure this device';

  @override
  String get rehearsalCalibrateBody =>
      'Your device takes a moment to play sound, and another to capture it. Together that delay would put every take behind the beat, so it is measured once and subtracted from what you record.\n\nThe measurement plays a few short sweeps and listens for them coming back through the microphone — so it has to be able to hear them:\n\n•  Use the speaker, not headphones. On headphones the microphone hears nothing and the measurement fails.\n•  Turn the volume up.\n•  Keep the room quiet for the few seconds it takes.\n\nMeasure again after switching to a Bluetooth speaker or headset: the delay belongs to the gear, not to the tune, and Bluetooth adds a great deal of it.';

  @override
  String get rehearsalCalibrateStart => 'Measure now';

  @override
  String get rehearsalRemoveMember => 'Remove this player';

  @override
  String rehearsalRemoveMemberConfirm(String name, int count) {
    return 'Remove $name from this tune? Their $count recording(s) go too, on every device.';
  }

  @override
  String get rehearsalRemoveMemberHere =>
      'For a device that is gone for good. Their parts go too.';

  @override
  String get rehearsalDocuments => 'Scores';

  @override
  String get rehearsalDocumentsEmpty => 'No scores yet';

  @override
  String get rehearsalDocumentsEmptyHint =>
      'Add a score, a chart or a photo of one. Everyone in the tune gets a copy.';

  @override
  String get rehearsalDocumentAdd => 'Add a score';

  @override
  String get rehearsalDocumentRemove => 'Remove';

  @override
  String rehearsalDocumentRemoveConfirm(String name) {
    return 'Remove \"$name\" from this tune? It goes from every device.';
  }

  @override
  String rehearsalDocumentAddedBy(String name) {
    return 'Added by $name';
  }

  @override
  String rehearsalDocumentSize(int kb) {
    return '$kb kB';
  }

  @override
  String get rehearsalDocumentWaiting => 'Waiting for the file';

  @override
  String get rehearsalDocumentNoViewer =>
      'Nothing on this device can open that file.';

  @override
  String get rehearsalChordGrid => 'Chords';

  @override
  String get rehearsalChordGridEmpty => 'Write the chords';

  @override
  String get rehearsalChordAddBar => 'Add a bar';

  @override
  String get rehearsalChordRemoveBar => 'Remove this bar';

  @override
  String rehearsalChordBar(int bar) {
    return 'Bar $bar';
  }

  @override
  String get rehearsalChordSlots => 'Chords per bar';

  @override
  String get rehearsalChordHint => 'Am7, C#m7, Gm7b5, C6/9, Am(M7)/B…';

  @override
  String get rehearsalChordInvalid => 'Not a chord I can read';

  @override
  String get rehearsalChordExpand => 'Show the whole chart';

  @override
  String get rehearsalChordCollapse => 'Collapse to one line';

  @override
  String get rehearsalChordClear => 'Clear';

  @override
  String get rehearsalChordSave => 'Save';

  @override
  String rehearsalChordBarCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bars',
      one: '1 bar',
    );
    return '$_temp0';
  }

  @override
  String rehearsalRouteUncalibrated(String device) {
    return '$device has not been measured. A take recorded through it will sit well behind the beat.';
  }

  @override
  String get rehearsalRouteBluetoothHint =>
      'Bluetooth adds a long delay of its own, and it differs from one headset to the next.\n\nThe microphone cannot hear your headphones through the air, so hold one earcup against the phone\'s microphone while the measurement runs. That way it hears the sweeps coming back through the headset and measures the real delay, Bluetooth and all.';

  @override
  String get rehearsalRouteWiredHint =>
      'Wired headphones are plugged in, so the sweeps play in the headphones, not through the speaker.\n\nHold one earcup against the phone\'s microphone while the measurement runs, and keep the room quiet. If your headphones have their own microphone, hold the earcup against that one instead.';

  @override
  String get audioRouteWired => 'Your wired headset';

  @override
  String get masterZoomIn => 'Zoom in';

  @override
  String get masterZoomOut => 'Zoom out';

  @override
  String get masterZoomReset => 'Whole recording';

  @override
  String get masterSkipSilence => 'Skip the silence';

  @override
  String get masterBpmFiner => 'Slower by 0.1';

  @override
  String get masterBpmFaster => 'Faster by 0.1';

  @override
  String masterZoomLevel(int zoom) {
    return '×$zoom';
  }

  @override
  String get masterBeatLinesHint =>
      'The red lines are the beats. Zoom in and adjust the tempo until they land on the sound.';

  @override
  String get rehearsalTempoFromMaster =>
      'Set by the recording — change it on the grid alignment screen.';

  @override
  String get patchViewBackTooltip => 'Back to the front panels';

  @override
  String get audioOutputPathTitle => 'Audio output path';

  @override
  String audioOutputPathFast(String ms) {
    return 'Low latency ($ms ms buffer).';
  }

  @override
  String audioOutputPathFastShared(String ms) {
    return 'Low latency, shared endpoint ($ms ms buffer). A few milliseconds dearer than exclusive; nothing to do.';
  }

  @override
  String get audioOutputPathSlow =>
      'Slow path: Android refused low latency for this stream. Changing output device may get it back.';

  @override
  String get audioOutputPathLatched =>
      'Slow path, locked for this session: GrooveForge gave up low latency after the phone\'s audio service failed on it. Playing will feel delayed — around a quarter of a second — until you restore it below.';

  @override
  String get audioOutputPathUsbDirect =>
      'Direct USB output is driving the sound, so Android\'s latency does not apply.';

  @override
  String get audioOutputPathNoStream => 'No audio stream open yet.';

  @override
  String get audioOutputPathRestore => 'Restore low latency';

  @override
  String get audioOutputPathRestoring => 'Reopening the audio stream…';

  @override
  String get audioOutputPathRestoreFailed =>
      'Low latency is still refused. Restarting GrooveForge clears it; if it comes back at once, this phone\'s audio service is failing on the fast path.';

  @override
  String get audioOutputPathIndicatorTooltip =>
      'Audio is delayed — tap for details';

  @override
  String get audioOutputPathRestartHint =>
      'Force-quitting GrooveForge also clears this, and is the fastest fix if you are on stage.';

  @override
  String get ccReleaseValueTitle => 'Neutral value on release';

  @override
  String get ccReleaseValueHelp =>
      'For ribbons and touch strips that jump back to 0 when you lift your finger. Leave off for knobs, faders, wheels, pedals and pads. If your controller has a hold or latch mode, use it to keep the last value.';

  @override
  String ccReleaseValueLabel(int value) {
    return 'Value: $value';
  }

  @override
  String ccReleaseValueSummary(int value) {
    return 'returns to $value on release';
  }

  @override
  String ccReleaseValueDialogTitle(int cc) {
    return 'CC $cc: release';
  }

  @override
  String get guideTabStart => 'Start here';

  @override
  String get guideTabModules => 'Modules';

  @override
  String get guideRulesTitle => 'How sound moves between modules';

  @override
  String get guideRulesIntro =>
      'Tap the cable icon at the top of the rack to see the back of your modules. That is where you connect them with cables.';

  @override
  String get guideRuleInstrument =>
      'An instrument plays through the speakers on its own. You do not need a cable to hear it.';

  @override
  String get guideRuleColours =>
      'Yellow cables carry notes (MIDI), from a keyboard to an instrument. Red and white cables carry sound, left and right.';

  @override
  String get guideRuleEffect =>
      'To put an effect after an instrument, cable the instrument\'s AUDIO OUT L and R into the effect\'s AUDIO IN L and R. What comes out of the effect goes to the speakers.';

  @override
  String get guideRuleDraw =>
      'To draw a cable, long-press a socket and drag it to another one. Sockets that accept it light up while you drag.';

  @override
  String get guideWatchClip => 'Watch the clip';

  @override
  String get guideRecipeScaleTitle => 'Play in a scale';

  @override
  String get guideRecipeScaleSteps =>
      'Every new project has a keyboard and a Xen module.\nHold a key and tap a scale, for example Blues. Xen switches on, and the key you hold becomes the root note.\nOpen Family for other traditions: maqamat, ragas, Japanese scales and more.';

  @override
  String get guideRecipeScaleResult =>
      'Grey keys are outside the scale: press one and you hear the nearest note that fits.';

  @override
  String get guideRecipeEffectTitle => 'Add an effect to your keyboard';

  @override
  String get guideRecipeEffectSteps =>
      'Tap + and pick an effect, for example Reverb.\nTap the cable icon at the top.\nLong-press the keyboard\'s red AUDIO OUT L and drag it to the effect\'s AUDIO IN L. Then the white R to R.\nTap the back arrow and play.';

  @override
  String get guideRecipeEffectResult =>
      'You hear the keyboard through the effect. Turn its knobs to change the sound.';

  @override
  String get guideRecipeRemoveTitle => 'Remove a cable or a module';

  @override
  String get guideRecipeRemoveSteps =>
      'A cable: in the cable view, tap the small ✕ in the middle of the cable, then Disconnect.\nA module: tap the bin icon at the top of the module, then Remove. Its cables go with it.';

  @override
  String get guideRecipeRemoveResult => '';

  @override
  String get guideRecipeGuitarTitle => 'Play the guitar from the keyboard';

  @override
  String get guideRecipeGuitarSteps =>
      'Tap + and pick Riff.\nIn the cable view, drag the keyboard\'s yellow MIDI OUT to Riff\'s MIDI IN.\nPlay: you hear the piano and the guitar together.\nTo hear only the guitar, set the keyboard\'s sound menu to None (MIDI only).';

  @override
  String get guideRecipeGuitarResult =>
      'Riff has no keys of its own: the keyboard sends it the notes.';

  @override
  String get guideRecipeAmpTitle => 'Put the guitar through the amp';

  @override
  String get guideRecipeAmpSteps =>
      'Tap + and pick Amp.\nIn the cable view, drag Riff\'s AUDIO OUT L to the Amp\'s AUDIO IN L, then R to R.\nPlay, and turn Drive on the Amp.';

  @override
  String get guideRecipeAmpResult =>
      'The clean guitar gets crunchy or distorted.';

  @override
  String get guideRecipeControllerTitle => 'Connect a MIDI controller';

  @override
  String get guideRecipeControllerSteps =>
      'Plug it in over USB (with an OTG adapter on a phone), or switch on a Bluetooth MIDI controller.\nOpen Preferences with the gear icon.\nUnder MIDI Connection, tap Connect MIDI Device and pick it.';

  @override
  String get guideRecipeControllerResult =>
      'It plays the module whose MIDI CH badge matches the channel it sends on, usually 1.';

  @override
  String get guideRecipeLearnTitle => 'Map a knob';

  @override
  String get guideRecipeLearnSteps =>
      'Tap the sliders icon at the top of a module.\nTap Learn next to a control, for example Palm mute.\nMove a knob or press a pad on your controller.';

  @override
  String get guideRecipeLearnResult =>
      'The control now follows your hardware. The mapping is saved with the project.';

  @override
  String get guideRecipeDrumsTitle => 'Start a drum beat';

  @override
  String get guideRecipeDrumsSteps =>
      'Tap + and pick Drum Generator.\nPick a pattern from the menu.\nSwitch Active on and press play at the top.';

  @override
  String get guideRecipeDrumsResult =>
      'The beat follows the tempo in the transport bar.';

  @override
  String get guideRecipeLoopTitle => 'Record a loop';

  @override
  String get guideRecipeLoopSteps =>
      'Tap + and pick Audio Looper.\nIn the cable view, cable the keyboard\'s AUDIO OUT L and R into the looper\'s AUDIO IN L and R.\nPress the looper\'s record button. Recording starts on the first beat of the next bar.\nPlay, then press it again: recording stops at the end of the bar and the loop plays. Press it once more to add a layer.';

  @override
  String get guideRecipeLoopResult =>
      'If the tempo was stopped, it starts and gives you one bar to get ready.';

  @override
  String get guideRecipeProjectsTitle => 'Save and open projects';

  @override
  String get guideRecipeProjectsSteps =>
      'Tap the folder icon at the top.\nSave As… writes your modules, cables and settings to a .gf file.\nNew Project starts over with a keyboard and Xen. Anything not saved is lost.\nOpen Project loads a saved file.';

  @override
  String get guideRecipeProjectsResult =>
      'The app also keeps your current session between launches, except in the web demo.';

  @override
  String get guideModulesIntro =>
      'Everything the + button at the bottom of the rack can add. Drag the handle on the left of a module to move it.';

  @override
  String get guideVocoderNote =>
      'Use wired headphones or speakers: Bluetooth adds too much delay to sing live.';

  @override
  String get guideJackLegendTitle => 'Socket colours';

  @override
  String get guideJackMidi => 'notes and controls (MIDI)';

  @override
  String get guideJackAudioL => 'sound, left';

  @override
  String get guideJackAudioR => 'sound, right';

  @override
  String get guideJackSend => 'effects loop';

  @override
  String get guideJackData => 'the scale and the current chord';

  @override
  String get guideJackTune => 'tuning for scales between the piano keys';

  @override
  String get guideMidiHardwareStep3 =>
      'It plays the module whose MIDI CH badge matches the channel it sends on, usually 1. Tap the badge on a module to change its channel.';
}
