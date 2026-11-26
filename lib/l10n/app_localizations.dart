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

  /// No description provided for @pianoVelocityTitle.
  ///
  /// In en, this message translates to:
  /// **'Key velocity'**
  String get pianoVelocityTitle;

  /// No description provided for @pianoVelocitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'How hard the on-screen keys play. By touch: the closer to the front edge of the key, the louder.'**
  String get pianoVelocitySubtitle;

  /// No description provided for @pianoVelocityTouch.
  ///
  /// In en, this message translates to:
  /// **'By touch'**
  String get pianoVelocityTouch;

  /// No description provided for @pianoVelocitySoft.
  ///
  /// In en, this message translates to:
  /// **'Soft'**
  String get pianoVelocitySoft;

  /// No description provided for @pianoVelocityMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get pianoVelocityMedium;

  /// No description provided for @pianoVelocityLoud.
  ///
  /// In en, this message translates to:
  /// **'Loud'**
  String get pianoVelocityLoud;

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
  /// **'Made with Flutter in Paris'**
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

  /// No description provided for @guideTabMidi.
  ///
  /// In en, this message translates to:
  /// **'MIDI controllers'**
  String get guideTabMidi;

  /// No description provided for @guideTabTips.
  ///
  /// In en, this message translates to:
  /// **'Playing tips'**
  String get guideTabTips;

  /// No description provided for @guideTabPatch.
  ///
  /// In en, this message translates to:
  /// **'Cables'**
  String get guideTabPatch;

  /// No description provided for @guidePatchGroupInstruments.
  ///
  /// In en, this message translates to:
  /// **'Instruments'**
  String get guidePatchGroupInstruments;

  /// No description provided for @guidePatchGroupRhythm.
  ///
  /// In en, this message translates to:
  /// **'Drums & loopers'**
  String get guidePatchGroupRhythm;

  /// No description provided for @guidePatchGroupCustom.
  ///
  /// In en, this message translates to:
  /// **'Your own plugins'**
  String get guidePatchGroupCustom;

  /// No description provided for @guidePatchSlotKeyboard.
  ///
  /// In en, this message translates to:
  /// **'Keyboard'**
  String get guidePatchSlotKeyboard;

  /// No description provided for @guidePatchSlotKeyboardDesc.
  ///
  /// In en, this message translates to:
  /// **'Plays a piano or any sound from a soundfont (.sf2). Set it to None (MIDI only) to use it only to send notes to other modules. A key touched near its front edge plays louder than near the back; Preferences > Key velocity can fix one strength instead.'**
  String get guidePatchSlotKeyboardDesc;

  /// No description provided for @guidePatchSlotVocoder.
  ///
  /// In en, this message translates to:
  /// **'Vocoder'**
  String get guidePatchSlotVocoder;

  /// No description provided for @guidePatchSlotVocoderDesc.
  ///
  /// In en, this message translates to:
  /// **'Your voice through the microphone becomes a synth that plays the notes you hold.'**
  String get guidePatchSlotVocoderDesc;

  /// No description provided for @guidePatchSlotJam.
  ///
  /// In en, this message translates to:
  /// **'Jam Mode'**
  String get guidePatchSlotJam;

  /// No description provided for @guidePatchSlotJamDesc.
  ///
  /// In en, this message translates to:
  /// **'Keeps one keyboard in the scale of the chords another keyboard plays.'**
  String get guidePatchSlotJamDesc;

  /// No description provided for @guidePatchSlotVst3.
  ///
  /// In en, this message translates to:
  /// **'VST3 Plugin'**
  String get guidePatchSlotVst3;

  /// No description provided for @guidePatchSlotVst3Desc.
  ///
  /// In en, this message translates to:
  /// **'Loads a VST3 instrument or effect installed on your computer.'**
  String get guidePatchSlotVst3Desc;

  /// No description provided for @guidePatchSlotVst3DesktopOnly.
  ///
  /// In en, this message translates to:
  /// **'VST3 plugins work on Linux, macOS and Windows only, not on Android or in the web demo.'**
  String get guidePatchSlotVst3DesktopOnly;

  /// No description provided for @guidePatchTitle.
  ///
  /// In en, this message translates to:
  /// **'The cable view'**
  String get guidePatchTitle;

  /// No description provided for @guidePatchIntro.
  ///
  /// In en, this message translates to:
  /// **'Tap the cable icon at the top of the rack to see the back of every module. Tap the back arrow to return. Modules cannot be moved in this view.'**
  String get guidePatchIntro;

  /// No description provided for @guidePatchDrawTitle.
  ///
  /// In en, this message translates to:
  /// **'Drawing a cable'**
  String get guidePatchDrawTitle;

  /// No description provided for @guidePatchDrawBody.
  ///
  /// In en, this message translates to:
  /// **'Long-press an output socket and drag. Sockets that accept the cable light up. Release on one to connect, anywhere else to cancel. An output only connects to an input of the same colour.'**
  String get guidePatchDrawBody;

  /// No description provided for @guidePatchDisconnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Removing a cable'**
  String get guidePatchDisconnectTitle;

  /// No description provided for @guidePatchDisconnectBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the small ✕ in the middle of a cable, then Disconnect. Removing a module removes its cables too.'**
  String get guidePatchDisconnectBody;

  /// No description provided for @guidePatchDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Scale and tuning cables'**
  String get guidePatchDataTitle;

  /// No description provided for @guidePatchDataBody.
  ///
  /// In en, this message translates to:
  /// **'Purple cables carry harmony. CHORD OUT into CHORD IN tells Jam Mode or Xen which keyboard\'s chords to follow. SCALE OUT into SCALE IN adds a keyboard that follows the scale. The cables and the menus in the panels always agree.\nTeal TUNE OUT into TUNE IN carries a Xen scale\'s tuning to an instrument. It is separate from the scale cable, so you can keep a keyboard in a scale without retuning it, or the other way round.'**
  String get guidePatchDataBody;

  /// No description provided for @guidePatchSharedEffectTitle.
  ///
  /// In en, this message translates to:
  /// **'One effect, one signal'**
  String get guidePatchSharedEffectTitle;

  /// No description provided for @guidePatchSharedEffectBody.
  ///
  /// In en, this message translates to:
  /// **'An effect remembers the sound passing through it (a reverb tail, a delay line), so it can only process one signal. Two keyboards cabled straight into the same reverb is fine: they are mixed first. One keyboard straight into a reverb and another through a harmonizer into the same reverb is two different signals, and GrooveForge refuses the cable.'**
  String get guidePatchSharedEffectBody;

  /// No description provided for @guidePatchSharedEffectWorkaround.
  ///
  /// In en, this message translates to:
  /// **'If a cable is refused for this reason, add a second copy of the effect and cable the other signal into it.'**
  String get guidePatchSharedEffectWorkaround;

  /// No description provided for @guidePatchTip.
  ///
  /// In en, this message translates to:
  /// **'Cables are saved with the project.'**
  String get guidePatchTip;

  /// No description provided for @guideXenTitle.
  ///
  /// In en, this message translates to:
  /// **'Xen: scales and tunings'**
  String get guideXenTitle;

  /// No description provided for @guideXenBody.
  ///
  /// In en, this message translates to:
  /// **'Xen keeps every note you play inside a scale. Hold a key and tap a scale: the key you hold becomes the root note, until you do it again. Picking a scale also switches Xen on.\nSNAP moves notes that are outside the scale to the nearest one that fits; the piano greys them out. TUNE plays the scale\'s own tuning, for scales whose notes fall between the piano keys: those keys get a teal band and their offset in cents. SNAP and TUNE switch on and off separately.\nThe Family menu has Western modes, Arabic and Turkish maqamat, Indian ragas, Chinese, Japanese and Korean scales, gamelan tunings, historical temperaments and more. My Scales holds the scales you build or import from Scala (.scl) files.'**
  String get guideXenBody;

  /// No description provided for @guideJamModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Jam Mode'**
  String get guideJamModeTitle;

  /// No description provided for @guideJamModeBody.
  ///
  /// In en, this message translates to:
  /// **'Jam Mode is for two keyboards: one plays chords, the other improvises. In its panel, MASTER is the keyboard whose chords set the scale, and TARGETS are the keyboards that follow. Every note a target plays moves into that scale. You can also draw the link in the cable view: CHORD OUT into CHORD IN, SCALE OUT into SCALE IN.'**
  String get guideJamModeBody;

  /// No description provided for @guideVocoderTitle.
  ///
  /// In en, this message translates to:
  /// **'Vocoder'**
  String get guideVocoderTitle;

  /// No description provided for @guideVocoderBody.
  ///
  /// In en, this message translates to:
  /// **'Tap + and pick Vocoder. Sing or talk into the microphone while you hold notes: your voice shapes a synth that plays them. Set the microphone level with the gain knobs. Try the carrier waves (Saw, Square, Choral), or Harmony, which drops the synth and moves your own voice onto the keys you hold.'**
  String get guideVocoderBody;

  /// No description provided for @guideThereminTitle.
  ///
  /// In en, this message translates to:
  /// **'Theremin and Stylophone'**
  String get guideThereminTitle;

  /// No description provided for @guideThereminBody.
  ///
  /// In en, this message translates to:
  /// **'The Theremin has two modes. PAD is a touch pad: slide up and down for pitch, left and right for volume. CAM (Android, iOS and macOS) uses the front camera to sense how far your hand is: closer plays higher, far enough away is silent, and volume stays full. BASE sets the lowest note, RANGE the span in octaves, VIB the vibrato and HEIGHT the size of the pad.\nThe Stylophone is a 25-key strip you play by touching or sliding along it. It plays one note at a time, like the original, and glides between keys without a click. SQR, SAW, SIN and TRI pick the waveform.'**
  String get guideThereminBody;

  /// No description provided for @guideDrumGeneratorTitle.
  ///
  /// In en, this message translates to:
  /// **'Drum Generator'**
  String get guideDrumGeneratorTitle;

  /// No description provided for @guideDrumGeneratorBody.
  ///
  /// In en, this message translates to:
  /// **'Plays a drum pattern at the transport tempo, from bossa nova to metal. Swing pushes the off-beats late. Human feel goes from a strict grid to a drummer who breathes. Count-in plays a few hits before the pattern starts, and Fill every adds a fill every few bars.\nSong form lays out a whole song as blocks (intro, verse, chorus, bridge, break, ending). Tap + to add one, tap a block to edit it, long-press to move it. Without an ending block the form loops; with one, the drums end the song and stop the transport.\nPatterns are .gfdrum files, so you can add your own.'**
  String get guideDrumGeneratorBody;

  /// No description provided for @guideLoopersTitle.
  ///
  /// In en, this message translates to:
  /// **'Loopers'**
  String get guideLoopersTitle;

  /// No description provided for @guideLoopersBody.
  ///
  /// In en, this message translates to:
  /// **'The MIDI Looper records the notes you play and loops them. The Audio Looper records sound, and can also overdub and reverse.\nBoth wait for the next bar to start recording and round the loop to whole bars, so loops stay in time with each other.\nThe Audio Looper records what is cabled into its AUDIO IN: cable an instrument or a Live Input into it first.'**
  String get guideLoopersBody;

  /// No description provided for @guideMidiFxTitle.
  ///
  /// In en, this message translates to:
  /// **'MIDI FX'**
  String get guideMidiFxTitle;

  /// No description provided for @guideMidiFxBody.
  ///
  /// In en, this message translates to:
  /// **'MIDI FX change the notes on their way from a keyboard to its sound. Harmonizer adds up to four voices to what you play; with Scale Lock on, they stay in the current scale. Chord Expand turns one note into a chord. Arpeggiator plays held notes one after another, in time. Transposer shifts everything by up to two octaves. Velocity Curve changes how loud soft and hard notes come out. Gate lets through only notes within a velocity or pitch range. Microtone merges held notes into one microtonal pitch.'**
  String get guideMidiFxBody;

  /// No description provided for @guideMidiTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect a controller'**
  String get guideMidiTitle;

  /// No description provided for @guideMidiBody.
  ///
  /// In en, this message translates to:
  /// **'GrooveForge works with USB MIDI keyboards and pads (through an OTG adapter on a phone) and with Bluetooth MIDI devices.'**
  String get guideMidiBody;

  /// No description provided for @guideMidiBestPracticeTitle.
  ///
  /// In en, this message translates to:
  /// **'One keyboard or two?'**
  String get guideMidiBestPracticeTitle;

  /// No description provided for @guideMidiBestPracticeBody.
  ///
  /// In en, this message translates to:
  /// **'One keyboard is enough: a new project pairs a GrooveForge Keyboard with a Xen module. Xen starts off and switches on when you pick a scale: hold a note and tap a scale button.\nA second keyboard, or a controller split in two, is useful for Jam Mode: one hand plays the chords that set the scale, the other improvises over them.'**
  String get guideMidiBestPracticeBody;

  /// No description provided for @guideSoundfontsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sounds (soundfonts)'**
  String get guideSoundfontsTitle;

  /// No description provided for @guideSoundfontsBody.
  ///
  /// In en, this message translates to:
  /// **'The keyboard plays its sounds from soundfont files (.sf2). To add one, open Preferences, then under Soundfonts tap Load Soundfont (.sf2). It then appears in the sound menu of every keyboard. A good soundfont can take several hundred MB.'**
  String get guideSoundfontsBody;

  /// No description provided for @guideTipsTitle.
  ///
  /// In en, this message translates to:
  /// **'Improvising'**
  String get guideTipsTitle;

  /// No description provided for @guideTipsBody.
  ///
  /// In en, this message translates to:
  /// **'New to improvising? A few ideas:\n• In a scale, every key fits the music. There are no wrong notes, only surprising ones.\n• Start or end your phrases on the root note: it sounds like coming home.\n• Rhythm first. A simple idea played in time beats a fast run.\n• Leave space. Short phrases with rests between them sound more musical than a stream of notes.'**
  String get guideTipsBody;

  /// No description provided for @guideWelcomeHeader.
  ///
  /// In en, this message translates to:
  /// **'Welcome to GrooveForge v{version}'**
  String guideWelcomeHeader(String version);

  /// No description provided for @guideWelcomeIntro.
  ///
  /// In en, this message translates to:
  /// **'Short recipes to get going. Each one links to a clip of the gesture on the website.'**
  String get guideWelcomeIntro;

  /// No description provided for @guideChangelogExpand.
  ///
  /// In en, this message translates to:
  /// **'What\'s new in this version'**
  String get guideChangelogExpand;

  /// No description provided for @guideMidiHardwareStep1.
  ///
  /// In en, this message translates to:
  /// **'Plug the controller in, or switch on the Bluetooth one.'**
  String get guideMidiHardwareStep1;

  /// No description provided for @guideMidiHardwareStep2.
  ///
  /// In en, this message translates to:
  /// **'Open Preferences with the gear icon. Under MIDI Connection, tap Connect MIDI Device and pick it.'**
  String get guideMidiHardwareStep2;

  /// No description provided for @guideMidiCcMappings.
  ///
  /// In en, this message translates to:
  /// **'Map knobs and pads'**
  String get guideMidiCcMappings;

  /// No description provided for @guideMidiCcMappingsBody.
  ///
  /// In en, this message translates to:
  /// **'For a module\'s controls: tap the sliders icon at the top of the module, tap Learn next to a control, then move a knob or press a pad.\nFor actions that concern the whole app (looper, transport, channel swap and more): open Preferences, then CC Mapping Preferences, then Add Mapping.'**
  String get guideMidiCcMappingsBody;

  /// No description provided for @guideMidiTipSplit.
  ///
  /// In en, this message translates to:
  /// **'Many controllers can split their keys into two zones on different MIDI channels, for example bass in the left hand and melody in the right.'**
  String get guideMidiTipSplit;

  /// No description provided for @guideAndroidUsbLimitation.
  ///
  /// In en, this message translates to:
  /// **'Android keeps only one USB audio device at a time. If plugging in a USB microphone silences your USB headphones or sound card, turn on Direct USB output in Preferences, under Audio Output.'**
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

  /// No description provided for @usbDirectOutputTitle.
  ///
  /// In en, this message translates to:
  /// **'Direct USB output'**
  String get usbDirectOutputTitle;

  /// No description provided for @usbDirectOutputSubtitle.
  ///
  /// In en, this message translates to:
  /// **'For a USB mic and a USB sound card (DAC) used together: Android only keeps one of them. Tap ? to learn more.'**
  String get usbDirectOutputSubtitle;

  /// No description provided for @usbDirectOutputUnknownDevice.
  ///
  /// In en, this message translates to:
  /// **'USB DAC'**
  String get usbDirectOutputUnknownDevice;

  /// No description provided for @usbDirectOutputStatusNoDevice.
  ///
  /// In en, this message translates to:
  /// **'Waiting: no compatible USB DAC is plugged in.'**
  String get usbDirectOutputStatusNoDevice;

  /// No description provided for @usbDirectOutputStatusAndroidRoutes.
  ///
  /// In en, this message translates to:
  /// **'Not needed right now: Android already plays through your USB device.'**
  String get usbDirectOutputStatusAndroidRoutes;

  /// No description provided for @usbDirectOutputStatusPermission.
  ///
  /// In en, this message translates to:
  /// **'Android is asking for access to {device}: tap Allow.'**
  String usbDirectOutputStatusPermission(String device);

  /// No description provided for @usbDirectOutputStatusDenied.
  ///
  /// In en, this message translates to:
  /// **'USB access to {device} was declined. Replug it, or turn this off and on, to be asked again.'**
  String usbDirectOutputStatusDenied(String device);

  /// No description provided for @usbDirectOutputStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Playing through {device} ({rate} Hz, {bits}-bit). Set the volume in GrooveForge or on your speaker: the phone\'s volume keys don\'t reach this output.'**
  String usbDirectOutputStatusActive(String device, int rate, int bits);

  /// No description provided for @usbDirectOutputStatusUnsupported.
  ///
  /// In en, this message translates to:
  /// **'{device} can\'t be used: only simple USB DACs (USB Audio Class 1) are supported.'**
  String usbDirectOutputStatusUnsupported(String device);

  /// No description provided for @usbDirectOutputStatusError.
  ///
  /// In en, this message translates to:
  /// **'{device} stopped. Unplug and replug it to try again.'**
  String usbDirectOutputStatusError(String device);

  /// Tooltip of the help button next to the Direct USB output switch.
  ///
  /// In en, this message translates to:
  /// **'How does it work?'**
  String get usbDirectOutputHelpTooltip;

  /// Help sheet section title.
  ///
  /// In en, this message translates to:
  /// **'The problem'**
  String get usbDirectOutputHelpProblemTitle;

  /// No description provided for @usbDirectOutputHelpProblemBody.
  ///
  /// In en, this message translates to:
  /// **'Android can only use one USB audio device at a time. Plug in a USB microphone (a wireless mic receiver, for example) and a USB sound card (such as the headphone jack of a USB-C hub), and Android keeps the one it detected last and quietly ignores the other. Your music then comes out of the phone\'s speaker instead of your headphones or speakers.'**
  String get usbDirectOutputHelpProblemBody;

  /// Help sheet section title.
  ///
  /// In en, this message translates to:
  /// **'What this option does'**
  String get usbDirectOutputHelpSolutionTitle;

  /// No description provided for @usbDirectOutputHelpSolutionBody.
  ///
  /// In en, this message translates to:
  /// **'GrooveForge sends its sound straight to the sound card Android ignored, over USB, without going through Android\'s audio system. Your microphone keeps working normally.'**
  String get usbDirectOutputHelpSolutionBody;

  /// Help sheet section title.
  ///
  /// In en, this message translates to:
  /// **'When it kicks in'**
  String get usbDirectOutputHelpWhenTitle;

  /// No description provided for @usbDirectOutputHelpWhenBody.
  ///
  /// In en, this message translates to:
  /// **'Only when it is needed: a compatible USB sound card is plugged in and Android is not already playing through a USB device. The rest of the time nothing changes, so you can leave it on.'**
  String get usbDirectOutputHelpWhenBody;

  /// Help sheet section title.
  ///
  /// In en, this message translates to:
  /// **'How to use it'**
  String get usbDirectOutputHelpStepsTitle;

  /// No description provided for @usbDirectOutputHelpStep1.
  ///
  /// In en, this message translates to:
  /// **'Turn the option on.'**
  String get usbDirectOutputHelpStep1;

  /// No description provided for @usbDirectOutputHelpStep2.
  ///
  /// In en, this message translates to:
  /// **'Plug in your sound card and your USB microphone.'**
  String get usbDirectOutputHelpStep2;

  /// No description provided for @usbDirectOutputHelpStep3.
  ///
  /// In en, this message translates to:
  /// **'When Android asks for access to the sound card, tap Allow.'**
  String get usbDirectOutputHelpStep3;

  /// No description provided for @usbDirectOutputHelpStep4.
  ///
  /// In en, this message translates to:
  /// **'The line under the switch shows \"Playing through…\": you\'re set.'**
  String get usbDirectOutputHelpStep4;

  /// Help sheet section title.
  ///
  /// In en, this message translates to:
  /// **'Good to know'**
  String get usbDirectOutputHelpTipsTitle;

  /// No description provided for @usbDirectOutputHelpTipVolume.
  ///
  /// In en, this message translates to:
  /// **'The phone\'s volume keys don\'t change this output. Use GrooveForge\'s gain and your speaker\'s volume.'**
  String get usbDirectOutputHelpTipVolume;

  /// No description provided for @usbDirectOutputHelpTipCompat.
  ///
  /// In en, this message translates to:
  /// **'Works with simple USB sound cards (USB Audio Class 1), which covers most USB-C hubs and jack adapters. High-end USB interfaces are shown as not supported.'**
  String get usbDirectOutputHelpTipCompat;

  /// No description provided for @usbDirectOutputHelpTipOtherApps.
  ///
  /// In en, this message translates to:
  /// **'Only GrooveForge plays through the sound card this way. Notifications and other apps still use the phone.'**
  String get usbDirectOutputHelpTipOtherApps;

  /// No description provided for @usbDirectOutputHelpTipGiveBack.
  ///
  /// In en, this message translates to:
  /// **'After turning the option off, unplug and replug the sound card so Android can use it again.'**
  String get usbDirectOutputHelpTipGiveBack;

  /// No description provided for @usbDirectOutputHelpTipCharger.
  ///
  /// In en, this message translates to:
  /// **'Plug the charger into the hub before connecting the hub to the phone. Adding power while playing makes the phone reconnect every USB device, which cuts the sound and can even restart some phones.'**
  String get usbDirectOutputHelpTipCharger;

  /// Button closing the help sheet.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get usbDirectOutputHelpClose;

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

  /// No description provided for @rackChannelShort.
  ///
  /// In en, this message translates to:
  /// **'CH {channel}'**
  String rackChannelShort(int channel);

  /// No description provided for @rackChannelInUse.
  ///
  /// In en, this message translates to:
  /// **'CH {channel} (in use)'**
  String rackChannelInUse(int channel);

  /// No description provided for @rackPluginNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Plugin not installed: {pluginId}'**
  String rackPluginNotInstalled(String pluginId);

  /// Shown in a keyboard slot whose stored MIDI channel is outside 1-16.
  ///
  /// In en, this message translates to:
  /// **'Invalid MIDI channel'**
  String get rackInvalidMidiChannel;

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

  /// No description provided for @splashCheckingPermissions.
  ///
  /// In en, this message translates to:
  /// **'Checking permissions...'**
  String get splashCheckingPermissions;

  /// No description provided for @splashLoadingPlugin.
  ///
  /// In en, this message translates to:
  /// **'Loading {name}…'**
  String splashLoadingPlugin(String name);

  /// No description provided for @prefsVersionLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get prefsVersionLoading;

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

  /// No description provided for @vst3EditorOpenFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Could not open the plugin\'s window.'**
  String get vst3EditorOpenFailedGeneric;

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

  /// Shown when a user tries to cable two divergent signal paths into the same stateful effect. Named the 'Phase H block' in the audio routing redesign.
  ///
  /// In en, this message translates to:
  /// **'{effectName} is already cabled from another signal path. Duplicate the effect slot so each path has its own instance.'**
  String connectionSharedEffectError(String effectName);

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

  /// No description provided for @portTuningOut.
  ///
  /// In en, this message translates to:
  /// **'TUNE OUT'**
  String get portTuningOut;

  /// No description provided for @portTuningIn.
  ///
  /// In en, this message translates to:
  /// **'TUNE IN'**
  String get portTuningIn;

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

  /// No description provided for @rackAddAudioLooper.
  ///
  /// In en, this message translates to:
  /// **'Audio Looper'**
  String get rackAddAudioLooper;

  /// No description provided for @rackAddAudioLooperSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Record and loop live audio (PCM) with bar sync, overdub, and reverse'**
  String get rackAddAudioLooperSubtitle;

  /// Section header in the Add Plugin sheet for hardware audio source slots (microphone, line-in).
  ///
  /// In en, this message translates to:
  /// **'Audio Sources'**
  String get rackAddSourcesSectionLabel;

  /// Tile title for the Live Input source slot that exposes a hardware audio input as a cable-able audio output.
  ///
  /// In en, this message translates to:
  /// **'Live Input'**
  String get rackAddLiveInputSource;

  /// Subtitle for the Live Input source slot tile.
  ///
  /// In en, this message translates to:
  /// **'Route a microphone or line-in into any effect (harmonizer, vocoder, reverb…)'**
  String get rackAddLiveInputSourceSubtitle;

  /// Shown in the Live Input slot when no capture device is available.
  ///
  /// In en, this message translates to:
  /// **'No input device detected'**
  String get liveInputNoDevice;

  /// Under the input device name in the Live Input slot: the device is chosen in Preferences, not in the slot.
  ///
  /// In en, this message translates to:
  /// **'Change the input in Preferences › Audio Input'**
  String get liveInputDeviceHint;

  /// Live Input slot notice when the input chosen in Preferences is unplugged; capture stops instead of switching to the phone's microphone.
  ///
  /// In en, this message translates to:
  /// **'Microphone unplugged: input stopped. Plug it back in or choose another input in Preferences.'**
  String get liveInputDisconnected;

  /// Live Input slot notice when the input fell back to the phone microphone while the output is the phone speaker.
  ///
  /// In en, this message translates to:
  /// **'Muted: the phone\'s mic would feed back through its speaker.'**
  String get liveInputFeedbackMuted;

  /// Button that lets Live Input play despite the feedback risk.
  ///
  /// In en, this message translates to:
  /// **'Unmute anyway'**
  String get liveInputFeedbackUnmute;

  /// Preferences: the chosen audio device is not plugged in.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get audioDeviceDisconnected;

  /// Snackbar when the chosen input device disappears.
  ///
  /// In en, this message translates to:
  /// **'Microphone unplugged: input stopped instead of switching to the phone mic'**
  String get micDisconnectedToast;

  /// Label for the input gain slider in the Live Input slot.
  ///
  /// In en, this message translates to:
  /// **'Gain'**
  String get liveInputGainLabel;

  /// Tooltip for the monitor-mute toggle in the Live Input slot.
  ///
  /// In en, this message translates to:
  /// **'Mute local monitor (still feeds effects)'**
  String get liveInputMonitorMute;

  /// Placeholder shown inside the audio looper waveform area while a clip is actively recording and no waveform has been computed yet.
  ///
  /// In en, this message translates to:
  /// **'Recording…'**
  String get audioLooperWaveformRecording;

  /// Placeholder shown when an audio looper slot has no cables on its back-panel Audio IN ports — recording would produce silence.
  ///
  /// In en, this message translates to:
  /// **'Cable an instrument to Audio IN'**
  String get audioLooperWaveformCableInstrument;

  /// Placeholder shown when an audio looper slot has cables wired but the clip has no recorded audio yet.
  ///
  /// In en, this message translates to:
  /// **'No audio recorded'**
  String get audioLooperWaveformEmpty;

  /// Tooltip for the audio looper Stop button.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get audioLooperTooltipStop;

  /// Tooltip for the audio looper Reverse-playback toggle button.
  ///
  /// In en, this message translates to:
  /// **'Reverse'**
  String get audioLooperTooltipReverse;

  /// Tooltip for the audio looper bar-sync toggle when it is enabled — recording will wait for the next downbeat.
  ///
  /// In en, this message translates to:
  /// **'Bar sync: ON'**
  String get audioLooperTooltipBarSyncOn;

  /// Tooltip for the audio looper bar-sync toggle when it is disabled — recording will start immediately.
  ///
  /// In en, this message translates to:
  /// **'Bar sync: OFF'**
  String get audioLooperTooltipBarSyncOff;

  /// Tooltip for the audio looper Clear button (erases the clip).
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get audioLooperTooltipClear;

  /// Tooltip for the audio looper main loop button when idle with no audio — next press starts recording.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get audioLooperTooltipRecord;

  /// Tooltip for the audio looper main loop button when idle with existing audio — next press starts playback.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get audioLooperTooltipPlay;

  /// Tooltip for the audio looper main loop button while armed — next press cancels the arm.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get audioLooperTooltipCancel;

  /// Tooltip for the audio looper main loop button while recording — next press ends recording and begins playback.
  ///
  /// In en, this message translates to:
  /// **'Stop recording & play'**
  String get audioLooperTooltipStopRecordingAndPlay;

  /// Tooltip for the audio looper main loop button while silence is being padded to the next bar boundary (STOPPING state).
  ///
  /// In en, this message translates to:
  /// **'Padding to bar…'**
  String get audioLooperTooltipPaddingToBar;

  /// Tooltip for the audio looper main loop button while playing — next press starts overdubbing new audio on top.
  ///
  /// In en, this message translates to:
  /// **'Overdub'**
  String get audioLooperTooltipOverdub;

  /// Tooltip for the audio looper main loop button while overdubbing — next press ends the overdub pass and returns to playing.
  ///
  /// In en, this message translates to:
  /// **'Stop overdub'**
  String get audioLooperTooltipStopOverdub;

  /// Short status chip label for the audio looper IDLE state (uppercase; kept short to fit the chip).
  ///
  /// In en, this message translates to:
  /// **'IDLE'**
  String get audioLooperStatusIdle;

  /// Short status chip label for the audio looper ARMED state (waiting for the next downbeat to start recording).
  ///
  /// In en, this message translates to:
  /// **'ARMED'**
  String get audioLooperStatusArmed;

  /// Short status chip label for the audio looper RECORDING state.
  ///
  /// In en, this message translates to:
  /// **'REC'**
  String get audioLooperStatusRecording;

  /// Short status chip label for the audio looper PLAYING state.
  ///
  /// In en, this message translates to:
  /// **'PLAY'**
  String get audioLooperStatusPlaying;

  /// Short status chip label for the audio looper OVERDUBBING state.
  ///
  /// In en, this message translates to:
  /// **'ODUB'**
  String get audioLooperStatusOverdubbing;

  /// Short status chip label for the audio looper STOPPING state (padding silence to the next bar boundary).
  ///
  /// In en, this message translates to:
  /// **'PAD'**
  String get audioLooperStatusStopping;

  /// Label preceding the audio looper's source-selector dropdown — shows which instrument feeds the clip.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get audioLooperSourceLabel;

  /// Tooltip for the audio looper source-selector dropdown button.
  ///
  /// In en, this message translates to:
  /// **'Pick which instrument feeds this looper'**
  String get audioLooperSourceTooltip;

  /// Source-selector entry shown when no audio cable feeds the looper (recording would be silent).
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get audioLooperSourceNone;

  /// Source-selector label when the current upstream slot cannot be matched to any known audio-producing plugin type — usually a stale reference to a removed slot.
  ///
  /// In en, this message translates to:
  /// **'Unknown source'**
  String get audioLooperSourceUnknown;

  /// Source-selector label when the user has wired multiple upstream slots to the looper by hand from the back panel. Shown as a non-destructive informational state — selecting a new item from the dropdown still overrides it.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =2{Multiple (2 sources)} other{Multiple ({count} sources)}}'**
  String audioLooperSourceMultiple(int count);

  /// Toast shown once per session the first time the audio looper's total allocated pool memory crosses its soft cap. Not a hard cap — recording continues, but the user is nudged to clear clips.
  ///
  /// In en, this message translates to:
  /// **'Audio looper memory: {usedMb} MB / {capMb} MB cap — consider clearing unused clips'**
  String audioLooperMemoryCapWarning(String usedMb, int capMb);

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

  /// No description provided for @jamModeOn.
  ///
  /// In en, this message translates to:
  /// **'ON'**
  String get jamModeOn;

  /// No description provided for @jamModeOff.
  ///
  /// In en, this message translates to:
  /// **'OFF'**
  String get jamModeOff;

  /// No description provided for @jamModeScaleTypeStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get jamModeScaleTypeStandard;

  /// No description provided for @jamModeScaleTypePentatonic.
  ///
  /// In en, this message translates to:
  /// **'Pentatonic'**
  String get jamModeScaleTypePentatonic;

  /// No description provided for @jamModeScaleTypeBlues.
  ///
  /// In en, this message translates to:
  /// **'Blues'**
  String get jamModeScaleTypeBlues;

  /// No description provided for @jamModeScaleTypeRock.
  ///
  /// In en, this message translates to:
  /// **'Rock'**
  String get jamModeScaleTypeRock;

  /// No description provided for @jamModeScaleTypeJazz.
  ///
  /// In en, this message translates to:
  /// **'Jazz'**
  String get jamModeScaleTypeJazz;

  /// No description provided for @jamModeScaleTypeDorian.
  ///
  /// In en, this message translates to:
  /// **'Dorian'**
  String get jamModeScaleTypeDorian;

  /// No description provided for @jamModeScaleTypeMixolydian.
  ///
  /// In en, this message translates to:
  /// **'Mixolydian'**
  String get jamModeScaleTypeMixolydian;

  /// No description provided for @jamModeScaleTypeHarmonicMinor.
  ///
  /// In en, this message translates to:
  /// **'Harm. Minor'**
  String get jamModeScaleTypeHarmonicMinor;

  /// No description provided for @jamModeScaleTypeMelodicMinor.
  ///
  /// In en, this message translates to:
  /// **'Mel. Minor'**
  String get jamModeScaleTypeMelodicMinor;

  /// No description provided for @jamModeScaleTypeClassical.
  ///
  /// In en, this message translates to:
  /// **'Classical'**
  String get jamModeScaleTypeClassical;

  /// No description provided for @jamModeScaleTypeAsiatic.
  ///
  /// In en, this message translates to:
  /// **'Asiatic'**
  String get jamModeScaleTypeAsiatic;

  /// No description provided for @jamModeScaleTypeOriental.
  ///
  /// In en, this message translates to:
  /// **'Oriental'**
  String get jamModeScaleTypeOriental;

  /// No description provided for @jamModeScaleTypeWholeTone.
  ///
  /// In en, this message translates to:
  /// **'Whole Tone'**
  String get jamModeScaleTypeWholeTone;

  /// No description provided for @jamModeScaleTypeDiminished.
  ///
  /// In en, this message translates to:
  /// **'Diminished'**
  String get jamModeScaleTypeDiminished;

  /// No description provided for @jamModeNoMaster.
  ///
  /// In en, this message translates to:
  /// **'— NO MASTER —'**
  String get jamModeNoMaster;

  /// No description provided for @jamModeScaleTypeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Tap to change the scale type\nCurrent: {scale}'**
  String jamModeScaleTypeTooltip(String scale);

  /// No description provided for @jamModeScaleTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'SCALE TYPE'**
  String get jamModeScaleTypeLabel;

  /// Jam Mode panel label for the keyboard whose chords set the scale.
  ///
  /// In en, this message translates to:
  /// **'MASTER'**
  String get jamModeMasterLabel;

  /// No description provided for @jamModePickHint.
  ///
  /// In en, this message translates to:
  /// **'— pick —'**
  String get jamModePickHint;

  /// No description provided for @jamModeNone.
  ///
  /// In en, this message translates to:
  /// **'— none —'**
  String get jamModeNone;

  /// Jam Mode panel label for the keyboards that follow the scale.
  ///
  /// In en, this message translates to:
  /// **'TARGETS'**
  String get jamModeTargetsLabel;

  /// No description provided for @jamModeAddTarget.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get jamModeAddTarget;

  /// No description provided for @jamModeDetectLabel.
  ///
  /// In en, this message translates to:
  /// **'DETECT'**
  String get jamModeDetectLabel;

  /// No description provided for @jamModeDetectTooltip.
  ///
  /// In en, this message translates to:
  /// **'♪ Chord — detect the scale from all notes pressed simultaneously on the master channel.\n♩ Bass note — use only the lowest note (ideal for walking bass lines).'**
  String get jamModeDetectTooltip;

  /// No description provided for @jamModeSyncLabel.
  ///
  /// In en, this message translates to:
  /// **'SYNC'**
  String get jamModeSyncLabel;

  /// No description provided for @jamModeSyncTooltip.
  ///
  /// In en, this message translates to:
  /// **'When to apply scale changes detected from the master channel.\n\nOff — apply immediately on each new note/chord\n1 beat — wait for the next beat\n½ bar — change every 2 beats\n1 bar — change every 4 beats'**
  String get jamModeSyncTooltip;

  /// No description provided for @jamModeDetectChord.
  ///
  /// In en, this message translates to:
  /// **'Chord'**
  String get jamModeDetectChord;

  /// No description provided for @jamModeDetectBass.
  ///
  /// In en, this message translates to:
  /// **'Bass'**
  String get jamModeDetectBass;

  /// No description provided for @jamModeSyncOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get jamModeSyncOff;

  /// No description provided for @jamModeSyncBeat.
  ///
  /// In en, this message translates to:
  /// **'1 beat'**
  String get jamModeSyncBeat;

  /// No description provided for @jamModeSyncHalfBar.
  ///
  /// In en, this message translates to:
  /// **'½ bar'**
  String get jamModeSyncHalfBar;

  /// No description provided for @jamModeSyncBar.
  ///
  /// In en, this message translates to:
  /// **'1 bar'**
  String get jamModeSyncBar;

  /// No description provided for @jamModeShowBordersTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show scale borders on keys'**
  String get jamModeShowBordersTooltip;

  /// No description provided for @jamModeDimWrongNotesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Dim out-of-scale notes'**
  String get jamModeDimWrongNotesTooltip;

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

  /// No description provided for @looperStatusIdle.
  ///
  /// In en, this message translates to:
  /// **'IDLE'**
  String get looperStatusIdle;

  /// No description provided for @looperCcTargetAction.
  ///
  /// In en, this message translates to:
  /// **'Action {code}'**
  String looperCcTargetAction(int code);

  /// No description provided for @looperCcTargetSlotParam.
  ///
  /// In en, this message translates to:
  /// **'{param} on {slot}'**
  String looperCcTargetSlotParam(String param, String slot);

  /// No description provided for @looperCcTargetCategory.
  ///
  /// In en, this message translates to:
  /// **'{category}: {action}'**
  String looperCcTargetCategory(String category, String action);

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

  /// No description provided for @kbConfigKeysCount.
  ///
  /// In en, this message translates to:
  /// **'{count} keys'**
  String kbConfigKeysCount(int count);

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

  /// No description provided for @chiptuneDuty.
  ///
  /// In en, this message translates to:
  /// **'DUTY'**
  String get chiptuneDuty;

  /// No description provided for @chiptuneNoise.
  ///
  /// In en, this message translates to:
  /// **'NOISE'**
  String get chiptuneNoise;

  /// No description provided for @chiptuneCrush.
  ///
  /// In en, this message translates to:
  /// **'CRUSH'**
  String get chiptuneCrush;

  /// No description provided for @chiptuneSub.
  ///
  /// In en, this message translates to:
  /// **'SUB'**
  String get chiptuneSub;

  /// No description provided for @chiptuneOff.
  ///
  /// In en, this message translates to:
  /// **'OFF'**
  String get chiptuneOff;

  /// No description provided for @chiptuneArp.
  ///
  /// In en, this message translates to:
  /// **'ARP'**
  String get chiptuneArp;

  /// No description provided for @chiptuneChord.
  ///
  /// In en, this message translates to:
  /// **'CHORD'**
  String get chiptuneChord;

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

  /// Faint hint at the top of the theremin pad: higher pitch is up.
  ///
  /// In en, this message translates to:
  /// **'▲ High'**
  String get thereminPadHigh;

  /// Faint hint at the bottom of the theremin pad: lower pitch is down.
  ///
  /// In en, this message translates to:
  /// **'▼ Low'**
  String get thereminPadLow;

  /// Faint hint at the right of the theremin pad: volume grows to the right.
  ///
  /// In en, this message translates to:
  /// **'Vol ▶'**
  String get thereminPadVolume;

  /// Theremin side control: lowest note of the pad. Keep it short.
  ///
  /// In en, this message translates to:
  /// **'BASE'**
  String get thereminBaseNote;

  /// Theremin side control: pitch span of the pad, in octaves. Keep it short.
  ///
  /// In en, this message translates to:
  /// **'RANGE'**
  String get thereminRange;

  /// Compact octave count shown in small controls, e.g. 2oct.
  ///
  /// In en, this message translates to:
  /// **'{count}oct'**
  String octaveCountShort(int count);

  /// Stylophone arpeggio chord type: the note and its octave.
  ///
  /// In en, this message translates to:
  /// **'OCT'**
  String get stylophoneArpOctave;

  /// Stylophone arpeggio chord type: the note and its fifth.
  ///
  /// In en, this message translates to:
  /// **'5TH'**
  String get stylophoneArpFifth;

  /// Stylophone arpeggio chord type: arpeggiates the notes currently held.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get stylophoneArpLive;

  /// Bit crusher depth in the stylophone chiptune row, e.g. 8bit.
  ///
  /// In en, this message translates to:
  /// **'{bits}bit'**
  String stylophoneBitDepth(int bits);

  /// Stylophone octave shift; shift is already signed, e.g. +1 or -2.
  ///
  /// In en, this message translates to:
  /// **'OCT {shift}'**
  String stylophoneOctaveShift(String shift);

  /// Stylophone vibrato on/off button. Keep it short.
  ///
  /// In en, this message translates to:
  /// **'VIB'**
  String get stylophoneVibrato;

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

  /// Name of the parameter group a VST3 plugin leaves unnamed.
  ///
  /// In en, this message translates to:
  /// **'Parameters'**
  String get vst3ParamsDefaultGroup;

  /// Fallback name of a VST3 parameter group the plugin did not name.
  ///
  /// In en, this message translates to:
  /// **'Group {id}'**
  String vst3ParamsGroupNumber(int id);

  /// No description provided for @vst3ParamsHeader.
  ///
  /// In en, this message translates to:
  /// **'PARAMETERS'**
  String get vst3ParamsHeader;

  /// No description provided for @vst3ParamsAllGroups.
  ///
  /// In en, this message translates to:
  /// **'All groups ({count})'**
  String vst3ParamsAllGroups(int count);

  /// No description provided for @vst3ParamsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search parameters…'**
  String get vst3ParamsSearchHint;

  /// No description provided for @vst3ParamsNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No parameters match.'**
  String get vst3ParamsNoMatch;

  /// No description provided for @vst3NoParamsTitle.
  ///
  /// In en, this message translates to:
  /// **'No automatable parameters found.'**
  String get vst3NoParamsTitle;

  /// No description provided for @vst3NoParamsBody.
  ///
  /// In en, this message translates to:
  /// **'{pluginName} doesn\'t share its settings with GrooveForge. Open its own window to tweak it.'**
  String vst3NoParamsBody(String pluginName);

  /// No description provided for @vst3ShowPluginUi.
  ///
  /// In en, this message translates to:
  /// **'Show Plugin UI'**
  String get vst3ShowPluginUi;

  /// No description provided for @vst3ClosePluginUi.
  ///
  /// In en, this message translates to:
  /// **'Close Plugin UI'**
  String get vst3ClosePluginUi;

  /// No description provided for @rackAddEffectsSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Built-in Effects'**
  String get rackAddEffectsSectionLabel;

  /// Badge on add-module entries that don't work in the web demo.
  ///
  /// In en, this message translates to:
  /// **'Apps only'**
  String get rackAddNativeOnlyBadge;

  /// Tooltip explaining why a module is greyed out on the web.
  ///
  /// In en, this message translates to:
  /// **'Available in the GrooveForge apps for Android, Linux, macOS and Windows, not in this web demo.'**
  String get rackAddNativeOnlyTooltip;

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
  /// **'Wah'**
  String get rackAddWah;

  /// No description provided for @rackAddWahSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Wah filter: LFO sweep with BPM sync, or played from a pedal / CC knob'**
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

  /// No description provided for @rackAddAudioHarmonizer.
  ///
  /// In en, this message translates to:
  /// **'Audio Harmonizer'**
  String get rackAddAudioHarmonizer;

  /// No description provided for @rackAddAudioHarmonizerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Up to 4 pitch-shifted harmony voices from any audio input'**
  String get rackAddAudioHarmonizerSubtitle;

  /// No description provided for @rackAddAutotune.
  ///
  /// In en, this message translates to:
  /// **'Autotune'**
  String get rackAddAutotune;

  /// No description provided for @rackAddRiff.
  ///
  /// In en, this message translates to:
  /// **'Riff'**
  String get rackAddRiff;

  /// No description provided for @rackAddRiffSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Modelled electric guitar, string by string; cable it into the Amp'**
  String get rackAddRiffSubtitle;

  /// No description provided for @rackAddAmp.
  ///
  /// In en, this message translates to:
  /// **'Amp'**
  String get rackAddAmp;

  /// No description provided for @rackAddAmpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Guitar amp: drive pedal, amp tone stack and speaker cabinet'**
  String get rackAddAmpSubtitle;

  /// No description provided for @ampIrNone.
  ///
  /// In en, this message translates to:
  /// **'Cabinet IR: none loaded'**
  String get ampIrNone;

  /// No description provided for @ampIrLoaded.
  ///
  /// In en, this message translates to:
  /// **'Cabinet IR: {name}'**
  String ampIrLoaded(String name);

  /// No description provided for @ampIrLoad.
  ///
  /// In en, this message translates to:
  /// **'Load IR'**
  String get ampIrLoad;

  /// No description provided for @ampIrRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove the IR'**
  String get ampIrRemove;

  /// No description provided for @ampIrPickTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a cabinet impulse response (.wav)'**
  String get ampIrPickTitle;

  /// No description provided for @ampIrNotWav.
  ///
  /// In en, this message translates to:
  /// **'This file is not a WAV file.'**
  String get ampIrNotWav;

  /// No description provided for @ampIrUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This WAV uses a compressed format. Export it as a PCM or float WAV.'**
  String get ampIrUnsupported;

  /// No description provided for @ampIrEmpty.
  ///
  /// In en, this message translates to:
  /// **'This file contains no sound.'**
  String get ampIrEmpty;

  /// No description provided for @ampIrUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Could not read this file.'**
  String get ampIrUnreadable;

  /// No description provided for @ampIrRejected.
  ///
  /// In en, this message translates to:
  /// **'The amp could not use this IR.'**
  String get ampIrRejected;

  /// No description provided for @guideRiffTitle.
  ///
  /// In en, this message translates to:
  /// **'Riff, the modelled guitar'**
  String get guideRiffTitle;

  /// No description provided for @guideRiffBody.
  ///
  /// In en, this message translates to:
  /// **'Riff is an electric guitar modelled string by string. It has no keys: cable a keyboard\'s MIDI OUT into its MIDI IN, or play it from a controller on its MIDI channel.\nClose notes go to separate strings, so they ring together. With Legato on, a note close to the previous one hammers on or pulls off on the same string. Overlap does the same only when you press a key before letting go of the last one.\nThe pitch wheel bends, the mod wheel adds vibrato, the sustain pedal lets strings ring. Feedback makes held strings bloom into a harmonic, like in front of an amp.\nPalm mute, Pick position, Tone and the pickup selector change strings that are already ringing: map them to a pedal or a knob with Learn and play them like a guitarist\'s hands. For crunch and distortion, cable Riff into the Amp.'**
  String get guideRiffBody;

  /// No description provided for @guideAmpTitle.
  ///
  /// In en, this message translates to:
  /// **'Amp and cabinet IRs'**
  String get guideAmpTitle;

  /// No description provided for @guideAmpBody.
  ///
  /// In en, this message translates to:
  /// **'The Amp has three sections you can switch on and off, by hand or with a footswitch: a Drive pedal (Overdrive or Distortion), the amp itself (Gain, Bass, Middle, Treble) and the speaker cabinet.\nThe cabinet shapes most of a guitar sound. Besides the three built-in ones, the Amp can play an impulse response (IR), a recording of a real cabinet: tap Load IR under the Amp and pick a .wav file. It is saved in your project; the cross next to its name removes it.'**
  String get guideAmpBody;

  /// No description provided for @guideAmpIrSourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Where to find free cabinet IRs'**
  String get guideAmpIrSourcesTitle;

  /// No description provided for @guideAmpIrSourcesNote.
  ///
  /// In en, this message translates to:
  /// **'Each pack comes with its own licence: free to play through, but usually not to share. Download them yourself from these sites.'**
  String get guideAmpIrSourcesNote;

  /// No description provided for @guideIrSourceTone3000.
  ///
  /// In en, this message translates to:
  /// **'TONE3000: a community library with thousands of free IRs'**
  String get guideIrSourceTone3000;

  /// No description provided for @guideIrSourceKalthallen.
  ///
  /// In en, this message translates to:
  /// **'Kalthallen Cabs: free and paid packs of classic cabinets'**
  String get guideIrSourceKalthallen;

  /// No description provided for @guideIrSourceCelestion.
  ///
  /// In en, this message translates to:
  /// **'Celestion: a free IR from the speaker maker'**
  String get guideIrSourceCelestion;

  /// No description provided for @rackAddAutotuneSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Snaps your voice onto the notes of a scale, from subtle to robot'**
  String get rackAddAutotuneSubtitle;

  /// No description provided for @autotuneListening.
  ///
  /// In en, this message translates to:
  /// **'Sing something…'**
  String get autotuneListening;

  /// How far the sung pitch is from its target note, in cents. cents already carries its sign.
  ///
  /// In en, this message translates to:
  /// **'{cents} ¢'**
  String autotuneCents(String cents);

  /// No description provided for @autotuneDisplayTooltip.
  ///
  /// In en, this message translates to:
  /// **'Left: the note you are singing and how far off it is. Right: the note it is being tuned to.'**
  String get autotuneDisplayTooltip;

  /// No description provided for @autotuneScalePatched.
  ///
  /// In en, this message translates to:
  /// **'Following the patched scale'**
  String get autotuneScalePatched;

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

  /// No description provided for @rackAddGfpdInvalid.
  ///
  /// In en, this message translates to:
  /// **'That file is not a valid .gfpd plugin.'**
  String get rackAddGfpdInvalid;

  /// No description provided for @rackAddGfpdReadError.
  ///
  /// In en, this message translates to:
  /// **'That file could not be read.'**
  String get rackAddGfpdReadError;

  /// No description provided for @rackAddGfpdReserved.
  ///
  /// In en, this message translates to:
  /// **'This plugin\'s id starts with com.grooveforge., which is kept for the modules that come with the app. Give it an id of your own.'**
  String get rackAddGfpdReserved;

  /// No description provided for @rackAddGfpdUpdated.
  ///
  /// In en, this message translates to:
  /// **'{name} updated. Its slots in the rack now use the new version.'**
  String rackAddGfpdUpdated(String name);

  /// No description provided for @rackAddCustomPluginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your plugin, from a .gfpd file'**
  String get rackAddCustomPluginSubtitle;

  /// No description provided for @rackAddCustomPluginRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove from this menu'**
  String get rackAddCustomPluginRemove;

  /// No description provided for @rackAddPluginNotFound.
  ///
  /// In en, this message translates to:
  /// **'Plugin not found: {pluginId}'**
  String rackAddPluginNotFound(String pluginId);

  /// No description provided for @rackAddNoFreeMidiChannel.
  ///
  /// In en, this message translates to:
  /// **'All 16 MIDI channels are already in use.'**
  String get rackAddNoFreeMidiChannel;

  /// No description provided for @rackAddVst3Loading.
  ///
  /// In en, this message translates to:
  /// **'Loading VST3 plugin…'**
  String get rackAddVst3Loading;

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

  /// No description provided for @rackAddMicrotone.
  ///
  /// In en, this message translates to:
  /// **'Microtone'**
  String get rackAddMicrotone;

  /// No description provided for @rackAddMicrotoneSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Combine held notes into a single microtonal pitch via pitch-bend (MIDI FX)'**
  String get rackAddMicrotoneSubtitle;

  /// No description provided for @rackAddXen.
  ///
  /// In en, this message translates to:
  /// **'Xen'**
  String get rackAddXen;

  /// No description provided for @rackAddXenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Lock the keyboard to a scale and retune it — maqam, raga, gamelan, historical temperaments (MIDI FX)'**
  String get rackAddXenSubtitle;

  /// No description provided for @xenAbout.
  ///
  /// In en, this message translates to:
  /// **'Hold a note, tap a scale: that note becomes the tonic, and the keyboard locks to the scale around it. Scales that are not equal-tempered — an Arabic maqam, an Indian raga, a Highland pipe chanter — also retune the keys they use, so the intervals sound as the tradition intends rather than as a piano approximates them. Unlike the Microtone module, which bends pitch one note at a time, Xen retunes each key independently: a whole chord can hold its own intonation.'**
  String get xenAbout;

  /// No description provided for @xenSnap.
  ///
  /// In en, this message translates to:
  /// **'SNAP'**
  String get xenSnap;

  /// No description provided for @xenTune.
  ///
  /// In en, this message translates to:
  /// **'TUNE'**
  String get xenTune;

  /// No description provided for @xenRoot.
  ///
  /// In en, this message translates to:
  /// **'ROOT'**
  String get xenRoot;

  /// No description provided for @xenFamily.
  ///
  /// In en, this message translates to:
  /// **'FAMILY'**
  String get xenFamily;

  /// No description provided for @xenScale.
  ///
  /// In en, this message translates to:
  /// **'SCALE'**
  String get xenScale;

  /// No description provided for @xenLatch.
  ///
  /// In en, this message translates to:
  /// **'LATCH'**
  String get xenLatch;

  /// No description provided for @xenTargetsLock.
  ///
  /// In en, this message translates to:
  /// **'SCALE LOCK'**
  String get xenTargetsLock;

  /// No description provided for @xenTargetsTune.
  ///
  /// In en, this message translates to:
  /// **'RETUNE'**
  String get xenTargetsTune;

  /// No description provided for @xenHint.
  ///
  /// In en, this message translates to:
  /// **'Hold a note, then tap a scale'**
  String get xenHint;

  /// No description provided for @xenHolding.
  ///
  /// In en, this message translates to:
  /// **'Holding {note}'**
  String xenHolding(String note);

  /// No description provided for @xenNoSlots.
  ///
  /// In en, this message translates to:
  /// **'no slots'**
  String get xenNoSlots;

  /// No description provided for @xenNoTargets.
  ///
  /// In en, this message translates to:
  /// **'not patched'**
  String get xenNoTargets;

  /// No description provided for @xenMicrotonalTooltip.
  ///
  /// In en, this message translates to:
  /// **'Retunes the keys it uses'**
  String get xenMicrotonalTooltip;

  /// No description provided for @xenTemperedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Equal-tempered — key layout only'**
  String get xenTemperedTooltip;

  /// No description provided for @xenFamilyWestern.
  ///
  /// In en, this message translates to:
  /// **'Western'**
  String get xenFamilyWestern;

  /// No description provided for @xenFamilyMaqam.
  ///
  /// In en, this message translates to:
  /// **'Maqam'**
  String get xenFamilyMaqam;

  /// No description provided for @xenFamilyRaga.
  ///
  /// In en, this message translates to:
  /// **'Raga'**
  String get xenFamilyRaga;

  /// No description provided for @xenFamilyFarEast.
  ///
  /// In en, this message translates to:
  /// **'Far East'**
  String get xenFamilyFarEast;

  /// No description provided for @xenFamilyPersian.
  ///
  /// In en, this message translates to:
  /// **'Persian'**
  String get xenFamilyPersian;

  /// No description provided for @xenFamilySoutheastAsia.
  ///
  /// In en, this message translates to:
  /// **'SE Asia'**
  String get xenFamilySoutheastAsia;

  /// No description provided for @xenFamilyAfrica.
  ///
  /// In en, this message translates to:
  /// **'Africa'**
  String get xenFamilyAfrica;

  /// No description provided for @xenFamilyEurope.
  ///
  /// In en, this message translates to:
  /// **'Europe'**
  String get xenFamilyEurope;

  /// No description provided for @xenFamilyGamelan.
  ///
  /// In en, this message translates to:
  /// **'Gamelan'**
  String get xenFamilyGamelan;

  /// No description provided for @xenFamilyTemperament.
  ///
  /// In en, this message translates to:
  /// **'Temperaments'**
  String get xenFamilyTemperament;

  /// No description provided for @xenFamilyExperimental.
  ///
  /// In en, this message translates to:
  /// **'Experimental'**
  String get xenFamilyExperimental;

  /// No description provided for @xenFamilyCustom.
  ///
  /// In en, this message translates to:
  /// **'My Scales'**
  String get xenFamilyCustom;

  /// No description provided for @xenEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'Scale editor'**
  String get xenEditorTitle;

  /// No description provided for @xenEditorName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get xenEditorName;

  /// No description provided for @xenEditorLayout.
  ///
  /// In en, this message translates to:
  /// **'Layout'**
  String get xenEditorLayout;

  /// No description provided for @xenEditorLayoutKeyboard.
  ///
  /// In en, this message translates to:
  /// **'Keyboard'**
  String get xenEditorLayoutKeyboard;

  /// No description provided for @xenEditorLayoutLinear.
  ///
  /// In en, this message translates to:
  /// **'Linear'**
  String get xenEditorLayoutLinear;

  /// No description provided for @xenEditorLayoutKeyboardHint.
  ///
  /// In en, this message translates to:
  /// **'Each degree keeps its own key; the pattern repeats every octave.'**
  String get xenEditorLayoutKeyboardHint;

  /// No description provided for @xenEditorLayoutLinearHint.
  ///
  /// In en, this message translates to:
  /// **'Degrees take successive keys; one period spans {count} keys.'**
  String xenEditorLayoutLinearHint(int count);

  /// No description provided for @xenEditorPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period (cents)'**
  String get xenEditorPeriod;

  /// No description provided for @xenEditorKey.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get xenEditorKey;

  /// No description provided for @xenEditorOffset.
  ///
  /// In en, this message translates to:
  /// **'Offset'**
  String get xenEditorOffset;

  /// No description provided for @xenEditorSounds.
  ///
  /// In en, this message translates to:
  /// **'sounds {cents}¢'**
  String xenEditorSounds(String cents);

  /// No description provided for @xenEditorAddDegree.
  ///
  /// In en, this message translates to:
  /// **'Add degree'**
  String get xenEditorAddDegree;

  /// No description provided for @xenEditorRemoveDegree.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get xenEditorRemoveDegree;

  /// No description provided for @xenEditorMute.
  ///
  /// In en, this message translates to:
  /// **'Mute — playable and tuned, but the snap ignores it'**
  String get xenEditorMute;

  /// No description provided for @xenEditorSeed.
  ///
  /// In en, this message translates to:
  /// **'Start from'**
  String get xenEditorSeed;

  /// No description provided for @xenEditorSeedNone.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get xenEditorSeedNone;

  /// No description provided for @xenEditorSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get xenEditorSave;

  /// No description provided for @xenEditorCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get xenEditorCancel;

  /// No description provided for @xenEditorImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get xenEditorImport;

  /// No description provided for @xenEditorExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get xenEditorExport;

  /// No description provided for @xenEditorExportJson.
  ///
  /// In en, this message translates to:
  /// **'GrooveForge scale (.json)'**
  String get xenEditorExportJson;

  /// No description provided for @xenEditorExportScala.
  ///
  /// In en, this message translates to:
  /// **'Scala tuning (.scl)'**
  String get xenEditorExportScala;

  /// No description provided for @xenEditorDegreeCount.
  ///
  /// In en, this message translates to:
  /// **'{count} degrees, {active} active'**
  String xenEditorDegreeCount(int count, int active);

  /// No description provided for @xenEditorNoDegrees.
  ///
  /// In en, this message translates to:
  /// **'No degrees yet — add one, or start from an existing scale.'**
  String get xenEditorNoDegrees;

  /// No description provided for @xenEditorDuplicateKeys.
  ///
  /// In en, this message translates to:
  /// **'Two degrees share a key; the scale will use the linear layout.'**
  String get xenEditorDuplicateKeys;

  /// No description provided for @xenEditorImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read that file: {reason}'**
  String xenEditorImportFailed(String reason);

  /// No description provided for @scalaErrorNotScalaFile.
  ///
  /// In en, this message translates to:
  /// **'Not a Scala file: expected a description line and a note count.'**
  String get scalaErrorNotScalaFile;

  /// No description provided for @scalaErrorBadNoteCount.
  ///
  /// In en, this message translates to:
  /// **'Expected a note count on line 2, found \"{found}\".'**
  String scalaErrorBadNoteCount(String found);

  /// No description provided for @scalaErrorMissingNotes.
  ///
  /// In en, this message translates to:
  /// **'File declares {declared} notes but contains {actual}.'**
  String scalaErrorMissingNotes(int declared, int actual);

  /// No description provided for @scalaErrorBadPitch.
  ///
  /// In en, this message translates to:
  /// **'Line {line} is not a pitch: \"{found}\".'**
  String scalaErrorBadPitch(int line, String found);

  /// No description provided for @scalaErrorNonPositivePeriod.
  ///
  /// In en, this message translates to:
  /// **'The repeat interval must be greater than zero.'**
  String get scalaErrorNonPositivePeriod;

  /// No description provided for @scalaErrorDegreeBelowTonic.
  ///
  /// In en, this message translates to:
  /// **'Degrees below the tonic are not supported.'**
  String get scalaErrorDegreeBelowTonic;

  /// No description provided for @xenEditorNotGrooveForgeScale.
  ///
  /// In en, this message translates to:
  /// **'not a GrooveForge scale'**
  String get xenEditorNotGrooveForgeScale;

  /// No description provided for @xenEditorImported.
  ///
  /// In en, this message translates to:
  /// **'Imported “{name}”'**
  String xenEditorImported(String name);

  /// No description provided for @xenEditorExported.
  ///
  /// In en, this message translates to:
  /// **'Exported to {path}'**
  String xenEditorExported(String path);

  /// No description provided for @xenEditorDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete scale'**
  String get xenEditorDelete;

  /// No description provided for @xenEditorUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Untitled scale'**
  String get xenEditorUnnamed;

  /// No description provided for @xenScaleMajor.
  ///
  /// In en, this message translates to:
  /// **'Major'**
  String get xenScaleMajor;

  /// No description provided for @xenScaleNaturalMinor.
  ///
  /// In en, this message translates to:
  /// **'Natural Minor'**
  String get xenScaleNaturalMinor;

  /// No description provided for @xenScaleHarmonicMinor.
  ///
  /// In en, this message translates to:
  /// **'Harmonic Minor'**
  String get xenScaleHarmonicMinor;

  /// No description provided for @xenScaleMelodicMinor.
  ///
  /// In en, this message translates to:
  /// **'Melodic Minor'**
  String get xenScaleMelodicMinor;

  /// No description provided for @xenScaleMajorPentatonic.
  ///
  /// In en, this message translates to:
  /// **'Major Pentatonic'**
  String get xenScaleMajorPentatonic;

  /// No description provided for @xenScaleMinorPentatonic.
  ///
  /// In en, this message translates to:
  /// **'Minor Pentatonic'**
  String get xenScaleMinorPentatonic;

  /// No description provided for @xenScaleBlues.
  ///
  /// In en, this message translates to:
  /// **'Blues'**
  String get xenScaleBlues;

  /// No description provided for @xenScaleRock.
  ///
  /// In en, this message translates to:
  /// **'Rock'**
  String get xenScaleRock;

  /// No description provided for @xenScaleDorian.
  ///
  /// In en, this message translates to:
  /// **'Dorian'**
  String get xenScaleDorian;

  /// No description provided for @xenScalePhrygian.
  ///
  /// In en, this message translates to:
  /// **'Phrygian'**
  String get xenScalePhrygian;

  /// No description provided for @xenScaleLydian.
  ///
  /// In en, this message translates to:
  /// **'Lydian'**
  String get xenScaleLydian;

  /// No description provided for @xenScaleMixolydian.
  ///
  /// In en, this message translates to:
  /// **'Mixolydian'**
  String get xenScaleMixolydian;

  /// No description provided for @xenScaleLocrian.
  ///
  /// In en, this message translates to:
  /// **'Locrian'**
  String get xenScaleLocrian;

  /// No description provided for @xenScalePhrygianDominant.
  ///
  /// In en, this message translates to:
  /// **'Phrygian Dominant'**
  String get xenScalePhrygianDominant;

  /// No description provided for @xenScaleWholeTone.
  ///
  /// In en, this message translates to:
  /// **'Whole Tone'**
  String get xenScaleWholeTone;

  /// No description provided for @xenScaleDiminished.
  ///
  /// In en, this message translates to:
  /// **'Diminished'**
  String get xenScaleDiminished;

  /// No description provided for @xenScaleJustIntonation.
  ///
  /// In en, this message translates to:
  /// **'Just Intonation'**
  String get xenScaleJustIntonation;

  /// No description provided for @xenScalePythagorean.
  ///
  /// In en, this message translates to:
  /// **'Pythagorean'**
  String get xenScalePythagorean;

  /// No description provided for @xenScaleMeantone.
  ///
  /// In en, this message translates to:
  /// **'Quarter-comma Meantone'**
  String get xenScaleMeantone;

  /// No description provided for @xenScaleWerckmeisterIII.
  ///
  /// In en, this message translates to:
  /// **'Werckmeister III'**
  String get xenScaleWerckmeisterIII;

  /// No description provided for @xenProvenance12Tet.
  ///
  /// In en, this message translates to:
  /// **'12-TET'**
  String get xenProvenance12Tet;

  /// No description provided for @xenProvenanceArabicQuarterTones.
  ///
  /// In en, this message translates to:
  /// **'24-tone Arabic convention (half-flats at −50 cents)'**
  String get xenProvenanceArabicQuarterTones;

  /// No description provided for @xenProvenanceEqualTemperedMaqam.
  ///
  /// In en, this message translates to:
  /// **'Equal-tempered maqam — no quarter-tones'**
  String get xenProvenanceEqualTemperedMaqam;

  /// No description provided for @xenProvenanceTurkishRast.
  ///
  /// In en, this message translates to:
  /// **'Arel-Ezgi-Uzdilek, 53 Holdrian commas of 22.641 cents'**
  String get xenProvenanceTurkishRast;

  /// No description provided for @xenProvenanceTurkishUssak.
  ///
  /// In en, this message translates to:
  /// **'Arel-Ezgi-Uzdilek: 8, 5, 9, 9, 4, 9, 9 Holdrian commas'**
  String get xenProvenanceTurkishUssak;

  /// No description provided for @xenProvenanceTurkishHuseyni.
  ///
  /// In en, this message translates to:
  /// **'Arel-Ezgi-Uzdilek: 8, 5, 9, 9, 8, 5, 9 Holdrian commas'**
  String get xenProvenanceTurkishHuseyni;

  /// No description provided for @xenProvenancePersian.
  ///
  /// In en, this message translates to:
  /// **'24-tone notation convention; performed koron size varies'**
  String get xenProvenancePersian;

  /// No description provided for @xenProvenanceShruti.
  ///
  /// In en, this message translates to:
  /// **'Just intonation from the shruti ratios (ascending form)'**
  String get xenProvenanceShruti;

  /// No description provided for @xenProvenanceDarbari.
  ///
  /// In en, this message translates to:
  /// **'Shruti ratios; komal ga is oscillated in performance'**
  String get xenProvenanceDarbari;

  /// No description provided for @xenProvenanceMelakarta15.
  ///
  /// In en, this message translates to:
  /// **'Carnatic melakarta 15, just intonation'**
  String get xenProvenanceMelakarta15;

  /// No description provided for @xenProvenanceSanfen.
  ///
  /// In en, this message translates to:
  /// **'Sanfen sunyi cycle of fifths (Pythagorean)'**
  String get xenProvenanceSanfen;

  /// No description provided for @xenProvenanceKoto.
  ///
  /// In en, this message translates to:
  /// **'Koto tuning, equal-tempered notation'**
  String get xenProvenanceKoto;

  /// No description provided for @xenProvenanceInSen.
  ///
  /// In en, this message translates to:
  /// **'Japanese in scale, equal-tempered notation'**
  String get xenProvenanceInSen;

  /// No description provided for @xenProvenanceYo.
  ///
  /// In en, this message translates to:
  /// **'Japanese yo scale, equal-tempered notation'**
  String get xenProvenanceYo;

  /// No description provided for @xenProvenanceJeongak.
  ///
  /// In en, this message translates to:
  /// **'Korean jeongak, Pythagorean cycle of fifths'**
  String get xenProvenanceJeongak;

  /// No description provided for @xenProvenanceGagaku.
  ///
  /// In en, this message translates to:
  /// **'Gagaku mode, equal-tempered notation'**
  String get xenProvenanceGagaku;

  /// No description provided for @xenProvenanceThai.
  ///
  /// In en, this message translates to:
  /// **'Idealised 7-fold equal division, 171.4 cents per step'**
  String get xenProvenanceThai;

  /// No description provided for @xenProvenanceQenet.
  ///
  /// In en, this message translates to:
  /// **'Ethiopian qenet; untempered in performance'**
  String get xenProvenanceQenet;

  /// No description provided for @xenProvenanceQenetNeutral.
  ///
  /// In en, this message translates to:
  /// **'Ethiopian qenet; neutral degrees at 24-tone positions'**
  String get xenProvenanceQenetNeutral;

  /// No description provided for @xenProvenanceAmadinda.
  ///
  /// In en, this message translates to:
  /// **'Ganda xylophone tuning, idealised 5-fold equal division'**
  String get xenProvenanceAmadinda;

  /// No description provided for @xenProvenanceHighlandPipe.
  ///
  /// In en, this message translates to:
  /// **'Near-just chanter scale (9/8, 5/4, 4/3, 3/2, 27/16, 16/9)'**
  String get xenProvenanceHighlandPipe;

  /// No description provided for @xenProvenanceHardingfele.
  ///
  /// In en, this message translates to:
  /// **'Averaged Norwegian fiddle intonation; varies by district'**
  String get xenProvenanceHardingfele;

  /// No description provided for @xenProvenanceByzantineSoft.
  ///
  /// In en, this message translates to:
  /// **'72-division Byzantine theory, soft chromatic genus'**
  String get xenProvenanceByzantineSoft;

  /// No description provided for @xenProvenanceByzantineHard.
  ///
  /// In en, this message translates to:
  /// **'72-division Byzantine theory, hard chromatic genus'**
  String get xenProvenanceByzantineHard;

  /// No description provided for @xenProvenanceSlendro.
  ///
  /// In en, this message translates to:
  /// **'Idealised 5-fold equal division; real gamelans vary widely'**
  String get xenProvenanceSlendro;

  /// No description provided for @xenProvenancePelog.
  ///
  /// In en, this message translates to:
  /// **'Averaged Javanese pelog; every gamelan differs'**
  String get xenProvenancePelog;

  /// No description provided for @xenProvenancePelogBarang.
  ///
  /// In en, this message translates to:
  /// **'Averaged Javanese pelog barang; every gamelan differs'**
  String get xenProvenancePelogBarang;

  /// No description provided for @xenProvenanceSelisir.
  ///
  /// In en, this message translates to:
  /// **'Averaged Balinese selisir; every gamelan differs'**
  String get xenProvenanceSelisir;

  /// No description provided for @xenProvenanceJustIntonation.
  ///
  /// In en, this message translates to:
  /// **'Five-limit ratios: 16/15, 9/8, 6/5, 5/4, 4/3, 45/32, 3/2, 8/5, 5/3, 9/5, 15/8'**
  String get xenProvenanceJustIntonation;

  /// No description provided for @xenProvenancePythagorean.
  ///
  /// In en, this message translates to:
  /// **'Chain of pure 3/2 fifths, E♭–G♯; wolf between G♯ and E♭'**
  String get xenProvenancePythagorean;

  /// No description provided for @xenProvenanceMeantone.
  ///
  /// In en, this message translates to:
  /// **'Fifths narrowed by 1/4 syntonic comma (696.578 cents)'**
  String get xenProvenanceMeantone;

  /// No description provided for @xenProvenanceWerckmeister.
  ///
  /// In en, this message translates to:
  /// **'Werckmeister 1691, four fifths narrowed by 1/4 Pythagorean comma'**
  String get xenProvenanceWerckmeister;

  /// No description provided for @xenProvenanceEdo24.
  ///
  /// In en, this message translates to:
  /// **'24 equal divisions of the octave, 50 cents apart'**
  String get xenProvenanceEdo24;

  /// No description provided for @xenProvenanceEdo19.
  ///
  /// In en, this message translates to:
  /// **'19 equal divisions of the octave, 63.16 cents apart'**
  String get xenProvenanceEdo19;

  /// No description provided for @xenProvenanceEdo31.
  ///
  /// In en, this message translates to:
  /// **'31 equal divisions of the octave, 38.71 cents apart'**
  String get xenProvenanceEdo31;

  /// No description provided for @xenProvenanceBohlenPierce.
  ///
  /// In en, this message translates to:
  /// **'13 equal divisions of the 3:1 tritave — no octave'**
  String get xenProvenanceBohlenPierce;

  /// No description provided for @xenProvenanceHarmonicSeries.
  ///
  /// In en, this message translates to:
  /// **'Harmonics 8-16: 9/8, 5/4, 11/8, 3/2, 13/8, 7/4, 15/8'**
  String get xenProvenanceHarmonicSeries;

  /// No description provided for @xenProvenanceQuarterToneCluster.
  ///
  /// In en, this message translates to:
  /// **'Four keys at 0, 50, 100 and 150 cents, then the octave resumes'**
  String get xenProvenanceQuarterToneCluster;

  /// No description provided for @xenProvenanceEdo17.
  ///
  /// In en, this message translates to:
  /// **'17 equal divisions of the octave, 70.59 cents apart'**
  String get xenProvenanceEdo17;

  /// No description provided for @xenProvenanceEdo22.
  ///
  /// In en, this message translates to:
  /// **'22 equal divisions of the octave, 54.55 cents apart'**
  String get xenProvenanceEdo22;

  /// No description provided for @xenProvenanceEdo15.
  ///
  /// In en, this message translates to:
  /// **'15 equal divisions of the octave, 80 cents apart'**
  String get xenProvenanceEdo15;

  /// No description provided for @xenProvenanceEdo13.
  ///
  /// In en, this message translates to:
  /// **'13 equal divisions of the octave, 92.31 cents apart'**
  String get xenProvenanceEdo13;

  /// No description provided for @xenProvenanceEdo16.
  ///
  /// In en, this message translates to:
  /// **'16 equal divisions of the octave, 75 cents apart'**
  String get xenProvenanceEdo16;

  /// No description provided for @xenProvenanceBlackwood.
  ///
  /// In en, this message translates to:
  /// **'Ten notes of 15-EDO, alternating 80 and 160 cent steps'**
  String get xenProvenanceBlackwood;

  /// No description provided for @xenProvenanceCarlosAlpha.
  ///
  /// In en, this message translates to:
  /// **'Wendy Carlos: steps of 78.0 cents, no octave'**
  String get xenProvenanceCarlosAlpha;

  /// No description provided for @xenProvenanceCarlosBeta.
  ///
  /// In en, this message translates to:
  /// **'Wendy Carlos: steps of 63.8 cents, no octave'**
  String get xenProvenanceCarlosBeta;

  /// No description provided for @xenProvenanceCarlosGamma.
  ///
  /// In en, this message translates to:
  /// **'Wendy Carlos: steps of 35.1 cents, no octave'**
  String get xenProvenanceCarlosGamma;

  /// No description provided for @xenProvenanceBohlenPierceLambda.
  ///
  /// In en, this message translates to:
  /// **'Steps 0, 1, 3, 4, 6, 7, 9, 10, 12 of 13-tone Bohlen-Pierce'**
  String get xenProvenanceBohlenPierceLambda;

  /// No description provided for @xenProvenanceSubharmonicSeries.
  ///
  /// In en, this message translates to:
  /// **'Undertones 16-8: 16/15, 8/7, 16/13, 4/3, 16/11, 8/5, 16/9'**
  String get xenProvenanceSubharmonicSeries;

  /// No description provided for @xenProvenanceImportedScala.
  ///
  /// In en, this message translates to:
  /// **'Imported from Scala (.scl)'**
  String get xenProvenanceImportedScala;

  /// No description provided for @xenProvenanceMadeInGrooveForge.
  ///
  /// In en, this message translates to:
  /// **'Made in GrooveForge'**
  String get xenProvenanceMadeInGrooveForge;

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

  /// No description provided for @drumGeneratorLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'That file is not a valid .gfdrum pattern.'**
  String get drumGeneratorLoadFailed;

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
  /// **'Chopsticks ({hits} hits)'**
  String drumGeneratorIntroChopsticks(int hits);

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

  /// No description provided for @drumGeneratorBreakLabel.
  ///
  /// In en, this message translates to:
  /// **'Breaks'**
  String get drumGeneratorBreakLabel;

  /// No description provided for @drumGeneratorBreakNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get drumGeneratorBreakNone;

  /// No description provided for @drumGeneratorBreakRare.
  ///
  /// In en, this message translates to:
  /// **'Rare'**
  String get drumGeneratorBreakRare;

  /// No description provided for @drumGeneratorBreakOccasional.
  ///
  /// In en, this message translates to:
  /// **'Now and then'**
  String get drumGeneratorBreakOccasional;

  /// No description provided for @drumGeneratorBreakFrequent.
  ///
  /// In en, this message translates to:
  /// **'Often'**
  String get drumGeneratorBreakFrequent;

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

  /// No description provided for @drumFormTitle.
  ///
  /// In en, this message translates to:
  /// **'Song form'**
  String get drumFormTitle;

  /// No description provided for @drumFormOffHint.
  ///
  /// In en, this message translates to:
  /// **'Without a song form, the drummer plays in phrases and ends each one with a fill.'**
  String get drumFormOffHint;

  /// No description provided for @drumFormTemplates.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get drumFormTemplates;

  /// No description provided for @drumFormTemplatesHint.
  ///
  /// In en, this message translates to:
  /// **'Replaces the current form'**
  String get drumFormTemplatesHint;

  /// No description provided for @drumFormTemplatePop.
  ///
  /// In en, this message translates to:
  /// **'Pop: verse, chorus, bridge, ending'**
  String get drumFormTemplatePop;

  /// No description provided for @drumFormTemplateRock.
  ///
  /// In en, this message translates to:
  /// **'Rock: intro, verse, chorus, ending'**
  String get drumFormTemplateRock;

  /// No description provided for @drumFormTemplateBlues.
  ///
  /// In en, this message translates to:
  /// **'Blues: three 12-bar choruses, ending'**
  String get drumFormTemplateBlues;

  /// No description provided for @drumFormTemplateJam.
  ///
  /// In en, this message translates to:
  /// **'Jam: one verse that loops'**
  String get drumFormTemplateJam;

  /// No description provided for @drumFormKindIntro.
  ///
  /// In en, this message translates to:
  /// **'Intro'**
  String get drumFormKindIntro;

  /// No description provided for @drumFormKindVerse.
  ///
  /// In en, this message translates to:
  /// **'Verse'**
  String get drumFormKindVerse;

  /// No description provided for @drumFormKindChorus.
  ///
  /// In en, this message translates to:
  /// **'Chorus'**
  String get drumFormKindChorus;

  /// No description provided for @drumFormKindBridge.
  ///
  /// In en, this message translates to:
  /// **'Bridge'**
  String get drumFormKindBridge;

  /// No description provided for @drumFormKindBreak.
  ///
  /// In en, this message translates to:
  /// **'Break'**
  String get drumFormKindBreak;

  /// No description provided for @drumFormKindEnding.
  ///
  /// In en, this message translates to:
  /// **'Ending'**
  String get drumFormKindEnding;

  /// No description provided for @drumFormAddBlock.
  ///
  /// In en, this message translates to:
  /// **'Add a block'**
  String get drumFormAddBlock;

  /// No description provided for @drumFormTagFill.
  ///
  /// In en, this message translates to:
  /// **'FILL'**
  String get drumFormTagFill;

  /// No description provided for @drumFormTagStop.
  ///
  /// In en, this message translates to:
  /// **'STOP'**
  String get drumFormTagStop;

  /// No description provided for @drumFormEventFill.
  ///
  /// In en, this message translates to:
  /// **'FILL'**
  String get drumFormEventFill;

  /// No description provided for @drumFormEventCrash.
  ///
  /// In en, this message translates to:
  /// **'CRASH'**
  String get drumFormEventCrash;

  /// No description provided for @drumFormEventBreak.
  ///
  /// In en, this message translates to:
  /// **'BREAK'**
  String get drumFormEventBreak;

  /// No description provided for @drumFormEventEnd.
  ///
  /// In en, this message translates to:
  /// **'END'**
  String get drumFormEventEnd;

  /// No description provided for @drumFormBlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Block {index}: {kind}'**
  String drumFormBlockTitle(int index, String kind);

  /// No description provided for @drumFormType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get drumFormType;

  /// No description provided for @drumFormBars.
  ///
  /// In en, this message translates to:
  /// **'Bars'**
  String get drumFormBars;

  /// No description provided for @drumFormFillAtEnd.
  ///
  /// In en, this message translates to:
  /// **'Fill at the end'**
  String get drumFormFillAtEnd;

  /// No description provided for @drumFormVariation.
  ///
  /// In en, this message translates to:
  /// **'Groove'**
  String get drumFormVariation;

  /// No description provided for @drumFormVariationAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto ({name})'**
  String drumFormVariationAuto(String name);

  /// No description provided for @drumFormStopTransport.
  ///
  /// In en, this message translates to:
  /// **'Stop the transport'**
  String get drumFormStopTransport;

  /// No description provided for @drumFormStopTransportHint.
  ///
  /// In en, this message translates to:
  /// **'Also stops the looper and the other modules.'**
  String get drumFormStopTransportHint;

  /// No description provided for @drumFormHintIntro.
  ///
  /// In en, this message translates to:
  /// **'Plays the lightest groove of the style, with no crash at its start. The count-in, if any, comes before it.'**
  String get drumFormHintIntro;

  /// No description provided for @drumFormHintBreak.
  ///
  /// In en, this message translates to:
  /// **'The band drops out: the style\'s break, or one hit on beat 1 then silence. With a fill at the end, its last bar is the drummer\'s pickup.'**
  String get drumFormHintBreak;

  /// No description provided for @drumFormHintEnding.
  ///
  /// In en, this message translates to:
  /// **'Plays the style\'s ending, then the drums stop. Always the last block.'**
  String get drumFormHintEnding;

  /// No description provided for @drumFormMoveEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get drumFormMoveEarlier;

  /// No description provided for @drumFormMoveLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get drumFormMoveLater;

  /// No description provided for @drumFormDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get drumFormDuplicate;

  /// No description provided for @drumFormDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get drumFormDelete;

  /// No description provided for @drumFormClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get drumFormClose;

  /// No description provided for @drumFormDragHint.
  ///
  /// In en, this message translates to:
  /// **'Long-press a block to drag it.'**
  String get drumFormDragHint;

  /// No description provided for @drumFormLoops.
  ///
  /// In en, this message translates to:
  /// **'No ending block: the form loops.'**
  String get drumFormLoops;

  /// No description provided for @drumFormStops.
  ///
  /// In en, this message translates to:
  /// **'The form stops after its ending.'**
  String get drumFormStops;

  /// No description provided for @drumFormEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add a first block with +.'**
  String get drumFormEmpty;

  /// No description provided for @drumFormBarCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 bar} other{{count} bars}}'**
  String drumFormBarCount(int count);

  /// No description provided for @drumFormSummary.
  ///
  /// In en, this message translates to:
  /// **'{blocks, plural, =1{1 block} other{{blocks} blocks}} · {bars, plural, =1{1 bar} other{{bars} bars}} · {duration} at {bpm} BPM'**
  String drumFormSummary(int blocks, int bars, String duration, int bpm);

  /// No description provided for @drumFormPlaying.
  ///
  /// In en, this message translates to:
  /// **'Block {index}/{count} · {kind} · bar {bar}/{bars}'**
  String drumFormPlaying(int index, int count, String kind, int bar, int bars);

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
  /// **'A .gfdrum file is a YAML text file describing a drum pattern.\n\nStep grid notation:\nX = strong hit (~100)\nx = medium hit (~75)\no = soft hit (~55)\ng = ghost note (~28)\n. = rest\n\nVelocity fields: base_velocity, velocity_range\nTiming fields: timing_jitter, rush (in beats; negative plays ahead of the beat)\nSections: groove, fill, break, crash, intro, ending\nSection types: loop (one variation per phrase), sequence (bars in order)\nGroove variations can have a role (intro, verse, chorus, bridge) for the song form.\n\nThe full format is described on the website, under .gfdrum.'**
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

  /// No description provided for @drumGeneratorFamilyMarch.
  ///
  /// In en, this message translates to:
  /// **'March'**
  String get drumGeneratorFamilyMarch;

  /// No description provided for @drumGeneratorFamilyReggae.
  ///
  /// In en, this message translates to:
  /// **'Reggae'**
  String get drumGeneratorFamilyReggae;

  /// No description provided for @drumGeneratorFamilyRnb.
  ///
  /// In en, this message translates to:
  /// **'R&B'**
  String get drumGeneratorFamilyRnb;

  /// No description provided for @drumGeneratorFamilyArabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get drumGeneratorFamilyArabic;

  /// No description provided for @drumGeneratorFamilyTurkish.
  ///
  /// In en, this message translates to:
  /// **'Turkish'**
  String get drumGeneratorFamilyTurkish;

  /// No description provided for @drumGeneratorFamilyPersian.
  ///
  /// In en, this message translates to:
  /// **'Persian'**
  String get drumGeneratorFamilyPersian;

  /// No description provided for @drumGeneratorFamilyIndian.
  ///
  /// In en, this message translates to:
  /// **'Indian'**
  String get drumGeneratorFamilyIndian;

  /// No description provided for @drumGeneratorFamilyFarEast.
  ///
  /// In en, this message translates to:
  /// **'Far East'**
  String get drumGeneratorFamilyFarEast;

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

  /// No description provided for @ccDirectValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Value to recall'**
  String get ccDirectValueLabel;

  /// No description provided for @ccAssignAddValue.
  ///
  /// In en, this message translates to:
  /// **'Assign a value…'**
  String get ccAssignAddValue;

  /// No description provided for @ccAssignNoValues.
  ///
  /// In en, this message translates to:
  /// **'Nothing assigned yet'**
  String get ccAssignNoValues;

  /// Instruction shown in CC assign dialog when listening for incoming MIDI CC input.
  ///
  /// In en, this message translates to:
  /// **'Move a CC knob or press button…'**
  String get ccAssignMoveKnobOrButton;

  /// No description provided for @ccAssignTitle.
  ///
  /// In en, this message translates to:
  /// **'CC Assign — {slot}'**
  String ccAssignTitle(String slot);

  /// No description provided for @ccAssignNoParams.
  ///
  /// In en, this message translates to:
  /// **'No CC-controllable parameters for this slot.'**
  String get ccAssignNoParams;

  /// No description provided for @ccAssignLearn.
  ///
  /// In en, this message translates to:
  /// **'Learn'**
  String get ccAssignLearn;

  /// No description provided for @ccAssignMoveKnob.
  ///
  /// In en, this message translates to:
  /// **'Move a CC knob…'**
  String get ccAssignMoveKnob;

  /// No description provided for @ccParamModeAbsolute.
  ///
  /// In en, this message translates to:
  /// **'absolute'**
  String get ccParamModeAbsolute;

  /// No description provided for @ccParamModeToggle.
  ///
  /// In en, this message translates to:
  /// **'toggle'**
  String get ccParamModeToggle;

  /// No description provided for @ccParamModeCycle.
  ///
  /// In en, this message translates to:
  /// **'cycle'**
  String get ccParamModeCycle;

  /// No description provided for @ccParamModeDirect.
  ///
  /// In en, this message translates to:
  /// **'direct'**
  String get ccParamModeDirect;

  /// No description provided for @ccSlotChannelShort.
  ///
  /// In en, this message translates to:
  /// **'Ch {channel}'**
  String ccSlotChannelShort(int channel);

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

  /// No description provided for @toastOutputDeviceDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Audio output disconnected — back to the default output'**
  String get toastOutputDeviceDisconnected;

  /// A soundfont file finished loading.
  ///
  /// In en, this message translates to:
  /// **'Loaded: {fileName}'**
  String toastSoundfontLoaded(String fileName);

  /// No description provided for @toastSoundfontLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the soundfont: {error}'**
  String toastSoundfontLoadError(String error);

  /// No description provided for @toastSoundfontUnloaded.
  ///
  /// In en, this message translates to:
  /// **'Soundfont unloaded'**
  String get toastSoundfontUnloaded;

  /// A MIDI controller button turned scale lock on for a channel (1-16).
  ///
  /// In en, this message translates to:
  /// **'Scale lock on — channel {channel}'**
  String toastScaleLockOn(int channel);

  /// No description provided for @toastScaleLockOff.
  ///
  /// In en, this message translates to:
  /// **'Scale lock off — channel {channel}'**
  String toastScaleLockOff(int channel);

  /// No description provided for @toastScaleTypeChanged.
  ///
  /// In en, this message translates to:
  /// **'Scale: {scaleName} — channel {channel}'**
  String toastScaleTypeChanged(String scaleName, int channel);

  /// A MIDI controller knob swept the sound (program) of a channel.
  ///
  /// In en, this message translates to:
  /// **'Program {program} — channel {channel}'**
  String toastPatchSweep(int program, int channel);

  /// No description provided for @toastBankSweep.
  ///
  /// In en, this message translates to:
  /// **'Bank {bank} — channel {channel}'**
  String toastBankSweep(int bank, int channel);

  /// No description provided for @toastPreferencesReset.
  ///
  /// In en, this message translates to:
  /// **'All preferences reset'**
  String get toastPreferencesReset;

  /// Musical interval name shown under a harmonizer voice control.
  ///
  /// In en, this message translates to:
  /// **'Unison'**
  String get intervalNameUnison;

  /// Musical interval name shown under a harmonizer voice control.
  ///
  /// In en, this message translates to:
  /// **'Minor 2nd'**
  String get intervalNameMinor2;

  /// Musical interval name shown under a harmonizer voice control.
  ///
  /// In en, this message translates to:
  /// **'Major 2nd'**
  String get intervalNameMajor2;

  /// Musical interval name shown under a harmonizer voice control.
  ///
  /// In en, this message translates to:
  /// **'Minor 3rd'**
  String get intervalNameMinor3;

  /// Musical interval name shown under a harmonizer voice control.
  ///
  /// In en, this message translates to:
  /// **'Major 3rd'**
  String get intervalNameMajor3;

  /// Musical interval name shown under a harmonizer voice control.
  ///
  /// In en, this message translates to:
  /// **'Perfect 4th'**
  String get intervalNamePerfect4;

  /// Musical interval name shown under a harmonizer voice control.
  ///
  /// In en, this message translates to:
  /// **'Tritone'**
  String get intervalNameTritone;

  /// Musical interval name shown under a harmonizer voice control.
  ///
  /// In en, this message translates to:
  /// **'Perfect 5th'**
  String get intervalNamePerfect5;

  /// Musical interval name shown under a harmonizer voice control.
  ///
  /// In en, this message translates to:
  /// **'Minor 6th'**
  String get intervalNameMinor6;

  /// Musical interval name shown under a harmonizer voice control.
  ///
  /// In en, this message translates to:
  /// **'Major 6th'**
  String get intervalNameMajor6;

  /// Musical interval name shown under a harmonizer voice control.
  ///
  /// In en, this message translates to:
  /// **'Minor 7th'**
  String get intervalNameMinor7;

  /// Musical interval name shown under a harmonizer voice control.
  ///
  /// In en, this message translates to:
  /// **'Major 7th'**
  String get intervalNameMajor7;

  /// Musical interval name shown under a harmonizer voice control.
  ///
  /// In en, this message translates to:
  /// **'Octave'**
  String get intervalNameOctave;

  /// Several whole octaves, e.g. 2 octaves for 24 semitones.
  ///
  /// In en, this message translates to:
  /// **'{count} octaves'**
  String intervalNameOctaves(int count);

  /// An interval wider than an octave, named by its simple form plus the octaves on top.
  ///
  /// In en, this message translates to:
  /// **'{base} +{octaves} oct'**
  String intervalNameCompound(String base, int octaves);

  /// Primary readout under a harmonizer interval control. semitones already carries its sign.
  ///
  /// In en, this message translates to:
  /// **'{semitones} st'**
  String intervalSemitones(String semitones);

  /// Long-press text on a harmonizer interval readout, for an upward voice.
  ///
  /// In en, this message translates to:
  /// **'{name}, {semitones} semitones above the played note'**
  String intervalTooltipAbove(String name, int semitones);

  /// Long-press text on a harmonizer interval readout, for a downward voice.
  ///
  /// In en, this message translates to:
  /// **'{name}, {semitones} semitones below the played note'**
  String intervalTooltipBelow(String name, int semitones);

  /// Long-press text on a harmonizer interval readout set to zero.
  ///
  /// In en, this message translates to:
  /// **'Unison — the same pitch as the played note'**
  String get intervalTooltipUnison;

  /// Vocoder carrier waveform: sawtooth.
  ///
  /// In en, this message translates to:
  /// **'Saw'**
  String get vocoderWaveSaw;

  /// Vocoder carrier waveform: square.
  ///
  /// In en, this message translates to:
  /// **'Square'**
  String get vocoderWaveSquare;

  /// Vocoder carrier waveform: a choral ensemble of glottal pulses.
  ///
  /// In en, this message translates to:
  /// **'Choral'**
  String get vocoderWaveChoral;

  /// Vocoder mode that pitch-shifts the live voice onto the held keys instead of using a synthetic carrier.
  ///
  /// In en, this message translates to:
  /// **'Harmony'**
  String get vocoderWaveHarmony;

  /// Vocoder knob label: amount of noise mixed into the carrier. Drawn under a small knob, keep it short.
  ///
  /// In en, this message translates to:
  /// **'NOISE'**
  String get vocoderKnobNoise;

  /// Vocoder knob label: how fast the band envelopes follow the voice. Keep it short.
  ///
  /// In en, this message translates to:
  /// **'SPEED'**
  String get vocoderKnobSpeed;

  /// Vocoder knob label: width of each filter band. Keep it short.
  ///
  /// In en, this message translates to:
  /// **'BW'**
  String get vocoderKnobBandwidth;

  /// Vocoder knob label: noise gate threshold. Keep it short.
  ///
  /// In en, this message translates to:
  /// **'GATE'**
  String get vocoderKnobGate;

  /// Vocoder level meter label for the microphone input. At most 4 characters.
  ///
  /// In en, this message translates to:
  /// **'MIC'**
  String get vocoderMeterMic;

  /// Vocoder level meter label for the vocoder output. At most 4 characters.
  ///
  /// In en, this message translates to:
  /// **'OUT'**
  String get vocoderMeterOut;

  /// No description provided for @latencyProbeTitle.
  ///
  /// In en, this message translates to:
  /// **'Overdub latency'**
  String get latencyProbeTitle;

  /// No description provided for @latencyProbeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Measure how late the mic hears what the app plays'**
  String get latencyProbeSubtitle;

  /// No description provided for @latencyProbeExplain.
  ///
  /// In en, this message translates to:
  /// **'Plays six short sweeps through the speaker and listens for them on the microphone. Use the speaker: a microphone cannot hear headphones, and the measurement will correctly report that it found nothing.'**
  String get latencyProbeExplain;

  /// No description provided for @latencyProbeStart.
  ///
  /// In en, this message translates to:
  /// **'Measure'**
  String get latencyProbeStart;

  /// No description provided for @latencyProbeMeasuring.
  ///
  /// In en, this message translates to:
  /// **'Measuring…'**
  String get latencyProbeMeasuring;

  /// No description provided for @latencyProbeRoundTrip.
  ///
  /// In en, this message translates to:
  /// **'Round trip'**
  String get latencyProbeRoundTrip;

  /// No description provided for @latencyProbeJitter.
  ///
  /// In en, this message translates to:
  /// **'Jitter'**
  String get latencyProbeJitter;

  /// No description provided for @latencyProbeConfidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get latencyProbeConfidence;

  /// No description provided for @latencyProbeShots.
  ///
  /// In en, this message translates to:
  /// **'Usable sweeps'**
  String get latencyProbeShots;

  /// No description provided for @latencyProbeDrift.
  ///
  /// In en, this message translates to:
  /// **'Clock drift'**
  String get latencyProbeDrift;

  /// No description provided for @latencyProbeSkew.
  ///
  /// In en, this message translates to:
  /// **'Counter skew'**
  String get latencyProbeSkew;

  /// No description provided for @latencyProbeDriftOverTake.
  ///
  /// In en, this message translates to:
  /// **'A 4-minute take would slide {ms} ms'**
  String latencyProbeDriftOverTake(String ms);

  /// No description provided for @latencyProbeShotsValue.
  ///
  /// In en, this message translates to:
  /// **'{found} of {total}'**
  String latencyProbeShotsValue(int found, int total);

  /// No description provided for @latencyProbeMs.
  ///
  /// In en, this message translates to:
  /// **'{value} ms'**
  String latencyProbeMs(String value);

  /// No description provided for @latencyProbeFramesSuffix.
  ///
  /// In en, this message translates to:
  /// **'{frames} frames'**
  String latencyProbeFramesSuffix(int frames);

  /// No description provided for @latencyProbePpm.
  ///
  /// In en, this message translates to:
  /// **'{value} ppm'**
  String latencyProbePpm(String value);

  /// No description provided for @latencyProbeFailed.
  ///
  /// In en, this message translates to:
  /// **'No usable measurement'**
  String get latencyProbeFailed;

  /// No description provided for @latencyProbeSilentInput.
  ///
  /// In en, this message translates to:
  /// **'The microphone heard nothing. Check the microphone permission, and play through the speaker rather than headphones.'**
  String get latencyProbeSilentInput;

  /// No description provided for @latencyProbeNeedsAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio capture is not running. Open a live input or the vocoder first.'**
  String get latencyProbeNeedsAudio;

  /// No description provided for @latencyProbeHint.
  ///
  /// In en, this message translates to:
  /// **'Keep the room quiet and hold the phone so the speaker faces the mic.'**
  String get latencyProbeHint;

  /// No description provided for @rackTabLabel.
  ///
  /// In en, this message translates to:
  /// **'Rack'**
  String get rackTabLabel;

  /// No description provided for @rehearsalsTabLabel.
  ///
  /// In en, this message translates to:
  /// **'Rehearse'**
  String get rehearsalsTabLabel;

  /// No description provided for @rehearsalsTitle.
  ///
  /// In en, this message translates to:
  /// **'Rehearsals'**
  String get rehearsalsTitle;

  /// No description provided for @rehearsalsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No rehearsals yet'**
  String get rehearsalsEmpty;

  /// No description provided for @rehearsalsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Start a tune, set the tempo, and record your part. The rest of the band can join later.'**
  String get rehearsalsEmptyHint;

  /// No description provided for @rehearsalsNew.
  ///
  /// In en, this message translates to:
  /// **'Start a tune'**
  String get rehearsalsNew;

  /// No description provided for @rehearsalCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New rehearsal'**
  String get rehearsalCreateTitle;

  /// No description provided for @rehearsalFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Tune'**
  String get rehearsalFieldTitle;

  /// No description provided for @rehearsalFieldTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Autumn Leaves'**
  String get rehearsalFieldTitleHint;

  /// No description provided for @rehearsalFieldYourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get rehearsalFieldYourName;

  /// No description provided for @rehearsalFieldInstrument.
  ///
  /// In en, this message translates to:
  /// **'Your instrument'**
  String get rehearsalFieldInstrument;

  /// No description provided for @rehearsalFieldTempo.
  ///
  /// In en, this message translates to:
  /// **'Tempo'**
  String get rehearsalFieldTempo;

  /// No description provided for @rehearsalFieldTimeSignature.
  ///
  /// In en, this message translates to:
  /// **'Time signature'**
  String get rehearsalFieldTimeSignature;

  /// No description provided for @rehearsalFieldCountIn.
  ///
  /// In en, this message translates to:
  /// **'Count-in'**
  String get rehearsalFieldCountIn;

  /// No description provided for @rehearsalCountInBars.
  ///
  /// In en, this message translates to:
  /// **'{bars, plural, =1{{bars} bar} other{{bars} bars}}'**
  String rehearsalCountInBars(int bars);

  /// No description provided for @rehearsalCountInNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get rehearsalCountInNone;

  /// No description provided for @rehearsalCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get rehearsalCreate;

  /// No description provided for @rehearsalCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get rehearsalCancel;

  /// No description provided for @rehearsalPartsProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} parts recorded'**
  String rehearsalPartsProgress(int done, int total);

  /// No description provided for @rehearsalBpmValue.
  ///
  /// In en, this message translates to:
  /// **'{bpm} BPM'**
  String rehearsalBpmValue(String bpm);

  /// No description provided for @rehearsalMeter.
  ///
  /// In en, this message translates to:
  /// **'{num}/{den}'**
  String rehearsalMeter(int num, int den);

  /// No description provided for @rehearsalDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get rehearsalDelete;

  /// No description provided for @rehearsalDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\" and every recording in it?'**
  String rehearsalDeleteConfirm(String title);

  /// No description provided for @rehearsalAddPart.
  ///
  /// In en, this message translates to:
  /// **'Add a part'**
  String get rehearsalAddPart;

  /// No description provided for @rehearsalNotRecorded.
  ///
  /// In en, this message translates to:
  /// **'Not recorded yet'**
  String get rehearsalNotRecorded;

  /// No description provided for @rehearsalTakeLength.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String rehearsalTakeLength(String seconds);

  /// No description provided for @rehearsalMetronome.
  ///
  /// In en, this message translates to:
  /// **'Metronome'**
  String get rehearsalMetronome;

  /// No description provided for @rehearsalPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get rehearsalPlay;

  /// No description provided for @rehearsalStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get rehearsalStop;

  /// No description provided for @rehearsalRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get rehearsalRecord;

  /// No description provided for @rehearsalRerecord.
  ///
  /// In en, this message translates to:
  /// **'Record again'**
  String get rehearsalRerecord;

  /// No description provided for @rehearsalCountingIn.
  ///
  /// In en, this message translates to:
  /// **'Counting in'**
  String get rehearsalCountingIn;

  /// No description provided for @rehearsalBarBeat.
  ///
  /// In en, this message translates to:
  /// **'Bar {bar}  ·  beat {beat}'**
  String rehearsalBarBeat(int bar, int beat);

  /// No description provided for @rehearsalMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get rehearsalMute;

  /// No description provided for @rehearsalGridFrozen.
  ///
  /// In en, this message translates to:
  /// **'Once a part is recorded, the tempo can no longer be set here: every take is aligned to it. You can still move the first beat.'**
  String get rehearsalGridFrozen;

  /// Rehearsal screen: latency calibration prompt and its explanation.
  ///
  /// In en, this message translates to:
  /// **'Latency has not been measured on this device, so a new take may sit behind the beat.'**
  String get rehearsalNoCompensation;

  /// No description provided for @instrumentVocals.
  ///
  /// In en, this message translates to:
  /// **'Vocals'**
  String get instrumentVocals;

  /// No description provided for @instrumentGuitar.
  ///
  /// In en, this message translates to:
  /// **'Acoustic guitar'**
  String get instrumentGuitar;

  /// No description provided for @instrumentElectricGuitar.
  ///
  /// In en, this message translates to:
  /// **'Electric guitar'**
  String get instrumentElectricGuitar;

  /// No description provided for @instrumentBassGuitar.
  ///
  /// In en, this message translates to:
  /// **'Bass'**
  String get instrumentBassGuitar;

  /// No description provided for @instrumentDrums.
  ///
  /// In en, this message translates to:
  /// **'Drums'**
  String get instrumentDrums;

  /// No description provided for @instrumentKeyboard.
  ///
  /// In en, this message translates to:
  /// **'Keyboard'**
  String get instrumentKeyboard;

  /// No description provided for @instrumentSynth.
  ///
  /// In en, this message translates to:
  /// **'Synth'**
  String get instrumentSynth;

  /// No description provided for @instrumentViolin.
  ///
  /// In en, this message translates to:
  /// **'Violin'**
  String get instrumentViolin;

  /// No description provided for @instrumentSaxophone.
  ///
  /// In en, this message translates to:
  /// **'Saxophone'**
  String get instrumentSaxophone;

  /// No description provided for @instrumentTrumpet.
  ///
  /// In en, this message translates to:
  /// **'Trumpet'**
  String get instrumentTrumpet;

  /// No description provided for @instrumentPercussion.
  ///
  /// In en, this message translates to:
  /// **'Percussion'**
  String get instrumentPercussion;

  /// No description provided for @instrumentOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get instrumentOther;

  /// No description provided for @masterImport.
  ///
  /// In en, this message translates to:
  /// **'Play along to a recording'**
  String get masterImport;

  /// No description provided for @masterImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get masterImporting;

  /// No description provided for @masterImportFailed.
  ///
  /// In en, this message translates to:
  /// **'That file could not be read. These formats work: {formats}.'**
  String masterImportFailed(String formats);

  /// No description provided for @masterTitle.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get masterTitle;

  /// No description provided for @masterRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove the recording'**
  String get masterRemove;

  /// No description provided for @masterRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" from this rehearsal?'**
  String masterRemoveConfirm(String name);

  /// No description provided for @masterAlign.
  ///
  /// In en, this message translates to:
  /// **'Set the first downbeat'**
  String get masterAlign;

  /// No description provided for @masterAlignTitle.
  ///
  /// In en, this message translates to:
  /// **'Align the grid'**
  String get masterAlignTitle;

  /// No description provided for @masterAlignHint.
  ///
  /// In en, this message translates to:
  /// **'Play the recording and tap along on the beat to set the tempo, then drag the marker to the first downbeat.'**
  String get masterAlignHint;

  /// No description provided for @masterTapTempo.
  ///
  /// In en, this message translates to:
  /// **'Tap the beat'**
  String get masterTapTempo;

  /// No description provided for @masterTapMore.
  ///
  /// In en, this message translates to:
  /// **'Keep tapping…'**
  String get masterTapMore;

  /// No description provided for @masterDownbeatAt.
  ///
  /// In en, this message translates to:
  /// **'First downbeat at {time}'**
  String masterDownbeatAt(String time);

  /// No description provided for @masterNudgeBack.
  ///
  /// In en, this message translates to:
  /// **'10 ms earlier'**
  String get masterNudgeBack;

  /// No description provided for @masterNudgeForward.
  ///
  /// In en, this message translates to:
  /// **'10 ms later'**
  String get masterNudgeForward;

  /// No description provided for @masterCheck.
  ///
  /// In en, this message translates to:
  /// **'Check two bars'**
  String get masterCheck;

  /// No description provided for @masterDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get masterDone;

  /// No description provided for @masterVideoAudioOnly.
  ///
  /// In en, this message translates to:
  /// **'Video files are imported for their audio only.'**
  String get masterVideoAudioOnly;

  /// No description provided for @masterMetronomeOff.
  ///
  /// In en, this message translates to:
  /// **'The click is off: the recording is the timing reference now.'**
  String get masterMetronomeOff;

  /// No description provided for @nearbyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nearby'**
  String get nearbyTitle;

  /// No description provided for @nearbyShare.
  ///
  /// In en, this message translates to:
  /// **'Share this rehearsal'**
  String get nearbyShare;

  /// No description provided for @nearbyHint.
  ///
  /// In en, this message translates to:
  /// **'Have the others scan this, or send them the link below.'**
  String get nearbyHint;

  /// No description provided for @nearbyStop.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing'**
  String get nearbyStop;

  /// No description provided for @nearbyStart.
  ///
  /// In en, this message translates to:
  /// **'Start sharing'**
  String get nearbyStart;

  /// No description provided for @nearbyNoNetwork.
  ///
  /// In en, this message translates to:
  /// **'This device is not on a network. Join the same Wi-Fi as the others, or turn on a hotspot.'**
  String get nearbyNoNetwork;

  /// No description provided for @nearbyWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for someone to join…'**
  String get nearbyWaiting;

  /// No description provided for @nearbyPeers.
  ///
  /// In en, this message translates to:
  /// **'{count} connected'**
  String nearbyPeers(int count);

  /// No description provided for @nearbyJoin.
  ///
  /// In en, this message translates to:
  /// **'Join a rehearsal'**
  String get nearbyJoin;

  /// No description provided for @nearbyScan.
  ///
  /// In en, this message translates to:
  /// **'Scan the code'**
  String get nearbyScan;

  /// No description provided for @nearbyConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get nearbyConnecting;

  /// No description provided for @nearbySyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get nearbySyncing;

  /// No description provided for @nearbySynced.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get nearbySynced;

  /// No description provided for @nearbySyncedWith.
  ///
  /// In en, this message translates to:
  /// **'Received {takes} parts'**
  String nearbySyncedWith(int takes);

  /// No description provided for @nearbyFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not sync: {reason}'**
  String nearbyFailed(String reason);

  /// No description provided for @nearbyWrongCode.
  ///
  /// In en, this message translates to:
  /// **'That code does not match this rehearsal.'**
  String get nearbyWrongCode;

  /// No description provided for @nearbyScanUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This device has no scanner. Type the code from the other device instead.'**
  String get nearbyScanUnsupported;

  /// No description provided for @nearbyHostAddress.
  ///
  /// In en, this message translates to:
  /// **'{host} · port {port}'**
  String nearbyHostAddress(String host, int port);

  /// No description provided for @syncStepHandshake.
  ///
  /// In en, this message translates to:
  /// **'Saying hello'**
  String get syncStepHandshake;

  /// No description provided for @syncStepManifest.
  ///
  /// In en, this message translates to:
  /// **'Comparing'**
  String get syncStepManifest;

  /// No description provided for @syncStepSending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get syncStepSending;

  /// No description provided for @syncStepReceiving.
  ///
  /// In en, this message translates to:
  /// **'Receiving'**
  String get syncStepReceiving;

  /// No description provided for @syncStepDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get syncStepDone;

  /// No description provided for @nearbyLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get nearbyLink;

  /// No description provided for @nearbyCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy the link'**
  String get nearbyCopyLink;

  /// No description provided for @nearbyCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get nearbyCopied;

  /// No description provided for @nearbyLinkHint.
  ///
  /// In en, this message translates to:
  /// **'No camera on the other device? Copy this link and send it to them — they paste it into Join.'**
  String get nearbyLinkHint;

  /// No description provided for @nearbyPasteLink.
  ///
  /// In en, this message translates to:
  /// **'Paste the link from the other device'**
  String get nearbyPasteLink;

  /// No description provided for @nearbyPasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get nearbyPasteFromClipboard;

  /// No description provided for @nearbyLooksLikeCode.
  ///
  /// In en, this message translates to:
  /// **'That is the short code, which is not enough on its own. Copy the whole link from the other device.'**
  String get nearbyLooksLikeCode;

  /// No description provided for @nearbyNotALink.
  ///
  /// In en, this message translates to:
  /// **'That is not a GrooveForge rehearsal link.'**
  String get nearbyNotALink;

  /// No description provided for @nearbyScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the code'**
  String get nearbyScanTitle;

  /// No description provided for @nearbyScanHint.
  ///
  /// In en, this message translates to:
  /// **'Hold it steady over the code on the other device.'**
  String get nearbyScanHint;

  /// No description provided for @nearbyScanPermission.
  ///
  /// In en, this message translates to:
  /// **'GrooveForge needs the camera to read the code. You can type the link instead.'**
  String get nearbyScanPermission;

  /// No description provided for @nearbyScanOr.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get nearbyScanOr;

  /// No description provided for @nearbyScanOpen.
  ///
  /// In en, this message translates to:
  /// **'Scan a code'**
  String get nearbyScanOpen;

  /// No description provided for @joinIdentityTitle.
  ///
  /// In en, this message translates to:
  /// **'Who are you?'**
  String get joinIdentityTitle;

  /// No description provided for @joinIdentityHint.
  ///
  /// In en, this message translates to:
  /// **'The others will see this name on your part.'**
  String get joinIdentityHint;

  /// No description provided for @joinIdentityConfirm.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get joinIdentityConfirm;

  /// No description provided for @rehearsalDeleteTake.
  ///
  /// In en, this message translates to:
  /// **'Delete this recording'**
  String get rehearsalDeleteTake;

  /// No description provided for @rehearsalTakeDropped.
  ///
  /// In en, this message translates to:
  /// **'This take lost {ms} ms of audio and will not line up with the click. Record it again.'**
  String rehearsalTakeDropped(int ms);

  /// No description provided for @rehearsalCleanTake.
  ///
  /// In en, this message translates to:
  /// **'Remove the speaker bleed'**
  String get rehearsalCleanTake;

  /// No description provided for @rehearsalCleaning.
  ///
  /// In en, this message translates to:
  /// **'Removing the speaker…'**
  String get rehearsalCleaning;

  /// No description provided for @rehearsalCleanDone.
  ///
  /// In en, this message translates to:
  /// **'Speaker bleed removed. The original is kept beside it.'**
  String get rehearsalCleanDone;

  /// No description provided for @rehearsalCleanFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove the speaker from this take.'**
  String get rehearsalCleanFailed;

  /// No description provided for @rehearsalDeleteTakeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete your recording of {instrument}? The others will lose it too, next time you sync.'**
  String rehearsalDeleteTakeConfirm(String instrument);

  /// No description provided for @rehearsalOthersPart.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s part'**
  String rehearsalOthersPart(String name);

  /// No description provided for @rehearsalYourPart.
  ///
  /// In en, this message translates to:
  /// **'Your part'**
  String get rehearsalYourPart;

  /// No description provided for @liveConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected — parts appear as they are recorded'**
  String get liveConnected;

  /// No description provided for @liveRefresh.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get liveRefresh;

  /// No description provided for @rehearsalRemovePart.
  ///
  /// In en, this message translates to:
  /// **'Remove this part'**
  String get rehearsalRemovePart;

  /// No description provided for @rehearsalRemovePartConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove your {instrument} part? It disappears for everyone, along with anything recorded on it.'**
  String rehearsalRemovePartConfirm(String instrument);

  /// Menu item on a part lane. Records the take from what the rack is playing instead of the microphone.
  ///
  /// In en, this message translates to:
  /// **'Record from the rack'**
  String get rehearsalRecordFromRack;

  /// Short tag on a part lane saying it records the rack's output rather than the microphone.
  ///
  /// In en, this message translates to:
  /// **'Rack'**
  String get rehearsalInputRack;

  /// No description provided for @rehearsalPartActions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get rehearsalPartActions;

  /// Tooltip on a part lane saying whether the player who owns it is reachable on the network right now.
  ///
  /// In en, this message translates to:
  /// **'Here now'**
  String get rehearsalMemberHere;

  /// Tooltip on a part lane saying whether the player who owns it is reachable on the network right now.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get rehearsalMemberAway;

  /// Button on the rehearsals tab that opens the join screen, paired with the button that starts a new tune.
  ///
  /// In en, this message translates to:
  /// **'Join a tune'**
  String get rehearsalsJoin;

  /// User guide, Rehearsals tab.
  ///
  /// In en, this message translates to:
  /// **'Rehearsals'**
  String get guideTabRehearsals;

  /// User guide, Rehearsals tab.
  ///
  /// In en, this message translates to:
  /// **'Rehearsing together'**
  String get guideRehearsalIntroTitle;

  /// User guide, Rehearsals tab.
  ///
  /// In en, this message translates to:
  /// **'The Rehearse tab is for a band learning a tune. Everyone records their own part over a shared click, on their own device, and every device ends up with all the parts.\n\nNothing is uploaded anywhere. The devices talk straight to each other, so a rehearsal works in a room with no internet at all.'**
  String get guideRehearsalIntroBody;

  /// User guide, Rehearsals tab.
  ///
  /// In en, this message translates to:
  /// **'Starting a tune'**
  String get guideRehearsalStartTitle;

  /// User guide, Rehearsals tab.
  ///
  /// In en, this message translates to:
  /// **'Start a tune, give it a name, and say what you play. Set the tempo and the time signature, or tap the beat if you would rather feel it than count it.\n\nTo play along to a recording, import it as the master track: MP3, FLAC and WAV everywhere, and on Android also M4A, AAC and the sound of a video. Then tap along to the beat and drag the marker onto the first downbeat, so the bars line up with the music. The click then switches off: the recording sets the tempo.'**
  String get guideRehearsalStartBody;

  /// User guide, Rehearsals tab.
  ///
  /// In en, this message translates to:
  /// **'Recording your part'**
  String get guideRehearsalRecordTitle;

  /// User guide, Rehearsals tab.
  ///
  /// In en, this message translates to:
  /// **'Add a part for your instrument and press record. A count-in plays first, two bars by default, and recording starts on the downbeat.\n\nEvery device takes a moment to play sound and another to record it, which would put your take late against the others. The app measures that delay on your device and moves your take back by it, so what you played on the beat lands on the beat. Measure it once with Calibrate in the tune, or from Preferences, and again when you change headphones or switch to a Bluetooth speaker: the delay belongs to the gear, not to the tune.\n\nYou record your own parts and nobody else\'s. Yours can be re-recorded or deleted as often as you like.'**
  String get guideRehearsalRecordBody;

  /// User guide, Rehearsals tab: info box under Recording.
  ///
  /// In en, this message translates to:
  /// **'Record with headphones, or with an external microphone kept away from the speaker. Through the built-in speaker, the microphone hears the click and the parts already recorded, and they all end up in your take.'**
  String get guideRehearsalMonitoringNote;

  /// User guide, Rehearsals tab.
  ///
  /// In en, this message translates to:
  /// **'Getting the band together'**
  String get guideRehearsalShareTitle;

  /// User guide, Rehearsals tab.
  ///
  /// In en, this message translates to:
  /// **'The first time, one person opens the tune and taps the share icon; the others join from the Rehearse tab, with Join a tune: on a phone they scan the code, on a computer they paste the link. After that, the devices know each other: opening the same tune is enough, and they find each other within a few seconds.\n\nA dot next to each part shows whether its player is connected. What you record reaches everyone in the room as soon as you stop, and what you missed while away arrives the next time you are all together.'**
  String get guideRehearsalShareBody;

  /// User guide, Rehearsals tab.
  ///
  /// In en, this message translates to:
  /// **'When there is no Wi-Fi'**
  String get guideRehearsalHotspotTitle;

  /// User guide, Rehearsals tab.
  ///
  /// In en, this message translates to:
  /// **'Everyone has to be on the same network. Phones on mobile data cannot see each other, and rehearsal rooms rarely have usable Wi-Fi, so one person makes the network:\n\n1. One phone turns on its personal hotspot, in the phone\'s own settings (usually under Connections or Network).\n2. Everyone else joins that hotspot from their Wi-Fi settings, like any network.\n3. Everyone opens the tune. The devices find each other within a few seconds.\n\nIt does not have to be the same person every time: if the usual host is away, anybody else turns theirs on and the rest join it. There is nothing to scan again.'**
  String get guideRehearsalHotspotBody;

  /// User guide, Rehearsals tab.
  ///
  /// In en, this message translates to:
  /// **'Sharing parts uses no mobile data: it never leaves the room. Some phones ask to turn mobile data on before sharing a hotspot, but the rehearsal itself does not use any.'**
  String get guideRehearsalHotspotNote;

  /// Rehearsal screen: warns that a recorded take has not reached every connected device yet.
  ///
  /// In en, this message translates to:
  /// **'Not sent yet'**
  String get rehearsalTakePending;

  /// Rehearsal screen: warns that a recorded take has not reached every connected device yet.
  ///
  /// In en, this message translates to:
  /// **'Stay connected: not everyone has the latest takes yet.'**
  String get rehearsalSyncIncomplete;

  /// Rehearsal lane tag: the take is known but its recording has not arrived on this device yet.
  ///
  /// In en, this message translates to:
  /// **'Waiting for audio'**
  String get rehearsalTakeAwaitingAudio;

  /// Rehearsal tempo controls.
  ///
  /// In en, this message translates to:
  /// **'Tempo'**
  String get rehearsalTempoTitle;

  /// Rehearsal tempo controls.
  ///
  /// In en, this message translates to:
  /// **'Tune tempo'**
  String get rehearsalTuneTempo;

  /// Rehearsal tempo controls.
  ///
  /// In en, this message translates to:
  /// **'Shared with the band. Recordings are re-rendered to match.'**
  String get rehearsalTuneTempoHint;

  /// Rehearsal tempo controls.
  ///
  /// In en, this message translates to:
  /// **'Practice speed'**
  String get rehearsalPracticeSpeed;

  /// Rehearsal tempo controls.
  ///
  /// In en, this message translates to:
  /// **'Only on this device. Slow a passage down without changing pitch.'**
  String get rehearsalPracticeSpeedHint;

  /// Rehearsal tempo controls.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String rehearsalPracticeSpeedValue(int percent);

  /// Rehearsal tempo controls.
  ///
  /// In en, this message translates to:
  /// **'Adjusting the recordings…'**
  String get rehearsalRendering;

  /// Rehearsal tempo controls.
  ///
  /// In en, this message translates to:
  /// **'Metre locked: a part is already recorded against it.'**
  String get rehearsalMeterFrozen;

  /// Rehearsal screen: latency calibration prompt and its explanation.
  ///
  /// In en, this message translates to:
  /// **'Calibrate'**
  String get rehearsalCalibrate;

  /// Rehearsal screen: latency calibration prompt and its explanation.
  ///
  /// In en, this message translates to:
  /// **'Measure this device'**
  String get rehearsalCalibrateTitle;

  /// Rehearsal screen: latency calibration prompt and its explanation.
  ///
  /// In en, this message translates to:
  /// **'Your device takes a moment to play sound, and another to capture it. Together that delay would put every take behind the beat, so it is measured once and subtracted from what you record.\n\nThe measurement plays a few short sweeps and listens for them coming back through the microphone — so it has to be able to hear them:\n\n•  Use the speaker, not headphones. On headphones the microphone hears nothing and the measurement fails.\n•  Turn the volume up.\n•  Keep the room quiet for the few seconds it takes.\n\nMeasure again after switching to a Bluetooth speaker or headset: the delay belongs to the gear, not to the tune, and Bluetooth adds a great deal of it.'**
  String get rehearsalCalibrateBody;

  /// Rehearsal screen: latency calibration prompt and its explanation.
  ///
  /// In en, this message translates to:
  /// **'Measure now'**
  String get rehearsalCalibrateStart;

  /// Rehearsal lane: removing a stale player from the band.
  ///
  /// In en, this message translates to:
  /// **'Remove this player'**
  String get rehearsalRemoveMember;

  /// Rehearsal lane: removing a stale player from the band.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from this tune? Their {count} recording(s) go too, on every device.'**
  String rehearsalRemoveMemberConfirm(String name, int count);

  /// Rehearsal lane: removing a stale player from the band.
  ///
  /// In en, this message translates to:
  /// **'For a device that is gone for good. Their parts go too.'**
  String get rehearsalRemoveMemberHere;

  /// The tune's shared score vault.
  ///
  /// In en, this message translates to:
  /// **'Scores'**
  String get rehearsalDocuments;

  /// The tune's shared score vault.
  ///
  /// In en, this message translates to:
  /// **'No scores yet'**
  String get rehearsalDocumentsEmpty;

  /// The tune's shared score vault.
  ///
  /// In en, this message translates to:
  /// **'Add a score, a chart or a photo of one. Everyone in the tune gets a copy.'**
  String get rehearsalDocumentsEmptyHint;

  /// The tune's shared score vault.
  ///
  /// In en, this message translates to:
  /// **'Add a score'**
  String get rehearsalDocumentAdd;

  /// The tune's shared score vault.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get rehearsalDocumentRemove;

  /// The tune's shared score vault.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" from this tune? It goes from every device.'**
  String rehearsalDocumentRemoveConfirm(String name);

  /// The tune's shared score vault.
  ///
  /// In en, this message translates to:
  /// **'Added by {name}'**
  String rehearsalDocumentAddedBy(String name);

  /// The tune's shared score vault.
  ///
  /// In en, this message translates to:
  /// **'{kb} kB'**
  String rehearsalDocumentSize(int kb);

  /// The tune's shared score vault.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the file'**
  String get rehearsalDocumentWaiting;

  /// The tune's shared score vault.
  ///
  /// In en, this message translates to:
  /// **'Nothing on this device can open that file.'**
  String get rehearsalDocumentNoViewer;

  /// Chord grid.
  ///
  /// In en, this message translates to:
  /// **'Chords'**
  String get rehearsalChordGrid;

  /// Chord grid.
  ///
  /// In en, this message translates to:
  /// **'Write the chords'**
  String get rehearsalChordGridEmpty;

  /// Chord grid.
  ///
  /// In en, this message translates to:
  /// **'Add a bar'**
  String get rehearsalChordAddBar;

  /// Chord grid.
  ///
  /// In en, this message translates to:
  /// **'Remove this bar'**
  String get rehearsalChordRemoveBar;

  /// Chord grid.
  ///
  /// In en, this message translates to:
  /// **'Bar {bar}'**
  String rehearsalChordBar(int bar);

  /// Chord grid.
  ///
  /// In en, this message translates to:
  /// **'Chords per bar'**
  String get rehearsalChordSlots;

  /// Chord grid.
  ///
  /// In en, this message translates to:
  /// **'Am7, C#m7, Gm7b5, C6/9, Am(M7)/B…'**
  String get rehearsalChordHint;

  /// Chord grid.
  ///
  /// In en, this message translates to:
  /// **'Not a chord I can read'**
  String get rehearsalChordInvalid;

  /// Chord grid.
  ///
  /// In en, this message translates to:
  /// **'Show the whole chart'**
  String get rehearsalChordExpand;

  /// Chord grid.
  ///
  /// In en, this message translates to:
  /// **'Collapse to one line'**
  String get rehearsalChordCollapse;

  /// Chord grid.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get rehearsalChordClear;

  /// Chord grid.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get rehearsalChordSave;

  /// Chord grid.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 bar} other{{count} bars}}'**
  String rehearsalChordBarCount(int count);

  /// Latency calibration, per output route.
  ///
  /// In en, this message translates to:
  /// **'{device} has not been measured. A take recorded through it will sit well behind the beat.'**
  String rehearsalRouteUncalibrated(String device);

  /// Latency calibration, per output route.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth adds a long delay of its own, and it differs from one headset to the next.\n\nThe microphone cannot hear your headphones through the air, so hold one earcup against the phone\'s microphone while the measurement runs. That way it hears the sweeps coming back through the headset and measures the real delay, Bluetooth and all.'**
  String get rehearsalRouteBluetoothHint;

  /// No description provided for @rehearsalRouteWiredHint.
  ///
  /// In en, this message translates to:
  /// **'Wired headphones are plugged in, so the sweeps play in the headphones, not through the speaker.\n\nHold one earcup against the phone\'s microphone while the measurement runs, and keep the room quiet. If your headphones have their own microphone, hold the earcup against that one instead.'**
  String get rehearsalRouteWiredHint;

  /// No description provided for @audioRouteWired.
  ///
  /// In en, this message translates to:
  /// **'Your wired headset'**
  String get audioRouteWired;

  /// Master alignment screen.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get masterZoomIn;

  /// Master alignment screen.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get masterZoomOut;

  /// Master alignment screen.
  ///
  /// In en, this message translates to:
  /// **'Whole recording'**
  String get masterZoomReset;

  /// Master alignment screen.
  ///
  /// In en, this message translates to:
  /// **'Skip the silence'**
  String get masterSkipSilence;

  /// Master alignment screen.
  ///
  /// In en, this message translates to:
  /// **'Slower by 0.1'**
  String get masterBpmFiner;

  /// Master alignment screen.
  ///
  /// In en, this message translates to:
  /// **'Faster by 0.1'**
  String get masterBpmFaster;

  /// Master alignment screen.
  ///
  /// In en, this message translates to:
  /// **'×{zoom}'**
  String masterZoomLevel(int zoom);

  /// Master alignment screen.
  ///
  /// In en, this message translates to:
  /// **'The red lines are the beats. Zoom in and adjust the tempo until they land on the sound.'**
  String get masterBeatLinesHint;

  /// Tempo panel, when a recording sets the tempo.
  ///
  /// In en, this message translates to:
  /// **'Set by the recording — change it on the grid alignment screen.'**
  String get rehearsalTempoFromMaster;

  /// Tooltip on the arrow that leaves the rack back panel.
  ///
  /// In en, this message translates to:
  /// **'Back to the front panels'**
  String get patchViewBackTooltip;

  /// No description provided for @audioOutputPathTitle.
  ///
  /// In en, this message translates to:
  /// **'Audio output path'**
  String get audioOutputPathTitle;

  /// No description provided for @audioOutputPathFast.
  ///
  /// In en, this message translates to:
  /// **'Low latency ({ms} ms buffer).'**
  String audioOutputPathFast(String ms);

  /// No description provided for @audioOutputPathFastShared.
  ///
  /// In en, this message translates to:
  /// **'Low latency, shared endpoint ({ms} ms buffer). A few milliseconds dearer than exclusive; nothing to do.'**
  String audioOutputPathFastShared(String ms);

  /// No description provided for @audioOutputPathSlow.
  ///
  /// In en, this message translates to:
  /// **'Slow path: Android refused low latency for this stream. Changing output device may get it back.'**
  String get audioOutputPathSlow;

  /// No description provided for @audioOutputPathLatched.
  ///
  /// In en, this message translates to:
  /// **'Slow path, locked for this session: GrooveForge gave up low latency after the phone\'s audio service failed on it. Playing will feel delayed — around a quarter of a second — until you restore it below.'**
  String get audioOutputPathLatched;

  /// No description provided for @audioOutputPathUsbDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct USB output is driving the sound, so Android\'s latency does not apply.'**
  String get audioOutputPathUsbDirect;

  /// No description provided for @audioOutputPathNoStream.
  ///
  /// In en, this message translates to:
  /// **'No audio stream open yet.'**
  String get audioOutputPathNoStream;

  /// No description provided for @audioOutputPathRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore low latency'**
  String get audioOutputPathRestore;

  /// No description provided for @audioOutputPathRestoring.
  ///
  /// In en, this message translates to:
  /// **'Reopening the audio stream…'**
  String get audioOutputPathRestoring;

  /// No description provided for @audioOutputPathRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Low latency is still refused. Restarting GrooveForge clears it; if it comes back at once, this phone\'s audio service is failing on the fast path.'**
  String get audioOutputPathRestoreFailed;

  /// No description provided for @audioOutputPathIndicatorTooltip.
  ///
  /// In en, this message translates to:
  /// **'Audio is delayed — tap for details'**
  String get audioOutputPathIndicatorTooltip;

  /// No description provided for @audioOutputPathRestartHint.
  ///
  /// In en, this message translates to:
  /// **'Force-quitting GrooveForge also clears this, and is the fastest fix if you are on stage.'**
  String get audioOutputPathRestartHint;

  /// No description provided for @ccReleaseValueTitle.
  ///
  /// In en, this message translates to:
  /// **'Neutral value on release'**
  String get ccReleaseValueTitle;

  /// No description provided for @ccReleaseValueHelp.
  ///
  /// In en, this message translates to:
  /// **'For ribbons and touch strips that jump back to 0 when you lift your finger. Leave off for knobs, faders, wheels, pedals and pads. If your controller has a hold or latch mode, use it to keep the last value.'**
  String get ccReleaseValueHelp;

  /// No description provided for @ccReleaseValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Value: {value}'**
  String ccReleaseValueLabel(int value);

  /// No description provided for @ccReleaseValueSummary.
  ///
  /// In en, this message translates to:
  /// **'returns to {value} on release'**
  String ccReleaseValueSummary(int value);

  /// No description provided for @ccReleaseValueDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'CC {cc}: release'**
  String ccReleaseValueDialogTitle(int cc);

  /// No description provided for @ccGmBankSelect.
  ///
  /// In en, this message translates to:
  /// **'Bank Select (MSB)'**
  String get ccGmBankSelect;

  /// No description provided for @ccGmModWheel.
  ///
  /// In en, this message translates to:
  /// **'Modulation Wheel (Vibrato)'**
  String get ccGmModWheel;

  /// No description provided for @ccGmBreath.
  ///
  /// In en, this message translates to:
  /// **'Breath Control'**
  String get ccGmBreath;

  /// No description provided for @ccGmFootPedal.
  ///
  /// In en, this message translates to:
  /// **'Foot Pedal'**
  String get ccGmFootPedal;

  /// No description provided for @ccGmPortamentoTime.
  ///
  /// In en, this message translates to:
  /// **'Portamento Time'**
  String get ccGmPortamentoTime;

  /// No description provided for @ccGmMainVolume.
  ///
  /// In en, this message translates to:
  /// **'Main Volume'**
  String get ccGmMainVolume;

  /// No description provided for @ccGmPan.
  ///
  /// In en, this message translates to:
  /// **'Pan (Stereo)'**
  String get ccGmPan;

  /// No description provided for @ccGmExpression.
  ///
  /// In en, this message translates to:
  /// **'Expression'**
  String get ccGmExpression;

  /// No description provided for @ccGmSustainPedal.
  ///
  /// In en, this message translates to:
  /// **'Sustain Pedal'**
  String get ccGmSustainPedal;

  /// No description provided for @ccGmPortamento.
  ///
  /// In en, this message translates to:
  /// **'Portamento'**
  String get ccGmPortamento;

  /// No description provided for @ccGmResonance.
  ///
  /// In en, this message translates to:
  /// **'Resonance (Filter)'**
  String get ccGmResonance;

  /// No description provided for @ccGmCutoff.
  ///
  /// In en, this message translates to:
  /// **'Frequency Cutoff (Filter)'**
  String get ccGmCutoff;

  /// No description provided for @ccGmReverbSend.
  ///
  /// In en, this message translates to:
  /// **'Reverb Send Level'**
  String get ccGmReverbSend;

  /// No description provided for @ccGmChorusSend.
  ///
  /// In en, this message translates to:
  /// **'Chorus Send Level'**
  String get ccGmChorusSend;

  /// No description provided for @ccSysNextSoundfont.
  ///
  /// In en, this message translates to:
  /// **'[System] Next Soundfont'**
  String get ccSysNextSoundfont;

  /// No description provided for @ccSysPrevSoundfont.
  ///
  /// In en, this message translates to:
  /// **'[System] Prev Soundfont'**
  String get ccSysPrevSoundfont;

  /// No description provided for @ccSysNextPatch.
  ///
  /// In en, this message translates to:
  /// **'[System] Next Program/Patch'**
  String get ccSysNextPatch;

  /// No description provided for @ccSysPrevPatch.
  ///
  /// In en, this message translates to:
  /// **'[System] Prev Program/Patch'**
  String get ccSysPrevPatch;

  /// No description provided for @ccSysPatchSweep.
  ///
  /// In en, this message translates to:
  /// **'[System] Absolute Patch Sweep'**
  String get ccSysPatchSweep;

  /// No description provided for @ccSysBankSweep.
  ///
  /// In en, this message translates to:
  /// **'[System] Absolute Bank/Tone Sweep'**
  String get ccSysBankSweep;

  /// No description provided for @ccSysJamMode.
  ///
  /// In en, this message translates to:
  /// **'[System] Start/Stop Jam Mode'**
  String get ccSysJamMode;

  /// No description provided for @ccSysCycleScale.
  ///
  /// In en, this message translates to:
  /// **'[System] Cycle Scale Type'**
  String get ccSysCycleScale;

  /// No description provided for @ccSysMidiLooperLoop.
  ///
  /// In en, this message translates to:
  /// **'[MIDI Looper] Loop Button'**
  String get ccSysMidiLooperLoop;

  /// No description provided for @ccSysMidiLooperStop.
  ///
  /// In en, this message translates to:
  /// **'[MIDI Looper] Stop'**
  String get ccSysMidiLooperStop;

  /// No description provided for @ccSysAudioLooperLoop.
  ///
  /// In en, this message translates to:
  /// **'[Audio Looper] Loop Button'**
  String get ccSysAudioLooperLoop;

  /// No description provided for @ccSysAudioLooperStop.
  ///
  /// In en, this message translates to:
  /// **'[Audio Looper] Stop'**
  String get ccSysAudioLooperStop;

  /// No description provided for @ccSysMuteChannels.
  ///
  /// In en, this message translates to:
  /// **'[System] Mute / Unmute Channels'**
  String get ccSysMuteChannels;

  /// No description provided for @ccParamMix.
  ///
  /// In en, this message translates to:
  /// **'Mix'**
  String get ccParamMix;

  /// No description provided for @ccParamWaveform.
  ///
  /// In en, this message translates to:
  /// **'Waveform'**
  String get ccParamWaveform;

  /// No description provided for @ccParamVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get ccParamVolume;

  /// No description provided for @ccParamToggleOnOff.
  ///
  /// In en, this message translates to:
  /// **'Toggle On/Off'**
  String get ccParamToggleOnOff;

  /// No description provided for @ccParamStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get ccParamStop;

  /// No description provided for @ccParamLevel.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get ccParamLevel;

  /// No description provided for @ccParamBypass.
  ///
  /// In en, this message translates to:
  /// **'Bypass'**
  String get ccParamBypass;

  /// No description provided for @ccParamVibratoDepth.
  ///
  /// In en, this message translates to:
  /// **'Vibrato Depth'**
  String get ccParamVibratoDepth;

  /// No description provided for @ccParamVibrato.
  ///
  /// In en, this message translates to:
  /// **'Vibrato'**
  String get ccParamVibrato;

  /// No description provided for @ccParamTuneOnOff.
  ///
  /// In en, this message translates to:
  /// **'Tune On/Off'**
  String get ccParamTuneOnOff;

  /// No description provided for @ccParamTone.
  ///
  /// In en, this message translates to:
  /// **'Tone'**
  String get ccParamTone;

  /// No description provided for @ccParamTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get ccParamTime;

  /// No description provided for @ccParamThreshold.
  ///
  /// In en, this message translates to:
  /// **'Threshold'**
  String get ccParamThreshold;

  /// No description provided for @ccParamSwing.
  ///
  /// In en, this message translates to:
  /// **'Swing'**
  String get ccParamSwing;

  /// No description provided for @ccParamSustain.
  ///
  /// In en, this message translates to:
  /// **'Sustain'**
  String get ccParamSustain;

  /// No description provided for @ccParamStrength.
  ///
  /// In en, this message translates to:
  /// **'Strength'**
  String get ccParamStrength;

  /// No description provided for @ccParamStartStop.
  ///
  /// In en, this message translates to:
  /// **'Start / Stop'**
  String get ccParamStartStop;

  /// No description provided for @ccParamSnapOnOff.
  ///
  /// In en, this message translates to:
  /// **'Snap On/Off'**
  String get ccParamSnapOnOff;

  /// No description provided for @ccParamSemitones.
  ///
  /// In en, this message translates to:
  /// **'Semitones'**
  String get ccParamSemitones;

  /// No description provided for @ccParamSelectPatch.
  ///
  /// In en, this message translates to:
  /// **'Select Patch'**
  String get ccParamSelectPatch;

  /// No description provided for @ccParamScaleType.
  ///
  /// In en, this message translates to:
  /// **'Scale Type'**
  String get ccParamScaleType;

  /// No description provided for @ccParamRetune.
  ///
  /// In en, this message translates to:
  /// **'Retune'**
  String get ccParamRetune;

  /// No description provided for @ccParamRecallScale.
  ///
  /// In en, this message translates to:
  /// **'Recall Scale'**
  String get ccParamRecallScale;

  /// No description provided for @ccParamRecallRoot.
  ///
  /// In en, this message translates to:
  /// **'Recall Root'**
  String get ccParamRecallRoot;

  /// No description provided for @ccParamRate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get ccParamRate;

  /// No description provided for @ccParamRangeOctaves.
  ///
  /// In en, this message translates to:
  /// **'Range (octaves)'**
  String get ccParamRangeOctaves;

  /// No description provided for @ccParamPrevSoundfont.
  ///
  /// In en, this message translates to:
  /// **'Previous Soundfont'**
  String get ccParamPrevSoundfont;

  /// No description provided for @ccParamPrevPattern.
  ///
  /// In en, this message translates to:
  /// **'Previous Pattern'**
  String get ccParamPrevPattern;

  /// No description provided for @ccParamPrevPatch.
  ///
  /// In en, this message translates to:
  /// **'Previous Patch'**
  String get ccParamPrevPatch;

  /// No description provided for @ccParamPickupType.
  ///
  /// In en, this message translates to:
  /// **'Pickup type'**
  String get ccParamPickupType;

  /// No description provided for @ccParamPickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get ccParamPickup;

  /// No description provided for @ccParamPickPosition.
  ///
  /// In en, this message translates to:
  /// **'Pick position'**
  String get ccParamPickPosition;

  /// No description provided for @ccParamPedalSustain.
  ///
  /// In en, this message translates to:
  /// **'Pedal sustain'**
  String get ccParamPedalSustain;

  /// No description provided for @ccParamPedal.
  ///
  /// In en, this message translates to:
  /// **'Pedal'**
  String get ccParamPedal;

  /// No description provided for @ccParamPattern.
  ///
  /// In en, this message translates to:
  /// **'Pattern'**
  String get ccParamPattern;

  /// No description provided for @ccParamPatchKnob.
  ///
  /// In en, this message translates to:
  /// **'Patch (knob)'**
  String get ccParamPatchKnob;

  /// No description provided for @ccParamPalmMuteOnOff.
  ///
  /// In en, this message translates to:
  /// **'Palm mute on/off'**
  String get ccParamPalmMuteOnOff;

  /// No description provided for @ccParamPalmMute.
  ///
  /// In en, this message translates to:
  /// **'Palm mute'**
  String get ccParamPalmMute;

  /// No description provided for @ccParamOverlapLegato.
  ///
  /// In en, this message translates to:
  /// **'Overlap legato on/off'**
  String get ccParamOverlapLegato;

  /// No description provided for @ccParamNoiseMix.
  ///
  /// In en, this message translates to:
  /// **'Noise Mix'**
  String get ccParamNoiseMix;

  /// No description provided for @ccParamNextSoundfont.
  ///
  /// In en, this message translates to:
  /// **'Next Soundfont'**
  String get ccParamNextSoundfont;

  /// No description provided for @ccParamNextScaleInFamily.
  ///
  /// In en, this message translates to:
  /// **'Next Scale (in family)'**
  String get ccParamNextScaleInFamily;

  /// No description provided for @ccParamNextPattern.
  ///
  /// In en, this message translates to:
  /// **'Next Pattern'**
  String get ccParamNextPattern;

  /// No description provided for @ccParamNextPatch.
  ///
  /// In en, this message translates to:
  /// **'Next Patch'**
  String get ccParamNextPatch;

  /// No description provided for @ccParamMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get ccParamMute;

  /// No description provided for @ccParamMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get ccParamMode;

  /// No description provided for @ccParamMidiLoopButton.
  ///
  /// In en, this message translates to:
  /// **'Loop Button (Record/Play/Overdub)'**
  String get ccParamMidiLoopButton;

  /// No description provided for @ccParamAudioLoopButton.
  ///
  /// In en, this message translates to:
  /// **'Loop Button (Arm/Record/Play/Overdub)'**
  String get ccParamAudioLoopButton;

  /// No description provided for @ccParamLegatoOnOff.
  ///
  /// In en, this message translates to:
  /// **'Legato on/off (hammer-on / pull-off)'**
  String get ccParamLegatoOnOff;

  /// No description provided for @ccParamLatchRoot.
  ///
  /// In en, this message translates to:
  /// **'Latch Root from Held Notes'**
  String get ccParamLatchRoot;

  /// No description provided for @ccParamInputGain.
  ///
  /// In en, this message translates to:
  /// **'Input Gain'**
  String get ccParamInputGain;

  /// No description provided for @ccParamHumanFeel.
  ///
  /// In en, this message translates to:
  /// **'Human Feel'**
  String get ccParamHumanFeel;

  /// No description provided for @ccParamGateThreshold.
  ///
  /// In en, this message translates to:
  /// **'Gate Threshold'**
  String get ccParamGateThreshold;

  /// No description provided for @ccParamGain.
  ///
  /// In en, this message translates to:
  /// **'Gain'**
  String get ccParamGain;

  /// No description provided for @ccParamFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback (larsen)'**
  String get ccParamFeedback;

  /// No description provided for @ccParamFeedbackHarmonic.
  ///
  /// In en, this message translates to:
  /// **'Feedback harmonic'**
  String get ccParamFeedbackHarmonic;

  /// No description provided for @ccParamEnvRelease.
  ///
  /// In en, this message translates to:
  /// **'Envelope Release'**
  String get ccParamEnvRelease;

  /// No description provided for @ccParamDriveType.
  ///
  /// In en, this message translates to:
  /// **'Drive type'**
  String get ccParamDriveType;

  /// No description provided for @ccParamDriveOnOff.
  ///
  /// In en, this message translates to:
  /// **'Drive on/off'**
  String get ccParamDriveOnOff;

  /// No description provided for @ccParamDrive.
  ///
  /// In en, this message translates to:
  /// **'Drive'**
  String get ccParamDrive;

  /// No description provided for @ccParamDivision.
  ///
  /// In en, this message translates to:
  /// **'Division'**
  String get ccParamDivision;

  /// No description provided for @ccParamDetectionMode.
  ///
  /// In en, this message translates to:
  /// **'Detection Mode'**
  String get ccParamDetectionMode;

  /// No description provided for @ccParamDepth.
  ///
  /// In en, this message translates to:
  /// **'Depth'**
  String get ccParamDepth;

  /// No description provided for @ccParamChordType.
  ///
  /// In en, this message translates to:
  /// **'Chord Type'**
  String get ccParamChordType;

  /// No description provided for @ccParamChipArpOnOff.
  ///
  /// In en, this message translates to:
  /// **'Chiptune Arp On/Off'**
  String get ccParamChipArpOnOff;

  /// No description provided for @ccParamChipArpChord.
  ///
  /// In en, this message translates to:
  /// **'Chiptune Arp Chord'**
  String get ccParamChipArpChord;

  /// No description provided for @ccParamCenter.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get ccParamCenter;

  /// No description provided for @ccParamCabOnOff.
  ///
  /// In en, this message translates to:
  /// **'Cab on/off'**
  String get ccParamCabOnOff;

  /// No description provided for @ccParamBpmSync.
  ///
  /// In en, this message translates to:
  /// **'BPM Sync'**
  String get ccParamBpmSync;

  /// No description provided for @ccParamBaseNote.
  ///
  /// In en, this message translates to:
  /// **'Base Note'**
  String get ccParamBaseNote;

  /// No description provided for @ccParamBandwidth.
  ///
  /// In en, this message translates to:
  /// **'Bandwidth'**
  String get ccParamBandwidth;

  /// No description provided for @ccParamAttack.
  ///
  /// In en, this message translates to:
  /// **'Attack'**
  String get ccParamAttack;

  /// No description provided for @ccParamArpRate.
  ///
  /// In en, this message translates to:
  /// **'Arp Rate (PAL/NTSC)'**
  String get ccParamArpRate;

  /// No description provided for @ccParamAmpOnOff.
  ///
  /// In en, this message translates to:
  /// **'Amp on/off'**
  String get ccParamAmpOnOff;

  /// No description provided for @ccParamAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get ccParamAmount;

  /// No description provided for @guideTabStart.
  ///
  /// In en, this message translates to:
  /// **'Start here'**
  String get guideTabStart;

  /// No description provided for @guideTabModules.
  ///
  /// In en, this message translates to:
  /// **'Modules'**
  String get guideTabModules;

  /// No description provided for @guideRulesTitle.
  ///
  /// In en, this message translates to:
  /// **'How sound moves between modules'**
  String get guideRulesTitle;

  /// No description provided for @guideRulesIntro.
  ///
  /// In en, this message translates to:
  /// **'Tap the cable icon at the top of the rack to see the back of your modules. That is where you connect them with cables.'**
  String get guideRulesIntro;

  /// No description provided for @guideRuleInstrument.
  ///
  /// In en, this message translates to:
  /// **'An instrument plays through the speakers on its own. You do not need a cable to hear it.'**
  String get guideRuleInstrument;

  /// No description provided for @guideRuleColours.
  ///
  /// In en, this message translates to:
  /// **'Yellow cables carry notes (MIDI), from a keyboard to an instrument. Red and white cables carry sound, left and right.'**
  String get guideRuleColours;

  /// No description provided for @guideRuleEffect.
  ///
  /// In en, this message translates to:
  /// **'To put an effect after an instrument, cable the instrument\'s AUDIO OUT L and R into the effect\'s AUDIO IN L and R. What comes out of the effect goes to the speakers.'**
  String get guideRuleEffect;

  /// No description provided for @guideRuleDraw.
  ///
  /// In en, this message translates to:
  /// **'To draw a cable, long-press a socket and drag it to another one. Sockets that accept it light up while you drag.'**
  String get guideRuleDraw;

  /// No description provided for @guideWatchClip.
  ///
  /// In en, this message translates to:
  /// **'Watch the clip'**
  String get guideWatchClip;

  /// No description provided for @guideRecipeScaleTitle.
  ///
  /// In en, this message translates to:
  /// **'Play in a scale'**
  String get guideRecipeScaleTitle;

  /// No description provided for @guideRecipeScaleSteps.
  ///
  /// In en, this message translates to:
  /// **'Every new project has a keyboard and a Xen module.\nHold a key and tap a scale, for example Blues. Xen switches on, and the key you hold becomes the root note.\nOpen Family for other traditions: maqamat, ragas, Japanese scales and more.'**
  String get guideRecipeScaleSteps;

  /// No description provided for @guideRecipeScaleResult.
  ///
  /// In en, this message translates to:
  /// **'Grey keys are outside the scale: press one and you hear the nearest note that fits.'**
  String get guideRecipeScaleResult;

  /// No description provided for @guideRecipeEffectTitle.
  ///
  /// In en, this message translates to:
  /// **'Add an effect to your keyboard'**
  String get guideRecipeEffectTitle;

  /// No description provided for @guideRecipeEffectSteps.
  ///
  /// In en, this message translates to:
  /// **'Tap + and pick an effect, for example Reverb.\nTap the cable icon at the top.\nLong-press the keyboard\'s red AUDIO OUT L and drag it to the effect\'s AUDIO IN L. Then the white R to R.\nTap the back arrow and play.'**
  String get guideRecipeEffectSteps;

  /// No description provided for @guideRecipeEffectResult.
  ///
  /// In en, this message translates to:
  /// **'You hear the keyboard through the effect. Turn its knobs to change the sound.'**
  String get guideRecipeEffectResult;

  /// No description provided for @guideRecipeRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove a cable or a module'**
  String get guideRecipeRemoveTitle;

  /// No description provided for @guideRecipeRemoveSteps.
  ///
  /// In en, this message translates to:
  /// **'A cable: in the cable view, tap the small ✕ in the middle of the cable, then Disconnect.\nA module: tap the bin icon at the top of the module, then Remove. Its cables go with it.'**
  String get guideRecipeRemoveSteps;

  /// No description provided for @guideRecipeRemoveResult.
  ///
  /// In en, this message translates to:
  /// **''**
  String get guideRecipeRemoveResult;

  /// No description provided for @guideRecipeGuitarTitle.
  ///
  /// In en, this message translates to:
  /// **'Play the guitar from the keyboard'**
  String get guideRecipeGuitarTitle;

  /// No description provided for @guideRecipeGuitarSteps.
  ///
  /// In en, this message translates to:
  /// **'Tap + and pick Riff.\nIn the cable view, drag the keyboard\'s yellow MIDI OUT to Riff\'s MIDI IN.\nPlay: you hear the piano and the guitar together.\nTo hear only the guitar, set the keyboard\'s sound menu to None (MIDI only).'**
  String get guideRecipeGuitarSteps;

  /// No description provided for @guideRecipeGuitarResult.
  ///
  /// In en, this message translates to:
  /// **'Riff has no keys of its own: the keyboard sends it the notes.'**
  String get guideRecipeGuitarResult;

  /// No description provided for @guideRecipeAmpTitle.
  ///
  /// In en, this message translates to:
  /// **'Put the guitar through the amp'**
  String get guideRecipeAmpTitle;

  /// No description provided for @guideRecipeAmpSteps.
  ///
  /// In en, this message translates to:
  /// **'Tap + and pick Amp.\nIn the cable view, drag Riff\'s AUDIO OUT L to the Amp\'s AUDIO IN L, then R to R.\nPlay, and turn Drive on the Amp.'**
  String get guideRecipeAmpSteps;

  /// No description provided for @guideRecipeAmpResult.
  ///
  /// In en, this message translates to:
  /// **'The clean guitar gets crunchy or distorted.'**
  String get guideRecipeAmpResult;

  /// No description provided for @guideRecipeControllerTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect a MIDI controller'**
  String get guideRecipeControllerTitle;

  /// No description provided for @guideRecipeControllerSteps.
  ///
  /// In en, this message translates to:
  /// **'Plug it in over USB (with an OTG adapter on a phone), or switch on a Bluetooth MIDI controller.\nOpen Preferences with the gear icon.\nUnder MIDI Connection, tap Connect MIDI Device and pick it.'**
  String get guideRecipeControllerSteps;

  /// No description provided for @guideRecipeControllerResult.
  ///
  /// In en, this message translates to:
  /// **'It plays the module whose MIDI CH badge matches the channel it sends on, usually 1.'**
  String get guideRecipeControllerResult;

  /// No description provided for @guideRecipeLearnTitle.
  ///
  /// In en, this message translates to:
  /// **'Map a knob'**
  String get guideRecipeLearnTitle;

  /// No description provided for @guideRecipeLearnSteps.
  ///
  /// In en, this message translates to:
  /// **'Tap the sliders icon at the top of a module.\nTap Learn next to a control, for example Palm mute.\nMove a knob or press a pad on your controller.'**
  String get guideRecipeLearnSteps;

  /// No description provided for @guideRecipeLearnResult.
  ///
  /// In en, this message translates to:
  /// **'The control now follows your hardware. The mapping is saved with the project.'**
  String get guideRecipeLearnResult;

  /// No description provided for @guideRecipeDrumsTitle.
  ///
  /// In en, this message translates to:
  /// **'Start a drum beat'**
  String get guideRecipeDrumsTitle;

  /// No description provided for @guideRecipeDrumsSteps.
  ///
  /// In en, this message translates to:
  /// **'Tap + and pick Drum Generator.\nPick a pattern from the menu.\nSwitch Active on and press play at the top.'**
  String get guideRecipeDrumsSteps;

  /// No description provided for @guideRecipeDrumsResult.
  ///
  /// In en, this message translates to:
  /// **'The beat follows the tempo in the transport bar.'**
  String get guideRecipeDrumsResult;

  /// No description provided for @guideRecipeLoopTitle.
  ///
  /// In en, this message translates to:
  /// **'Record a loop'**
  String get guideRecipeLoopTitle;

  /// No description provided for @guideRecipeLoopSteps.
  ///
  /// In en, this message translates to:
  /// **'Tap + and pick Audio Looper.\nIn the cable view, cable the keyboard\'s AUDIO OUT L and R into the looper\'s AUDIO IN L and R.\nPress the looper\'s record button. Recording starts on the first beat of the next bar.\nPlay, then press it again: recording stops at the end of the bar and the loop plays. Press it once more to add a layer.'**
  String get guideRecipeLoopSteps;

  /// No description provided for @guideRecipeLoopResult.
  ///
  /// In en, this message translates to:
  /// **'If the tempo was stopped, it starts and gives you one bar to get ready.'**
  String get guideRecipeLoopResult;

  /// No description provided for @guideRecipeProjectsTitle.
  ///
  /// In en, this message translates to:
  /// **'Save and open projects'**
  String get guideRecipeProjectsTitle;

  /// No description provided for @guideRecipeProjectsSteps.
  ///
  /// In en, this message translates to:
  /// **'Tap the folder icon at the top.\nSave As… writes your modules, cables and settings to a .gf file.\nNew Project starts over with a keyboard and Xen. Anything not saved is lost.\nOpen Project loads a saved file.'**
  String get guideRecipeProjectsSteps;

  /// No description provided for @guideRecipeProjectsResult.
  ///
  /// In en, this message translates to:
  /// **'The app also keeps your current session between launches, except in the web demo.'**
  String get guideRecipeProjectsResult;

  /// No description provided for @guideModulesIntro.
  ///
  /// In en, this message translates to:
  /// **'Everything the + button at the bottom of the rack can add. Drag the handle on the left of a module to move it.'**
  String get guideModulesIntro;

  /// No description provided for @guideVocoderNote.
  ///
  /// In en, this message translates to:
  /// **'Use wired headphones or speakers: Bluetooth adds too much delay to sing live.'**
  String get guideVocoderNote;

  /// No description provided for @guideJackLegendTitle.
  ///
  /// In en, this message translates to:
  /// **'Socket colours'**
  String get guideJackLegendTitle;

  /// No description provided for @guideJackMidi.
  ///
  /// In en, this message translates to:
  /// **'notes and controls (MIDI)'**
  String get guideJackMidi;

  /// No description provided for @guideJackAudioL.
  ///
  /// In en, this message translates to:
  /// **'sound, left'**
  String get guideJackAudioL;

  /// No description provided for @guideJackAudioR.
  ///
  /// In en, this message translates to:
  /// **'sound, right'**
  String get guideJackAudioR;

  /// No description provided for @guideJackSend.
  ///
  /// In en, this message translates to:
  /// **'effects loop'**
  String get guideJackSend;

  /// No description provided for @guideJackData.
  ///
  /// In en, this message translates to:
  /// **'the scale and the current chord'**
  String get guideJackData;

  /// No description provided for @guideJackTune.
  ///
  /// In en, this message translates to:
  /// **'tuning for scales between the piano keys'**
  String get guideJackTune;

  /// Socket names as printed on the back panels (CHORD and SCALE jacks); must match portChordOut/portScaleOut.
  ///
  /// In en, this message translates to:
  /// **'CHORD / SCALE'**
  String get guideJackLegendData;

  /// No description provided for @guideMidiHardwareStep3.
  ///
  /// In en, this message translates to:
  /// **'It plays the module whose MIDI CH badge matches the channel it sends on, usually 1. Tap the badge on a module to change its channel.'**
  String get guideMidiHardwareStep3;

  /// No description provided for @gfpaAmpAmp.
  ///
  /// In en, this message translates to:
  /// **'Amp'**
  String get gfpaAmpAmp;

  /// No description provided for @gfpaAmpBass.
  ///
  /// In en, this message translates to:
  /// **'Bass'**
  String get gfpaAmpBass;

  /// No description provided for @gfpaAmpCab.
  ///
  /// In en, this message translates to:
  /// **'Cab'**
  String get gfpaAmpCab;

  /// No description provided for @gfpaAmpCabinet.
  ///
  /// In en, this message translates to:
  /// **'Cabinet'**
  String get gfpaAmpCabinet;

  /// No description provided for @gfpaAmpDrive.
  ///
  /// In en, this message translates to:
  /// **'Drive'**
  String get gfpaAmpDrive;

  /// No description provided for @gfpaAmpGain.
  ///
  /// In en, this message translates to:
  /// **'Gain'**
  String get gfpaAmpGain;

  /// No description provided for @gfpaAmpMiddle.
  ///
  /// In en, this message translates to:
  /// **'Middle'**
  String get gfpaAmpMiddle;

  /// No description provided for @gfpaAmpModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get gfpaAmpModel;

  /// No description provided for @gfpaAmpOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get gfpaAmpOn;

  /// No description provided for @gfpaAmpOverdrive.
  ///
  /// In en, this message translates to:
  /// **'Overdrive'**
  String get gfpaAmpOverdrive;

  /// No description provided for @gfpaAmpTreble.
  ///
  /// In en, this message translates to:
  /// **'Treble'**
  String get gfpaAmpTreble;

  /// No description provided for @gfpaArpeggiatorDivision.
  ///
  /// In en, this message translates to:
  /// **'Division'**
  String get gfpaArpeggiatorDivision;

  /// No description provided for @gfpaArpeggiatorDnUp.
  ///
  /// In en, this message translates to:
  /// **'DnUp'**
  String get gfpaArpeggiatorDnUp;

  /// No description provided for @gfpaArpeggiatorDown.
  ///
  /// In en, this message translates to:
  /// **'Down'**
  String get gfpaArpeggiatorDown;

  /// No description provided for @gfpaArpeggiatorGate.
  ///
  /// In en, this message translates to:
  /// **'Gate'**
  String get gfpaArpeggiatorGate;

  /// No description provided for @gfpaArpeggiatorOctaves.
  ///
  /// In en, this message translates to:
  /// **'Octaves'**
  String get gfpaArpeggiatorOctaves;

  /// No description provided for @gfpaArpeggiatorPattern.
  ///
  /// In en, this message translates to:
  /// **'Pattern'**
  String get gfpaArpeggiatorPattern;

  /// No description provided for @gfpaArpeggiatorPlayed.
  ///
  /// In en, this message translates to:
  /// **'Played'**
  String get gfpaArpeggiatorPlayed;

  /// No description provided for @gfpaArpeggiatorRange.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get gfpaArpeggiatorRange;

  /// No description provided for @gfpaArpeggiatorRhythm.
  ///
  /// In en, this message translates to:
  /// **'Rhythm'**
  String get gfpaArpeggiatorRhythm;

  /// No description provided for @gfpaArpeggiatorUp.
  ///
  /// In en, this message translates to:
  /// **'Up'**
  String get gfpaArpeggiatorUp;

  /// No description provided for @gfpaArpeggiatorUpDown.
  ///
  /// In en, this message translates to:
  /// **'UpDown'**
  String get gfpaArpeggiatorUpDown;

  /// No description provided for @gfpaAudioHarmonizerDryWet.
  ///
  /// In en, this message translates to:
  /// **'Dry/Wet'**
  String get gfpaAudioHarmonizerDryWet;

  /// No description provided for @gfpaAutotuneBlues.
  ///
  /// In en, this message translates to:
  /// **'Blues'**
  String get gfpaAutotuneBlues;

  /// No description provided for @gfpaAutotuneChromatic.
  ///
  /// In en, this message translates to:
  /// **'Chromatic'**
  String get gfpaAutotuneChromatic;

  /// No description provided for @gfpaAutotuneHarmonicMinor.
  ///
  /// In en, this message translates to:
  /// **'Harmonic Minor'**
  String get gfpaAutotuneHarmonicMinor;

  /// No description provided for @gfpaAutotuneHumanize.
  ///
  /// In en, this message translates to:
  /// **'Humanize'**
  String get gfpaAutotuneHumanize;

  /// No description provided for @gfpaAutotuneKey.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get gfpaAutotuneKey;

  /// No description provided for @gfpaAutotuneMajor.
  ///
  /// In en, this message translates to:
  /// **'Major'**
  String get gfpaAutotuneMajor;

  /// No description provided for @gfpaAutotuneMajorPenta.
  ///
  /// In en, this message translates to:
  /// **'Major Penta'**
  String get gfpaAutotuneMajorPenta;

  /// No description provided for @gfpaAutotuneMinor.
  ///
  /// In en, this message translates to:
  /// **'Minor'**
  String get gfpaAutotuneMinor;

  /// No description provided for @gfpaAutotuneMinorPenta.
  ///
  /// In en, this message translates to:
  /// **'Minor Penta'**
  String get gfpaAutotuneMinorPenta;

  /// No description provided for @gfpaAutotuneNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get gfpaAutotuneNotes;

  /// No description provided for @gfpaAutotuneRetune.
  ///
  /// In en, this message translates to:
  /// **'Retune'**
  String get gfpaAutotuneRetune;

  /// No description provided for @gfpaAutotuneStrength.
  ///
  /// In en, this message translates to:
  /// **'Strength'**
  String get gfpaAutotuneStrength;

  /// No description provided for @gfpaAutotuneTune.
  ///
  /// In en, this message translates to:
  /// **'Tune'**
  String get gfpaAutotuneTune;

  /// No description provided for @gfpaAutotuneVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get gfpaAutotuneVoice;

  /// No description provided for @gfpaChordChord.
  ///
  /// In en, this message translates to:
  /// **'Chord'**
  String get gfpaChordChord;

  /// No description provided for @gfpaChordChordType.
  ///
  /// In en, this message translates to:
  /// **'Chord Type'**
  String get gfpaChordChordType;

  /// No description provided for @gfpaChordClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get gfpaChordClose;

  /// No description provided for @gfpaChordOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get gfpaChordOpen;

  /// No description provided for @gfpaChordSpread.
  ///
  /// In en, this message translates to:
  /// **'Spread'**
  String get gfpaChordSpread;

  /// No description provided for @gfpaChordVoicing.
  ///
  /// In en, this message translates to:
  /// **'Voicing'**
  String get gfpaChordVoicing;

  /// No description provided for @gfpaChordWide.
  ///
  /// In en, this message translates to:
  /// **'Wide'**
  String get gfpaChordWide;

  /// No description provided for @gfpaCompressorCompression.
  ///
  /// In en, this message translates to:
  /// **'Compression'**
  String get gfpaCompressorCompression;

  /// No description provided for @gfpaCompressorEnvelope.
  ///
  /// In en, this message translates to:
  /// **'Envelope'**
  String get gfpaCompressorEnvelope;

  /// No description provided for @gfpaCompressorMakeup.
  ///
  /// In en, this message translates to:
  /// **'Makeup'**
  String get gfpaCompressorMakeup;

  /// No description provided for @gfpaCompressorRatio.
  ///
  /// In en, this message translates to:
  /// **'Ratio'**
  String get gfpaCompressorRatio;

  /// No description provided for @gfpaCompressorRelease.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get gfpaCompressorRelease;

  /// No description provided for @gfpaCompressorThresh.
  ///
  /// In en, this message translates to:
  /// **'Thresh'**
  String get gfpaCompressorThresh;

  /// No description provided for @gfpaDelayCharacter.
  ///
  /// In en, this message translates to:
  /// **'Character'**
  String get gfpaDelayCharacter;

  /// No description provided for @gfpaDelayTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get gfpaDelayTime;

  /// No description provided for @gfpaDelayTiming.
  ///
  /// In en, this message translates to:
  /// **'Timing'**
  String get gfpaDelayTiming;

  /// No description provided for @gfpaEqFlat.
  ///
  /// In en, this message translates to:
  /// **'Flat'**
  String get gfpaEqFlat;

  /// No description provided for @gfpaEqHM.
  ///
  /// In en, this message translates to:
  /// **'HM'**
  String get gfpaEqHM;

  /// No description provided for @gfpaEqHMHz.
  ///
  /// In en, this message translates to:
  /// **'HM Hz'**
  String get gfpaEqHMHz;

  /// No description provided for @gfpaEqHMQ.
  ///
  /// In en, this message translates to:
  /// **'HM Q'**
  String get gfpaEqHMQ;

  /// No description provided for @gfpaEqHiHz.
  ///
  /// In en, this message translates to:
  /// **'Hi Hz'**
  String get gfpaEqHiHz;

  /// No description provided for @gfpaEqHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get gfpaEqHigh;

  /// No description provided for @gfpaEqHighGain.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get gfpaEqHighGain;

  /// No description provided for @gfpaEqHighMid.
  ///
  /// In en, this message translates to:
  /// **'High Mid'**
  String get gfpaEqHighMid;

  /// No description provided for @gfpaEqLM.
  ///
  /// In en, this message translates to:
  /// **'LM'**
  String get gfpaEqLM;

  /// No description provided for @gfpaEqLMHz.
  ///
  /// In en, this message translates to:
  /// **'LM Hz'**
  String get gfpaEqLMHz;

  /// No description provided for @gfpaEqLMQ.
  ///
  /// In en, this message translates to:
  /// **'LM Q'**
  String get gfpaEqLMQ;

  /// No description provided for @gfpaEqLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get gfpaEqLow;

  /// No description provided for @gfpaEqLowGain.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get gfpaEqLowGain;

  /// No description provided for @gfpaEqLowHz.
  ///
  /// In en, this message translates to:
  /// **'Low Hz'**
  String get gfpaEqLowHz;

  /// No description provided for @gfpaEqLowMid.
  ///
  /// In en, this message translates to:
  /// **'Low Mid'**
  String get gfpaEqLowMid;

  /// No description provided for @gfpaGateMaxNote.
  ///
  /// In en, this message translates to:
  /// **'Max Note'**
  String get gfpaGateMaxNote;

  /// No description provided for @gfpaGateMaxVel.
  ///
  /// In en, this message translates to:
  /// **'Max Vel'**
  String get gfpaGateMaxVel;

  /// No description provided for @gfpaGateMinNote.
  ///
  /// In en, this message translates to:
  /// **'Min Note'**
  String get gfpaGateMinNote;

  /// No description provided for @gfpaGateMinVel.
  ///
  /// In en, this message translates to:
  /// **'Min Vel'**
  String get gfpaGateMinVel;

  /// No description provided for @gfpaGatePitch.
  ///
  /// In en, this message translates to:
  /// **'Pitch'**
  String get gfpaGatePitch;

  /// No description provided for @gfpaLabelAttack.
  ///
  /// In en, this message translates to:
  /// **'Attack'**
  String get gfpaLabelAttack;

  /// No description provided for @gfpaLabelDelay.
  ///
  /// In en, this message translates to:
  /// **'Delay'**
  String get gfpaLabelDelay;

  /// No description provided for @gfpaLabelDepth.
  ///
  /// In en, this message translates to:
  /// **'Depth'**
  String get gfpaLabelDepth;

  /// No description provided for @gfpaLabelFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get gfpaLabelFeedback;

  /// No description provided for @gfpaLabelLevel.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get gfpaLabelLevel;

  /// No description provided for @gfpaLabelMix.
  ///
  /// In en, this message translates to:
  /// **'Mix'**
  String get gfpaLabelMix;

  /// No description provided for @gfpaLabelMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get gfpaLabelMode;

  /// No description provided for @gfpaLabelOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get gfpaLabelOutput;

  /// No description provided for @gfpaLabelRate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get gfpaLabelRate;

  /// No description provided for @gfpaLabelScale.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get gfpaLabelScale;

  /// No description provided for @gfpaLabelScaleLock.
  ///
  /// In en, this message translates to:
  /// **'Scale Lock'**
  String get gfpaLabelScaleLock;

  /// No description provided for @gfpaLabelSetup.
  ///
  /// In en, this message translates to:
  /// **'Setup'**
  String get gfpaLabelSetup;

  /// No description provided for @gfpaLabelTone.
  ///
  /// In en, this message translates to:
  /// **'Tone'**
  String get gfpaLabelTone;

  /// No description provided for @gfpaLabelType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get gfpaLabelType;

  /// No description provided for @gfpaLabelVelocity.
  ///
  /// In en, this message translates to:
  /// **'Velocity'**
  String get gfpaLabelVelocity;

  /// No description provided for @gfpaLabelVoices.
  ///
  /// In en, this message translates to:
  /// **'Voices'**
  String get gfpaLabelVoices;

  /// No description provided for @gfpaMicrotoneAverage.
  ///
  /// In en, this message translates to:
  /// **'Average'**
  String get gfpaMicrotoneAverage;

  /// No description provided for @gfpaMicrotoneBendRange.
  ///
  /// In en, this message translates to:
  /// **'Bend Range'**
  String get gfpaMicrotoneBendRange;

  /// No description provided for @gfpaMicrotoneCluster.
  ///
  /// In en, this message translates to:
  /// **'Cluster'**
  String get gfpaMicrotoneCluster;

  /// No description provided for @gfpaMicrotoneLastNote.
  ///
  /// In en, this message translates to:
  /// **'Last Note'**
  String get gfpaMicrotoneLastNote;

  /// No description provided for @gfpaMicrotoneMean.
  ///
  /// In en, this message translates to:
  /// **'Mean'**
  String get gfpaMicrotoneMean;

  /// No description provided for @gfpaMicrotoneOuterAvg.
  ///
  /// In en, this message translates to:
  /// **'Outer Avg'**
  String get gfpaMicrotoneOuterAvg;

  /// No description provided for @gfpaReverbDamp.
  ///
  /// In en, this message translates to:
  /// **'Damp'**
  String get gfpaReverbDamp;

  /// No description provided for @gfpaReverbRoom.
  ///
  /// In en, this message translates to:
  /// **'Room'**
  String get gfpaReverbRoom;

  /// No description provided for @gfpaReverbRoomSize.
  ///
  /// In en, this message translates to:
  /// **'Room'**
  String get gfpaReverbRoomSize;

  /// No description provided for @gfpaReverbWidth.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get gfpaReverbWidth;

  /// No description provided for @gfpaRiff2Oct.
  ///
  /// In en, this message translates to:
  /// **'2 Oct'**
  String get gfpaRiff2Oct;

  /// No description provided for @gfpaRiffBend.
  ///
  /// In en, this message translates to:
  /// **'Bend'**
  String get gfpaRiffBend;

  /// No description provided for @gfpaRiffBridge.
  ///
  /// In en, this message translates to:
  /// **'Bridge'**
  String get gfpaRiffBridge;

  /// No description provided for @gfpaRiffFrettingHand.
  ///
  /// In en, this message translates to:
  /// **'Fretting hand'**
  String get gfpaRiffFrettingHand;

  /// No description provided for @gfpaRiffHarmonic.
  ///
  /// In en, this message translates to:
  /// **'Harmonic'**
  String get gfpaRiffHarmonic;

  /// No description provided for @gfpaRiffHumbucker.
  ///
  /// In en, this message translates to:
  /// **'Humbucker'**
  String get gfpaRiffHumbucker;

  /// No description provided for @gfpaRiffLegato.
  ///
  /// In en, this message translates to:
  /// **'Legato'**
  String get gfpaRiffLegato;

  /// No description provided for @gfpaRiffMiddle.
  ///
  /// In en, this message translates to:
  /// **'Middle'**
  String get gfpaRiffMiddle;

  /// No description provided for @gfpaRiffNeck.
  ///
  /// In en, this message translates to:
  /// **'Neck'**
  String get gfpaRiffNeck;

  /// No description provided for @gfpaRiffNeckPlusBridge.
  ///
  /// In en, this message translates to:
  /// **'Neck+Bridge'**
  String get gfpaRiffNeckPlusBridge;

  /// No description provided for @gfpaRiffOctPlus5th.
  ///
  /// In en, this message translates to:
  /// **'Oct+5th'**
  String get gfpaRiffOctPlus5th;

  /// No description provided for @gfpaRiffOverlap.
  ///
  /// In en, this message translates to:
  /// **'Overlap'**
  String get gfpaRiffOverlap;

  /// No description provided for @gfpaRiffPalmMute.
  ///
  /// In en, this message translates to:
  /// **'Palm mute'**
  String get gfpaRiffPalmMute;

  /// No description provided for @gfpaRiffPedalSus.
  ///
  /// In en, this message translates to:
  /// **'Pedal sus.'**
  String get gfpaRiffPedalSus;

  /// No description provided for @gfpaRiffPickPos.
  ///
  /// In en, this message translates to:
  /// **'Pick pos.'**
  String get gfpaRiffPickPos;

  /// No description provided for @gfpaRiffPickingHand.
  ///
  /// In en, this message translates to:
  /// **'Picking hand'**
  String get gfpaRiffPickingHand;

  /// No description provided for @gfpaRiffPickup.
  ///
  /// In en, this message translates to:
  /// **'Pickup'**
  String get gfpaRiffPickup;

  /// No description provided for @gfpaRiffPickups.
  ///
  /// In en, this message translates to:
  /// **'Pickups'**
  String get gfpaRiffPickups;

  /// No description provided for @gfpaRiffRoot.
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get gfpaRiffRoot;

  /// No description provided for @gfpaRiffSingleCoil.
  ///
  /// In en, this message translates to:
  /// **'Single coil'**
  String get gfpaRiffSingleCoil;

  /// No description provided for @gfpaRiffStrings.
  ///
  /// In en, this message translates to:
  /// **'Strings'**
  String get gfpaRiffStrings;

  /// No description provided for @gfpaRiffSustain.
  ///
  /// In en, this message translates to:
  /// **'Sustain'**
  String get gfpaRiffSustain;

  /// No description provided for @gfpaTransposerPitchShift.
  ///
  /// In en, this message translates to:
  /// **'Pitch Shift'**
  String get gfpaTransposerPitchShift;

  /// No description provided for @gfpaTransposerSemitones.
  ///
  /// In en, this message translates to:
  /// **'Semitones'**
  String get gfpaTransposerSemitones;

  /// No description provided for @gfpaVelocityCurveAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get gfpaVelocityCurveAmount;

  /// No description provided for @gfpaVelocityCurveCurveType.
  ///
  /// In en, this message translates to:
  /// **'Curve Type'**
  String get gfpaVelocityCurveCurveType;

  /// No description provided for @gfpaVelocityCurveFixed.
  ///
  /// In en, this message translates to:
  /// **'Fixed'**
  String get gfpaVelocityCurveFixed;

  /// No description provided for @gfpaVelocityCurveIntensity.
  ///
  /// In en, this message translates to:
  /// **'Intensity'**
  String get gfpaVelocityCurveIntensity;

  /// No description provided for @gfpaVelocityCurvePower.
  ///
  /// In en, this message translates to:
  /// **'Power'**
  String get gfpaVelocityCurvePower;

  /// No description provided for @gfpaVelocityCurveSigmoid.
  ///
  /// In en, this message translates to:
  /// **'Sigmoid'**
  String get gfpaVelocityCurveSigmoid;

  /// No description provided for @gfpaWahAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get gfpaWahAuto;

  /// No description provided for @gfpaWahCenter.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get gfpaWahCenter;

  /// No description provided for @gfpaWahFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get gfpaWahFilter;

  /// No description provided for @gfpaWahManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get gfpaWahManual;

  /// No description provided for @gfpaWahPedal.
  ///
  /// In en, this message translates to:
  /// **'Pedal'**
  String get gfpaWahPedal;

  /// No description provided for @gfpaWahReso.
  ///
  /// In en, this message translates to:
  /// **'Reso'**
  String get gfpaWahReso;

  /// No description provided for @gfpaWahSaw.
  ///
  /// In en, this message translates to:
  /// **'Saw'**
  String get gfpaWahSaw;

  /// No description provided for @gfpaWahSine.
  ///
  /// In en, this message translates to:
  /// **'Sine'**
  String get gfpaWahSine;

  /// No description provided for @gfpaWahSweep.
  ///
  /// In en, this message translates to:
  /// **'Sweep'**
  String get gfpaWahSweep;

  /// No description provided for @gfpaWahWave.
  ///
  /// In en, this message translates to:
  /// **'Wave'**
  String get gfpaWahWave;

  /// No description provided for @scaleNameIonian.
  ///
  /// In en, this message translates to:
  /// **'Ionian'**
  String get scaleNameIonian;

  /// No description provided for @scaleNameDorian.
  ///
  /// In en, this message translates to:
  /// **'Dorian'**
  String get scaleNameDorian;

  /// No description provided for @scaleNamePhrygian.
  ///
  /// In en, this message translates to:
  /// **'Phrygian'**
  String get scaleNamePhrygian;

  /// No description provided for @scaleNameLydian.
  ///
  /// In en, this message translates to:
  /// **'Lydian'**
  String get scaleNameLydian;

  /// No description provided for @scaleNameMixolydian.
  ///
  /// In en, this message translates to:
  /// **'Mixolydian'**
  String get scaleNameMixolydian;

  /// No description provided for @scaleNameAeolian.
  ///
  /// In en, this message translates to:
  /// **'Aeolian'**
  String get scaleNameAeolian;

  /// No description provided for @scaleNameLocrian.
  ///
  /// In en, this message translates to:
  /// **'Locrian'**
  String get scaleNameLocrian;

  /// No description provided for @scaleNameLocrianSharp2.
  ///
  /// In en, this message translates to:
  /// **'Locrian #2'**
  String get scaleNameLocrianSharp2;

  /// No description provided for @scaleNameLydianDominant.
  ///
  /// In en, this message translates to:
  /// **'Lydian Dominant'**
  String get scaleNameLydianDominant;

  /// No description provided for @scaleNamePhrygianDominant.
  ///
  /// In en, this message translates to:
  /// **'Phrygian Dominant'**
  String get scaleNamePhrygianDominant;

  /// No description provided for @scaleNameAltered.
  ///
  /// In en, this message translates to:
  /// **'Altered Scale'**
  String get scaleNameAltered;

  /// No description provided for @scaleNameMajor.
  ///
  /// In en, this message translates to:
  /// **'Major'**
  String get scaleNameMajor;

  /// No description provided for @scaleNameNaturalMajor.
  ///
  /// In en, this message translates to:
  /// **'Natural Major'**
  String get scaleNameNaturalMajor;

  /// No description provided for @scaleNameHarmonicMinor.
  ///
  /// In en, this message translates to:
  /// **'Harmonic Minor'**
  String get scaleNameHarmonicMinor;

  /// No description provided for @scaleNameMelodicMinor.
  ///
  /// In en, this message translates to:
  /// **'Melodic Minor'**
  String get scaleNameMelodicMinor;

  /// No description provided for @scaleNameMajorPentatonic.
  ///
  /// In en, this message translates to:
  /// **'Major Pentatonic'**
  String get scaleNameMajorPentatonic;

  /// No description provided for @scaleNameMinorPentatonic.
  ///
  /// In en, this message translates to:
  /// **'Minor Pentatonic'**
  String get scaleNameMinorPentatonic;

  /// No description provided for @scaleNameMajorBlues.
  ///
  /// In en, this message translates to:
  /// **'Major Blues'**
  String get scaleNameMajorBlues;

  /// No description provided for @scaleNameMinorBlues.
  ///
  /// In en, this message translates to:
  /// **'Minor Blues'**
  String get scaleNameMinorBlues;

  /// No description provided for @scaleNameRockHexatonic.
  ///
  /// In en, this message translates to:
  /// **'Rock Hexatonic'**
  String get scaleNameRockHexatonic;

  /// No description provided for @scaleNameWholeTone.
  ///
  /// In en, this message translates to:
  /// **'Whole Tone'**
  String get scaleNameWholeTone;

  /// No description provided for @scaleNameDiminished.
  ///
  /// In en, this message translates to:
  /// **'Diminished'**
  String get scaleNameDiminished;

  /// No description provided for @scaleNameStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get scaleNameStandard;

  /// No description provided for @looperQuantizeOff.
  ///
  /// In en, this message translates to:
  /// **'off'**
  String get looperQuantizeOff;

  /// No description provided for @gfpdSilentEffect.
  ///
  /// In en, this message translates to:
  /// **'No sound: this plugin\'s graph could not be built, so it leaves the audio unchanged. Check its node types and connections against the plugin guide.'**
  String get gfpdSilentEffect;
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
