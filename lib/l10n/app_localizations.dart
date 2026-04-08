import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'GrooveForge Synth'**
  String get appTitle;

  /// No description provided for @loadingText.
  ///
  /// In en, this message translates to:
  /// **'Initializing Synth Engine...'**
  String get loadingText;

  /// No description provided for @preferencesTitle.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferencesTitle;

  /// No description provided for @midiConnectionSection.
  ///
  /// In en, this message translates to:
  /// **'MIDI Connection'**
  String get midiConnectionSection;

  /// No description provided for @connectMidiDevice.
  ///
  /// In en, this message translates to:
  /// **'Connect MIDI Device'**
  String get connectMidiDevice;

  /// No description provided for @notConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get notConnected;

  /// No description provided for @selectMidiDeviceDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Select MIDI Device'**
  String get selectMidiDeviceDialogTitle;

  /// No description provided for @midiNewDeviceDetected.
  ///
  /// In en, this message translates to:
  /// **'New MIDI Device Detected'**
  String get midiNewDeviceDetected;

  /// No description provided for @midiConnectNewDevicePrompt.
  ///
  /// In en, this message translates to:
  /// **'Connect to {deviceName}?'**
  String midiConnectNewDevicePrompt(String deviceName);

  /// No description provided for @actionConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get actionConnect;

  /// No description provided for @actionIgnore.
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get actionIgnore;

  /// No description provided for @soundfontsSection.
  ///
  /// In en, this message translates to:
  /// **'Soundfonts'**
  String get soundfontsSection;

  /// No description provided for @loadSoundfont.
  ///
  /// In en, this message translates to:
  /// **'Load Soundfont (.sf2)'**
  String get loadSoundfont;

  /// No description provided for @noSoundfontsLoaded.
  ///
  /// In en, this message translates to:
  /// **'No soundfonts loaded.'**
  String get noSoundfontsLoaded;

  /// No description provided for @defaultSoundfont.
  ///
  /// In en, this message translates to:
  /// **'Default soundfont'**
  String get defaultSoundfont;

  /// No description provided for @routingControlSection.
  ///
  /// In en, this message translates to:
  /// **'Routing & Control'**
  String get routingControlSection;

  /// No description provided for @ccMappingPreferences.
  ///
  /// In en, this message translates to:
  /// **'CC Mapping Preferences'**
  String get ccMappingPreferences;

  /// No description provided for @ccMappingPreferencesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Map hardware knobs to GM Effects and System Actions'**
  String get ccMappingPreferencesSubtitle;

  /// No description provided for @keyGesturesSection.
  ///
  /// In en, this message translates to:
  /// **'Key Gestures'**
  String get keyGesturesSection;

  /// No description provided for @verticalInteraction.
  ///
  /// In en, this message translates to:
  /// **'Vertical Interaction (default)'**
  String get verticalInteraction;

  /// No description provided for @verticalInteractionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Swipe up/down on a key — overridable per slot'**
  String get verticalInteractionSubtitle;

  /// No description provided for @horizontalInteraction.
  ///
  /// In en, this message translates to:
  /// **'Horizontal Interaction (default)'**
  String get horizontalInteraction;

  /// No description provided for @horizontalInteractionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Slide left/right on a key — overridable per slot'**
  String get horizontalInteractionSubtitle;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get actionSave;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @chNumber.
  ///
  /// In en, this message translates to:
  /// **'CH {channel}'**
  String chNumber(int channel);

  /// No description provided for @patchLoadSoundfont.
  ///
  /// In en, this message translates to:
  /// **'Load a soundfont from preferences'**
  String get patchLoadSoundfont;

  /// No description provided for @patchDefaultSoundfont.
  ///
  /// In en, this message translates to:
  /// **'Default soundfont'**
  String get patchDefaultSoundfont;

  /// No description provided for @patchSoundfontNoneMidiOnly.
  ///
  /// In en, this message translates to:
  /// **'None (MIDI only)'**
  String get patchSoundfontNoneMidiOnly;

  /// No description provided for @rackSlotKeyboardMidiOnlyShort.
  ///
  /// In en, this message translates to:
  /// **'MIDI only'**
  String get rackSlotKeyboardMidiOnlyShort;

  /// No description provided for @patchUnknownProgram.
  ///
  /// In en, this message translates to:
  /// **'Unknown Program {program}'**
  String patchUnknownProgram(int program);

  /// No description provided for @patchBank.
  ///
  /// In en, this message translates to:
  /// **'Bank {bank}'**
  String patchBank(int bank);

  /// No description provided for @ccTitle.
  ///
  /// In en, this message translates to:
  /// **'CC Mapping Preferences'**
  String get ccTitle;

  /// No description provided for @ccActiveMappings.
  ///
  /// In en, this message translates to:
  /// **'Active Mappings'**
  String get ccActiveMappings;

  /// No description provided for @ccAddMapping.
  ///
  /// In en, this message translates to:
  /// **'Add Mapping'**
  String get ccAddMapping;

  /// No description provided for @ccWaitingForEvents.
  ///
  /// In en, this message translates to:
  /// **'Waiting for incoming MIDI events...'**
  String get ccWaitingForEvents;

  /// No description provided for @ccLastEventCC.
  ///
  /// In en, this message translates to:
  /// **'Last Event: CC {cc} (Value: {val})'**
  String ccLastEventCC(int cc, int val);

  /// No description provided for @ccLastEventNote.
  ///
  /// In en, this message translates to:
  /// **'Last Event: {type} Note {note} (Velocity: {velocity})'**
  String ccLastEventNote(String type, int note, int velocity);

  /// No description provided for @ccReceivedOnChannel.
  ///
  /// In en, this message translates to:
  /// **'Received on Channel {channel}'**
  String ccReceivedOnChannel(int channel);

  /// No description provided for @ccInstructions.
  ///
  /// In en, this message translates to:
  /// **'Move a slider or play a note on your MIDI hardware controller to instantly identify its internal event data here.'**
  String get ccInstructions;

  /// No description provided for @ccNoMappings.
  ///
  /// In en, this message translates to:
  /// **'No custom mappings defined.\nClick below to add one.'**
  String get ccNoMappings;

  /// No description provided for @ccUnknownSequence.
  ///
  /// In en, this message translates to:
  /// **'CC {cc}'**
  String ccUnknownSequence(int cc);

  /// No description provided for @ccRoutingAllChannels.
  ///
  /// In en, this message translates to:
  /// **'All Channels'**
  String get ccRoutingAllChannels;

  /// No description provided for @ccRoutingSameAsIncoming.
  ///
  /// In en, this message translates to:
  /// **'Same as Incoming'**
  String get ccRoutingSameAsIncoming;

  /// No description provided for @ccRoutingChannel.
  ///
  /// In en, this message translates to:
  /// **'Channel {channel}'**
  String ccRoutingChannel(int channel);

  /// No description provided for @ccMappingHardwareToTarget.
  ///
  /// In en, this message translates to:
  /// **'Hardware CC {incoming} ➔ Mapped to {targetName}'**
  String ccMappingHardwareToTarget(int incoming, String targetName);

  /// No description provided for @ccMappingRouting.
  ///
  /// In en, this message translates to:
  /// **'Routing: {channelStr}'**
  String ccMappingRouting(String channelStr);

  /// No description provided for @ccNewMappingTitle.
  ///
  /// In en, this message translates to:
  /// **'New CC Mapping'**
  String get ccNewMappingTitle;

  /// No description provided for @ccIncomingLabel.
  ///
  /// In en, this message translates to:
  /// **'Incoming Hardware CC (e.g., 20)'**
  String get ccIncomingLabel;

  /// No description provided for @ccTargetEffectLabel.
  ///
  /// In en, this message translates to:
  /// **'Target GM Effect'**
  String get ccTargetEffectLabel;

  /// No description provided for @ccTargetChannelLabel.
  ///
  /// In en, this message translates to:
  /// **'Target Channel'**
  String get ccTargetChannelLabel;

  /// No description provided for @ccSaveBinding.
  ///
  /// In en, this message translates to:
  /// **'Save Binding'**
  String get ccSaveBinding;

  /// No description provided for @ccMuteChannelsLabel.
  ///
  /// In en, this message translates to:
  /// **'Channels to mute/unmute'**
  String get ccMuteChannelsLabel;

  /// No description provided for @ccMuteChannelsSummary.
  ///
  /// In en, this message translates to:
  /// **'Channels: {channels}'**
  String ccMuteChannelsSummary(String channels);

  /// No description provided for @ccMuteNoChannels.
  ///
  /// In en, this message translates to:
  /// **'No channels selected'**
  String get ccMuteNoChannels;

  /// No description provided for @ccTargetEffectFormat.
  ///
  /// In en, this message translates to:
  /// **'{name} (CC {cc})'**
  String ccTargetEffectFormat(String name, int cc);

  /// No description provided for @actionNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get actionNone;

  /// No description provided for @actionPitchBend.
  ///
  /// In en, this message translates to:
  /// **'Pitch Bend'**
  String get actionPitchBend;

  /// No description provided for @actionVibrato.
  ///
  /// In en, this message translates to:
  /// **'Vibrato'**
  String get actionVibrato;

  /// No description provided for @actionGlissando.
  ///
  /// In en, this message translates to:
  /// **'Glissando'**
  String get actionGlissando;

  /// No description provided for @virtualPianoDisplaySection.
  ///
  /// In en, this message translates to:
  /// **'Virtual Piano Display'**
  String get virtualPianoDisplaySection;

  /// No description provided for @visibleKeysTitle.
  ///
  /// In en, this message translates to:
  /// **'Default Key Count'**
  String get visibleKeysTitle;

  /// No description provided for @visibleKeysSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Number of white keys shown when no per-slot override is set'**
  String get visibleKeysSubtitle;

  /// No description provided for @keys25.
  ///
  /// In en, this message translates to:
  /// **'25 keys (15 white)'**
  String get keys25;

  /// No description provided for @keys37.
  ///
  /// In en, this message translates to:
  /// **'37 keys (22 white)'**
  String get keys37;

  /// No description provided for @keys49.
  ///
  /// In en, this message translates to:
  /// **'49 keys (29 white)'**
  String get keys49;

  /// No description provided for @keys88.
  ///
  /// In en, this message translates to:
  /// **'88 keys (52 white)'**
  String get keys88;

  /// No description provided for @notationFormatTitle.
  ///
  /// In en, this message translates to:
  /// **'Music Notation Format'**
  String get notationFormatTitle;

  /// No description provided for @notationFormatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How chord names are displayed'**
  String get notationFormatSubtitle;

  /// No description provided for @notationStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard (C, D, E)'**
  String get notationStandard;

  /// No description provided for @notationSolfege.
  ///
  /// In en, this message translates to:
  /// **'Solfège (Do, Ré, Mi)'**
  String get notationSolfege;

  /// No description provided for @prefAboutMadeWith.
  ///
  /// In en, this message translates to:
  /// **'Made with Flutter in Paris 🇫🇷'**
  String get prefAboutMadeWith;

  /// No description provided for @splashStartingEngine.
  ///
  /// In en, this message translates to:
  /// **'Starting audio engine...'**
  String get splashStartingEngine;

  /// No description provided for @splashLoadingPreferences.
  ///
  /// In en, this message translates to:
  /// **'Loading preferences...'**
  String get splashLoadingPreferences;

  /// No description provided for @splashStartingFluidSynth.
  ///
  /// In en, this message translates to:
  /// **'Starting FluidSynth backend...'**
  String get splashStartingFluidSynth;

  /// No description provided for @splashRestoringState.
  ///
  /// In en, this message translates to:
  /// **'Restoring saved state...'**
  String get splashRestoringState;

  /// No description provided for @splashCheckingSoundfonts.
  ///
  /// In en, this message translates to:
  /// **'Checking bundled soundfonts...'**
  String get splashCheckingSoundfonts;

  /// No description provided for @splashExtractingSoundfont.
  ///
  /// In en, this message translates to:
  /// **'Extracting default soundfont...'**
  String get splashExtractingSoundfont;

  /// No description provided for @splashReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get splashReady;

  /// No description provided for @synthTooltipUserGuide.
  ///
  /// In en, this message translates to:
  /// **'User Guide'**
  String get synthTooltipUserGuide;

  /// No description provided for @synthTooltipSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings & Setup'**
  String get synthTooltipSettings;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @aftertouchEffectTitle.
  ///
  /// In en, this message translates to:
  /// **'Aftertouch Effect (default)'**
  String get aftertouchEffectTitle;

  /// No description provided for @aftertouchEffectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Route keyboard pressure to this CC — overridable per slot'**
  String get aftertouchEffectSubtitle;

  /// No description provided for @aboutSection.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutSection;

  /// No description provided for @versionTitle.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get versionTitle;

  /// No description provided for @viewChangelogTitle.
  ///
  /// In en, this message translates to:
  /// **'View Changelog'**
  String get viewChangelogTitle;

  /// No description provided for @viewChangelogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'History of changes and updates'**
  String get viewChangelogSubtitle;

  /// No description provided for @changelogDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Changelog'**
  String get changelogDialogTitle;

  /// No description provided for @closeButton.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeButton;

  /// No description provided for @errorLoadingChangelog.
  ///
  /// In en, this message translates to:
  /// **'Error loading changelog.'**
  String get errorLoadingChangelog;

  /// No description provided for @resetPreferencesButton.
  ///
  /// In en, this message translates to:
  /// **'Reset All Preferences'**
  String get resetPreferencesButton;

  /// No description provided for @resetPreferencesDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset All Preferences?'**
  String get resetPreferencesDialogTitle;

  /// No description provided for @resetPreferencesDialogBody.
  ///
  /// In en, this message translates to:
  /// **'This will clear all your settings, loaded soundfonts, and custom assignments. This action cannot be undone.'**
  String get resetPreferencesDialogBody;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// Generic confirm/OK button label used in dialogs
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get confirmButton;

  /// Title for the fallback file picker dialog when the native file chooser is unavailable
  ///
  /// In en, this message translates to:
  /// **'Select File'**
  String get selectFile;

  /// Title for the fallback directory picker dialog when the native file chooser is unavailable
  ///
  /// In en, this message translates to:
  /// **'Select Directory'**
  String get selectDirectory;

  /// Label shown in the fallback file picker dialog indicating which file extensions are accepted
  ///
  /// In en, this message translates to:
  /// **'Allowed types'**
  String get filePickerAllowedTypes;

  /// No description provided for @resetEverythingButton.
  ///
  /// In en, this message translates to:
  /// **'Reset Everything'**
  String get resetEverythingButton;

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// No description provided for @languageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'App interface language'**
  String get languageSubtitle;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get languageFrench;

  /// No description provided for @guideTitle.
  ///
  /// In en, this message translates to:
  /// **'User Guide'**
  String get guideTitle;

  /// No description provided for @guideTabFeatures.
  ///
  /// In en, this message translates to:
  /// **'Features'**
  String get guideTabFeatures;

  /// No description provided for @guideTabMidi.
  ///
  /// In en, this message translates to:
  /// **'MIDI Connectivity'**
  String get guideTabMidi;

  /// No description provided for @guideTabSoundfonts.
  ///
  /// In en, this message translates to:
  /// **'Soundfonts'**
  String get guideTabSoundfonts;

  /// No description provided for @guideTabTips.
  ///
  /// In en, this message translates to:
  /// **'Musical Tips'**
  String get guideTabTips;

  /// No description provided for @guideTabPatch.
  ///
  /// In en, this message translates to:
  /// **'Rack & Cables'**
  String get guideTabPatch;

  /// No description provided for @guidePatchRackTitle.
  ///
  /// In en, this message translates to:
  /// **'The Rack'**
  String get guidePatchRackTitle;

  /// No description provided for @guidePatchRackBody.
  ///
  /// In en, this message translates to:
  /// **'The rack is the heart of GrooveForge. Each row is a slot — an independent instrument or effect processor. Add slots with the + button, remove them with the trash icon, and reorder them by dragging the handle on the left side of each slot.'**
  String get guidePatchRackBody;

  /// No description provided for @guidePatchSlotTypesTitle.
  ///
  /// In en, this message translates to:
  /// **'Slot Types'**
  String get guidePatchSlotTypesTitle;

  /// No description provided for @guidePatchSlotKeyboard.
  ///
  /// In en, this message translates to:
  /// **'Keyboard'**
  String get guidePatchSlotKeyboard;

  /// No description provided for @guidePatchSlotKeyboardDesc.
  ///
  /// In en, this message translates to:
  /// **'Built-in FluidSynth driven by a soundfont (.sf2). Play from the on-screen keyboard or external MIDI. Choose None as the soundfont to use the keyboard as a MIDI-only controller (MIDI OUT cables in patch view, no built-in synth).'**
  String get guidePatchSlotKeyboardDesc;

  /// No description provided for @guidePatchSlotVocoder.
  ///
  /// In en, this message translates to:
  /// **'Vocoder'**
  String get guidePatchSlotVocoder;

  /// No description provided for @guidePatchSlotVocoderDesc.
  ///
  /// In en, this message translates to:
  /// **'Processes microphone audio through a carrier wave for voice-synth effects.'**
  String get guidePatchSlotVocoderDesc;

  /// No description provided for @guidePatchSlotJam.
  ///
  /// In en, this message translates to:
  /// **'Jam Mode'**
  String get guidePatchSlotJam;

  /// No description provided for @guidePatchSlotJamDesc.
  ///
  /// In en, this message translates to:
  /// **'Harmony engine that snaps incoming MIDI notes to a scale in real time. Receives chord information from a master keyboard slot.'**
  String get guidePatchSlotJamDesc;

  /// No description provided for @guidePatchSlotVst3.
  ///
  /// In en, this message translates to:
  /// **'VST3 Plugin'**
  String get guidePatchSlotVst3;

  /// No description provided for @guidePatchSlotVst3Desc.
  ///
  /// In en, this message translates to:
  /// **'Load any third-party VST3 instrument or effect. Requires a compatible .vst3 bundle installed on your system.'**
  String get guidePatchSlotVst3Desc;

  /// No description provided for @guidePatchSlotVst3DesktopOnly.
  ///
  /// In en, this message translates to:
  /// **'VST3 plugin slots are available on desktop platforms only (Linux, macOS, Windows). They are not available on Android or iOS.'**
  String get guidePatchSlotVst3DesktopOnly;

  /// No description provided for @guidePatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Cable Patching'**
  String get guidePatchTitle;

  /// No description provided for @guidePatchIntro.
  ///
  /// In en, this message translates to:
  /// **'The patch view lets you see the back panel of every slot in your rack and draw virtual cables between jacks, just like on a real hardware rack. Tap the cable icon in the top app bar to toggle between the front view (playing) and the back view (patching).'**
  String get guidePatchIntro;

  /// No description provided for @guidePatchToggleTitle.
  ///
  /// In en, this message translates to:
  /// **'Toggling Patch View'**
  String get guidePatchToggleTitle;

  /// No description provided for @guidePatchToggleBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the cable icon (⊡) in the top-right of the rack screen to switch to the back panel view. Tap it again (or the agenda icon) to return to the front view. Slot reordering is disabled while in patch view.'**
  String get guidePatchToggleBody;

  /// No description provided for @guidePatchJacksTitle.
  ///
  /// In en, this message translates to:
  /// **'Jack Types'**
  String get guidePatchJacksTitle;

  /// No description provided for @guidePatchJacksBody.
  ///
  /// In en, this message translates to:
  /// **'Each slot exposes a set of jacks grouped by signal family:\n• MIDI (yellow) — MIDI IN / MIDI OUT for note and CC messages.\n• Audio (red / white / orange) — AUDIO IN L, AUDIO IN R, AUDIO OUT L, AUDIO OUT R for stereo audio; SEND / RETURN for effects loops.\n• Data (purple) — CHORD OUT/IN and SCALE OUT/IN for Jam Mode harmony routing.'**
  String get guidePatchJacksBody;

  /// No description provided for @guidePatchDrawTitle.
  ///
  /// In en, this message translates to:
  /// **'Drawing a Cable'**
  String get guidePatchDrawTitle;

  /// No description provided for @guidePatchDrawBody.
  ///
  /// In en, this message translates to:
  /// **'Long-press an output jack (●) to start dragging a cable. Compatible input jacks will pulse to show valid targets. Drag to a compatible input jack and release to connect. Dropping in empty space cancels the drag.\n\nCompatible pairs: MIDI OUT → MIDI IN, AUDIO OUT L → AUDIO IN L, AUDIO OUT R → AUDIO IN R, SEND → RETURN, CHORD OUT → CHORD IN, SCALE OUT → SCALE IN.'**
  String get guidePatchDrawBody;

  /// No description provided for @guidePatchDisconnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnecting a Cable'**
  String get guidePatchDisconnectTitle;

  /// No description provided for @guidePatchDisconnectBody.
  ///
  /// In en, this message translates to:
  /// **'Each cable has a small ✕ badge at its midpoint. Tap the badge to bring up the Disconnect menu. The badge is also the cable\'s hit zone, so aim for the circle with the coloured ring.'**
  String get guidePatchDisconnectBody;

  /// No description provided for @guidePatchDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Data Cables (Jam Mode)'**
  String get guidePatchDataTitle;

  /// No description provided for @guidePatchDataBody.
  ///
  /// In en, this message translates to:
  /// **'Purple data cables represent the Jam Mode harmony flow between slots. Drawing a CHORD OUT → CHORD IN cable is the same as selecting a Jam Mode master in the dropdown — both controls stay in sync. Similarly, a SCALE OUT → SCALE IN cable corresponds to a target follower slot.'**
  String get guidePatchDataBody;

  /// No description provided for @guidePatchTip.
  ///
  /// In en, this message translates to:
  /// **'Tip: Cables are saved as part of your project (.gf file). Open a saved project to restore all connections exactly as you left them.'**
  String get guidePatchTip;

  /// No description provided for @guideJamModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Jam Mode (Auto-Harmony)'**
  String get guideJamModeTitle;

  /// No description provided for @guideJamModeBody.
  ///
  /// In en, this message translates to:
  /// **'Jam Mode allows you to play flawlessly by locking all keys to a specific scale. In Jam Mode, one channel acts as the \'Master\' (transmitting its scale/harmony) while other channels act as \'Slaves\'. Use the top controls to define the root note and scale type.'**
  String get guideJamModeBody;

  /// No description provided for @guideVocoderTitle.
  ///
  /// In en, this message translates to:
  /// **'Vocoder (Voice Synth)'**
  String get guideVocoderTitle;

  /// No description provided for @guideVocoderBody.
  ///
  /// In en, this message translates to:
  /// **'The Vocoder uses your device microphone to modulate the synth sound. Access it by selecting the \'VOCODER\' preset in the soundfont dropdown. For best results:\n• Use wired headphones or speakers (latency over Bluetooth is too high).\n• Setup mic levels with the gain knobs.\n• Android Limitation: You cannot use separate USB devices for input and output. Use a single USB hub/interface that handles both, or the internal mic.\n• Experiment with different carrier waves (Saw, Pulse, Neutral).'**
  String get guideVocoderBody;

  /// No description provided for @guideMidiTitle.
  ///
  /// In en, this message translates to:
  /// **'MIDI Connectivity'**
  String get guideMidiTitle;

  /// No description provided for @guideMidiBody.
  ///
  /// In en, this message translates to:
  /// **'Connect hardware controllers via USB (OTG adapter) or BLE MIDI. Enable CC Mapping in preferences to bind physical knobs to internal effects or system actions like \'Next Patch\'.'**
  String get guideMidiBody;

  /// No description provided for @guideMidiBestPracticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Hardware Recommendations'**
  String get guideMidiBestPracticeTitle;

  /// No description provided for @guideMidiBestPracticeBody.
  ///
  /// In en, this message translates to:
  /// **'For an optimal experience, we recommend using a split MIDI keyboard or a dual-keyboard setup:\n• Channel 2 (Left Hand): Send notes here to control chords and harmony (Jam Master).\n• Channel 1 (Right Hand): Use this channel to improvise over the generated harmony with the current scale.'**
  String get guideMidiBestPracticeBody;

  /// No description provided for @guideSoundfontsTitle.
  ///
  /// In en, this message translates to:
  /// **'Soundfonts (SF2)'**
  String get guideSoundfontsTitle;

  /// No description provided for @guideSoundfontsBody.
  ///
  /// In en, this message translates to:
  /// **'Import high-quality instrument sounds (.sf2) in the Soundfont preferences. Once loaded, you can assign them to any MIDI channel via the patch selector.'**
  String get guideSoundfontsBody;

  /// No description provided for @guideTipsTitle.
  ///
  /// In en, this message translates to:
  /// **'Musical Tips & Improvisation'**
  String get guideTipsTitle;

  /// No description provided for @guideTipsBody.
  ///
  /// In en, this message translates to:
  /// **'New to improvisation? Try these tips:\n• Scale as Safe Zone: Every key in the selected scale will sound \'correct\' with the music.\n• The Root Note: Start or end your phrases on the root note (highlighted) to create a sense of resolution.\n• Rhythm first: Focus on simple rhythmic patterns rather than complex melodies.'**
  String get guideTipsBody;

  /// No description provided for @guideScalesTitle.
  ///
  /// In en, this message translates to:
  /// **'Available Scales'**
  String get guideScalesTitle;

  /// No description provided for @guideWelcomeHeader.
  ///
  /// In en, this message translates to:
  /// **'Welcome to GrooveForge v{version}'**
  String guideWelcomeHeader(String version);

  /// No description provided for @guideWelcomeIntro.
  ///
  /// In en, this message translates to:
  /// **'This update brings significant improvements to your workflow and creative tools:'**
  String get guideWelcomeIntro;

  /// No description provided for @guideChangelogExpand.
  ///
  /// In en, this message translates to:
  /// **'See what\'s new in this version'**
  String get guideChangelogExpand;

  /// No description provided for @guideMidiHardware.
  ///
  /// In en, this message translates to:
  /// **'1. Hardware Connection'**
  String get guideMidiHardware;

  /// No description provided for @guideMidiHardwareStep1.
  ///
  /// In en, this message translates to:
  /// **'Connect controller via USB (OTG) or power on BLE device.'**
  String get guideMidiHardwareStep1;

  /// No description provided for @guideMidiHardwareStep2.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings > MIDI Input and select your device.'**
  String get guideMidiHardwareStep2;

  /// No description provided for @guideMidiCcMappings.
  ///
  /// In en, this message translates to:
  /// **'2. CC & System Mappings'**
  String get guideMidiCcMappings;

  /// No description provided for @guideMidiCcMappingsBody.
  ///
  /// In en, this message translates to:
  /// **'Bind knobs to effects like Volume or System Actions:'**
  String get guideMidiCcMappingsBody;

  /// No description provided for @guideMidiFeaturePatch.
  ///
  /// In en, this message translates to:
  /// **'Patch Up/Down'**
  String get guideMidiFeaturePatch;

  /// No description provided for @guideMidiFeaturePatchDesc.
  ///
  /// In en, this message translates to:
  /// **'Quickly switch instruments.'**
  String get guideMidiFeaturePatchDesc;

  /// No description provided for @guideMidiFeatureScales.
  ///
  /// In en, this message translates to:
  /// **'Cycle Scales'**
  String get guideMidiFeatureScales;

  /// No description provided for @guideMidiFeatureScalesDesc.
  ///
  /// In en, this message translates to:
  /// **'Change harmony on the fly.'**
  String get guideMidiFeatureScalesDesc;

  /// No description provided for @guideMidiFeatureJam.
  ///
  /// In en, this message translates to:
  /// **'Toggle Jam'**
  String get guideMidiFeatureJam;

  /// No description provided for @guideMidiFeatureJamDesc.
  ///
  /// In en, this message translates to:
  /// **'Force slaves to follow your lead.'**
  String get guideMidiFeatureJamDesc;

  /// No description provided for @guideMidiTipSplit.
  ///
  /// In en, this message translates to:
  /// **'Tip: Most modern MIDI controllers allow splitting the keys into distinct zones/channels.'**
  String get guideMidiTipSplit;

  /// No description provided for @guideAndroidUsbLimitation.
  ///
  /// In en, this message translates to:
  /// **'Important: On Android, using a USB hub with separate input and output devices can be unstable. Use an integrated USB Audio Interface for best results.'**
  String get guideAndroidUsbLimitation;

  /// No description provided for @micSelectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Audio Input'**
  String get micSelectionTitle;

  /// No description provided for @micSelectionDevice.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get micSelectionDevice;

  /// No description provided for @micSelectionSensitivity.
  ///
  /// In en, this message translates to:
  /// **'Sensitivity'**
  String get micSelectionSensitivity;

  /// No description provided for @micSelectionDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get micSelectionDefault;

  /// No description provided for @audioOutputTitle.
  ///
  /// In en, this message translates to:
  /// **'Audio Output'**
  String get audioOutputTitle;

  /// No description provided for @audioOutputDevice.
  ///
  /// In en, this message translates to:
  /// **'Output Device'**
  String get audioOutputDevice;

  /// No description provided for @audioOutputDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get audioOutputDefault;

  /// No description provided for @audioSettingsBarGain.
  ///
  /// In en, this message translates to:
  /// **'Gain'**
  String get audioSettingsBarGain;

  /// No description provided for @audioSettingsBarMicSensitivity.
  ///
  /// In en, this message translates to:
  /// **'Mic'**
  String get audioSettingsBarMicSensitivity;

  /// No description provided for @audioSettingsBarMicDevice.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get audioSettingsBarMicDevice;

  /// No description provided for @audioSettingsBarOutputDevice.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get audioSettingsBarOutputDevice;

  /// No description provided for @audioSettingsBarToggleTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show/hide audio settings bar'**
  String get audioSettingsBarToggleTooltip;

  /// No description provided for @synthAutoScrollTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-scroll to Active Channel'**
  String get synthAutoScrollTitle;

  /// No description provided for @synthAutoScrollSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically scroll the list when MIDI is received'**
  String get synthAutoScrollSubtitle;

  /// No description provided for @rackTitle.
  ///
  /// In en, this message translates to:
  /// **'Rack'**
  String get rackTitle;

  /// No description provided for @rackAddPlugin.
  ///
  /// In en, this message translates to:
  /// **'Add Plugin'**
  String get rackAddPlugin;

  /// No description provided for @rackAddGrooveForgeKeyboard.
  ///
  /// In en, this message translates to:
  /// **'GrooveForge Keyboard'**
  String get rackAddGrooveForgeKeyboard;

  /// No description provided for @rackAddGrooveForgeKeyboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Soundfont synth or MIDI-only (None) for patch routing'**
  String get rackAddGrooveForgeKeyboardSubtitle;

  /// No description provided for @rackAddVocoder.
  ///
  /// In en, this message translates to:
  /// **'Vocoder'**
  String get rackAddVocoder;

  /// No description provided for @rackAddVocoderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Mic-driven voice synthesizer (GFPA)'**
  String get rackAddVocoderSubtitle;

  /// No description provided for @rackAddJamMode.
  ///
  /// In en, this message translates to:
  /// **'Jam Mode'**
  String get rackAddJamMode;

  /// No description provided for @rackAddJamModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scale-lock a keyboard slot to another\'s harmony'**
  String get rackAddJamModeSubtitle;

  /// No description provided for @rackAddVst3.
  ///
  /// In en, this message translates to:
  /// **'Browse VST3 Plugin…'**
  String get rackAddVst3;

  /// No description provided for @rackAddVst3Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Load an external .vst3 from disk'**
  String get rackAddVst3Subtitle;

  /// No description provided for @rackRemovePlugin.
  ///
  /// In en, this message translates to:
  /// **'Remove Plugin'**
  String get rackRemovePlugin;

  /// No description provided for @rackRemovePluginConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this plugin slot? All unsaved settings will be lost.'**
  String get rackRemovePluginConfirm;

  /// No description provided for @rackRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get rackRemove;

  /// No description provided for @rackPluginUnavailableOnMobile.
  ///
  /// In en, this message translates to:
  /// **'This VST3 plugin is not available on mobile.'**
  String get rackPluginUnavailableOnMobile;

  /// No description provided for @rackMidiChannel.
  ///
  /// In en, this message translates to:
  /// **'MIDI CH'**
  String get rackMidiChannel;

  /// No description provided for @rackMenuProject.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get rackMenuProject;

  /// No description provided for @rackOpenProject.
  ///
  /// In en, this message translates to:
  /// **'Open Project'**
  String get rackOpenProject;

  /// No description provided for @rackSaveProject.
  ///
  /// In en, this message translates to:
  /// **'Save Project'**
  String get rackSaveProject;

  /// No description provided for @rackSaveProjectAs.
  ///
  /// In en, this message translates to:
  /// **'Save As…'**
  String get rackSaveProjectAs;

  /// No description provided for @rackNewProject.
  ///
  /// In en, this message translates to:
  /// **'New Project'**
  String get rackNewProject;

  /// No description provided for @rackNewProjectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Start a new project? Unsaved changes will be lost.'**
  String get rackNewProjectConfirm;

  /// No description provided for @rackNewProjectButton.
  ///
  /// In en, this message translates to:
  /// **'New Project'**
  String get rackNewProjectButton;

  /// No description provided for @rackProjectSaved.
  ///
  /// In en, this message translates to:
  /// **'Project saved.'**
  String get rackProjectSaved;

  /// No description provided for @rackProjectOpened.
  ///
  /// In en, this message translates to:
  /// **'Project opened.'**
  String get rackProjectOpened;

  /// No description provided for @rackAutosaveRestored.
  ///
  /// In en, this message translates to:
  /// **'Session restored.'**
  String get rackAutosaveRestored;

  /// No description provided for @splashRestoringRack.
  ///
  /// In en, this message translates to:
  /// **'Restoring rack state...'**
  String get splashRestoringRack;

  /// No description provided for @vst3LoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load VST3 plugin. Make sure you selected the .vst3 bundle folder.'**
  String get vst3LoadFailed;

  /// No description provided for @vst3EditorOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open plugin editor. If the plugin uses OpenGL, try launching GrooveForge with LIBGL_ALWAYS_SOFTWARE=1 or in a pure X11 session (unset WAYLAND_DISPLAY).'**
  String get vst3EditorOpenFailed;

  /// No description provided for @vst3NotLoaded.
  ///
  /// In en, this message translates to:
  /// **'Plugin not yet loaded.'**
  String get vst3NotLoaded;

  /// No description provided for @vst3NotABundle.
  ///
  /// In en, this message translates to:
  /// **'Selected folder is not a .vst3 bundle. Please select a folder that ends in .vst3.'**
  String get vst3NotABundle;

  /// No description provided for @vst3BrowseTitle.
  ///
  /// In en, this message translates to:
  /// **'Browse for .vst3 folder…'**
  String get vst3BrowseTitle;

  /// No description provided for @vst3BrowseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select a .vst3 bundle directory from your filesystem.'**
  String get vst3BrowseSubtitle;

  /// No description provided for @vst3PickInstalledTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick from installed plugins'**
  String get vst3PickInstalledTitle;

  /// No description provided for @vst3PickInstalledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose from plugins found in default system paths.'**
  String get vst3PickInstalledSubtitle;

  /// No description provided for @vst3ScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan for VST3 Plugins'**
  String get vst3ScanTitle;

  /// No description provided for @vst3ScanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Search default system paths for installed .vst3 plugins.'**
  String get vst3ScanSubtitle;

  /// No description provided for @vst3Scanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get vst3Scanning;

  /// No description provided for @vst3ScanFound.
  ///
  /// In en, this message translates to:
  /// **'{count} plugin(s) found.'**
  String vst3ScanFound(int count);

  /// No description provided for @vst3ScanNoneFound.
  ///
  /// In en, this message translates to:
  /// **'No .vst3 plugins found in default paths.'**
  String get vst3ScanNoneFound;

  /// No description provided for @vst3ScanError.
  ///
  /// In en, this message translates to:
  /// **'Scan failed: {error}'**
  String vst3ScanError(String error);

  /// No description provided for @transportBpm.
  ///
  /// In en, this message translates to:
  /// **'BPM'**
  String get transportBpm;

  /// No description provided for @transportTapTempo.
  ///
  /// In en, this message translates to:
  /// **'Tap'**
  String get transportTapTempo;

  /// No description provided for @transportPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get transportPlay;

  /// No description provided for @transportStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get transportStop;

  /// No description provided for @transportTimeSignature.
  ///
  /// In en, this message translates to:
  /// **'Time Sig'**
  String get transportTimeSignature;

  /// No description provided for @transportMetronome.
  ///
  /// In en, this message translates to:
  /// **'Metronome'**
  String get transportMetronome;

  /// No description provided for @transportTimeSigCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get transportTimeSigCustom;

  /// No description provided for @transportTimeSigNumerator.
  ///
  /// In en, this message translates to:
  /// **'Beats / bar'**
  String get transportTimeSigNumerator;

  /// No description provided for @transportTimeSigDenominator.
  ///
  /// In en, this message translates to:
  /// **'Beat unit'**
  String get transportTimeSigDenominator;

  /// No description provided for @patchViewToggleTooltip.
  ///
  /// In en, this message translates to:
  /// **'Patch view'**
  String get patchViewToggleTooltip;

  /// No description provided for @patchViewFrontButton.
  ///
  /// In en, this message translates to:
  /// **'FRONT'**
  String get patchViewFrontButton;

  /// No description provided for @disconnectCable.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnectCable;

  /// No description provided for @cableColour.
  ///
  /// In en, this message translates to:
  /// **'Cable colour'**
  String get cableColour;

  /// No description provided for @connectionCycleError.
  ///
  /// In en, this message translates to:
  /// **'Cycle detected: this connection would create a feedback loop'**
  String get connectionCycleError;

  /// No description provided for @portMidiIn.
  ///
  /// In en, this message translates to:
  /// **'MIDI IN'**
  String get portMidiIn;

  /// No description provided for @portMidiOut.
  ///
  /// In en, this message translates to:
  /// **'MIDI OUT'**
  String get portMidiOut;

  /// No description provided for @portAudioInL.
  ///
  /// In en, this message translates to:
  /// **'AUDIO IN L'**
  String get portAudioInL;

  /// No description provided for @portAudioInR.
  ///
  /// In en, this message translates to:
  /// **'AUDIO IN R'**
  String get portAudioInR;

  /// No description provided for @portAudioOutL.
  ///
  /// In en, this message translates to:
  /// **'AUDIO OUT L'**
  String get portAudioOutL;

  /// No description provided for @portAudioOutR.
  ///
  /// In en, this message translates to:
  /// **'AUDIO OUT R'**
  String get portAudioOutR;

  /// No description provided for @portSendOut.
  ///
  /// In en, this message translates to:
  /// **'SEND'**
  String get portSendOut;

  /// No description provided for @portReturnIn.
  ///
  /// In en, this message translates to:
  /// **'RETURN'**
  String get portReturnIn;

  /// No description provided for @portChordOut.
  ///
  /// In en, this message translates to:
  /// **'CHORD OUT'**
  String get portChordOut;

  /// No description provided for @portChordIn.
  ///
  /// In en, this message translates to:
  /// **'CHORD IN'**
  String get portChordIn;

  /// No description provided for @portScaleOut.
  ///
  /// In en, this message translates to:
  /// **'SCALE OUT'**
  String get portScaleOut;

  /// No description provided for @portScaleIn.
  ///
  /// In en, this message translates to:
  /// **'SCALE IN'**
  String get portScaleIn;

  /// No description provided for @looperSlotName.
  ///
  /// In en, this message translates to:
  /// **'MIDI Looper'**
  String get looperSlotName;

  /// No description provided for @addLooper.
  ///
  /// In en, this message translates to:
  /// **'MIDI Looper'**
  String get addLooper;

  /// No description provided for @addLooperSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Record and loop MIDI patterns with bar sync'**
  String get addLooperSubtitle;

  /// No description provided for @addLooperAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'A MIDI Looper is already in the rack. Only one is allowed.'**
  String get addLooperAlreadyExists;

  /// No description provided for @addJamModeAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'A Jam Mode is already in the rack. Only one is allowed.'**
  String get addJamModeAlreadyExists;

  /// No description provided for @looperRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get looperRecord;

  /// No description provided for @looperPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get looperPlay;

  /// No description provided for @looperStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get looperStop;

  /// No description provided for @looperClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get looperClear;

  /// No description provided for @looperOverdub.
  ///
  /// In en, this message translates to:
  /// **'Overdub'**
  String get looperOverdub;

  /// No description provided for @looperArmed.
  ///
  /// In en, this message translates to:
  /// **'Armed — waiting for transport'**
  String get looperArmed;

  /// No description provided for @looperWaitingForBar.
  ///
  /// In en, this message translates to:
  /// **'Waiting for bar'**
  String get looperWaitingForBar;

  /// No description provided for @looperWaitingForOverdub.
  ///
  /// In en, this message translates to:
  /// **'Waiting for overdub'**
  String get looperWaitingForOverdub;

  /// No description provided for @looperTrack.
  ///
  /// In en, this message translates to:
  /// **'Track {n}'**
  String looperTrack(int n);

  /// No description provided for @looperPinBelow.
  ///
  /// In en, this message translates to:
  /// **'Pin below transport'**
  String get looperPinBelow;

  /// No description provided for @jamModePinBelow.
  ///
  /// In en, this message translates to:
  /// **'Pin below transport'**
  String get jamModePinBelow;

  /// No description provided for @looperHalfSpeed.
  ///
  /// In en, this message translates to:
  /// **'½×'**
  String get looperHalfSpeed;

  /// No description provided for @looperNormalSpeed.
  ///
  /// In en, this message translates to:
  /// **'1×'**
  String get looperNormalSpeed;

  /// No description provided for @looperDoubleSpeed.
  ///
  /// In en, this message translates to:
  /// **'2×'**
  String get looperDoubleSpeed;

  /// No description provided for @looperReverse.
  ///
  /// In en, this message translates to:
  /// **'Reverse'**
  String get looperReverse;

  /// No description provided for @looperMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get looperMute;

  /// No description provided for @looperBar.
  ///
  /// In en, this message translates to:
  /// **'Bar {n}'**
  String looperBar(int n);

  /// No description provided for @looperCcAssign.
  ///
  /// In en, this message translates to:
  /// **'Assign CC'**
  String get looperCcAssign;

  /// No description provided for @looperCcAssignTitle.
  ///
  /// In en, this message translates to:
  /// **'Assign hardware CC to looper'**
  String get looperCcAssignTitle;

  /// No description provided for @looperCcRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove CC binding'**
  String get looperCcRemove;

  /// No description provided for @looperCcLearn.
  ///
  /// In en, this message translates to:
  /// **'Move a knob or fader…'**
  String get looperCcLearn;

  /// No description provided for @looperActionLoop.
  ///
  /// In en, this message translates to:
  /// **'Loop'**
  String get looperActionLoop;

  /// No description provided for @looperActionStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get looperActionStop;

  /// No description provided for @looperCcConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'CC already assigned'**
  String get looperCcConflictTitle;

  /// No description provided for @looperCcConflictBody.
  ///
  /// In en, this message translates to:
  /// **'CC {cc} is already mapped to {target}. Overwrite?'**
  String looperCcConflictBody(int cc, String target);

  /// No description provided for @looperCcConflictOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get looperCcConflictOverwrite;

  /// No description provided for @looperVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get looperVolume;

  /// No description provided for @looperQuantize.
  ///
  /// In en, this message translates to:
  /// **'Quantize'**
  String get looperQuantize;

  /// No description provided for @kbConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Config'**
  String get kbConfigTitle;

  /// No description provided for @kbConfigDefault.
  ///
  /// In en, this message translates to:
  /// **'Default ({value})'**
  String kbConfigDefault(String value);

  /// No description provided for @kbConfigKeysToShow.
  ///
  /// In en, this message translates to:
  /// **'Keys to show'**
  String get kbConfigKeysToShow;

  /// No description provided for @kbConfigKeysToShowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Number of visible keys (overrides default)'**
  String get kbConfigKeysToShowSubtitle;

  /// No description provided for @kbConfigKeysDefault.
  ///
  /// In en, this message translates to:
  /// **'Default ({count} keys)'**
  String kbConfigKeysDefault(int count);

  /// No description provided for @kbConfigKeyHeight.
  ///
  /// In en, this message translates to:
  /// **'Key height'**
  String get kbConfigKeyHeight;

  /// No description provided for @kbConfigKeyHeightSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Taller keys are easier to play on phones'**
  String get kbConfigKeyHeightSubtitle;

  /// No description provided for @kbConfigVertGesture.
  ///
  /// In en, this message translates to:
  /// **'Vertical swipe'**
  String get kbConfigVertGesture;

  /// No description provided for @kbConfigVertGestureSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Swipe up/down on a key'**
  String get kbConfigVertGestureSubtitle;

  /// No description provided for @kbConfigHorizGesture.
  ///
  /// In en, this message translates to:
  /// **'Horizontal swipe'**
  String get kbConfigHorizGesture;

  /// No description provided for @kbConfigHorizGestureSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Slide left/right across keys'**
  String get kbConfigHorizGestureSubtitle;

  /// No description provided for @kbConfigAftertouch.
  ///
  /// In en, this message translates to:
  /// **'Aftertouch CC'**
  String get kbConfigAftertouch;

  /// No description provided for @kbConfigAftertouchSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Vertical pressure routes to this CC'**
  String get kbConfigAftertouchSubtitle;

  /// No description provided for @kbConfigResetDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get kbConfigResetDefaults;

  /// No description provided for @keyHeightSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get keyHeightSmall;

  /// No description provided for @keyHeightNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get keyHeightNormal;

  /// No description provided for @keyHeightLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get keyHeightLarge;

  /// No description provided for @keyHeightExtraLarge.
  ///
  /// In en, this message translates to:
  /// **'Extra Large'**
  String get keyHeightExtraLarge;

  /// No description provided for @rackAddStylophone.
  ///
  /// In en, this message translates to:
  /// **'Stylophone'**
  String get rackAddStylophone;

  /// No description provided for @rackAddStyloPhoneSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Monophonic metal-strip instrument (GFPA)'**
  String get rackAddStyloPhoneSubtitle;

  /// No description provided for @rackAddTheremin.
  ///
  /// In en, this message translates to:
  /// **'Theremin'**
  String get rackAddTheremin;

  /// No description provided for @rackAddThereminSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Touch pad — vertical pitch, horizontal volume (GFPA)'**
  String get rackAddThereminSubtitle;

  /// No description provided for @thereminModePad.
  ///
  /// In en, this message translates to:
  /// **'PAD'**
  String get thereminModePad;

  /// No description provided for @thereminModeCam.
  ///
  /// In en, this message translates to:
  /// **'CAM'**
  String get thereminModeCam;

  /// No description provided for @thereminCamHint.
  ///
  /// In en, this message translates to:
  /// **'Move your hand towards or away from the camera to play'**
  String get thereminCamHint;

  /// No description provided for @thereminCamErrUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Camera mode is not available on this platform.'**
  String get thereminCamErrUnsupported;

  /// No description provided for @thereminCamErrNoPermission.
  ///
  /// In en, this message translates to:
  /// **'Camera permission denied. Switch to PAD mode to try again.'**
  String get thereminCamErrNoPermission;

  /// No description provided for @thereminCamErrNoCamera.
  ///
  /// In en, this message translates to:
  /// **'No suitable camera found on this device.'**
  String get thereminCamErrNoCamera;

  /// No description provided for @thereminCamErrFixedFocus.
  ///
  /// In en, this message translates to:
  /// **'This camera has fixed focus — hand tracking is not available.'**
  String get thereminCamErrFixedFocus;

  /// No description provided for @thereminCamErrConfigError.
  ///
  /// In en, this message translates to:
  /// **'Camera configuration error. Please switch to PAD mode.'**
  String get thereminCamErrConfigError;

  /// No description provided for @styloWaveformSquare.
  ///
  /// In en, this message translates to:
  /// **'SQR'**
  String get styloWaveformSquare;

  /// No description provided for @styloWaveformSawtooth.
  ///
  /// In en, this message translates to:
  /// **'SAW'**
  String get styloWaveformSawtooth;

  /// No description provided for @styloWaveformSine.
  ///
  /// In en, this message translates to:
  /// **'SIN'**
  String get styloWaveformSine;

  /// No description provided for @styloWaveformTriangle.
  ///
  /// In en, this message translates to:
  /// **'TRI'**
  String get styloWaveformTriangle;

  /// No description provided for @thereminVibrato.
  ///
  /// In en, this message translates to:
  /// **'VIB'**
  String get thereminVibrato;

  /// No description provided for @thereminPadHeight.
  ///
  /// In en, this message translates to:
  /// **'HEIGHT'**
  String get thereminPadHeight;

  /// No description provided for @midiMuteOwnSound.
  ///
  /// In en, this message translates to:
  /// **'MUTE'**
  String get midiMuteOwnSound;

  /// No description provided for @vst3BrowseInstrumentTitle.
  ///
  /// In en, this message translates to:
  /// **'Browse VST3 Instrument…'**
  String get vst3BrowseInstrumentTitle;

  /// No description provided for @vst3BrowseInstrumentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Load a synthesizer or sampler plugin (.vst3)'**
  String get vst3BrowseInstrumentSubtitle;

  /// No description provided for @vst3BrowseEffectTitle.
  ///
  /// In en, this message translates to:
  /// **'Browse VST3 Effect…'**
  String get vst3BrowseEffectTitle;

  /// No description provided for @vst3BrowseEffectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Load an audio effect plugin (.vst3)'**
  String get vst3BrowseEffectSubtitle;

  /// No description provided for @vst3PickInstalledInstrumentTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick Installed Instrument'**
  String get vst3PickInstalledInstrumentTitle;

  /// No description provided for @vst3PickInstalledEffectTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick Installed Effect'**
  String get vst3PickInstalledEffectTitle;

  /// No description provided for @vst3EffectTypeReverb.
  ///
  /// In en, this message translates to:
  /// **'Reverb'**
  String get vst3EffectTypeReverb;

  /// No description provided for @vst3EffectTypeCompressor.
  ///
  /// In en, this message translates to:
  /// **'Compressor'**
  String get vst3EffectTypeCompressor;

  /// No description provided for @vst3EffectTypeEq.
  ///
  /// In en, this message translates to:
  /// **'EQ'**
  String get vst3EffectTypeEq;

  /// No description provided for @vst3EffectTypeDelay.
  ///
  /// In en, this message translates to:
  /// **'Delay'**
  String get vst3EffectTypeDelay;

  /// No description provided for @vst3EffectTypeModulation.
  ///
  /// In en, this message translates to:
  /// **'Modulation'**
  String get vst3EffectTypeModulation;

  /// No description provided for @vst3EffectTypeDistortion.
  ///
  /// In en, this message translates to:
  /// **'Distortion'**
  String get vst3EffectTypeDistortion;

  /// No description provided for @vst3EffectTypeDynamics.
  ///
  /// In en, this message translates to:
  /// **'Dynamics'**
  String get vst3EffectTypeDynamics;

  /// No description provided for @vst3EffectTypeFx.
  ///
  /// In en, this message translates to:
  /// **'FX'**
  String get vst3EffectTypeFx;

  /// No description provided for @vst3FxInserts.
  ///
  /// In en, this message translates to:
  /// **'FX'**
  String get vst3FxInserts;

  /// No description provided for @vst3FxAddEffect.
  ///
  /// In en, this message translates to:
  /// **'Add effect'**
  String get vst3FxAddEffect;

  /// No description provided for @vst3FxNoEffects.
  ///
  /// In en, this message translates to:
  /// **'No effects — connect via patch view'**
  String get vst3FxNoEffects;

  /// No description provided for @rackAddEffectsSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Built-in Effects'**
  String get rackAddEffectsSectionLabel;

  /// No description provided for @rackAddVstSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'VST3 Plugins'**
  String get rackAddVstSectionLabel;

  /// No description provided for @rackAddReverb.
  ///
  /// In en, this message translates to:
  /// **'Plate Reverb'**
  String get rackAddReverb;

  /// No description provided for @rackAddReverbSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Lush stereo room reverb'**
  String get rackAddReverbSubtitle;

  /// No description provided for @rackAddDelay.
  ///
  /// In en, this message translates to:
  /// **'Ping-Pong Delay'**
  String get rackAddDelay;

  /// No description provided for @rackAddDelaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stereo delay with BPM sync'**
  String get rackAddDelaySubtitle;

  /// No description provided for @rackAddWah.
  ///
  /// In en, this message translates to:
  /// **'Auto-Wah'**
  String get rackAddWah;

  /// No description provided for @rackAddWahSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Envelope / LFO wah filter with BPM sync'**
  String get rackAddWahSubtitle;

  /// No description provided for @rackAddEq.
  ///
  /// In en, this message translates to:
  /// **'4-Band EQ'**
  String get rackAddEq;

  /// No description provided for @rackAddEqSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Low shelf, 2× peaking, high shelf'**
  String get rackAddEqSubtitle;

  /// No description provided for @rackAddCompressor.
  ///
  /// In en, this message translates to:
  /// **'Compressor'**
  String get rackAddCompressor;

  /// No description provided for @rackAddCompressorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'RMS compressor with soft knee'**
  String get rackAddCompressorSubtitle;

  /// No description provided for @rackAddChorus.
  ///
  /// In en, this message translates to:
  /// **'Chorus / Flanger'**
  String get rackAddChorus;

  /// No description provided for @rackAddChorusSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stereo chorus with BPM sync'**
  String get rackAddChorusSubtitle;

  /// No description provided for @rackAddLoadGfpd.
  ///
  /// In en, this message translates to:
  /// **'Load .gfpd from file…'**
  String get rackAddLoadGfpd;

  /// No description provided for @rackAddLoadGfpdSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Import a custom GrooveForge plugin descriptor'**
  String get rackAddLoadGfpdSubtitle;

  /// No description provided for @rackAddMidiFxSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Built-in MIDI FX'**
  String get rackAddMidiFxSectionLabel;

  /// No description provided for @rackAddHarmonizer.
  ///
  /// In en, this message translates to:
  /// **'Harmonizer'**
  String get rackAddHarmonizer;

  /// No description provided for @rackAddHarmonizerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add harmony voices to any MIDI input (MIDI FX)'**
  String get rackAddHarmonizerSubtitle;

  /// No description provided for @rackAddChordExpand.
  ///
  /// In en, this message translates to:
  /// **'Chord Expand'**
  String get rackAddChordExpand;

  /// No description provided for @rackAddChordExpandSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Expand each note into a full chord voicing (MIDI FX)'**
  String get rackAddChordExpandSubtitle;

  /// No description provided for @rackAddArpeggiator.
  ///
  /// In en, this message translates to:
  /// **'Arpeggiator'**
  String get rackAddArpeggiator;

  /// No description provided for @rackAddArpeggiatorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Arpeggiate held notes in a rhythmic sequence (MIDI FX)'**
  String get rackAddArpeggiatorSubtitle;

  /// No description provided for @rackAddTransposer.
  ///
  /// In en, this message translates to:
  /// **'Transposer'**
  String get rackAddTransposer;

  /// No description provided for @rackAddTransposerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shift all notes up or down by ±24 semitones (MIDI FX)'**
  String get rackAddTransposerSubtitle;

  /// No description provided for @rackAddVelocityCurve.
  ///
  /// In en, this message translates to:
  /// **'Velocity Curve'**
  String get rackAddVelocityCurve;

  /// No description provided for @rackAddVelocityCurveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Remap velocity with a power, sigmoid, or fixed curve (MIDI FX)'**
  String get rackAddVelocityCurveSubtitle;

  /// No description provided for @rackAddGate.
  ///
  /// In en, this message translates to:
  /// **'Gate'**
  String get rackAddGate;

  /// No description provided for @rackAddGateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Filter notes by velocity range and pitch range (MIDI FX)'**
  String get rackAddGateSubtitle;

  /// No description provided for @midiFxBypass.
  ///
  /// In en, this message translates to:
  /// **'Bypass'**
  String get midiFxBypass;

  /// No description provided for @midiFxCcAssign.
  ///
  /// In en, this message translates to:
  /// **'Assign CC to bypass'**
  String get midiFxCcAssign;

  /// No description provided for @midiFxCcAssignTitle.
  ///
  /// In en, this message translates to:
  /// **'Assign hardware CC to bypass'**
  String get midiFxCcAssignTitle;

  /// No description provided for @midiFxCcWaiting.
  ///
  /// In en, this message translates to:
  /// **'Move a knob or button on your MIDI controller to assign it...'**
  String get midiFxCcWaiting;

  /// No description provided for @midiFxCcAssigned.
  ///
  /// In en, this message translates to:
  /// **'CC {cc} assigned to bypass'**
  String midiFxCcAssigned(int cc);

  /// No description provided for @midiFxCcRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove CC binding'**
  String get midiFxCcRemove;

  /// No description provided for @drumGeneratorAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Drum Generator'**
  String get drumGeneratorAddTitle;

  /// No description provided for @drumGeneratorAddSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Beat patterns from bossa nova to metal, with human feel'**
  String get drumGeneratorAddSubtitle;

  /// No description provided for @drumGeneratorActiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get drumGeneratorActiveLabel;

  /// No description provided for @drumGeneratorStyleLabel.
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get drumGeneratorStyleLabel;

  /// No description provided for @drumGeneratorSwingLabel.
  ///
  /// In en, this message translates to:
  /// **'Swing'**
  String get drumGeneratorSwingLabel;

  /// No description provided for @drumGeneratorSwingPattern.
  ///
  /// In en, this message translates to:
  /// **'Pattern'**
  String get drumGeneratorSwingPattern;

  /// No description provided for @drumGeneratorHumanizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Human feel'**
  String get drumGeneratorHumanizeLabel;

  /// No description provided for @drumGeneratorHumanizeRobotic.
  ///
  /// In en, this message translates to:
  /// **'Robotic'**
  String get drumGeneratorHumanizeRobotic;

  /// No description provided for @drumGeneratorHumanizeLive.
  ///
  /// In en, this message translates to:
  /// **'Live drummer'**
  String get drumGeneratorHumanizeLive;

  /// No description provided for @drumGeneratorIntroLabel.
  ///
  /// In en, this message translates to:
  /// **'Count-in'**
  String get drumGeneratorIntroLabel;

  /// No description provided for @drumGeneratorFillLabel.
  ///
  /// In en, this message translates to:
  /// **'Fill every'**
  String get drumGeneratorFillLabel;

  /// No description provided for @drumGeneratorSoundfontLabel.
  ///
  /// In en, this message translates to:
  /// **'Soundfont'**
  String get drumGeneratorSoundfontLabel;

  /// No description provided for @drumGeneratorLoadPattern.
  ///
  /// In en, this message translates to:
  /// **'Load .gfdrum…'**
  String get drumGeneratorLoadPattern;

  /// No description provided for @drumGeneratorFormatGuide.
  ///
  /// In en, this message translates to:
  /// **'Format guide'**
  String get drumGeneratorFormatGuide;

  /// No description provided for @drumGeneratorIntroNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get drumGeneratorIntroNone;

  /// No description provided for @drumGeneratorIntroCountIn1.
  ///
  /// In en, this message translates to:
  /// **'1 bar'**
  String get drumGeneratorIntroCountIn1;

  /// No description provided for @drumGeneratorIntroCountIn2.
  ///
  /// In en, this message translates to:
  /// **'2 bars'**
  String get drumGeneratorIntroCountIn2;

  /// No description provided for @drumGeneratorIntroChopsticks.
  ///
  /// In en, this message translates to:
  /// **'Chopsticks (4 hits)'**
  String get drumGeneratorIntroChopsticks;

  /// No description provided for @drumGeneratorFillOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get drumGeneratorFillOff;

  /// No description provided for @drumGeneratorFillEvery4.
  ///
  /// In en, this message translates to:
  /// **'Every 4 bars'**
  String get drumGeneratorFillEvery4;

  /// No description provided for @drumGeneratorFillEvery8.
  ///
  /// In en, this message translates to:
  /// **'Every 8 bars'**
  String get drumGeneratorFillEvery8;

  /// No description provided for @drumGeneratorFillEvery16.
  ///
  /// In en, this message translates to:
  /// **'Every 16 bars'**
  String get drumGeneratorFillEvery16;

  /// No description provided for @drumGeneratorFillRandom.
  ///
  /// In en, this message translates to:
  /// **'Random'**
  String get drumGeneratorFillRandom;

  /// No description provided for @drumGeneratorCrashAfterFill.
  ///
  /// In en, this message translates to:
  /// **'Crash after fill'**
  String get drumGeneratorCrashAfterFill;

  /// No description provided for @drumGeneratorDynamicBuild.
  ///
  /// In en, this message translates to:
  /// **'Dynamic build'**
  String get drumGeneratorDynamicBuild;

  /// No description provided for @drumGeneratorDefaultSoundfont.
  ///
  /// In en, this message translates to:
  /// **'Default soundfont'**
  String get drumGeneratorDefaultSoundfont;

  /// No description provided for @drumGeneratorFormatGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'Drum Pattern Format (.gfdrum)'**
  String get drumGeneratorFormatGuideTitle;

  /// No description provided for @drumGeneratorFormatGuideContent.
  ///
  /// In en, this message translates to:
  /// **'A .gfdrum file is a YAML text file describing a drum pattern.\n\nStep grid notation:\nX = strong hit (~100)\nx = medium hit (~75)\no = soft hit (~55)\ng = ghost note (~28)\n. = rest\n\nVelocity fields: base_velocity, velocity_range\nTiming fields: timing_jitter, rush\nSections: groove, fill, break, crash, intro\nSection types: loop (random), sequence (ordered bars)\n\nSee bundled patterns in assets/drums/ for examples.'**
  String get drumGeneratorFormatGuideContent;

  /// No description provided for @drumGeneratorNoPatternsFound.
  ///
  /// In en, this message translates to:
  /// **'No patterns loaded'**
  String get drumGeneratorNoPatternsFound;

  /// No description provided for @drumGeneratorFamilyRock.
  ///
  /// In en, this message translates to:
  /// **'Rock'**
  String get drumGeneratorFamilyRock;

  /// No description provided for @drumGeneratorFamilyJazz.
  ///
  /// In en, this message translates to:
  /// **'Jazz'**
  String get drumGeneratorFamilyJazz;

  /// No description provided for @drumGeneratorFamilyFunk.
  ///
  /// In en, this message translates to:
  /// **'Funk'**
  String get drumGeneratorFamilyFunk;

  /// No description provided for @drumGeneratorFamilyLatin.
  ///
  /// In en, this message translates to:
  /// **'Latin'**
  String get drumGeneratorFamilyLatin;

  /// No description provided for @drumGeneratorFamilyCeltic.
  ///
  /// In en, this message translates to:
  /// **'Celtic'**
  String get drumGeneratorFamilyCeltic;

  /// No description provided for @drumGeneratorFamilyPop.
  ///
  /// In en, this message translates to:
  /// **'Pop'**
  String get drumGeneratorFamilyPop;

  /// No description provided for @drumGeneratorFamilyElectronic.
  ///
  /// In en, this message translates to:
  /// **'Electronic'**
  String get drumGeneratorFamilyElectronic;

  /// No description provided for @drumGeneratorFamilyWorld.
  ///
  /// In en, this message translates to:
  /// **'World'**
  String get drumGeneratorFamilyWorld;

  /// No description provided for @drumGeneratorFamilyMetal.
  ///
  /// In en, this message translates to:
  /// **'Metal'**
  String get drumGeneratorFamilyMetal;

  /// No description provided for @drumGeneratorFamilyCountry.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get drumGeneratorFamilyCountry;

  /// No description provided for @drumGeneratorFamilyFolk.
  ///
  /// In en, this message translates to:
  /// **'Folk'**
  String get drumGeneratorFamilyFolk;

  /// No description provided for @drumGeneratorCustomPattern.
  ///
  /// In en, this message translates to:
  /// **'Custom pattern'**
  String get drumGeneratorCustomPattern;

  /// No description provided for @drumGeneratorNoSoundfonts.
  ///
  /// In en, this message translates to:
  /// **'No soundfonts — add one in Preferences'**
  String get drumGeneratorNoSoundfonts;

  /// No description provided for @audioDeviceDisconnectedInput.
  ///
  /// In en, this message translates to:
  /// **'Audio input device disconnected — using default'**
  String get audioDeviceDisconnectedInput;

  /// No description provided for @audioDeviceDisconnectedOutput.
  ///
  /// In en, this message translates to:
  /// **'Audio output device disconnected — using default'**
  String get audioDeviceDisconnectedOutput;

  /// No description provided for @usbAudioDebugTitle.
  ///
  /// In en, this message translates to:
  /// **'USB Audio Devices'**
  String get usbAudioDebugTitle;

  /// No description provided for @usbAudioDebugSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Detailed device information for multi-USB investigation'**
  String get usbAudioDebugSubtitle;

  /// No description provided for @usbAudioDebugNoDevices.
  ///
  /// In en, this message translates to:
  /// **'No audio devices found'**
  String get usbAudioDebugNoDevices;

  /// No description provided for @usbAudioDebugRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get usbAudioDebugRefresh;

  /// No description provided for @usbAudioDebugDeviceId.
  ///
  /// In en, this message translates to:
  /// **'Device ID'**
  String get usbAudioDebugDeviceId;

  /// No description provided for @usbAudioDebugDirection.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get usbAudioDebugDirection;

  /// No description provided for @usbAudioDebugInput.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get usbAudioDebugInput;

  /// No description provided for @usbAudioDebugOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get usbAudioDebugOutput;

  /// No description provided for @usbAudioDebugInputOutput.
  ///
  /// In en, this message translates to:
  /// **'Input + Output'**
  String get usbAudioDebugInputOutput;

  /// No description provided for @usbAudioDebugSampleRates.
  ///
  /// In en, this message translates to:
  /// **'Sample rates'**
  String get usbAudioDebugSampleRates;

  /// No description provided for @usbAudioDebugChannelCounts.
  ///
  /// In en, this message translates to:
  /// **'Channel counts'**
  String get usbAudioDebugChannelCounts;

  /// No description provided for @usbAudioDebugEncodings.
  ///
  /// In en, this message translates to:
  /// **'Encodings'**
  String get usbAudioDebugEncodings;

  /// No description provided for @usbAudioDebugAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get usbAudioDebugAddress;

  /// No description provided for @usbAudioDebugAny.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get usbAudioDebugAny;

  /// No description provided for @usbAudioDebugPlatformOnly.
  ///
  /// In en, this message translates to:
  /// **'Android only — not available on this platform'**
  String get usbAudioDebugPlatformOnly;

  /// No description provided for @ccCategoryTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Target category'**
  String get ccCategoryTargetLabel;

  /// No description provided for @ccCategoryGmCc.
  ///
  /// In en, this message translates to:
  /// **'Standard GM CC'**
  String get ccCategoryGmCc;

  /// No description provided for @ccCategoryInstruments.
  ///
  /// In en, this message translates to:
  /// **'Instruments'**
  String get ccCategoryInstruments;

  /// No description provided for @ccCategoryAudioEffects.
  ///
  /// In en, this message translates to:
  /// **'Audio Effects'**
  String get ccCategoryAudioEffects;

  /// No description provided for @ccCategoryMidiFx.
  ///
  /// In en, this message translates to:
  /// **'MIDI FX'**
  String get ccCategoryMidiFx;

  /// No description provided for @ccCategoryLooper.
  ///
  /// In en, this message translates to:
  /// **'Looper'**
  String get ccCategoryLooper;

  /// No description provided for @ccCategoryTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get ccCategoryTransport;

  /// No description provided for @ccCategoryGlobal.
  ///
  /// In en, this message translates to:
  /// **'Global'**
  String get ccCategoryGlobal;

  /// No description provided for @ccCategoryChannelSwap.
  ///
  /// In en, this message translates to:
  /// **'Channel Swap'**
  String get ccCategoryChannelSwap;

  /// No description provided for @ccTransportPlayStop.
  ///
  /// In en, this message translates to:
  /// **'Play / Stop'**
  String get ccTransportPlayStop;

  /// No description provided for @ccTransportTapTempo.
  ///
  /// In en, this message translates to:
  /// **'Tap Tempo'**
  String get ccTransportTapTempo;

  /// No description provided for @ccTransportMetronomeToggle.
  ///
  /// In en, this message translates to:
  /// **'Metronome Toggle'**
  String get ccTransportMetronomeToggle;

  /// No description provided for @ccGlobalSystemVolume.
  ///
  /// In en, this message translates to:
  /// **'System Volume'**
  String get ccGlobalSystemVolume;

  /// No description provided for @ccGlobalSystemVolumeHint.
  ///
  /// In en, this message translates to:
  /// **'CC 0-127 → System media volume (0-100%)'**
  String get ccGlobalSystemVolumeHint;

  /// No description provided for @ccSlotPickerLabel.
  ///
  /// In en, this message translates to:
  /// **'Slot'**
  String get ccSlotPickerLabel;

  /// No description provided for @ccParamPickerLabel.
  ///
  /// In en, this message translates to:
  /// **'Parameter'**
  String get ccParamPickerLabel;

  /// No description provided for @ccActionPickerLabel.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get ccActionPickerLabel;

  /// No description provided for @ccNoSlotsOfType.
  ///
  /// In en, this message translates to:
  /// **'No slots of this type in the rack.'**
  String get ccNoSlotsOfType;

  /// No description provided for @ccSwapInstrumentA.
  ///
  /// In en, this message translates to:
  /// **'Instrument A'**
  String get ccSwapInstrumentA;

  /// No description provided for @ccSwapInstrumentB.
  ///
  /// In en, this message translates to:
  /// **'Instrument B'**
  String get ccSwapInstrumentB;

  /// No description provided for @ccSwapCablesLabel.
  ///
  /// In en, this message translates to:
  /// **'Swap cables (effect chains, Jam Mode links)'**
  String get ccSwapCablesLabel;

  /// No description provided for @ccSwapNeedTwoSlots.
  ///
  /// In en, this message translates to:
  /// **'Need at least 2 instrument slots in the rack.'**
  String get ccSwapNeedTwoSlots;

  /// No description provided for @ccSwapDisplayLabel.
  ///
  /// In en, this message translates to:
  /// **'Swap: {slotA} ↔ {slotB}'**
  String ccSwapDisplayLabel(String slotA, String slotB);

  /// No description provided for @ccSwapCablesYes.
  ///
  /// In en, this message translates to:
  /// **'with cables'**
  String get ccSwapCablesYes;

  /// No description provided for @ccSwapCablesNo.
  ///
  /// In en, this message translates to:
  /// **'channels only'**
  String get ccSwapCablesNo;

  /// No description provided for @toastSwapped.
  ///
  /// In en, this message translates to:
  /// **'Swapped: {slotA} ↔ {slotB}'**
  String toastSwapped(String slotA, String slotB);

  /// No description provided for @toastBypassOn.
  ///
  /// In en, this message translates to:
  /// **'{slotName} — bypassed'**
  String toastBypassOn(String slotName);

  /// No description provided for @toastBypassOff.
  ///
  /// In en, this message translates to:
  /// **'{slotName} — active'**
  String toastBypassOff(String slotName);

  /// No description provided for @toastSystemVolume.
  ///
  /// In en, this message translates to:
  /// **'System volume: {percent}%'**
  String toastSystemVolume(int percent);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
