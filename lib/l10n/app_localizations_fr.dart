// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'GrooveForge Synth';

  @override
  String get loadingText => 'Initialisation du moteur de synthèse...';

  @override
  String get preferencesTitle => 'Préférences';

  @override
  String get midiConnectionSection => 'Connexion MIDI';

  @override
  String get connectMidiDevice => 'Connecter un appareil MIDI';

  @override
  String get notConnected => 'Non connecté';

  @override
  String get selectMidiDeviceDialogTitle => 'Sélectionner un appareil MIDI';

  @override
  String get soundfontsSection => 'Soundfonts';

  @override
  String get loadSoundfont => 'Charger une Soundfont (.sf2)';

  @override
  String get noSoundfontsLoaded => 'Aucune soundfont chargée.';

  @override
  String get defaultSoundfont => 'Soundfont par défaut';

  @override
  String get routingControlSection => 'Routage et Contrôle';

  @override
  String get ccMappingPreferences => 'Préférences de mapping CC';

  @override
  String get ccMappingPreferencesSubtitle =>
      'Associez les potards matériels aux effets GM et actions système';

  @override
  String get keyGesturesSection => 'Gestes sur les touches';

  @override
  String get verticalInteraction => 'Interaction verticale';

  @override
  String get verticalInteractionSubtitle =>
      'Glissez vers le haut/bas sur une touche';

  @override
  String get horizontalInteraction => 'Interaction horizontale';

  @override
  String get horizontalInteractionSubtitle =>
      'Glissez à gauche/droite sur une touche';

  @override
  String get actionSave => 'SAUVEGARDER';

  @override
  String chNumber(int channel) {
    return 'CH $channel';
  }

  @override
  String get patchLoadSoundfont => 'Charger une soundfont via les préférences';

  @override
  String get patchDefaultSoundfont => 'Soundfont par défaut';

  @override
  String patchUnknownProgram(int program) {
    return 'Programme inconnu $program';
  }

  @override
  String patchBank(int bank) {
    return 'Banque $bank';
  }

  @override
  String get jamStart => 'JAM';

  @override
  String get jamStop => 'STOP';

  @override
  String get jamMaster => 'Maître';

  @override
  String get jamSlaves => 'Esclaves';

  @override
  String get jamScale => 'Gamme';

  @override
  String get jamSelectSlavesDialogTitle => 'Sélectionner les canaux esclaves';

  @override
  String jamModeToast(String status) {
    return 'Mode Jam : $status';
  }

  @override
  String get jamStarted => 'DÉMARRÉ';

  @override
  String get jamStopped => 'ARRÊTÉ';

  @override
  String get ccTitle => 'Préférences de Mapping CC';

  @override
  String get ccActiveMappings => 'Mappings Actifs';

  @override
  String get ccAddMapping => 'Ajouter un Mapping';

  @override
  String get ccWaitingForEvents => 'En attente d\'événements MIDI...';

  @override
  String ccLastEventCC(int cc, int val) {
    return 'Dernier Événement : CC $cc (Valeur : $val)';
  }

  @override
  String ccLastEventNote(String type, int note, int velocity) {
    return 'Dernier Événement : Note $type $note (Vélocité : $velocity)';
  }

  @override
  String ccReceivedOnChannel(int channel) {
    return 'Reçu sur le Canal $channel';
  }

  @override
  String get ccInstructions =>
      'Bougez un fader ou jouez une note sur votre contrôleur MIDI pour identifier instantanément ses données internes ici.';

  @override
  String get ccNoMappings =>
      'Aucun mapping personnalisé défini.\nCliquez ci-dessous pour en ajouter un.';

  @override
  String ccUnknownSequence(int cc) {
    return 'CC $cc';
  }

  @override
  String get ccRoutingAllChannels => 'Tous les Canaux';

  @override
  String get ccRoutingSameAsIncoming => 'Même que le signal entrant';

  @override
  String ccRoutingChannel(int channel) {
    return 'Canal $channel';
  }

  @override
  String ccMappingHardwareToTarget(int incoming, String targetName) {
    return 'CC Matériel $incoming ➔ Mappé vers $targetName';
  }

  @override
  String ccMappingRouting(String channelStr) {
    return 'Routage : $channelStr';
  }

  @override
  String get ccNewMappingTitle => 'Nouveau Mapping CC';

  @override
  String get ccIncomingLabel => 'CC Matériel Entrant (ex: 20)';

  @override
  String get ccTargetEffectLabel => 'Effet GM Cible';

  @override
  String get ccTargetChannelLabel => 'Canal Cible';

  @override
  String get ccSaveBinding => 'Sauvegarder l\'Assignation';

  @override
  String ccTargetEffectFormat(String name, int cc) {
    return '$name (CC $cc)';
  }

  @override
  String get actionNone => 'Aucun';

  @override
  String get actionPitchBend => 'Pitch Bend';

  @override
  String get actionVibrato => 'Vibrato';

  @override
  String get actionGlissando => 'Glissando';

  @override
  String get virtualPianoDisplaySection => 'Affichage du Clavier Virtuel';

  @override
  String get visibleKeysTitle => 'Touches visibles (Zoom)';

  @override
  String get visibleKeysSubtitle => 'Nombre de touches blanches affichées';

  @override
  String get keys25 => '25 touches (15 blanches)';

  @override
  String get keys37 => '37 touches (22 blanches)';

  @override
  String get keys49 => '49 touches (29 blanches)';

  @override
  String get keys88 => '88 touches (52 blanches)';

  @override
  String get notationFormatTitle => 'Format de Notation Musicale';

  @override
  String get notationFormatSubtitle => 'Comment les accords sont affichés';

  @override
  String get notationStandard => 'Standard (C, D, E)';

  @override
  String get notationSolfege => 'Solfège (Do, Ré, Mi)';

  @override
  String get prefAboutMadeWith => 'Fait avec Flutter à Paris 🇫🇷';

  @override
  String get splashStartingEngine => 'Démarrage du moteur audio...';

  @override
  String get splashLoadingPreferences => 'Chargement des préférences...';

  @override
  String get splashStartingFluidSynth => 'Démarrage de FluidSynth...';

  @override
  String get splashRestoringState => 'Restauration de l\'état...';

  @override
  String get splashCheckingSoundfonts => 'Vérification des soundfonts...';

  @override
  String get splashExtractingSoundfont =>
      'Extraction de la soundfont par défaut...';

  @override
  String get splashReady => 'Prêt';

  @override
  String get synthVisibleChannelsTitle => 'Canaux Visibles';

  @override
  String synthChannelLabel(int channelIndex) {
    return 'Canal $channelIndex';
  }

  @override
  String get synthErrorAtLeastOneChannel =>
      'Au moins un canal doit être visible';

  @override
  String get synthSaveFilters => 'Sauvegarder les Filtres';

  @override
  String get synthTooltipUserGuide => 'Guide d\'Utilisateur';

  @override
  String get synthTooltipFilterChannels => 'Filtrer les Canaux Visibles';

  @override
  String get synthTooltipSettings => 'Paramètres & Configuration';

  @override
  String get actionCancel => 'Annuler';

  @override
  String get scaleLockModeTitle => 'Mode Scale Lock';

  @override
  String get scaleLockModeSubtitle =>
      'Classique (par canal) vs Jam (maître-esclave)';

  @override
  String get modeClassic => 'Mode Classique';

  @override
  String get modeJam => 'Mode Jam';

  @override
  String get jamModeKeyGroupsTitle => 'Groupes de touches Mode Jam';

  @override
  String get jamModeKeyGroupsSubtitle =>
      'Regrouper visuellement les touches mappées (bordures)';

  @override
  String get highlightWrongNotesTitle => 'Griser les fausses notes';

  @override
  String get highlightWrongNotesSubtitle =>
      'Colorer les touches hors-gamme en rouge';

  @override
  String get aftertouchEffectTitle => 'Effet Aftertouch';

  @override
  String get aftertouchEffectSubtitle =>
      'Router la pression du clavier vers ce CC';

  @override
  String get aboutSection => 'À propos';

  @override
  String get versionTitle => 'Version';

  @override
  String get viewChangelogTitle => 'Voir le Changelog';

  @override
  String get viewChangelogSubtitle => 'Historique des modifications';

  @override
  String get changelogDialogTitle => 'Changelog';

  @override
  String get closeButton => 'Fermer';

  @override
  String get errorLoadingChangelog => 'Erreur lors du chargement du changelog.';

  @override
  String get resetPreferencesButton => 'Réinitialiser toutes les préférences';

  @override
  String get resetPreferencesDialogTitle => 'Tout réinitialiser ?';

  @override
  String get resetPreferencesDialogBody =>
      'Cela effacera tous vos réglages, soundfonts chargées et assignations personnalisées. Action irréversible.';

  @override
  String get cancelButton => 'Annuler';

  @override
  String get resetEverythingButton => 'Tout réinitialiser';

  @override
  String get languageTitle => 'Langue';

  @override
  String get languageSubtitle => 'Langue de l\'interface';

  @override
  String get languageSystem => 'Système (défaut)';

  @override
  String get languageEnglish => 'Anglais';

  @override
  String get languageFrench => 'Français';
}
