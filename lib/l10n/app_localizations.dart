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
  /// **'Vertical Interaction'**
  String get verticalInteraction;

  /// No description provided for @verticalInteractionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Swipe up/down on a key'**
  String get verticalInteractionSubtitle;

  /// No description provided for @horizontalInteraction.
  ///
  /// In en, this message translates to:
  /// **'Horizontal Interaction'**
  String get horizontalInteraction;

  /// No description provided for @horizontalInteractionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Slide left/right on a key'**
  String get horizontalInteractionSubtitle;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get actionSave;

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

  /// No description provided for @jamStart.
  ///
  /// In en, this message translates to:
  /// **'JAM'**
  String get jamStart;

  /// No description provided for @jamStop.
  ///
  /// In en, this message translates to:
  /// **'STOP'**
  String get jamStop;

  /// No description provided for @jamMaster.
  ///
  /// In en, this message translates to:
  /// **'Master'**
  String get jamMaster;

  /// No description provided for @jamSlaves.
  ///
  /// In en, this message translates to:
  /// **'Slaves'**
  String get jamSlaves;

  /// No description provided for @jamScale.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get jamScale;

  /// No description provided for @jamSelectSlavesDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Slave Channels'**
  String get jamSelectSlavesDialogTitle;

  /// No description provided for @jamModeToast.
  ///
  /// In en, this message translates to:
  /// **'Jam Mode: {status}'**
  String jamModeToast(String status);

  /// No description provided for @jamStarted.
  ///
  /// In en, this message translates to:
  /// **'STARTED'**
  String get jamStarted;

  /// No description provided for @jamStopped.
  ///
  /// In en, this message translates to:
  /// **'STOPPED'**
  String get jamStopped;

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
  /// **'Visible Keys (Zoom)'**
  String get visibleKeysTitle;

  /// No description provided for @visibleKeysSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Number of white keys to show at once'**
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

  /// No description provided for @synthVisibleChannelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Visible Channels'**
  String get synthVisibleChannelsTitle;

  /// No description provided for @synthChannelLabel.
  ///
  /// In en, this message translates to:
  /// **'Channel {channelIndex}'**
  String synthChannelLabel(int channelIndex);

  /// No description provided for @synthErrorAtLeastOneChannel.
  ///
  /// In en, this message translates to:
  /// **'At least one channel must be visible'**
  String get synthErrorAtLeastOneChannel;

  /// No description provided for @synthSaveFilters.
  ///
  /// In en, this message translates to:
  /// **'Save Filters'**
  String get synthSaveFilters;

  /// No description provided for @synthTooltipUserGuide.
  ///
  /// In en, this message translates to:
  /// **'User Guide'**
  String get synthTooltipUserGuide;

  /// No description provided for @synthTooltipFilterChannels.
  ///
  /// In en, this message translates to:
  /// **'Filter Visible Channels'**
  String get synthTooltipFilterChannels;

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

  /// No description provided for @scaleLockModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Scale Lock Mode'**
  String get scaleLockModeTitle;

  /// No description provided for @scaleLockModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Classic (per channel) vs Jam (master-slave)'**
  String get scaleLockModeSubtitle;

  /// No description provided for @modeClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic Mode'**
  String get modeClassic;

  /// No description provided for @modeJam.
  ///
  /// In en, this message translates to:
  /// **'Jam Mode'**
  String get modeJam;

  /// No description provided for @jamModeKeyGroupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Jam Mode Key Groups'**
  String get jamModeKeyGroupsTitle;

  /// No description provided for @jamModeKeyGroupsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Visually group scale-mapped keys with borders'**
  String get jamModeKeyGroupsSubtitle;

  /// No description provided for @highlightWrongNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'Highlight Wrong Notes'**
  String get highlightWrongNotesTitle;

  /// No description provided for @highlightWrongNotesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Color out-of-scale pressed keys in red'**
  String get highlightWrongNotesSubtitle;

  /// No description provided for @aftertouchEffectTitle.
  ///
  /// In en, this message translates to:
  /// **'Aftertouch Effect'**
  String get aftertouchEffectTitle;

  /// No description provided for @aftertouchEffectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Route keyboard pressure to this CC'**
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

  /// No description provided for @vocoderWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Feedback Warning'**
  String get vocoderWarningTitle;

  /// No description provided for @vocoderWarningBody.
  ///
  /// In en, this message translates to:
  /// **'Using the internal microphone and speakers simultaneously can cause a loud feedback loop (Larsen effect). Please use external headphones, a separate microphone, or an external speaker for a safe experience.'**
  String get vocoderWarningBody;

  /// No description provided for @vocoderWarningValidate.
  ///
  /// In en, this message translates to:
  /// **'Enable Vocoder'**
  String get vocoderWarningValidate;

  /// No description provided for @vocoderWarningCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get vocoderWarningCancel;

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
  /// **'Built-in synth & vocoder'**
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

  /// No description provided for @jamSlotOff.
  ///
  /// In en, this message translates to:
  /// **'JAM OFF'**
  String get jamSlotOff;

  /// No description provided for @jamSlotOn.
  ///
  /// In en, this message translates to:
  /// **'JAM ON'**
  String get jamSlotOn;

  /// No description provided for @jamSlotSelectMaster.
  ///
  /// In en, this message translates to:
  /// **'Select Jam Master'**
  String get jamSlotSelectMaster;

  /// No description provided for @jamSlotSelectMasterHint.
  ///
  /// In en, this message translates to:
  /// **'Which slot will drive the harmony for this keyboard?'**
  String get jamSlotSelectMasterHint;

  /// No description provided for @jamSlotChangeMaster.
  ///
  /// In en, this message translates to:
  /// **'Change master…'**
  String get jamSlotChangeMaster;

  /// No description provided for @jamSlotNoMasterSelected.
  ///
  /// In en, this message translates to:
  /// **'Pick master'**
  String get jamSlotNoMasterSelected;

  /// No description provided for @jamSlotNoOtherSlots.
  ///
  /// In en, this message translates to:
  /// **'No other slots available to follow.'**
  String get jamSlotNoOtherSlots;

  /// No description provided for @jamSlotClearMaster.
  ///
  /// In en, this message translates to:
  /// **'Clear Jam master'**
  String get jamSlotClearMaster;

  /// No description provided for @vst3LoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load VST3 plugin. Make sure you selected the .vst3 bundle folder.'**
  String get vst3LoadFailed;

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
