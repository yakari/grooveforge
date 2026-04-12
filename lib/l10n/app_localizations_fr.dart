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
  String get verticalInteraction => 'Interaction verticale (défaut)';

  @override
  String get verticalInteractionSubtitle =>
      'Glissez vers le haut/bas sur une touche — modifiable par slot';

  @override
  String get horizontalInteraction => 'Interaction horizontale (défaut)';

  @override
  String get horizontalInteractionSubtitle =>
      'Glissez à gauche/droite sur une touche — modifiable par slot';

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
  String get patchSoundfontNoneMidiOnly => 'Aucune (MIDI seulement)';

  @override
  String get rackSlotKeyboardMidiOnlyShort => 'MIDI seul';

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
  String get visibleKeysTitle => 'Nombre de touches (défaut)';

  @override
  String get visibleKeysSubtitle =>
      'Touches blanches affichées sans override par slot';

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
  String get aftertouchEffectTitle => 'Effet Aftertouch (défaut)';

  @override
  String get aftertouchEffectSubtitle =>
      'Router la pression du clavier vers ce CC — modifiable par slot';

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
  String get confirmButton => 'OK';

  @override
  String get selectFile => 'Sélectionner un fichier';

  @override
  String get selectDirectory => 'Sélectionner un dossier';

  @override
  String get filePickerAllowedTypes => 'Types autorisés';

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
      'FluidSynth intégré avec soundfont (.sf2). Jouez au clavier à l\'écran ou en MIDI externe. Choisissez Aucune comme soundfont pour un contrôleur MIDI uniquement (câbles MIDI OUT, sans synthé intégré).';

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
  String get rackAddGrooveForgeKeyboardSubtitle =>
      'Synthé soundfont ou MIDI seul (Aucune) pour le câblage';

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
  String get rackMenuProject => 'Projets';

  @override
  String get rackOpenProject => 'Ouvrir un projet';

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
  String get vst3EditorOpenFailed =>
      'Impossible d\'ouvrir l\'éditeur du plugin. Si le plugin utilise OpenGL, lancez GrooveForge avec LIBGL_ALWAYS_SOFTWARE=1 ou en session X11 pure (désactivez WAYLAND_DISPLAY).';

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
  String get looperSlotName => 'Looper MIDI';

  @override
  String get addLooper => 'Looper MIDI';

  @override
  String get addLooperSubtitle =>
      'Enregistrez et bouclez des séquences MIDI avec synchro de mesure';

  @override
  String get rackAddAudioLooper => 'Looper Audio';

  @override
  String get rackAddAudioLooperSubtitle =>
      'Enregistrez et bouclez de l\'audio en temps réel (PCM) avec synchro, overdub et reverse';

  @override
  String get audioLooperWaveformRecording => 'Enregistrement…';

  @override
  String get audioLooperWaveformCableInstrument =>
      'Câblez un instrument sur Audio IN';

  @override
  String get audioLooperWaveformEmpty => 'Aucun audio enregistré';

  @override
  String get audioLooperTooltipStop => 'Stop';

  @override
  String get audioLooperTooltipReverse => 'Inverser';

  @override
  String get audioLooperTooltipBarSyncOn => 'Synchro mesure : ON';

  @override
  String get audioLooperTooltipBarSyncOff => 'Synchro mesure : OFF';

  @override
  String get audioLooperTooltipClear => 'Effacer';

  @override
  String get audioLooperTooltipRecord => 'Enregistrer';

  @override
  String get audioLooperTooltipPlay => 'Lecture';

  @override
  String get audioLooperTooltipCancel => 'Annuler';

  @override
  String get audioLooperTooltipStopRecordingAndPlay =>
      'Arrêter l\'enregistrement & lire';

  @override
  String get audioLooperTooltipPaddingToBar => 'Complément jusqu\'à la mesure…';

  @override
  String get audioLooperTooltipOverdub => 'Overdub';

  @override
  String get audioLooperTooltipStopOverdub => 'Arrêter l\'overdub';

  @override
  String get audioLooperStatusIdle => 'VIDE';

  @override
  String get audioLooperStatusArmed => 'ARMÉ';

  @override
  String get audioLooperStatusRecording => 'REC';

  @override
  String get audioLooperStatusPlaying => 'LECT';

  @override
  String get audioLooperStatusOverdubbing => 'ODUB';

  @override
  String get audioLooperStatusStopping => 'PAD';

  @override
  String get audioLooperSourceLabel => 'Source';

  @override
  String get audioLooperSourceTooltip =>
      'Choisissez quel instrument alimente ce looper';

  @override
  String get audioLooperSourceNone => 'Aucune';

  @override
  String get audioLooperSourceUnknown => 'Source inconnue';

  @override
  String audioLooperSourceMultiple(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Multiples ($count sources)',
      two: 'Multiples (2 sources)',
    );
    return '$_temp0';
  }

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
  String looperBar(int n) {
    return 'Mesure $n';
  }

  @override
  String get looperCcAssign => 'Assigner CC';

  @override
  String get looperCcAssignTitle => 'Assigner un CC matériel au looper';

  @override
  String get looperCcRemove => 'Supprimer l\'assignation CC';

  @override
  String get looperCcLearn => 'Bougez un potard ou fader…';

  @override
  String get looperActionLoop => 'Boucle';

  @override
  String get looperActionStop => 'Stop';

  @override
  String get looperCcConflictTitle => 'CC déjà assigné';

  @override
  String looperCcConflictBody(int cc, String target) {
    return 'CC $cc est déjà assigné à $target. Écraser ?';
  }

  @override
  String get looperCcConflictOverwrite => 'Écraser';

  @override
  String get looperVolume => 'Volume';

  @override
  String get looperQuantize => 'Quantification';

  @override
  String get kbConfigTitle => 'Config. clavier';

  @override
  String kbConfigDefault(String value) {
    return 'Défaut ($value)';
  }

  @override
  String get kbConfigKeysToShow => 'Touches à afficher';

  @override
  String get kbConfigKeysToShowSubtitle =>
      'Nombre de touches visibles (remplace le défaut)';

  @override
  String kbConfigKeysDefault(int count) {
    return 'Défaut ($count touches)';
  }

  @override
  String get kbConfigKeyHeight => 'Hauteur des touches';

  @override
  String get kbConfigKeyHeightSubtitle =>
      'Des touches plus hautes facilitent le jeu sur téléphone';

  @override
  String get kbConfigVertGesture => 'Geste vertical';

  @override
  String get kbConfigVertGestureSubtitle =>
      'Glissez vers le haut/bas sur une touche';

  @override
  String get kbConfigHorizGesture => 'Geste horizontal';

  @override
  String get kbConfigHorizGestureSubtitle =>
      'Glissez à gauche/droite sur les touches';

  @override
  String get kbConfigAftertouch => 'CC Aftertouch';

  @override
  String get kbConfigAftertouchSubtitle =>
      'La pression verticale est routée vers ce CC';

  @override
  String get kbConfigResetDefaults => 'Réinitialiser';

  @override
  String get keyHeightSmall => 'Petit';

  @override
  String get keyHeightNormal => 'Normal';

  @override
  String get keyHeightLarge => 'Grand';

  @override
  String get keyHeightExtraLarge => 'Très grand';

  @override
  String get rackAddStylophone => 'Stylophone';

  @override
  String get rackAddStyloPhoneSubtitle =>
      'Instrument monophonique à lamelles métalliques (GFPA)';

  @override
  String get rackAddTheremin => 'Thérémine';

  @override
  String get rackAddThereminSubtitle =>
      'Pad tactile — hauteur verticale, volume horizontal (GFPA)';

  @override
  String get thereminModePad => 'PAD';

  @override
  String get thereminModeCam => 'CAM';

  @override
  String get thereminCamHint =>
      'Rapprochez ou éloignez votre main de la caméra pour jouer';

  @override
  String get thereminCamErrUnsupported =>
      'Le mode caméra n\'est pas disponible sur cette plateforme.';

  @override
  String get thereminCamErrNoPermission =>
      'Permission caméra refusée. Repassez en mode PAD pour réessayer.';

  @override
  String get thereminCamErrNoCamera =>
      'Aucune caméra compatible trouvée sur cet appareil.';

  @override
  String get thereminCamErrFixedFocus =>
      'Cette caméra a une mise au point fixe — le suivi de la main n\'est pas disponible.';

  @override
  String get thereminCamErrConfigError =>
      'Erreur de configuration caméra. Veuillez passer en mode PAD.';

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
  String get thereminPadHeight => 'HAUTEUR';

  @override
  String get midiMuteOwnSound => 'MUTE';

  @override
  String get vst3BrowseInstrumentTitle => 'Parcourir un instrument VST3…';

  @override
  String get vst3BrowseInstrumentSubtitle =>
      'Charger un synthétiseur ou un échantillonneur (.vst3)';

  @override
  String get vst3BrowseEffectTitle => 'Parcourir un effet VST3…';

  @override
  String get vst3BrowseEffectSubtitle =>
      'Charger un plugin d\'effet audio (.vst3)';

  @override
  String get vst3PickInstalledInstrumentTitle =>
      'Choisir un instrument installé';

  @override
  String get vst3PickInstalledEffectTitle => 'Choisir un effet installé';

  @override
  String get vst3EffectTypeReverb => 'Réverbération';

  @override
  String get vst3EffectTypeCompressor => 'Compresseur';

  @override
  String get vst3EffectTypeEq => 'EQ';

  @override
  String get vst3EffectTypeDelay => 'Delay';

  @override
  String get vst3EffectTypeModulation => 'Modulation';

  @override
  String get vst3EffectTypeDistortion => 'Distorsion';

  @override
  String get vst3EffectTypeDynamics => 'Dynamique';

  @override
  String get vst3EffectTypeFx => 'FX';

  @override
  String get vst3FxInserts => 'FX';

  @override
  String get vst3FxAddEffect => 'Ajouter un effet';

  @override
  String get vst3FxNoEffects => 'Aucun effet — connecter via la vue patch';

  @override
  String get rackAddEffectsSectionLabel => 'Effets intégrés';

  @override
  String get rackAddVstSectionLabel => 'Plugins VST3';

  @override
  String get rackAddReverb => 'Réverb à plaque';

  @override
  String get rackAddReverbSubtitle => 'Réverbération stéréo riche';

  @override
  String get rackAddDelay => 'Delay Ping-Pong';

  @override
  String get rackAddDelaySubtitle => 'Delay stéréo synchronisable sur le BPM';

  @override
  String get rackAddWah => 'Auto-Wah';

  @override
  String get rackAddWahSubtitle => 'Filtre wah enveloppe / LFO avec sync BPM';

  @override
  String get rackAddEq => 'EQ 4 bandes';

  @override
  String get rackAddEqSubtitle =>
      'Filtre passe-bas en plateau, 2× crête, passe-haut en plateau';

  @override
  String get rackAddCompressor => 'Compresseur';

  @override
  String get rackAddCompressorSubtitle => 'Compresseur RMS à genou doux';

  @override
  String get rackAddChorus => 'Chorus / Flanger';

  @override
  String get rackAddChorusSubtitle => 'Chorus stéréo synchronisable sur le BPM';

  @override
  String get rackAddLoadGfpd => 'Charger un fichier .gfpd…';

  @override
  String get rackAddLoadGfpdSubtitle =>
      'Importer un descripteur de plugin GrooveForge personnalisé';

  @override
  String get rackAddMidiFxSectionLabel => 'Effets MIDI intégrés';

  @override
  String get rackAddHarmonizer => 'Harmoniseur';

  @override
  String get rackAddHarmonizerSubtitle =>
      'Ajoute des voix harmoniques à toute entrée MIDI (effet MIDI)';

  @override
  String get rackAddChordExpand => 'Chord Expand';

  @override
  String get rackAddChordExpandSubtitle =>
      'Développe chaque note en un accord complet (effet MIDI)';

  @override
  String get rackAddArpeggiator => 'Arpégiateur';

  @override
  String get rackAddArpeggiatorSubtitle =>
      'Arpège les notes maintenues en séquence rythmique (effet MIDI)';

  @override
  String get rackAddTransposer => 'Transposeur';

  @override
  String get rackAddTransposerSubtitle =>
      'Décale toutes les notes de ±24 demi-tons (effet MIDI)';

  @override
  String get rackAddVelocityCurve => 'Courbe de vélocité';

  @override
  String get rackAddVelocityCurveSubtitle =>
      'Remappage de vélocité via courbe en puissance, sigmoïde ou valeur fixe (effet MIDI)';

  @override
  String get rackAddGate => 'Gate';

  @override
  String get rackAddGateSubtitle =>
      'Filtre les notes par plage de vélocité et de hauteur (effet MIDI)';

  @override
  String get midiFxBypass => 'Bypass';

  @override
  String get midiFxCcAssign => 'Assigner CC au bypass';

  @override
  String get midiFxCcAssignTitle => 'Assigner un CC matériel au bypass';

  @override
  String get midiFxCcWaiting =>
      'Bougez un bouton ou un potentiomètre sur votre contrôleur MIDI...';

  @override
  String midiFxCcAssigned(int cc) {
    return 'CC $cc assigné au bypass';
  }

  @override
  String get midiFxCcRemove => 'Supprimer l\'assignation CC';

  @override
  String get drumGeneratorAddTitle => 'Générateur de batterie';

  @override
  String get drumGeneratorAddSubtitle =>
      'Grooves de bossa nova au métal, avec le feeling humain';

  @override
  String get drumGeneratorActiveLabel => 'Actif';

  @override
  String get drumGeneratorStyleLabel => 'Style';

  @override
  String get drumGeneratorSwingLabel => 'Swing';

  @override
  String get drumGeneratorSwingPattern => 'Pattern';

  @override
  String get drumGeneratorHumanizeLabel => 'Feeling humain';

  @override
  String get drumGeneratorHumanizeRobotic => 'Robotique';

  @override
  String get drumGeneratorHumanizeLive => 'Batteur live';

  @override
  String get drumGeneratorIntroLabel => 'Décompte';

  @override
  String get drumGeneratorFillLabel => 'Fill tous les';

  @override
  String get drumGeneratorSoundfontLabel => 'Police de son';

  @override
  String get drumGeneratorLoadPattern => 'Charger un .gfdrum…';

  @override
  String get drumGeneratorFormatGuide => 'Guide du format';

  @override
  String get drumGeneratorIntroNone => 'Aucun';

  @override
  String get drumGeneratorIntroCountIn1 => '1 mesure';

  @override
  String get drumGeneratorIntroCountIn2 => '2 mesures';

  @override
  String get drumGeneratorIntroChopsticks => 'Baguettes (4 coups)';

  @override
  String get drumGeneratorFillOff => 'Non';

  @override
  String get drumGeneratorFillEvery4 => 'Toutes les 4 mesures';

  @override
  String get drumGeneratorFillEvery8 => 'Toutes les 8 mesures';

  @override
  String get drumGeneratorFillEvery16 => 'Toutes les 16 mesures';

  @override
  String get drumGeneratorFillRandom => 'Aléatoire';

  @override
  String get drumGeneratorCrashAfterFill => 'Crash après le fill';

  @override
  String get drumGeneratorDynamicBuild => 'Montée dynamique';

  @override
  String get drumGeneratorDefaultSoundfont => 'Police de son par défaut';

  @override
  String get drumGeneratorFormatGuideTitle => 'Format de pattern (.gfdrum)';

  @override
  String get drumGeneratorFormatGuideContent =>
      'Un fichier .gfdrum est un fichier texte YAML décrivant un pattern de batterie.\n\nNotation de grille:\nX = coup fort (~100)\nx = coup moyen (~75)\no = coup doux (~55)\ng = note fantôme (~28)\n. = silence\n\nChamps de vélocité: base_velocity, velocity_range\nChamps de timing: timing_jitter, rush\nSections: groove, fill, break, crash, intro\nTypes de section: loop (aléatoire), sequence (mesures ordonnées)';

  @override
  String get drumGeneratorNoPatternsFound => 'Aucun pattern chargé';

  @override
  String get drumGeneratorFamilyRock => 'Rock';

  @override
  String get drumGeneratorFamilyJazz => 'Jazz';

  @override
  String get drumGeneratorFamilyFunk => 'Funk';

  @override
  String get drumGeneratorFamilyLatin => 'Latin';

  @override
  String get drumGeneratorFamilyCeltic => 'Celtique';

  @override
  String get drumGeneratorFamilyPop => 'Pop';

  @override
  String get drumGeneratorFamilyElectronic => 'Électronique';

  @override
  String get drumGeneratorFamilyWorld => 'Musique du monde';

  @override
  String get drumGeneratorFamilyMetal => 'Metal';

  @override
  String get drumGeneratorFamilyCountry => 'Country';

  @override
  String get drumGeneratorFamilyFolk => 'Folk';

  @override
  String get drumGeneratorCustomPattern => 'Pattern personnalisé';

  @override
  String get drumGeneratorNoSoundfonts =>
      'Aucune soundfont — ajoutez-en une dans Préférences';

  @override
  String get audioDeviceDisconnectedInput =>
      'Périphérique d\'entrée audio déconnecté — utilisation du défaut';

  @override
  String get audioDeviceDisconnectedOutput =>
      'Périphérique de sortie audio déconnecté — utilisation du défaut';

  @override
  String get usbAudioDebugTitle => 'Périphériques audio USB';

  @override
  String get usbAudioDebugSubtitle =>
      'Informations détaillées pour l\'investigation multi-USB';

  @override
  String get usbAudioDebugNoDevices => 'Aucun périphérique audio trouvé';

  @override
  String get usbAudioDebugRefresh => 'Actualiser';

  @override
  String get usbAudioDebugDeviceId => 'ID du périphérique';

  @override
  String get usbAudioDebugDirection => 'Direction';

  @override
  String get usbAudioDebugInput => 'Entrée';

  @override
  String get usbAudioDebugOutput => 'Sortie';

  @override
  String get usbAudioDebugInputOutput => 'Entrée + Sortie';

  @override
  String get usbAudioDebugSampleRates => 'Fréquences d\'échantillonnage';

  @override
  String get usbAudioDebugChannelCounts => 'Nombre de canaux';

  @override
  String get usbAudioDebugEncodings => 'Encodages';

  @override
  String get usbAudioDebugAddress => 'Adresse';

  @override
  String get usbAudioDebugAny => 'Quelconque';

  @override
  String get usbAudioDebugPlatformOnly =>
      'Android uniquement — non disponible sur cette plateforme';

  @override
  String get ccCategoryTargetLabel => 'Catégorie de cible';

  @override
  String get ccCategoryGmCc => 'CC standard GM';

  @override
  String get ccCategoryInstruments => 'Instruments';

  @override
  String get ccCategoryAudioEffects => 'Effets audio';

  @override
  String get ccCategoryMidiFx => 'Effets MIDI';

  @override
  String get ccCategoryLooper => 'Looper';

  @override
  String get ccCategoryTransport => 'Transport';

  @override
  String get ccCategoryGlobal => 'Global';

  @override
  String get ccCategoryChannelSwap => 'Échange de canaux';

  @override
  String get ccTransportPlayStop => 'Lecture / Stop';

  @override
  String get ccTransportTapTempo => 'Tap Tempo';

  @override
  String get ccTransportMetronomeToggle => 'Activer/Désactiver métronome';

  @override
  String get ccGlobalSystemVolume => 'Volume système';

  @override
  String get ccGlobalSystemVolumeHint =>
      'CC 0-127 → Volume média du système (0-100%)';

  @override
  String get ccSlotPickerLabel => 'Slot';

  @override
  String get ccParamPickerLabel => 'Paramètre';

  @override
  String get ccActionPickerLabel => 'Action';

  @override
  String get ccNoSlotsOfType => 'Aucun slot de ce type dans le rack.';

  @override
  String get ccSwapInstrumentA => 'Instrument A';

  @override
  String get ccSwapInstrumentB => 'Instrument B';

  @override
  String get ccSwapCablesLabel =>
      'Échanger les câbles (chaînes d\'effets, liens Jam Mode)';

  @override
  String get ccSwapNeedTwoSlots =>
      'Il faut au moins 2 slots instruments dans le rack.';

  @override
  String ccSwapDisplayLabel(String slotA, String slotB) {
    return 'Échange : $slotA ↔ $slotB';
  }

  @override
  String get ccSwapCablesYes => 'avec câbles';

  @override
  String get ccSwapCablesNo => 'canaux uniquement';

  @override
  String toastSwapped(String slotA, String slotB) {
    return 'Échangé : $slotA ↔ $slotB';
  }

  @override
  String toastBypassOn(String slotName) {
    return '$slotName — désactivé';
  }

  @override
  String toastBypassOff(String slotName) {
    return '$slotName — actif';
  }

  @override
  String toastSystemVolume(int percent) {
    return 'Volume système : $percent%';
  }
}
