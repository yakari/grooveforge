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
