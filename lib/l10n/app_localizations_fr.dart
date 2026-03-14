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
  String get midiNewDeviceDetected => 'Nouvel appareil MIDI détecté';

  @override
  String midiConnectNewDevicePrompt(String deviceName) {
    return 'Connecter à $deviceName ?';
  }

  @override
  String get actionConnect => 'Connecter';

  @override
  String get actionIgnore => 'Ignorer';

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
  String get actionDone => 'Terminé';

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
  String get ccMuteChannelsLabel => 'Canaux à couper/rétablir';

  @override
  String ccMuteChannelsSummary(String channels) {
    return 'Canaux : $channels';
  }

  @override
  String get ccMuteNoChannels => 'Aucun canal sélectionné';

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
  String get synthTooltipUserGuide => 'Guide d\'Utilisateur';

  @override
  String get synthTooltipSettings => 'Paramètres & Configuration';

  @override
  String get actionCancel => 'Annuler';

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

  @override
  String get guideTitle => 'Guide de l\'utilisateur';

  @override
  String get guideTabFeatures => 'Fonctionnalités';

  @override
  String get guideTabMidi => 'Connectivité MIDI';

  @override
  String get guideTabSoundfonts => 'Soundfonts';

  @override
  String get guideTabTips => 'Conseils musicaux';

  @override
  String get guideTabPatch => 'Rack & Câbles';

  @override
  String get guidePatchRackTitle => 'Le Rack';

  @override
  String get guidePatchRackBody =>
      'Le rack est le cœur de GrooveForge. Chaque ligne est un slot — un instrument ou processeur d\'effets indépendant. Ajoutez des slots avec le bouton +, supprimez-les avec l\'icône corbeille, et réordonnez-les en faisant glisser la poignée à gauche de chaque slot.';

  @override
  String get guidePatchSlotTypesTitle => 'Types de slots';

  @override
  String get guidePatchSlotKeyboard => 'Clavier';

  @override
  String get guidePatchSlotKeyboardDesc =>
      'Synthétiseur intégré piloté par une soundfont (.sf2). Jouez via le clavier à l\'écran ou un contrôleur MIDI externe.';

  @override
  String get guidePatchSlotVocoder => 'Vocodeur';

  @override
  String get guidePatchSlotVocoderDesc =>
      'Traite l\'audio du microphone à travers une onde porteuse pour des effets de voix synthétique.';

  @override
  String get guidePatchSlotJam => 'Mode Jam';

  @override
  String get guidePatchSlotJamDesc =>
      'Moteur d\'harmonie qui quantifie les notes MIDI entrantes sur une gamme en temps réel. Reçoit les informations d\'accord d\'un slot clavier maître.';

  @override
  String get guidePatchSlotVirtualPiano => 'Contrôleur MIDI Virtuel';

  @override
  String get guidePatchSlotVirtualPianoDesc =>
      'Source MIDI légère : achemine la saisie tactile de l\'écran dans la chaîne de signal sans produire d\'audio propre.';

  @override
  String get guidePatchSlotVst3 => 'Plugin VST3';

  @override
  String get guidePatchSlotVst3Desc =>
      'Chargez n\'importe quel instrument ou effet VST3 tiers. Nécessite un bundle .vst3 compatible installé sur votre système.';

  @override
  String get guidePatchSlotVst3DesktopOnly =>
      'Les slots VST3 sont disponibles uniquement sur les plateformes desktop (Linux, macOS, Windows). Ils ne sont pas disponibles sur Android ou iOS.';

  @override
  String get guidePatchTitle => 'Câblage';

  @override
  String get guidePatchIntro =>
      'La vue de câblage vous permet de voir le panneau arrière de chaque slot de votre rack et de tracer des câbles virtuels entre les jacks, comme sur un vrai rack matériel. Appuyez sur l\'icône câble dans la barre d\'outils pour basculer entre la vue avant (jeu) et la vue arrière (câblage).';

  @override
  String get guidePatchToggleTitle => 'Basculer la vue de câblage';

  @override
  String get guidePatchToggleBody =>
      'Appuyez sur l\'icône câble (⊡) en haut à droite de l\'écran rack pour passer à la vue panneau arrière. Appuyez à nouveau (ou sur l\'icône agenda) pour revenir à la vue avant. Le réordonnancement des slots est désactivé en vue de câblage.';

  @override
  String get guidePatchJacksTitle => 'Types de jacks';

  @override
  String get guidePatchJacksBody =>
      'Chaque slot expose un ensemble de jacks regroupés par famille de signal :\n• MIDI (jaune) — MIDI IN / MIDI OUT pour les notes et messages CC.\n• Audio (rouge / blanc / orange) — AUDIO IN L, AUDIO IN R, AUDIO OUT L, AUDIO OUT R pour l\'audio stéréo ; SEND / RETURN pour les boucles d\'effets.\n• Data (violet) — CHORD OUT/IN et SCALE OUT/IN pour le routage de l\'harmonie du Mode Jam.';

  @override
  String get guidePatchDrawTitle => 'Tracer un câble';

  @override
  String get guidePatchDrawBody =>
      'Appuyez longuement sur un jack de sortie (●) pour commencer à faire glisser un câble. Les jacks d\'entrée compatibles clignotent pour indiquer les cibles valides. Faites glisser vers un jack d\'entrée compatible et relâchez pour connecter. Relâcher dans l\'espace vide annule le glisser.\n\nPaires compatibles : MIDI OUT → MIDI IN, AUDIO OUT L → AUDIO IN L, AUDIO OUT R → AUDIO IN R, SEND → RETURN, CHORD OUT → CHORD IN, SCALE OUT → SCALE IN.';

  @override
  String get guidePatchDisconnectTitle => 'Déconnecter un câble';

  @override
  String get guidePatchDisconnectBody =>
      'Chaque câble affiche un petit badge ✕ en son milieu. Appuyez sur le badge pour ouvrir le menu Déconnecter. Le badge est aussi la zone de clic du câble — visez le cercle avec l\'anneau coloré.';

  @override
  String get guidePatchDataTitle => 'Câbles Data (Mode Jam)';

  @override
  String get guidePatchDataBody =>
      'Les câbles data violets représentent le flux d\'harmonie du Mode Jam entre les slots. Tracer un câble CHORD OUT → CHORD IN revient à sélectionner un master Mode Jam dans le menu déroulant — les deux contrôles restent synchronisés. De même, un câble SCALE OUT → SCALE IN correspond à un slot follower.';

  @override
  String get guidePatchTip =>
      'Conseil : Les câbles sont sauvegardés dans votre projet (.gf). Ouvrez un projet sauvegardé pour restaurer toutes les connexions telles que vous les avez laissées.';

  @override
  String get guideJamModeTitle => 'Mode Jam (Auto-Harmonie)';

  @override
  String get guideJamModeBody =>
      'Le Mode Jam vous permet de jouer sans fausse note en verrouillant toutes les touches sur une gamme spécifique. Un canal fait office de \'Master\' (transmettant sa gamme) tandis que les autres sont des \'Slaves\'. Utilisez les contrôles supérieurs pour définir la tonique et le type de gamme.';

  @override
  String get guideVocoderTitle => 'Vocodeur (Synthé Vocal)';

  @override
  String get guideVocoderBody =>
      'Le vocodeur utilise le micro pour moduler le son du synthé. Accédez-y via le preset \'VOCODER\' dans le sélecteur de patchs. Pour de meilleurs résultats :\n• Utilisez un casque ou des enceintes filaires (la latence Bluetooth est trop élevée).\n• Réglez les niveaux avec les boutons de gain.\n• Limitation Android : Vous ne pouvez pas utiliser deux périphériques USB séparés pour l\'entrée et la sortie. Utilisez un seul hub USB ou le micro interne.\n• Expérimentez avec les différentes ondes porteuses (Saw, Pulse, Neutral).';

  @override
  String get guideMidiTitle => 'Connectivité MIDI';

  @override
  String get guideMidiBody =>
      'Connectez vos contrôleurs via USB (adaptateur OTG) ou BLE MIDI. Activez le mappage CC dans les préférences pour lier vos boutons physiques aux effets ou aux actions système comme \'Patch Suivant\'.';

  @override
  String get guideMidiBestPracticeTitle => 'Recommandations Matérielles';

  @override
  String get guideMidiBestPracticeBody =>
      'Pour une expérience optimale, nous recommandons l\'utilisation d\'un clavier MIDI split ou de deux claviers :\n• Canal 2 (Main Gauche) : Envoyez les notes ici pour contrôler les accords et l\'harmonie (Master).\n• Canal 1 (Main Droite) : Utilisez ce canal pour improviser sur l\'harmonie générée avec la gamme actuelle.';

  @override
  String get guideSoundfontsTitle => 'Soundfonts (SF2)';

  @override
  String get guideSoundfontsBody =>
      'Importez des sons d\'instruments de haute qualité (.sf2) dans les préférences. Une fois chargés, vous pouvez les assigner à n\'importe quel canal MIDI via le sélecteur de patch.';

  @override
  String get guideTipsTitle => 'Conseils & Improvisation';

  @override
  String get guideTipsBody =>
      'Nouveau en improvisation ? Essayez ces conseils :\n• Gamme = Zone Sûre : Chaque touche de la gamme sélectionnée sonnera \'juste\'.\n• La Tonique : Commencez ou terminez vos phrases sur la tonique (mise en évidence) pour créer une résolution.\n• Rythme d\'abord : Concentrez-vous sur des motifs rythmiques simples plutôt que des mélodies complexes.';

  @override
  String get guideScalesTitle => 'Gammes disponibles';

  @override
  String guideWelcomeHeader(String version) {
    return 'Bienvenue dans GrooveForge v$version';
  }

  @override
  String get guideWelcomeIntro =>
      'Cette mise à jour apporte des améliorations significatives à votre flux de travail et à vos outils créatifs :';

  @override
  String get guideChangelogExpand => 'Voir les nouveautés de cette version';

  @override
  String get guideMidiHardware => '1. Connexion Matérielle';

  @override
  String get guideMidiHardwareStep1 =>
      'Connectez le contrôleur via USB (OTG) ou allumez l\'appareil BLE.';

  @override
  String get guideMidiHardwareStep2 =>
      'Allez dans Paramètres > Entrée MIDI et sélectionnez votre appareil.';

  @override
  String get guideMidiCcMappings => '2. Assignations CC & Système';

  @override
  String get guideMidiCcMappingsBody =>
      'Liez les boutons à des effets comme le Volume ou des Actions Système :';

  @override
  String get guideMidiFeaturePatch => 'Patch Suivant/Précédent';

  @override
  String get guideMidiFeaturePatchDesc => 'Changez d\'instrument rapidement.';

  @override
  String get guideMidiFeatureScales => 'Cycle de Gammes';

  @override
  String get guideMidiFeatureScalesDesc => 'Changez l\'harmonie à la volée.';

  @override
  String get guideMidiFeatureJam => 'Bascule Mode Jam';

  @override
  String get guideMidiFeatureJamDesc => 'Forcez les esclaves à vous suivre.';

  @override
  String get guideMidiTipSplit =>
      'Conseil : La plupart des contrôleurs MIDI modernes permettent de diviser les touches en zones/canaux distincts.';

  @override
  String get guideAndroidUsbLimitation =>
      'Important : Sur Android, l\'utilisation d\'un hub USB avec des périphériques d\'entrée et de sortie séparés peut être instable. Utilisez une interface audio USB intégrée pour de meilleurs résultats.';

  @override
  String get micSelectionTitle => 'Entrée Audio';

  @override
  String get micSelectionDevice => 'Microphone';

  @override
  String get micSelectionSensitivity => 'Sensibilité';

  @override
  String get micSelectionDefault => 'Système (défaut)';

  @override
  String get audioOutputTitle => 'Sortie Audio';

  @override
  String get audioOutputDevice => 'Appareil de sortie';

  @override
  String get audioOutputDefault => 'Système (défaut)';

  @override
  String get audioSettingsBarGain => 'Volume';

  @override
  String get audioSettingsBarMicSensitivity => 'Micro';

  @override
  String get audioSettingsBarMicDevice => 'Entrée';

  @override
  String get audioSettingsBarOutputDevice => 'Sortie';

  @override
  String get audioSettingsBarToggleTooltip =>
      'Afficher/masquer la barre de réglages audio';

  @override
  String get synthAutoScrollTitle => 'Auto-scroll vers le canal actif';

  @override
  String get synthAutoScrollSubtitle =>
      'Défiler automatiquement la liste lors de la réception MIDI';

  @override
  String get rackTitle => 'Rack';

  @override
  String get rackAddPlugin => 'Ajouter un plugin';

  @override
  String get rackAddGrooveForgeKeyboard => 'GrooveForge Keyboard';

  @override
  String get rackAddGrooveForgeKeyboardSubtitle => 'Clavier FluidSynth intégré';

  @override
  String get rackAddVocoder => 'Vocodeur';

  @override
  String get rackAddVocoderSubtitle => 'Synthèse vocale par microphone (GFPA)';

  @override
  String get rackAddJamMode => 'Mode Jam';

  @override
  String get rackAddJamModeSubtitle =>
      'Verrouille la gamme d\'un clavier sur l\'harmonie d\'un autre';

  @override
  String get rackAddVst3 => 'Parcourir les plugins VST3…';

  @override
  String get rackAddVst3Subtitle => 'Charger un fichier .vst3 depuis le disque';

  @override
  String get rackRemovePlugin => 'Supprimer le plugin';

  @override
  String get rackRemovePluginConfirm =>
      'Supprimer ce slot ? Les réglages non sauvegardés seront perdus.';

  @override
  String get rackRemove => 'Supprimer';

  @override
  String get rackPluginUnavailableOnMobile =>
      'Ce plugin VST3 n\'est pas disponible sur mobile.';

  @override
  String get rackMidiChannel => 'CANAL MIDI';

  @override
  String get rackOpenProject => 'Projets';

  @override
  String get rackSaveProject => 'Enregistrer';

  @override
  String get rackSaveProjectAs => 'Enregistrer sous…';

  @override
  String get rackNewProject => 'Nouveau projet';

  @override
  String get rackNewProjectConfirm =>
      'Créer un nouveau projet ? Les changements non sauvegardés seront perdus.';

  @override
  String get rackNewProjectButton => 'Nouveau projet';

  @override
  String get rackProjectSaved => 'Projet enregistré.';

  @override
  String get rackProjectOpened => 'Projet ouvert.';

  @override
  String get rackAutosaveRestored => 'Session restaurée.';

  @override
  String get splashRestoringRack => 'Restauration du rack...';

  @override
  String get vst3LoadFailed =>
      'Échec du chargement du plugin VST3. Assurez-vous d\'avoir sélectionné le dossier .vst3.';

  @override
  String get vst3NotLoaded => 'Plugin pas encore chargé.';

  @override
  String get vst3NotABundle =>
      'Le dossier sélectionné n\'est pas un bundle .vst3. Sélectionnez un dossier se terminant par .vst3.';

  @override
  String get vst3BrowseTitle => 'Parcourir un dossier .vst3…';

  @override
  String get vst3BrowseSubtitle =>
      'Sélectionner un répertoire bundle .vst3 depuis votre système de fichiers.';

  @override
  String get vst3PickInstalledTitle => 'Choisir parmi les plugins installés';

  @override
  String get vst3PickInstalledSubtitle =>
      'Choisissez parmi les plugins trouvés dans les chemins système par défaut.';

  @override
  String get vst3ScanTitle => 'Scanner les plugins VST3';

  @override
  String get vst3ScanSubtitle =>
      'Rechercher les plugins .vst3 installés dans les chemins système par défaut.';

  @override
  String get vst3Scanning => 'Analyse en cours…';

  @override
  String vst3ScanFound(int count) {
    return '$count plugin(s) trouvé(s).';
  }

  @override
  String get vst3ScanNoneFound =>
      'Aucun plugin .vst3 trouvé dans les chemins par défaut.';

  @override
  String vst3ScanError(String error) {
    return 'Échec de l\'analyse : $error';
  }

  @override
  String get transportBpm => 'BPM';

  @override
  String get transportTapTempo => 'Tap';

  @override
  String get transportPlay => 'Lecture';

  @override
  String get transportStop => 'Stop';

  @override
  String get transportTimeSignature => 'Métrique';

  @override
  String get transportMetronome => 'Métronome';

  @override
  String get transportTimeSigCustom => 'Personnalisé';

  @override
  String get transportTimeSigNumerator => 'Temps / mesure';

  @override
  String get transportTimeSigDenominator => 'Unité de temps';

  @override
  String get patchViewToggleTooltip => 'Vue de câblage';

  @override
  String get patchViewFrontButton => 'FACE';

  @override
  String get disconnectCable => 'Déconnecter';

  @override
  String get cableColour => 'Couleur du câble';

  @override
  String get connectionCycleError =>
      'Cycle détecté : cette connexion créerait une boucle de rétroaction';

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
  String get portChordOut => 'ACCORD OUT';

  @override
  String get portChordIn => 'ACCORD IN';

  @override
  String get portScaleOut => 'GAMME OUT';

  @override
  String get portScaleIn => 'GAMME IN';

  @override
  String get virtualPianoSlotName => 'Contrôleur MIDI Virtuel';

  @override
  String get addVirtualPiano => 'Contrôleur MIDI Virtuel';

  @override
  String get rackAddVirtualPianoSubtitle =>
      'Source MIDI autonome pour le câblage';

  @override
  String get virtualPianoSlotHint =>
      'Les notes passent par MIDI OUT — connectez un câble en vue de câblage.';

  @override
  String get looperSlotName => 'Looper MIDI';

  @override
  String get addLooper => 'Looper MIDI';

  @override
  String get addLooperSubtitle =>
      'Enregistrez et bouclez des séquences MIDI avec synchro de mesure';

  @override
  String get addLooperAlreadyExists =>
      'Un Looper MIDI est déjà dans le rack. Un seul est autorisé.';

  @override
  String get addJamModeAlreadyExists =>
      'Un Jam Mode est déjà dans le rack. Un seul est autorisé.';

  @override
  String get looperRecord => 'Enregistrer';

  @override
  String get looperPlay => 'Lecture';

  @override
  String get looperStop => 'Stop';

  @override
  String get looperClear => 'Effacer';

  @override
  String get looperOverdub => 'Overdub';

  @override
  String get looperArmed => 'Armé — en attente du transport';

  @override
  String get looperWaitingForBar => 'En attente de la mesure';

  @override
  String get looperWaitingForOverdub => 'En attente de l\'overdub';

  @override
  String looperTrack(int n) {
    return 'Piste $n';
  }

  @override
  String get looperPinBelow => 'Épingler sous le transport';

  @override
  String get jamModePinBelow => 'Épingler sous le transport';

  @override
  String get looperHalfSpeed => '½×';

  @override
  String get looperNormalSpeed => '1×';

  @override
  String get looperDoubleSpeed => '2×';

  @override
  String get looperReverse => 'Inverser';

  @override
  String get looperMute => 'Muet';

  @override
  String get looperNoChord => '—';

  @override
  String looperBar(int n) {
    return 'Mesure $n';
  }

  @override
  String get looperCcAssign => 'Assigner CC';

  @override
  String get looperCcAssignTitle =>
      'Assigner un CC matériel à une action du looper';

  @override
  String get looperCcRemove => 'Supprimer l\'assignation CC';

  @override
  String get looperQuantize => 'Quantification';
}
