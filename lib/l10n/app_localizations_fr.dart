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
  String get pianoVelocityTitle => 'Vélocité des touches';

  @override
  String get pianoVelocitySubtitle =>
      'La force des notes jouées sur le clavier à l\'écran. Au toucher : plus on appuie près du bord avant de la touche, plus c\'est fort.';

  @override
  String get pianoVelocityTouch => 'Au toucher';

  @override
  String get pianoVelocitySoft => 'Doux';

  @override
  String get pianoVelocityMedium => 'Moyen';

  @override
  String get pianoVelocityLoud => 'Fort';

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
  String get prefAboutMadeWith => 'Fait avec Flutter à Paris';

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
  String get guideTabMidi => 'Contrôleurs MIDI';

  @override
  String get guideTabTips => 'Conseils de jeu';

  @override
  String get guideTabPatch => 'Câbles';

  @override
  String get guidePatchGroupInstruments => 'Instruments';

  @override
  String get guidePatchGroupRhythm => 'Batterie et loopers';

  @override
  String get guidePatchGroupCustom => 'Vos propres plugins';

  @override
  String get guidePatchSlotKeyboard => 'Clavier';

  @override
  String get guidePatchSlotKeyboardDesc =>
      'Joue un piano ou n\'importe quel son d\'une soundfont (.sf2). Réglez-le sur Aucune (MIDI seulement) pour qu\'il serve seulement à envoyer des notes aux autres modules. Une touche jouée près de son bord avant sonne plus fort que près du fond ; Préférences > Vélocité des touches permet de fixer une seule force.';

  @override
  String get guidePatchSlotVocoder => 'Vocodeur';

  @override
  String get guidePatchSlotVocoderDesc =>
      'Votre voix au micro devient un synthé qui joue les notes tenues.';

  @override
  String get guidePatchSlotJam => 'Jam Mode';

  @override
  String get guidePatchSlotJamDesc =>
      'Garde un clavier dans la gamme des accords joués sur un autre clavier.';

  @override
  String get guidePatchSlotVst3 => 'Plugin VST3';

  @override
  String get guidePatchSlotVst3Desc =>
      'Charge un instrument ou un effet VST3 installé sur votre ordinateur.';

  @override
  String get guidePatchSlotVst3DesktopOnly =>
      'Les plugins VST3 ne fonctionnent que sur Linux, macOS et Windows, pas sur Android ni dans la démo web.';

  @override
  String get guidePatchTitle => 'La vue de câblage';

  @override
  String get guidePatchIntro =>
      'Touchez l\'icône de câble en haut du rack pour voir l\'arrière de chaque module. La flèche de retour vous ramène à l\'avant. On ne peut pas déplacer les modules dans cette vue.';

  @override
  String get guidePatchDrawTitle => 'Tirer un câble';

  @override
  String get guidePatchDrawBody =>
      'Appuyez longuement sur une prise de sortie et glissez. Les prises qui acceptent le câble s\'allument. Relâchez sur l\'une d\'elles pour brancher, ailleurs pour annuler. Une sortie ne se branche que sur une entrée de la même couleur.';

  @override
  String get guidePatchDisconnectTitle => 'Retirer un câble';

  @override
  String get guidePatchDisconnectBody =>
      'Touchez le petit ✕ au milieu d\'un câble, puis Déconnecter. Supprimer un module retire aussi ses câbles.';

  @override
  String get guidePatchDataTitle => 'Câbles de gamme et d\'accordage';

  @override
  String get guidePatchDataBody =>
      'Les câbles violets transportent l\'harmonie. CHORD OUT vers CHORD IN indique à Jam Mode ou Xen quel clavier donne les accords. SCALE OUT vers SCALE IN ajoute un clavier qui suit la gamme. Les câbles et les menus des panneaux sont toujours d\'accord.\nLe câble turquoise TUNE OUT vers TUNE IN porte l\'accordage d\'une gamme Xen jusqu\'à un instrument. Il est séparé du câble de gamme : on peut garder un clavier dans une gamme sans le réaccorder, ou l\'inverse.';

  @override
  String get guidePatchSharedEffectTitle => 'Un effet, un signal';

  @override
  String get guidePatchSharedEffectBody =>
      'Un effet garde en mémoire le son qui le traverse (la queue d\'une reverb, la ligne d\'un delay) : il ne peut donc traiter qu\'un seul signal. Deux claviers branchés directement dans la même reverb, ça marche : ils sont d\'abord mélangés. Un clavier directement dans une reverb et un autre qui passe par un harmoniseur avant la même reverb, ce sont deux signaux différents, et GrooveForge refuse le câble.';

  @override
  String get guidePatchSharedEffectWorkaround =>
      'Si un câble est refusé pour cette raison, ajoutez un deuxième exemplaire de l\'effet et branchez-y l\'autre signal.';

  @override
  String get guidePatchTip => 'Les câbles sont enregistrés avec le projet.';

  @override
  String get guideXenTitle => 'Xen : gammes et accordages';

  @override
  String get guideXenBody =>
      'Xen garde chaque note jouée dans une gamme. Tenez une touche et touchez une gamme : la touche tenue devient la tonique, jusqu\'à ce que vous recommenciez. Choisir une gamme allume aussi Xen.\nSNAP déplace les notes hors de la gamme vers la plus proche qui va bien ; le piano les grise. TUNE joue l\'accordage propre de la gamme, pour celles dont les notes tombent entre les touches du piano : ces touches portent une bande turquoise et leur écart en cents. SNAP et TUNE s\'activent séparément.\nLe menu Famille propose les modes occidentaux, les maqamat arabes et turcs, les ragas indiens, des gammes chinoises, japonaises et coréennes, des accordages de gamelan, les tempéraments historiques et bien d\'autres. Mes gammes contient celles que vous créez ou importez depuis des fichiers Scala (.scl).';

  @override
  String get guideJamModeTitle => 'Jam Mode';

  @override
  String get guideJamModeBody =>
      'Jam Mode sert à deux claviers : l\'un joue les accords, l\'autre improvise. Dans son panneau, MASTER est le clavier dont les accords fixent la gamme, et TARGETS les claviers qui suivent. Chaque note jouée sur un clavier cible est ramenée dans cette gamme. Vous pouvez aussi tirer le lien dans la vue de câblage : CHORD OUT vers CHORD IN, SCALE OUT vers SCALE IN.';

  @override
  String get guideVocoderTitle => 'Vocodeur';

  @override
  String get guideVocoderBody =>
      'Touchez + et choisissez Vocodeur. Chantez ou parlez dans le micro en tenant des notes : votre voix façonne un synthé qui les joue. Réglez le niveau du micro avec les boutons de gain. Essayez les ondes porteuses (Dent de scie, Carrée, Choral), ou Harmonie, qui retire le synthé et transpose votre propre voix sur les touches tenues.';

  @override
  String get guideThereminTitle => 'Thérémine et Stylophone';

  @override
  String get guideThereminBody =>
      'Le Thérémine a deux modes. PAD est un pavé tactile : glissez de haut en bas pour la hauteur, de gauche à droite pour le volume. CAM (Android, iOS et macOS) utilise la caméra frontale pour mesurer la distance de votre main : plus près, plus aigu ; assez loin, silence ; le volume reste au maximum. BASE règle la note la plus grave, RANGE l\'étendue en octaves, VIB le vibrato et HEIGHT la taille du pavé.\nLe Stylophone est une bande de 25 touches qu\'on joue en touchant ou en glissant. Il joue une note à la fois, comme l\'original, et glisse d\'une touche à l\'autre sans clic. SQR, SAW, SIN et TRI choisissent la forme d\'onde.';

  @override
  String get guideDrumGeneratorTitle => 'Générateur de batterie';

  @override
  String get guideDrumGeneratorBody =>
      'Joue un pattern de batterie au tempo du transport, de la bossa nova au metal. Swing retarde les contretemps. Feeling humain va d\'une grille stricte à un batteur qui respire. Le décompte joue quelques coups avant le pattern, et Fill toutes les ajoute un break toutes les quelques mesures.\nLes patterns sont des fichiers .gfdrum : vous pouvez ajouter les vôtres.';

  @override
  String get guideLoopersTitle => 'Loopers';

  @override
  String get guideLoopersBody =>
      'Le Looper MIDI enregistre les notes jouées et les répète en boucle. Le Looper Audio enregistre le son, et permet aussi l\'overdub et la lecture à l\'envers.\nLes deux attendent la mesure suivante pour enregistrer et arrondissent la boucle à des mesures entières, pour que les boucles restent calées entre elles.\nLe Looper Audio enregistre ce qui arrive sur son AUDIO IN : branchez-y d\'abord un instrument ou une Entrée live.';

  @override
  String get guideMidiFxTitle => 'MIDI FX';

  @override
  String get guideMidiFxBody =>
      'Les MIDI FX modifient les notes entre le clavier et son son. Harmonizer ajoute jusqu\'à quatre voix à ce que vous jouez ; avec Scale Lock, elles restent dans la gamme en cours. Chord Expand transforme une note en accord. Arpeggiator joue les notes tenues l\'une après l\'autre, en rythme. Transposer décale tout, jusqu\'à deux octaves. Velocity Curve change le volume des notes douces et fortes. Gate ne laisse passer que les notes dans une plage de vélocité ou de hauteur. Microtone fond les notes tenues en une seule hauteur microtonale.';

  @override
  String get guideMidiTitle => 'Brancher un contrôleur';

  @override
  String get guideMidiBody =>
      'GrooveForge fonctionne avec les claviers et pads MIDI USB (avec un adaptateur OTG sur un téléphone) et avec les appareils MIDI Bluetooth.';

  @override
  String get guideMidiBestPracticeTitle => 'Un clavier ou deux ?';

  @override
  String get guideMidiBestPracticeBody =>
      'Un seul clavier suffit : un nouveau projet associe un GrooveForge Keyboard à un module Xen. Xen démarre éteint et s\'allume dès que vous choisissez une gamme : tenez une note et appuyez sur un bouton de gamme.\nUn deuxième clavier, ou un contrôleur coupé en deux, sert au Jam Mode : une main joue les accords qui fixent la gamme, l\'autre improvise dessus.';

  @override
  String get guideSoundfontsTitle => 'Sons (soundfonts)';

  @override
  String get guideSoundfontsBody =>
      'Le clavier joue ses sons depuis des fichiers soundfont (.sf2). Pour en ajouter une, ouvrez les Préférences, puis sous Soundfonts touchez Charger une Soundfont (.sf2). Elle apparaît ensuite dans le menu de son de chaque clavier. Une bonne soundfont peut peser plusieurs centaines de Mo.';

  @override
  String get guideTipsTitle => 'Improviser';

  @override
  String get guideTipsBody =>
      'Vous débutez en improvisation ? Quelques idées :\n• Dans une gamme, toutes les touches vont avec la musique. Il n\'y a pas de fausses notes, seulement des notes surprenantes.\n• Commencez ou terminez vos phrases sur la tonique : on a l\'impression de rentrer à la maison.\n• Le rythme d\'abord. Une idée simple jouée en place vaut mieux qu\'une course rapide.\n• Laissez de l\'espace. Des phrases courtes séparées de silences sonnent plus musical qu\'un flot de notes.';

  @override
  String guideWelcomeHeader(String version) {
    return 'Bienvenue dans GrooveForge v$version';
  }

  @override
  String get guideWelcomeIntro =>
      'Des recettes courtes pour démarrer. Chacune renvoie à une vidéo du geste sur le site.';

  @override
  String get guideChangelogExpand => 'Les nouveautés de cette version';

  @override
  String get guideMidiHardwareStep1 =>
      'Branchez le contrôleur, ou allumez le contrôleur Bluetooth.';

  @override
  String get guideMidiHardwareStep2 =>
      'Ouvrez les Préférences avec l\'icône d\'engrenage. Sous Connexion MIDI, touchez Connecter un appareil MIDI et choisissez-le.';

  @override
  String get guideMidiCcMappings => 'Associer boutons et pads';

  @override
  String get guideMidiCcMappingsBody =>
      'Pour les réglages d\'un module : touchez l\'icône de curseurs en haut du module, touchez Learn à côté d\'un réglage, puis tournez un bouton ou frappez un pad.\nPour les actions qui concernent toute l\'app (looper, transport, échange de canaux et autres) : ouvrez les Préférences, puis Préférences de mapping CC, puis Ajouter un Mapping.';

  @override
  String get guideMidiTipSplit =>
      'Beaucoup de contrôleurs peuvent couper leurs touches en deux zones sur des canaux MIDI différents, par exemple la basse à la main gauche et la mélodie à la droite.';

  @override
  String get guideAndroidUsbLimitation =>
      'Android ne garde qu\'un seul appareil audio USB à la fois. Si brancher un micro USB coupe votre casque ou votre carte son USB, activez Sortie USB directe dans les Préférences, sous Sortie Audio.';

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
  String get usbDirectOutputTitle => 'Sortie USB directe';

  @override
  String get usbDirectOutputSubtitle =>
      'Pour un micro USB et une carte son USB (DAC) utilisés ensemble : Android n\'en garde qu\'un. Touchez ? pour en savoir plus.';

  @override
  String get usbDirectOutputUnknownDevice => 'DAC USB';

  @override
  String get usbDirectOutputStatusNoDevice =>
      'En attente : aucun DAC USB compatible n\'est branché.';

  @override
  String get usbDirectOutputStatusAndroidRoutes =>
      'Pas nécessaire pour l\'instant : Android joue déjà via votre périphérique USB.';

  @override
  String usbDirectOutputStatusPermission(String device) {
    return 'Android demande l\'accès à $device : touchez Autoriser.';
  }

  @override
  String usbDirectOutputStatusDenied(String device) {
    return 'Accès USB à $device refusé. Rebranchez-le, ou désactivez puis réactivez cette option, pour qu\'on vous le redemande.';
  }

  @override
  String usbDirectOutputStatusActive(String device, int rate, int bits) {
    return 'Lecture via $device ($rate Hz, $bits bits). Réglez le volume dans GrooveForge ou sur votre enceinte : les touches de volume du téléphone n\'agissent pas sur cette sortie.';
  }

  @override
  String usbDirectOutputStatusUnsupported(String device) {
    return '$device ne peut pas être utilisé : seuls les DAC USB simples (USB Audio Class 1) sont pris en charge.';
  }

  @override
  String usbDirectOutputStatusError(String device) {
    return '$device s\'est arrêté. Débranchez-le puis rebranchez-le pour réessayer.';
  }

  @override
  String get usbDirectOutputHelpTooltip => 'Comment ça marche ?';

  @override
  String get usbDirectOutputHelpProblemTitle => 'Le problème';

  @override
  String get usbDirectOutputHelpProblemBody =>
      'Android ne sait utiliser qu\'un seul périphérique audio USB à la fois. Branchez un micro USB (un récepteur de micro sans fil, par exemple) et une carte son USB (comme la prise casque d\'un hub USB-C) : Android garde celui qu\'il a détecté en dernier et ignore l\'autre sans prévenir. Le son sort alors du haut-parleur du téléphone au lieu de votre casque ou de vos enceintes.';

  @override
  String get usbDirectOutputHelpSolutionTitle => 'Ce que fait cette option';

  @override
  String get usbDirectOutputHelpSolutionBody =>
      'GrooveForge envoie son son directement à la carte son qu\'Android ignore, par l\'USB, sans passer par le système audio d\'Android. Votre micro continue de fonctionner normalement.';

  @override
  String get usbDirectOutputHelpWhenTitle => 'Quand elle s\'active';

  @override
  String get usbDirectOutputHelpWhenBody =>
      'Seulement quand c\'est utile : une carte son USB compatible est branchée et Android ne joue pas déjà via un périphérique USB. Le reste du temps, rien ne change : vous pouvez la laisser activée.';

  @override
  String get usbDirectOutputHelpStepsTitle => 'Mode d\'emploi';

  @override
  String get usbDirectOutputHelpStep1 => 'Activez l\'option.';

  @override
  String get usbDirectOutputHelpStep2 =>
      'Branchez votre carte son et votre micro USB.';

  @override
  String get usbDirectOutputHelpStep3 =>
      'Quand Android demande l\'accès à la carte son, touchez Autoriser.';

  @override
  String get usbDirectOutputHelpStep4 =>
      'La ligne sous l\'interrupteur indique « Lecture via… » : c\'est prêt.';

  @override
  String get usbDirectOutputHelpTipsTitle => 'Bon à savoir';

  @override
  String get usbDirectOutputHelpTipVolume =>
      'Les touches de volume du téléphone ne changent pas cette sortie. Utilisez le gain de GrooveForge et le volume de votre enceinte.';

  @override
  String get usbDirectOutputHelpTipCompat =>
      'Fonctionne avec les cartes son USB simples (USB Audio Class 1), ce qui couvre la plupart des hubs USB-C et adaptateurs jack. Les interfaces USB haut de gamme sont indiquées comme non prises en charge.';

  @override
  String get usbDirectOutputHelpTipOtherApps =>
      'Seul GrooveForge passe par la carte son de cette façon. Les notifications et les autres applis utilisent toujours le téléphone.';

  @override
  String get usbDirectOutputHelpTipGiveBack =>
      'Après avoir désactivé l\'option, débranchez puis rebranchez la carte son pour qu\'Android puisse la réutiliser.';

  @override
  String get usbDirectOutputHelpTipCharger =>
      'Branchez le chargeur sur le hub avant de brancher le hub au téléphone. Ajouter l\'alimentation en cours de jeu fait reconnecter tous les périphériques USB : le son se coupe, et certains téléphones peuvent même redémarrer.';

  @override
  String get usbDirectOutputHelpClose => 'Compris';

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
  String connectionSharedEffectError(String effectName) {
    return '$effectName est déjà câblé depuis un autre chemin de signal. Dupliquez le slot d\'effet pour que chaque chemin ait sa propre instance.';
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
  String get portChordOut => 'ACCORD OUT';

  @override
  String get portChordIn => 'ACCORD IN';

  @override
  String get portScaleOut => 'GAMME OUT';

  @override
  String get portScaleIn => 'GAMME IN';

  @override
  String get portTuningOut => 'TUNE OUT';

  @override
  String get portTuningIn => 'TUNE IN';

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
  String get rackAddSourcesSectionLabel => 'Sources audio';

  @override
  String get rackAddLiveInputSource => 'Live Input';

  @override
  String get rackAddLiveInputSourceSubtitle =>
      'Envoyez un micro ou une entrée ligne vers n\'importe quel effet (harmonizer, vocodeur, reverb…)';

  @override
  String get liveInputNoDevice => 'Aucun périphérique d\'entrée détecté';

  @override
  String get liveInputDeviceHint => 'Se change dans Préférences › Entrée Audio';

  @override
  String get liveInputDisconnected =>
      'Micro débranché : entrée arrêtée. Rebranchez-le ou choisissez une autre entrée dans les Préférences.';

  @override
  String get liveInputFeedbackMuted =>
      'Coupé : le micro du téléphone ferait un larsen dans son haut-parleur.';

  @override
  String get liveInputFeedbackUnmute => 'Réactiver quand même';

  @override
  String get audioDeviceDisconnected => 'Déconnecté';

  @override
  String get micDisconnectedToast =>
      'Micro débranché : entrée arrêtée au lieu de basculer sur le micro du téléphone';

  @override
  String get liveInputGainLabel => 'Gain';

  @override
  String get liveInputMonitorMute =>
      'Couper le monitoring local (les effets reçoivent toujours le signal)';

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
  String audioLooperMemoryCapWarning(String usedMb, int capMb) {
    return 'Mémoire du looper audio : $usedMb Mo / $capMb Mo — pensez à effacer les clips inutiles';
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
  String get chiptuneChord => 'ACCORD';

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
  String get rackAddNativeOnlyBadge => 'Applis uniquement';

  @override
  String get rackAddNativeOnlyTooltip =>
      'Disponible dans les applis GrooveForge pour Android, Linux, macOS et Windows, pas dans cette démo web.';

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
  String get rackAddWah => 'Wah';

  @override
  String get rackAddWahSubtitle =>
      'Filtre wah : balayage LFO avec sync BPM, ou joué à la pédale / au potard CC';

  @override
  String get rackAddEq => 'EQ 4 bandes';

  @override
  String get rackAddEqSubtitle => 'Shelf grave, 2 bandes en cloche, shelf aigu';

  @override
  String get rackAddCompressor => 'Compresseur';

  @override
  String get rackAddCompressorSubtitle => 'Compresseur RMS à genou doux';

  @override
  String get rackAddChorus => 'Chorus / Flanger';

  @override
  String get rackAddChorusSubtitle => 'Chorus stéréo synchronisable sur le BPM';

  @override
  String get rackAddAudioHarmonizer => 'Harmoniseur Audio';

  @override
  String get rackAddAudioHarmonizerSubtitle =>
      'Jusqu\'à 4 voix d\'harmonie transposées à partir d\'une entrée audio';

  @override
  String get rackAddAutotune => 'Autotune';

  @override
  String get rackAddRiff => 'Riff';

  @override
  String get rackAddRiffSubtitle =>
      'Guitare électrique modélisée corde par corde ; à câbler dans l\'Ampli';

  @override
  String get rackAddAmp => 'Ampli';

  @override
  String get rackAddAmpSubtitle =>
      'Ampli guitare : pédale de saturation, réglages de l\'ampli et baffle';

  @override
  String get ampIrNone => 'IR de baffle : aucune';

  @override
  String ampIrLoaded(String name) {
    return 'IR de baffle : $name';
  }

  @override
  String get ampIrLoad => 'Charger une IR';

  @override
  String get ampIrRemove => 'Retirer l\'IR';

  @override
  String get ampIrPickTitle =>
      'Choisir une réponse impulsionnelle de baffle (.wav)';

  @override
  String get ampIrNotWav => 'Ce fichier n\'est pas un WAV.';

  @override
  String get ampIrUnsupported =>
      'Ce WAV est dans un format compressé. Exportez-le en WAV PCM ou flottant.';

  @override
  String get ampIrEmpty => 'Ce fichier ne contient aucun son.';

  @override
  String get ampIrUnreadable => 'Impossible de lire ce fichier.';

  @override
  String get ampIrRejected => 'L\'ampli n\'a pas pu utiliser cette IR.';

  @override
  String get guideRiffTitle => 'Riff, la guitare modélisée';

  @override
  String get guideRiffBody =>
      'Riff est une guitare électrique modélisée corde par corde. Elle n\'a pas de touches : reliez le MIDI OUT d\'un clavier à son MIDI IN, ou jouez-la depuis un contrôleur sur son canal MIDI.\nLes notes proches vont sur des cordes différentes et sonnent ensemble. Avec Legato, une note proche de la précédente se joue en hammer-on ou en pull-off sur la même corde. Overlap fait de même, mais seulement quand vous enfoncez une touche avant de lâcher la précédente.\nLa molette de pitch fait des bends, la molette de modulation du vibrato, la pédale de sustain laisse sonner les cordes. Feedback fait monter les cordes tenues vers une harmonique, comme devant un ampli.\nPalm mute, Pick position, Tone et le sélecteur de micros agissent sur les cordes qui sonnent déjà : associez-les à une pédale ou un bouton avec Learn et jouez-en comme les mains d\'un guitariste. Pour du crunch ou de la saturation, branchez Riff dans l\'Ampli.';

  @override
  String get guideAmpTitle => 'Ampli et IR de baffle';

  @override
  String get guideAmpBody =>
      'L\'Ampli a trois sections à activer ou couper, à la main ou au footswitch : une pédale Drive (Overdrive ou Distortion), l\'ampli lui-même (Gain, Bass, Middle, Treble) et le baffle.\nC\'est le baffle qui fait l\'essentiel du son d\'une guitare. En plus des trois baffles intégrés, l\'Ampli peut jouer une réponse impulsionnelle (IR), l\'enregistrement d\'un vrai baffle : touchez Charger une IR sous l\'Ampli et choisissez un fichier .wav. Il est enregistré dans votre projet ; la croix à côté de son nom le retire.';

  @override
  String get guideAmpIrSourcesTitle => 'Où trouver des IR de baffle gratuites';

  @override
  String get guideAmpIrSourcesNote =>
      'Chaque pack a sa propre licence : libre pour jouer, mais en général pas pour le partager. Téléchargez-les vous-même sur ces sites.';

  @override
  String get guideIrSourceTone3000 =>
      'TONE3000 : une bibliothèque communautaire avec des milliers d\'IR gratuites';

  @override
  String get guideIrSourceKalthallen =>
      'Kalthallen Cabs : des packs gratuits et payants de baffles classiques';

  @override
  String get guideIrSourceCelestion =>
      'Celestion : une IR gratuite du fabricant de haut-parleurs';

  @override
  String get rackAddAutotuneSubtitle =>
      'Colle votre voix sur les notes d\'une gamme, de discret à robot';

  @override
  String get autotuneListening => 'Chantez quelque chose…';

  @override
  String autotuneCents(String cents) {
    return '$cents ¢';
  }

  @override
  String get autotuneDisplayTooltip =>
      'À gauche : la note que vous chantez et son écart. À droite : la note vers laquelle elle est corrigée.';

  @override
  String get autotuneScalePatched => 'Suit la gamme branchée';

  @override
  String get rackAddLoadGfpd => 'Charger un fichier .gfpd…';

  @override
  String get rackAddLoadGfpdSubtitle =>
      'Importer un descripteur de plugin GrooveForge personnalisé';

  @override
  String get rackAddGfpdInvalid =>
      'Ce fichier n\'est pas un module .gfpd valide.';

  @override
  String get rackAddGfpdReadError => 'Ce fichier n\'a pas pu être lu.';

  @override
  String get rackAddGfpdReserved =>
      'L\'id de ce module commence par com.grooveforge., réservé aux modules fournis avec l\'application. Donnez-lui un id à vous.';

  @override
  String rackAddGfpdUpdated(String name) {
    return '$name mis à jour. Ses emplacements dans le rack utilisent maintenant la nouvelle version.';
  }

  @override
  String get rackAddCustomPluginSubtitle =>
      'Votre module, depuis un fichier .gfpd';

  @override
  String get rackAddCustomPluginRemove => 'Retirer de ce menu';

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
  String get rackAddMicrotone => 'Microtone';

  @override
  String get rackAddMicrotoneSubtitle =>
      'Fusionne les notes tenues en une hauteur microtonale via pitch-bend (effet MIDI)';

  @override
  String get rackAddXen => 'Xen';

  @override
  String get rackAddXenSubtitle =>
      'Verrouille le clavier sur une gamme et le réaccorde — maqam, raga, gamelan, tempéraments anciens (effet MIDI)';

  @override
  String get xenAbout =>
      'Tenez une note, appuyez sur une gamme : cette note devient la tonique et le clavier se verrouille sur la gamme construite autour d\'elle. Les gammes qui ne sont pas tempérées — un maqam arabe, un raga indien, un chanter de cornemuse — réaccordent aussi les touches qu\'elles utilisent, pour que les intervalles sonnent comme la tradition les entend et non comme un piano les approxime. Contrairement au module Microtone, qui plie la hauteur d\'une note à la fois, Xen réaccorde chaque touche indépendamment : un accord entier peut garder sa propre intonation.';

  @override
  String get xenSnap => 'SNAP';

  @override
  String get xenTune => 'TUNE';

  @override
  String get xenRoot => 'TONIQUE';

  @override
  String get xenFamily => 'FAMILLE';

  @override
  String get xenScale => 'GAMME';

  @override
  String get xenLatch => 'FIXER';

  @override
  String get xenTargetsLock => 'VERROU GAMME';

  @override
  String get xenTargetsTune => 'ACCORDAGE';

  @override
  String get xenHint => 'Tenez une note, puis appuyez sur une gamme';

  @override
  String xenHolding(String note) {
    return 'Note tenue : $note';
  }

  @override
  String get xenNoSlots => 'aucun module';

  @override
  String get xenNoTargets => 'non câblé';

  @override
  String get xenMicrotonalTooltip => 'Réaccorde les touches qu\'elle utilise';

  @override
  String get xenTemperedTooltip =>
      'Tempérée — disposition des touches seulement';

  @override
  String get xenFamilyWestern => 'Occidental';

  @override
  String get xenFamilyMaqam => 'Maqam';

  @override
  String get xenFamilyRaga => 'Raga';

  @override
  String get xenFamilyFarEast => 'Extrême-Orient';

  @override
  String get xenFamilyPersian => 'Persan';

  @override
  String get xenFamilySoutheastAsia => 'Asie du SE';

  @override
  String get xenFamilyAfrica => 'Afrique';

  @override
  String get xenFamilyEurope => 'Europe';

  @override
  String get xenFamilyGamelan => 'Gamelan';

  @override
  String get xenFamilyTemperament => 'Tempéraments';

  @override
  String get xenFamilyExperimental => 'Expérimental';

  @override
  String get xenFamilyCustom => 'Mes gammes';

  @override
  String get xenEditorTitle => 'Éditeur de gamme';

  @override
  String get xenEditorName => 'Nom';

  @override
  String get xenEditorLayout => 'Disposition';

  @override
  String get xenEditorLayoutKeyboard => 'Clavier';

  @override
  String get xenEditorLayoutLinear => 'Linéaire';

  @override
  String get xenEditorLayoutKeyboardHint =>
      'Chaque degré garde sa touche ; le motif se répète à chaque octave.';

  @override
  String xenEditorLayoutLinearHint(int count) {
    return 'Les degrés occupent des touches successives ; une période couvre $count touches.';
  }

  @override
  String get xenEditorPeriod => 'Période (cents)';

  @override
  String get xenEditorKey => 'Touche';

  @override
  String get xenEditorOffset => 'Écart';

  @override
  String xenEditorSounds(String cents) {
    return 'sonne à $cents ¢';
  }

  @override
  String get xenEditorAddDegree => 'Ajouter un degré';

  @override
  String get xenEditorRemoveDegree => 'Retirer';

  @override
  String get xenEditorMute =>
      'Muter — jouable et accordé, mais le snap l\'ignore';

  @override
  String get xenEditorSeed => 'Partir de';

  @override
  String get xenEditorSeedNone => 'Vide';

  @override
  String get xenEditorSave => 'Enregistrer';

  @override
  String get xenEditorCancel => 'Annuler';

  @override
  String get xenEditorImport => 'Importer';

  @override
  String get xenEditorExport => 'Exporter';

  @override
  String get xenEditorExportJson => 'Gamme GrooveForge (.json)';

  @override
  String get xenEditorExportScala => 'Accordage Scala (.scl)';

  @override
  String xenEditorDegreeCount(int count, int active) {
    return '$count degrés, $active actifs';
  }

  @override
  String get xenEditorNoDegrees =>
      'Aucun degré — ajoutez-en un, ou partez d\'une gamme existante.';

  @override
  String get xenEditorDuplicateKeys =>
      'Deux degrés partagent une touche ; la gamme utilisera la disposition linéaire.';

  @override
  String xenEditorImportFailed(String reason) {
    return 'Lecture impossible : $reason';
  }

  @override
  String xenEditorImported(String name) {
    return '« $name » importée';
  }

  @override
  String xenEditorExported(String path) {
    return 'Exporté vers $path';
  }

  @override
  String get xenEditorDelete => 'Supprimer la gamme';

  @override
  String get xenEditorUnnamed => 'Gamme sans titre';

  @override
  String get xenScaleMajor => 'Majeure';

  @override
  String get xenScaleNaturalMinor => 'Mineure naturelle';

  @override
  String get xenScaleHarmonicMinor => 'Mineure harmonique';

  @override
  String get xenScaleMelodicMinor => 'Mineure mélodique';

  @override
  String get xenScaleMajorPentatonic => 'Pentatonique majeure';

  @override
  String get xenScaleMinorPentatonic => 'Pentatonique mineure';

  @override
  String get xenScaleBlues => 'Blues';

  @override
  String get xenScaleRock => 'Rock';

  @override
  String get xenScaleDorian => 'Dorien';

  @override
  String get xenScalePhrygian => 'Phrygien';

  @override
  String get xenScaleLydian => 'Lydien';

  @override
  String get xenScaleMixolydian => 'Mixolydien';

  @override
  String get xenScaleLocrian => 'Locrien';

  @override
  String get xenScalePhrygianDominant => 'Phrygien dominant';

  @override
  String get xenScaleWholeTone => 'Par tons';

  @override
  String get xenScaleDiminished => 'Diminuée';

  @override
  String get xenScaleJustIntonation => 'Intonation juste';

  @override
  String get xenScalePythagorean => 'Pythagoricienne';

  @override
  String get xenScaleMeantone => 'Mésotonique 1/4 de comma';

  @override
  String get xenScaleWerckmeisterIII => 'Werckmeister III';

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
  String get drumGeneratorLoadFailed =>
      'Ce fichier n\'est pas un motif .gfdrum valide.';

  @override
  String get drumGeneratorFormatGuide => 'Guide du format';

  @override
  String get drumGeneratorIntroNone => 'Aucun';

  @override
  String get drumGeneratorIntroCountIn1 => '1 mesure';

  @override
  String get drumGeneratorIntroCountIn2 => '2 mesures';

  @override
  String drumGeneratorIntroChopsticks(int hits) {
    return 'Baguettes ($hits coups)';
  }

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
  String get drumGeneratorBreakLabel => 'Breaks';

  @override
  String get drumGeneratorBreakNone => 'Aucun';

  @override
  String get drumGeneratorBreakRare => 'Rares';

  @override
  String get drumGeneratorBreakOccasional => 'De temps en temps';

  @override
  String get drumGeneratorBreakFrequent => 'Souvent';

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
      'Un fichier .gfdrum est un fichier texte YAML qui décrit un motif de batterie.\n\nNotation de la grille :\nX = coup fort (~100)\nx = coup moyen (~75)\no = coup doux (~55)\ng = note fantôme (~28)\n. = silence\n\nChamps de vélocité : base_velocity, velocity_range\nChamps de timing : timing_jitter, rush (en temps ; négatif = en avance sur le temps)\nSections : groove, fill, break, crash, intro\nTypes de section : loop (une variation par phrase), sequence (mesures dans l\'ordre)\n\nLe format complet est décrit sur le site, rubrique .gfdrum.';

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
  String get drumGeneratorFamilyMarch => 'Marche';

  @override
  String get drumGeneratorFamilyReggae => 'Reggae';

  @override
  String get drumGeneratorFamilyRnb => 'R&B';

  @override
  String get drumGeneratorFamilyArabic => 'Arabe';

  @override
  String get drumGeneratorFamilyTurkish => 'Turc';

  @override
  String get drumGeneratorFamilyPersian => 'Persan';

  @override
  String get drumGeneratorFamilyIndian => 'Indien';

  @override
  String get drumGeneratorFamilyFarEast => 'Extrême-Orient';

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
  String get ccDirectValueLabel => 'Valeur à rappeler';

  @override
  String get ccAssignAddValue => 'Assigner une valeur…';

  @override
  String get ccAssignNoValues => 'Rien d\'assigné';

  @override
  String get ccAssignMoveKnobOrButton => 'Bougez un bouton CC ou appuyez…';

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

  @override
  String get intervalNameUnison => 'Unisson';

  @override
  String get intervalNameMinor2 => 'Seconde mineure';

  @override
  String get intervalNameMajor2 => 'Seconde majeure';

  @override
  String get intervalNameMinor3 => 'Tierce mineure';

  @override
  String get intervalNameMajor3 => 'Tierce majeure';

  @override
  String get intervalNamePerfect4 => 'Quarte juste';

  @override
  String get intervalNameTritone => 'Triton';

  @override
  String get intervalNamePerfect5 => 'Quinte juste';

  @override
  String get intervalNameMinor6 => 'Sixte mineure';

  @override
  String get intervalNameMajor6 => 'Sixte majeure';

  @override
  String get intervalNameMinor7 => 'Septième mineure';

  @override
  String get intervalNameMajor7 => 'Septième majeure';

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
    return '$name, $semitones demi-tons au-dessus de la note jouée';
  }

  @override
  String intervalTooltipBelow(String name, int semitones) {
    return '$name, $semitones demi-tons en dessous de la note jouée';
  }

  @override
  String get intervalTooltipUnison =>
      'Unisson — la même hauteur que la note jouée';

  @override
  String get vocoderWaveSaw => 'Dent de scie';

  @override
  String get vocoderWaveSquare => 'Carrée';

  @override
  String get vocoderWaveChoral => 'Choral';

  @override
  String get vocoderWaveHarmony => 'Harmonie';

  @override
  String get latencyProbeTitle => 'Latence d\'overdub';

  @override
  String get latencyProbeSubtitle =>
      'Mesure le retard entre ce que l\'app joue et ce que le micro entend';

  @override
  String get latencyProbeExplain =>
      'Joue six brefs balayages dans le haut-parleur et les cherche sur le micro. Utilisez le haut-parleur : un micro n\'entend pas un casque, et la mesure signalera à juste titre n\'avoir rien trouvé.';

  @override
  String get latencyProbeStart => 'Mesurer';

  @override
  String get latencyProbeMeasuring => 'Mesure en cours…';

  @override
  String get latencyProbeRoundTrip => 'Aller-retour';

  @override
  String get latencyProbeJitter => 'Gigue';

  @override
  String get latencyProbeConfidence => 'Confiance';

  @override
  String get latencyProbeShots => 'Balayages exploitables';

  @override
  String get latencyProbeDrift => 'Dérive d\'horloge';

  @override
  String get latencyProbeSkew => 'Écart de compteurs';

  @override
  String latencyProbeDriftOverTake(String ms) {
    return 'Une prise de 4 minutes dériverait de $ms ms';
  }

  @override
  String latencyProbeShotsValue(int found, int total) {
    return '$found sur $total';
  }

  @override
  String latencyProbeMs(String value) {
    return '$value ms';
  }

  @override
  String latencyProbeFramesSuffix(int frames) {
    return '$frames échantillons';
  }

  @override
  String latencyProbePpm(String value) {
    return '$value ppm';
  }

  @override
  String get latencyProbeFailed => 'Aucune mesure exploitable';

  @override
  String get latencyProbeSilentInput =>
      'Le micro n\'a rien entendu. Vérifiez l\'autorisation du micro, et jouez sur le haut-parleur plutôt qu\'au casque.';

  @override
  String get latencyProbeNeedsAudio =>
      'La capture audio n\'est pas active. Ouvrez d\'abord une entrée live ou le vocodeur.';

  @override
  String get latencyProbeHint =>
      'Gardez la pièce silencieuse et orientez le haut-parleur vers le micro.';

  @override
  String get rackTabLabel => 'Rack';

  @override
  String get rehearsalsTabLabel => 'Répéter';

  @override
  String get rehearsalsTitle => 'Répétitions';

  @override
  String get rehearsalsEmpty => 'Aucune répétition';

  @override
  String get rehearsalsEmptyHint =>
      'Lancez un morceau, réglez le tempo et enregistrez votre partie. Le reste du groupe pourra rejoindre plus tard.';

  @override
  String get rehearsalsNew => 'Lancer un morceau';

  @override
  String get rehearsalCreateTitle => 'Nouvelle répétition';

  @override
  String get rehearsalFieldTitle => 'Morceau';

  @override
  String get rehearsalFieldTitleHint => 'Les Feuilles mortes';

  @override
  String get rehearsalFieldYourName => 'Votre nom';

  @override
  String get rehearsalFieldInstrument => 'Votre instrument';

  @override
  String get rehearsalFieldTempo => 'Tempo';

  @override
  String get rehearsalFieldTimeSignature => 'Métrique';

  @override
  String get rehearsalFieldCountIn => 'Décompte';

  @override
  String rehearsalCountInBars(int bars) {
    String _temp0 = intl.Intl.pluralLogic(
      bars,
      locale: localeName,
      other: '$bars mesures',
      one: '$bars mesure',
    );
    return '$_temp0';
  }

  @override
  String get rehearsalCountInNone => 'Aucun';

  @override
  String get rehearsalCreate => 'Créer';

  @override
  String get rehearsalCancel => 'Annuler';

  @override
  String rehearsalPartsProgress(int done, int total) {
    return '$done parties sur $total enregistrées';
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
  String get rehearsalDelete => 'Supprimer';

  @override
  String rehearsalDeleteConfirm(String title) {
    return 'Supprimer « $title » et tous ses enregistrements ?';
  }

  @override
  String get rehearsalAddPart => 'Ajouter une partie';

  @override
  String get rehearsalNotRecorded => 'Pas encore enregistrée';

  @override
  String rehearsalTakeLength(String seconds) {
    return '$seconds s';
  }

  @override
  String get rehearsalMetronome => 'Métronome';

  @override
  String get rehearsalPlay => 'Lecture';

  @override
  String get rehearsalStop => 'Stop';

  @override
  String get rehearsalRecord => 'Enregistrer';

  @override
  String get rehearsalRerecord => 'Réenregistrer';

  @override
  String get rehearsalCountingIn => 'Décompte';

  @override
  String rehearsalBarBeat(int bar, int beat) {
    return 'Mesure $bar  ·  temps $beat';
  }

  @override
  String get rehearsalMute => 'Muet';

  @override
  String get rehearsalGridFrozen =>
      'Une fois une partie enregistrée, le tempo ne se règle plus ici : chaque prise est calée dessus. Vous pouvez encore déplacer le premier temps.';

  @override
  String get rehearsalNoCompensation =>
      'La latence n\'a pas été mesurée sur cet appareil : une nouvelle prise risque de se retrouver derrière le temps.';

  @override
  String get instrumentVocals => 'Chant';

  @override
  String get instrumentGuitar => 'Guitare acoustique';

  @override
  String get instrumentElectricGuitar => 'Guitare électrique';

  @override
  String get instrumentBassGuitar => 'Basse';

  @override
  String get instrumentDrums => 'Batterie';

  @override
  String get instrumentKeyboard => 'Clavier';

  @override
  String get instrumentSynth => 'Synthé';

  @override
  String get instrumentViolin => 'Violon';

  @override
  String get instrumentSaxophone => 'Saxophone';

  @override
  String get instrumentTrumpet => 'Trompette';

  @override
  String get instrumentPercussion => 'Percussions';

  @override
  String get instrumentOther => 'Autre';

  @override
  String get masterImport => 'Jouer sur un enregistrement';

  @override
  String get masterImporting => 'Importation…';

  @override
  String masterImportFailed(String formats) {
    return 'Ce fichier n\'a pas pu être lu. Formats acceptés : $formats.';
  }

  @override
  String get masterTitle => 'Enregistrement';

  @override
  String get masterRemove => 'Retirer l\'enregistrement';

  @override
  String masterRemoveConfirm(String name) {
    return 'Retirer « $name » de cette répétition ?';
  }

  @override
  String get masterAlign => 'Placer le premier temps fort';

  @override
  String get masterAlignTitle => 'Caler la grille';

  @override
  String get masterAlignHint =>
      'Lancez l\'enregistrement et tapez en rythme pour régler le tempo, puis faites glisser le repère sur le premier temps fort.';

  @override
  String get masterTapTempo => 'Tapez le tempo';

  @override
  String get masterTapMore => 'Continuez à taper…';

  @override
  String masterDownbeatAt(String time) {
    return 'Premier temps fort à $time';
  }

  @override
  String get masterNudgeBack => '10 ms plus tôt';

  @override
  String get masterNudgeForward => '10 ms plus tard';

  @override
  String get masterCheck => 'Écouter deux mesures';

  @override
  String get masterDone => 'Terminé';

  @override
  String get masterVideoAudioOnly =>
      'Les vidéos sont importées pour leur audio uniquement.';

  @override
  String get masterMetronomeOff =>
      'Le clic est coupé : c\'est l\'enregistrement qui donne le tempo.';

  @override
  String get nearbyTitle => 'À proximité';

  @override
  String get nearbyShare => 'Partager cette répétition';

  @override
  String get nearbyHint =>
      'Faites scanner ce code aux autres, ou envoyez-leur le lien ci-dessous.';

  @override
  String get nearbyStop => 'Arrêter le partage';

  @override
  String get nearbyStart => 'Partager';

  @override
  String get nearbyNoNetwork =>
      'Cet appareil n\'est sur aucun réseau. Rejoignez le même Wi-Fi que les autres, ou activez un partage de connexion.';

  @override
  String get nearbyWaiting => 'En attente de quelqu\'un…';

  @override
  String nearbyPeers(int count) {
    return '$count connectés';
  }

  @override
  String get nearbyJoin => 'Rejoindre une répétition';

  @override
  String get nearbyScan => 'Scanner le code';

  @override
  String get nearbyConnecting => 'Connexion…';

  @override
  String get nearbySyncing => 'Synchronisation…';

  @override
  String get nearbySynced => 'À jour';

  @override
  String nearbySyncedWith(int takes) {
    return '$takes parties reçues';
  }

  @override
  String nearbyFailed(String reason) {
    return 'Synchronisation impossible : $reason';
  }

  @override
  String get nearbyWrongCode => 'Ce code ne correspond pas à cette répétition.';

  @override
  String get nearbyScanUnsupported =>
      'Cet appareil n\'a pas de scanner. Saisissez le code affiché sur l\'autre appareil.';

  @override
  String nearbyHostAddress(String host, int port) {
    return '$host · port $port';
  }

  @override
  String get syncStepHandshake => 'Prise de contact';

  @override
  String get syncStepManifest => 'Comparaison';

  @override
  String get syncStepSending => 'Envoi';

  @override
  String get syncStepReceiving => 'Réception';

  @override
  String get syncStepDone => 'Terminé';

  @override
  String get nearbyLink => 'Lien';

  @override
  String get nearbyCopyLink => 'Copier le lien';

  @override
  String get nearbyCopied => 'Copié';

  @override
  String get nearbyLinkHint =>
      'Pas de caméra sur l\'autre appareil ? Copiez ce lien et envoyez-le-lui — il le colle dans Rejoindre.';

  @override
  String get nearbyPasteLink => 'Collez le lien de l\'autre appareil';

  @override
  String get nearbyPasteFromClipboard => 'Coller';

  @override
  String get nearbyLooksLikeCode =>
      'C\'est le code court, qui ne suffit pas à lui seul. Copiez le lien complet depuis l\'autre appareil.';

  @override
  String get nearbyNotALink =>
      'Ce n\'est pas un lien de répétition GrooveForge.';

  @override
  String get nearbyScanTitle => 'Visez le code avec la caméra';

  @override
  String get nearbyScanHint =>
      'Maintenez-la bien en face du code affiché sur l\'autre appareil.';

  @override
  String get nearbyScanPermission =>
      'GrooveForge a besoin de la caméra pour lire le code. Vous pouvez aussi coller le lien.';

  @override
  String get nearbyScanOr => 'ou';

  @override
  String get nearbyScanOpen => 'Scanner un code';

  @override
  String get joinIdentityTitle => 'Qui êtes-vous ?';

  @override
  String get joinIdentityHint => 'Les autres verront ce nom sur votre partie.';

  @override
  String get joinIdentityConfirm => 'Rejoindre';

  @override
  String get rehearsalDeleteTake => 'Supprimer cet enregistrement';

  @override
  String rehearsalTakeDropped(int ms) {
    return 'Cette prise a perdu $ms ms d\'audio et ne sera pas calée sur le clic. Réenregistrez-la.';
  }

  @override
  String get rehearsalCleanTake => 'Enlever la fuite du haut-parleur';

  @override
  String get rehearsalCleaning => 'Suppression du haut-parleur…';

  @override
  String get rehearsalCleanDone =>
      'Fuite du haut-parleur enlevée. L\'original est conservé à côté.';

  @override
  String get rehearsalCleanFailed =>
      'Impossible d\'enlever le haut-parleur de cette prise.';

  @override
  String rehearsalDeleteTakeConfirm(String instrument) {
    return 'Supprimer votre enregistrement de $instrument ? Les autres le perdront aussi à la prochaine synchronisation.';
  }

  @override
  String rehearsalOthersPart(String name) {
    return 'Partie de $name';
  }

  @override
  String get rehearsalYourPart => 'Votre partie';

  @override
  String get liveConnected =>
      'Connecté — les parties arrivent au fur et à mesure';

  @override
  String get liveRefresh => 'Synchroniser maintenant';

  @override
  String get rehearsalRemovePart => 'Supprimer cette partie';

  @override
  String rehearsalRemovePartConfirm(String instrument) {
    return 'Supprimer votre partie de $instrument ? Elle disparaît pour tout le monde, avec ce qui y a été enregistré.';
  }

  @override
  String get rehearsalRecordFromRack => 'Enregistrer depuis le rack';

  @override
  String get rehearsalInputRack => 'Rack';

  @override
  String get rehearsalPartActions => 'Plus';

  @override
  String get rehearsalMemberHere => 'Présent';

  @override
  String get rehearsalMemberAway => 'Non connecté';

  @override
  String get rehearsalsJoin => 'Rejoindre un morceau';

  @override
  String get guideTabRehearsals => 'Répétitions';

  @override
  String get guideRehearsalIntroTitle => 'Répéter ensemble';

  @override
  String get guideRehearsalIntroBody =>
      'L\'onglet Répéter sert à un groupe qui apprend un morceau. Chacun enregistre sa partie sur un clic commun, sur son propre appareil, et chaque appareil finit par avoir toutes les parties.\n\nRien n\'est envoyé sur Internet. Les appareils se parlent directement, donc une répétition marche même dans une salle sans connexion.';

  @override
  String get guideRehearsalStartTitle => 'Démarrer un morceau';

  @override
  String get guideRehearsalStartBody =>
      'Démarrez un morceau, nommez-le et indiquez ce que vous jouez. Réglez le tempo et la mesure, ou tapez le tempo si vous préférez le sentir plutôt que le compter.\n\nPour jouer sur un enregistrement, importez-le comme piste maître : MP3, FLAC et WAV partout, et sur Android aussi M4A, AAC et le son d\'une vidéo. Tapez ensuite le tempo et glissez le repère sur le premier temps, pour que les mesures tombent sur la musique. Le clic se coupe alors : c\'est l\'enregistrement qui donne le tempo.';

  @override
  String get guideRehearsalRecordTitle => 'Enregistrer sa partie';

  @override
  String get guideRehearsalRecordBody =>
      'Ajoutez une partie pour votre instrument et appuyez sur enregistrer. Un décompte joue d\'abord, deux mesures par défaut, et l\'enregistrement commence sur le premier temps.\n\nChaque appareil met un instant à jouer le son et un autre à l\'enregistrer, ce qui mettrait votre prise en retard sur les autres. L\'app mesure ce retard sur votre appareil et recale votre prise d\'autant : ce que vous jouez sur le temps tombe sur le temps. Mesurez-le une fois avec Calibrer dans le morceau, ou depuis les Préférences, et de nouveau quand vous changez de casque ou passez sur une enceinte Bluetooth : le retard dépend du matériel, pas du morceau.\n\nVous enregistrez vos parties, pas celles des autres. Les vôtres peuvent être refaites ou supprimées autant de fois que vous voulez.';

  @override
  String get guideRehearsalMonitoringNote =>
      'Enregistrez au casque, ou avec un micro externe éloigné du haut-parleur. Avec le haut-parleur intégré, le micro entend le clic et les parties déjà enregistrées, et tout se retrouve dans votre prise.';

  @override
  String get guideRehearsalShareTitle => 'Réunir le groupe';

  @override
  String get guideRehearsalShareBody =>
      'La première fois, une personne ouvre le morceau et touche l\'icône de partage ; les autres le rejoignent depuis l\'onglet Répéter, avec Rejoindre un morceau : sur un téléphone ils scannent le code, sur un ordinateur ils collent le lien. Ensuite, les appareils se connaissent : il suffit d\'ouvrir le même morceau, et ils se retrouvent en quelques secondes.\n\nUn point à côté de chaque partie indique si son musicien est connecté. Ce que vous enregistrez arrive chez tout le monde dès que vous arrêtez, et ce que vous avez manqué arrive la prochaine fois que vous êtes réunis.';

  @override
  String get guideRehearsalHotspotTitle => 'Quand il n\'y a pas de Wi-Fi';

  @override
  String get guideRehearsalHotspotBody =>
      'Tout le monde doit être sur le même réseau. Les téléphones en données mobiles ne se voient pas, et les salles de répétition ont rarement un Wi-Fi utilisable : une personne crée donc le réseau.\n\n1. Un téléphone active son partage de connexion, dans les réglages du téléphone (en général sous Connexions ou Réseau).\n2. Les autres rejoignent ce réseau depuis leurs réglages Wi-Fi, comme n\'importe quel réseau.\n3. Tout le monde ouvre le morceau. Les appareils se retrouvent en quelques secondes.\n\nCe n\'est pas forcément la même personne à chaque fois : si l\'hôte habituel est absent, quelqu\'un d\'autre active le sien et les autres s\'y connectent. Il n\'y a rien à rescanner.';

  @override
  String get guideRehearsalHotspotNote =>
      'Le partage des parties ne consomme aucune donnée mobile : rien ne sort de la pièce. Certains téléphones demandent d\'activer les données mobiles avant de partager la connexion, mais la répétition elle-même n\'en consomme pas.';

  @override
  String get rehearsalTakePending => 'Pas encore transmise';

  @override
  String get rehearsalSyncIncomplete =>
      'Restez connectés : tout le monde n\'a pas encore les dernières prises.';

  @override
  String get rehearsalTakeAwaitingAudio => 'En attente de l\'audio';

  @override
  String get rehearsalTempoTitle => 'Tempo';

  @override
  String get rehearsalTuneTempo => 'Tempo du morceau';

  @override
  String get rehearsalTuneTempoHint =>
      'Partagé avec le groupe. Les enregistrements sont recalculés en conséquence.';

  @override
  String get rehearsalPracticeSpeed => 'Vitesse de travail';

  @override
  String get rehearsalPracticeSpeedHint =>
      'Sur cet appareil uniquement. Ralentissez un passage sans changer la hauteur.';

  @override
  String rehearsalPracticeSpeedValue(int percent) {
    return '$percent %';
  }

  @override
  String get rehearsalRendering => 'Ajustement des enregistrements…';

  @override
  String get rehearsalMeterFrozen =>
      'Mesure verrouillée : une partie est déjà enregistrée dessus.';

  @override
  String get rehearsalCalibrate => 'Calibrer';

  @override
  String get rehearsalCalibrateTitle => 'Mesurer cet appareil';

  @override
  String get rehearsalCalibrateBody =>
      'Votre appareil met un instant à sortir le son, et un autre à le capter. Ce retard mettrait chaque prise derrière le temps : on le mesure une fois, puis on le retranche de ce que vous enregistrez.\n\nLa mesure joue quelques brefs balayages et les guette au retour dans le micro — encore faut-il qu\'elle puisse les entendre :\n\n•  Utilisez le haut-parleur, pas un casque. Au casque, le micro n\'entend rien et la mesure échoue.\n•  Montez le volume.\n•  Gardez le silence pendant les quelques secondes nécessaires.\n\nRefaites la mesure après être passé sur une enceinte ou un casque Bluetooth : le retard appartient au matériel, pas au morceau, et le Bluetooth en ajoute beaucoup.';

  @override
  String get rehearsalCalibrateStart => 'Mesurer maintenant';

  @override
  String get rehearsalRemoveMember => 'Retirer ce musicien';

  @override
  String rehearsalRemoveMemberConfirm(String name, int count) {
    return 'Retirer $name de ce morceau ? Ses $count enregistrement(s) partent aussi, sur tous les appareils.';
  }

  @override
  String get rehearsalRemoveMemberHere =>
      'Pour un appareil définitivement parti. Ses parties partent aussi.';

  @override
  String get rehearsalDocuments => 'Partitions';

  @override
  String get rehearsalDocumentsEmpty => 'Aucune partition';

  @override
  String get rehearsalDocumentsEmptyHint =>
      'Ajoutez une partition, une grille ou une photo. Tout le monde en reçoit une copie.';

  @override
  String get rehearsalDocumentAdd => 'Ajouter une partition';

  @override
  String get rehearsalDocumentRemove => 'Retirer';

  @override
  String rehearsalDocumentRemoveConfirm(String name) {
    return 'Retirer « $name » de ce morceau ? Elle disparaît de tous les appareils.';
  }

  @override
  String rehearsalDocumentAddedBy(String name) {
    return 'Ajouté par $name';
  }

  @override
  String rehearsalDocumentSize(int kb) {
    return '$kb ko';
  }

  @override
  String get rehearsalDocumentWaiting => 'En attente du fichier';

  @override
  String get rehearsalDocumentNoViewer =>
      'Aucune application de cet appareil ne peut ouvrir ce fichier.';

  @override
  String get rehearsalChordGrid => 'Accords';

  @override
  String get rehearsalChordGridEmpty => 'Écrire les accords';

  @override
  String get rehearsalChordAddBar => 'Ajouter une mesure';

  @override
  String get rehearsalChordRemoveBar => 'Supprimer cette mesure';

  @override
  String rehearsalChordBar(int bar) {
    return 'Mesure $bar';
  }

  @override
  String get rehearsalChordSlots => 'Accords par mesure';

  @override
  String get rehearsalChordHint => 'Am7, C#m7, Gm7b5, C6/9, Am(M7)/B…';

  @override
  String get rehearsalChordInvalid => 'Accord illisible';

  @override
  String get rehearsalChordExpand => 'Afficher toute la grille';

  @override
  String get rehearsalChordCollapse => 'Réduire à une ligne';

  @override
  String get rehearsalChordClear => 'Effacer';

  @override
  String get rehearsalChordSave => 'Enregistrer';

  @override
  String rehearsalChordBarCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mesures',
      one: '1 mesure',
    );
    return '$_temp0';
  }

  @override
  String rehearsalRouteUncalibrated(String device) {
    return '$device n\'a pas été mesuré. Une prise enregistrée dessus se retrouvera nettement derrière le temps.';
  }

  @override
  String get rehearsalRouteBluetoothHint =>
      'Le Bluetooth ajoute un retard important, qui varie d\'un casque à l\'autre.\n\nLe micro ne peut pas entendre votre casque à travers l\'air : pendant la mesure, plaquez un écouteur contre le micro du téléphone. Il entendra ainsi les balayages revenir par le casque et mesurera le vrai retard, Bluetooth compris.';

  @override
  String get rehearsalRouteWiredHint =>
      'Un casque filaire est branché : les balayages sortent dans le casque, pas dans le haut-parleur.\n\nPendant la mesure, plaquez un écouteur contre le micro du téléphone et gardez le silence. Si votre casque a son propre micro, plaquez l\'écouteur contre celui-ci.';

  @override
  String get audioRouteWired => 'Votre casque filaire';

  @override
  String get masterZoomIn => 'Zoom avant';

  @override
  String get masterZoomOut => 'Zoom arrière';

  @override
  String get masterZoomReset => 'Tout l\'enregistrement';

  @override
  String get masterSkipSilence => 'Passer le silence';

  @override
  String get masterBpmFiner => 'Ralentir de 0,1';

  @override
  String get masterBpmFaster => 'Accélérer de 0,1';

  @override
  String masterZoomLevel(int zoom) {
    return '×$zoom';
  }

  @override
  String get masterBeatLinesHint =>
      'Les traits rouges sont les temps. Zoomez et ajustez le tempo jusqu\'à ce qu\'ils tombent sur le son.';

  @override
  String get rehearsalTempoFromMaster =>
      'Donné par l\'enregistrement — se règle sur l\'écran de calage de la grille.';

  @override
  String get patchViewBackTooltip => 'Revenir aux faces avant';

  @override
  String get audioOutputPathTitle => 'Chemin de sortie audio';

  @override
  String audioOutputPathFast(String ms) {
    return 'Faible latence (buffer de $ms ms).';
  }

  @override
  String audioOutputPathFastShared(String ms) {
    return 'Faible latence, endpoint partagé (buffer de $ms ms). Quelques millisecondes de plus qu\'en exclusif ; rien à faire.';
  }

  @override
  String get audioOutputPathSlow =>
      'Chemin lent : Android a refusé la faible latence pour ce flux. Changer de périphérique de sortie peut la rétablir.';

  @override
  String get audioOutputPathLatched =>
      'Chemin lent, verrouillé pour cette session : GrooveForge a abandonné la faible latence après une défaillance du service audio du téléphone. Le jeu accusera un retard — de l\'ordre d\'un quart de seconde — tant que vous ne l\'aurez pas rétablie ci-dessous.';

  @override
  String get audioOutputPathUsbDirect =>
      'La sortie USB directe pilote le son, la latence d\'Android ne s\'applique donc pas.';

  @override
  String get audioOutputPathNoStream =>
      'Aucun flux audio ouvert pour l\'instant.';

  @override
  String get audioOutputPathRestore => 'Rétablir la faible latence';

  @override
  String get audioOutputPathRestoring => 'Réouverture du flux audio…';

  @override
  String get audioOutputPathRestoreFailed =>
      'La faible latence est toujours refusée. Redémarrer GrooveForge la réinitialise ; si elle retombe aussitôt, c\'est le service audio de ce téléphone qui échoue sur le chemin rapide.';

  @override
  String get audioOutputPathIndicatorTooltip =>
      'Le son est en retard — touchez pour en savoir plus';

  @override
  String get audioOutputPathRestartHint =>
      'Fermer complètement GrooveForge réinitialise aussi ce verrou, et c\'est le geste le plus rapide si vous êtes sur scène.';

  @override
  String get ccReleaseValueTitle => 'Valeur neutre au relâchement';

  @override
  String get ccReleaseValueHelp =>
      'Pour les ribbons et touch strips qui retombent à 0 quand on lève le doigt. À laisser désactivé pour les potentiomètres, faders, molettes, pédales et pads. Si votre contrôleur a un mode hold ou latch, utilisez-le pour garder la dernière valeur.';

  @override
  String ccReleaseValueLabel(int value) {
    return 'Valeur : $value';
  }

  @override
  String ccReleaseValueSummary(int value) {
    return 'revient à $value au relâchement';
  }

  @override
  String ccReleaseValueDialogTitle(int cc) {
    return 'CC $cc : relâchement';
  }

  @override
  String get guideTabStart => 'Pour commencer';

  @override
  String get guideTabModules => 'Modules';

  @override
  String get guideRulesTitle => 'Comment le son circule entre les modules';

  @override
  String get guideRulesIntro =>
      'Touchez l\'icône de câble en haut du rack pour voir l\'arrière des modules. C\'est là que vous les reliez par des câbles.';

  @override
  String get guideRuleInstrument =>
      'Un instrument joue tout seul dans les haut-parleurs. Pas besoin de câble pour l\'entendre.';

  @override
  String get guideRuleColours =>
      'Les câbles jaunes transportent les notes (MIDI), d\'un clavier vers un instrument. Les câbles rouges et blancs transportent le son, à gauche et à droite.';

  @override
  String get guideRuleEffect =>
      'Pour placer un effet après un instrument, reliez les AUDIO OUT L et R de l\'instrument aux AUDIO IN L et R de l\'effet. Ce qui sort de l\'effet part dans les haut-parleurs.';

  @override
  String get guideRuleDraw =>
      'Pour tirer un câble, appuyez longuement sur une prise et glissez jusqu\'à une autre. Les prises compatibles s\'allument pendant que vous glissez.';

  @override
  String get guideWatchClip => 'Voir la vidéo';

  @override
  String get guideRecipeScaleTitle => 'Jouer dans une gamme';

  @override
  String get guideRecipeScaleSteps =>
      'Chaque nouveau projet contient un clavier et un module Xen.\nTenez une touche et touchez une gamme, par exemple Blues. Xen s\'allume, et la touche tenue devient la tonique.\nOuvrez Famille pour d\'autres traditions : maqamat, ragas, gammes japonaises et bien d\'autres.';

  @override
  String get guideRecipeScaleResult =>
      'Les touches grises sont hors de la gamme : si vous en jouez une, vous entendez la note la plus proche qui va bien.';

  @override
  String get guideRecipeEffectTitle => 'Ajouter un effet au clavier';

  @override
  String get guideRecipeEffectSteps =>
      'Touchez + et choisissez un effet, par exemple Reverb.\nTouchez l\'icône de câble en haut.\nAppuyez longuement sur la prise rouge AUDIO OUT L du clavier et glissez-la sur l\'AUDIO IN L de l\'effet. Puis la blanche, R sur R.\nTouchez la flèche de retour et jouez.';

  @override
  String get guideRecipeEffectResult =>
      'Vous entendez le clavier à travers l\'effet. Tournez ses boutons pour changer le son.';

  @override
  String get guideRecipeRemoveTitle => 'Retirer un câble ou un module';

  @override
  String get guideRecipeRemoveSteps =>
      'Un câble : dans la vue de câblage, touchez le petit ✕ au milieu du câble, puis Déconnecter.\nUn module : touchez la corbeille en haut du module, puis Supprimer. Ses câbles partent avec lui.';

  @override
  String get guideRecipeRemoveResult => '';

  @override
  String get guideRecipeGuitarTitle => 'Jouer de la guitare au clavier';

  @override
  String get guideRecipeGuitarSteps =>
      'Touchez + et choisissez Riff.\nDans la vue de câblage, glissez la prise jaune MIDI OUT du clavier sur le MIDI IN de Riff.\nJouez : vous entendez le piano et la guitare ensemble.\nPour n\'entendre que la guitare, réglez le menu de son du clavier sur Aucune (MIDI seulement).';

  @override
  String get guideRecipeGuitarResult =>
      'Riff n\'a pas de touches : c\'est le clavier qui lui envoie les notes.';

  @override
  String get guideRecipeAmpTitle => 'Brancher la guitare dans l\'ampli';

  @override
  String get guideRecipeAmpSteps =>
      'Touchez + et choisissez Ampli.\nDans la vue de câblage, glissez l\'AUDIO OUT L de Riff sur l\'AUDIO IN L de l\'Ampli, puis R sur R.\nJouez, et tournez le bouton Drive de l\'Ampli.';

  @override
  String get guideRecipeAmpResult =>
      'La guitare claire devient crunch ou saturée.';

  @override
  String get guideRecipeControllerTitle => 'Brancher un contrôleur MIDI';

  @override
  String get guideRecipeControllerSteps =>
      'Branchez-le en USB (avec un adaptateur OTG sur un téléphone), ou allumez un contrôleur MIDI Bluetooth.\nOuvrez les Préférences avec l\'icône d\'engrenage.\nSous Connexion MIDI, touchez Connecter un appareil MIDI et choisissez-le.';

  @override
  String get guideRecipeControllerResult =>
      'Il joue le module dont le badge CANAL MIDI correspond au canal qu\'il envoie, en général le 1.';

  @override
  String get guideRecipeLearnTitle => 'Associer un bouton';

  @override
  String get guideRecipeLearnSteps =>
      'Touchez l\'icône de curseurs en haut d\'un module.\nTouchez Learn à côté d\'un réglage, par exemple Palm mute.\nTournez un bouton ou frappez un pad de votre contrôleur.';

  @override
  String get guideRecipeLearnResult =>
      'Le réglage suit maintenant votre matériel. L\'association est enregistrée avec le projet.';

  @override
  String get guideRecipeDrumsTitle => 'Lancer une batterie';

  @override
  String get guideRecipeDrumsSteps =>
      'Touchez + et choisissez Générateur de batterie.\nChoisissez un pattern dans le menu.\nActivez Actif et appuyez sur lecture en haut.';

  @override
  String get guideRecipeDrumsResult =>
      'Le rythme suit le tempo de la barre de transport.';

  @override
  String get guideRecipeLoopTitle => 'Enregistrer une boucle';

  @override
  String get guideRecipeLoopSteps =>
      'Touchez + et choisissez Looper Audio.\nDans la vue de câblage, reliez les AUDIO OUT L et R du clavier aux AUDIO IN L et R du looper.\nAppuyez sur le bouton d\'enregistrement du looper. L\'enregistrement commence au premier temps de la mesure suivante.\nJouez, puis appuyez de nouveau : l\'enregistrement s\'arrête à la fin de la mesure et la boucle démarre. Appuyez encore pour ajouter une couche.';

  @override
  String get guideRecipeLoopResult =>
      'Si le tempo était arrêté, il démarre et vous laisse une mesure pour vous préparer.';

  @override
  String get guideRecipeProjectsTitle => 'Sauvegarder et ouvrir un projet';

  @override
  String get guideRecipeProjectsSteps =>
      'Touchez l\'icône de dossier en haut.\nEnregistrer sous… écrit vos modules, câbles et réglages dans un fichier .gf.\nNouveau projet repart d\'un clavier et de Xen. Ce qui n\'est pas enregistré est perdu.\nOuvrir un projet charge un fichier enregistré.';

  @override
  String get guideRecipeProjectsResult =>
      'L\'app garde aussi votre session en cours d\'un lancement à l\'autre, sauf dans la démo web.';

  @override
  String get guideModulesIntro =>
      'Tout ce que le bouton + en bas du rack peut ajouter. Glissez la poignée à gauche d\'un module pour le déplacer.';

  @override
  String get guideVocoderNote =>
      'Utilisez un casque ou des enceintes filaires : le Bluetooth ajoute trop de retard pour chanter en direct.';

  @override
  String get guideJackLegendTitle => 'Couleurs des prises';

  @override
  String get guideJackMidi => 'notes et commandes (MIDI)';

  @override
  String get guideJackAudioL => 'son, gauche';

  @override
  String get guideJackAudioR => 'son, droite';

  @override
  String get guideJackSend => 'boucle d\'effets';

  @override
  String get guideJackData => 'la gamme et l\'accord en cours';

  @override
  String get guideJackTune =>
      'l\'accordage des gammes entre les touches du piano';

  @override
  String get guideMidiHardwareStep3 =>
      'Il joue le module dont le badge CANAL MIDI correspond au canal qu\'il envoie, en général le 1. Touchez le badge d\'un module pour changer son canal.';
}
