# Fonctionnalités de GrooveForge

GrooveForge a d’abord été conçu pour **apprendre les gammes**. Le module **Xen** verrouille un clavier sur l’une de 92 gammes — tenez une note, appuyez sur une gamme — et le réaccorde quand la gamme n’est pas tempérée ; le plugin **Jam Mode** fait de même depuis un instrument maître, en suivant un accord ou une note de basse jouée sur un autre canal. Les notes « hors ton » sont ramenées au degré le plus proche, et le clavier fournit un retour visuel. À partir de ce cœur, l’application est devenue une station musicale multi-plateforme complète : rack de plugins avec synthèse **multi-timbrale**, **hébergement VST3** (bureau), **boucleur MIDI**, et instruments intégrés comme le vocodeur, le Stylophone et le Theremin. Elle tourne sous Linux, macOS, Windows, Android et en application web (WASM).

---

## Plateforme et déploiement

*   **Bureau (Linux, macOS, Windows)**  
    Prise en charge complète : synthèse FluidSynth, vocodeur (C natif / FFI), hébergement de plugins VST3, audio ALSA (Linux) / CoreAudio (macOS) / WASAPI (Windows). Linux utilise un processus FluidSynth en arrière-plan pour une faible latence ; macOS et Windows utilisent des moteurs en processus.

*   **Android**  
    Clavier GrooveForge avec SoundFont et vocodeur, Stylophone, Theremin (y compris mode CAM), Jam Mode, boucleur MIDI et MIDI externe. L’hébergement VST3 est réservé au bureau. Utilise Oboe pour l’audio basse latence.

*   **iOS**  
    Non pris en charge pour l’instant : la compilation iOS n’a jamais été testée.

*   **Web (WASM)**  
    Compilation Flutter web déployable sur GitHub Pages : le site marketing et la documentation sont servis à la racine du dépôt, et l’application WASM interactive sous `/demo/` (par ex. `https://<user>.github.io/<repo>/demo/`). Un miroir français du manuel est disponible sous `/fr/` ; les pages longues utilisent `docs/features.fr.md` et `docs/privacy.fr.md` sur `/fr/features/` et `/fr/privacy/`. La lecture SF2 passe par un pont JavaScript SpessaSynth ; le Stylophone et le Theremin utilisent l’API Web Audio. « Enregistrer sous… » pour un projet déclenche le téléchargement d’un fichier `.gf`. Aucun stockage persistant côté web ; chaque session repart des réglages par défaut.

---

## Rack de plugins et vue patch

*   **Rack dynamique**  
    Liste ordonnée de slots de plugins par glisser-déposer. Ajoutez, supprimez et réordonnez les slots à tout moment. Chaque slot a son propre canal MIDI (ou le canal 0 partagé pour les effets MIDI comme Jam Mode et le Looper).

*   **Feuille d’ajout de plugin**  
    Choix parmi : clavier GrooveForge, piano virtuel, vocodeur, Stylophone, Theremin, Jam Mode (une seule instance), boucleur MIDI (une seule instance) ou parcourir les VST3 (bureau uniquement).

*   **Vue patch (arrière du rack)**  
    Activable via l’icône câble dans la barre d’application. Chaque slot affiche un panneau arrière avec des jacks colorés : MIDI IN / MIDI OUT, audio IN G/D, audio OUT G/D, envoi/retour, et données (accord/gamme pour Jam Mode). Les câbles sont des courbes de Bézier ; appui long sur une sortie pour commencer un câble, relâchez sur une entrée compatible pour connecter. Touchez un câble pour le déconnecter.

*   **Graphe audio**  
    Un graphe orienté valide la compatibilité des ports, empêche les arêtes en double et détecte les cycles. Le routage MIDI et audio est enregistré dans les projets `.gf` et restauré au chargement.

---

## Instruments et plugins intégrés

### Clavier GrooveForge

*   **Moteur multi-timbral**  
    Jusqu’à 16 canaux MIDI indépendants, chacun avec sa propre SoundFont (`.sf2`), banque et programme. Chargez plusieurs soundfonts et assignez des instruments différents par canal.

*   **Vocodeur par slot**  
    Vocodeur optionnel sur chaque slot clavier : le micro module la porteuse (dent de scie, carré, choral ou mode naturel/PSOLA « autotune »). Pitch bend et vibrato (CC n°1) pris en charge. Gain micro et périphérique réglables dans la barre de réglages audio ou les préférences.

*   **Configuration clavier par slot**  
    Touchez l’icône d’accord (⊞) à côté du badge de canal MIDI pour définir le nombre de touches visibles, la hauteur des touches (Compact / Normal / Large / Très large), les gestes vertical/horizontal (pitch bend, vibrato, glissando) et le CC de destination du aftertouch. Stocké dans le fichier de projet.

### Vocoder (GFPA)

*   **Slot dédié**  
    Canal MIDI propre, piano à l’écran et jacks arrière. Plusieurs slots vocodeur peuvent coexister.

*   **Formes d’onde**  
    Dent de scie, carré, choral et naturel. Le mode naturel utilise un décaleur de hauteur PSOLA (style autotune) qui préserve le timbre de la voix plutôt qu’un banc de filtres.

*   **Pitch bend et vibrato**  
    Pitch bend MIDI (±2 demi-tons) et CC n°1 (molette de modulation) pour la profondeur de vibrato. Même configuration clavier par slot que le clavier GF et le piano virtuel.

### Stylophone (GFPA)

*   **Bande chromatique monophonique 25 touches**  
    Quatre formes d’onde (CARR, SCIE, SIN, TRI), legato sans clic, octave ±2. Le bouton VIB active un LFO 5,5 Hz ±0,5 demi-ton (vibration type bande). MUET coupe le synthé intégré tandis que MIDI OUT continue d’envoyer les notes.

*   **MIDI OUT**  
    Connexion à un clavier GF, un VST3 ou le Looper dans la vue patch.

### Theremin (GFPA)

*   **Pavé tactile**  
    Position verticale = hauteur, horizontale = volume. Oscillateur sinus natif en C avec portamento (~42 ms), LFO de vibrato 6,5 Hz (0–100 %), note de base et plage configurables. Hauteur du pavé (S/M/L/XL) et MIDI OUT / MUET comme le Stylophone.

*   **Mode CAM (Android, iOS, macOS)**  
    La proximité de la main via la caméra avant (autofocus ou repli luminosité/contraste) contrôle la hauteur. Aperçu semi-transparent derrière l’orb ; miroir selfie sur mobile. Les autorisations sont décrites dans la politique de confidentialité.

### Jam Mode (GFPA, instance unique)

*   **Maître → cibles**  
    Un slot Jam Mode choisit un canal maître (par ex. un clavier ou le piano virtuel). Lorsque le maître joue, tous les slots cibles (claviers, vocodeurs) se verrouillent sur la même gamme. Plusieurs cibles par slot Jam.

*   **Détection**  
    Mode accords : la détection d’accords en temps réel fixe la fondamentale de la gamme. Mode note de basse : la note la plus grave tenue sur le maître fixe la fondamentale (par ex. ligne de basse).

*   **Types de gammes**  
    Standard, jazz, blues, rock, pentatonique, dorien, mixolydien, mineur harmonique, mineur mélodique, gamme par tons, diminuée, asiatique, orientale, classique. Le nom et le type de gamme s’affichent sur un LCD ; le type est sélectionnable dans le slot.

*   **Verrouillage BPM**  
    Synchronisation optionnelle (Désactivé / 1 temps / ½ mesure / 1 mesure) pour que la fondamentale ne change qu’aux frontières de temps. Utilise le BPM du transport global.

*   **Épingler sous le transport**  
    Bandeau compact d’une ligne (nom du slot, voyant ON/OFF, LCD de gamme) sous la barre de transport pour un accès rapide sans faire défiler.

### Xen (GFPA, gammes et microtonalité)

*   **Tenez une note, appuyez sur une gamme**  
    La note tenue devient la tonique et le clavier se verrouille sur la gamme construite dessus. Contrairement au Jam Mode, aucun canal maître n'est nécessaire : un clavier, un geste. La tonique ne bouge plus jusqu'au geste suivant, si bien que le module accompagne votre propre harmonie plutôt que de suivre celle d'un autre.

*   **92 gammes réparties en onze familles**  
    Modes occidentaux ; maqamat arabes et turcs ; dastgah persans ; ragas indiens en intonation juste ; modes chinois, japonais et coréens ; heptatonique égal thaï ; gamelans javanais et balinais ; qenet éthiopiens et amadinda ougandais ; cornemuse écossaise, hardingfele et chant byzantin ; tempéraments historiques ; et divisions égales de 13 à 31 tons, Bohlen-Pierce, le décatonique de Blackwood et les alpha, beta et gamma non octaviantes de Wendy Carlos.

*   **Deux étages, câblés séparément**  
    SNAP quantifie les notes hors gamme ; TUNE applique l'intonation propre de la gamme. Chacun a son jack en face arrière : un clavier peut être verrouillé sans être réaccordé, ou réaccordé sans être verrouillé.

*   **Réaccordage polyphonique**  
    Passe par une table de tuning MIDI complète plutôt que par le pitch bend : chaque note d'un accord sonne à sa propre hauteur. Le pitch bend agit par canal et ne peut déplacer qu'une note à la fois — c'est ce qui limite le plugin Microtone à une seule voix microtonale.

*   **Retour visuel**  
    Les touches hors gamme sont grisées sur le clavier à l'écran ; les touches réaccordées portent une bande turquoise et leur écart en cents. Chaque gamme indique d'où viennent ses valeurs — exactes pour un tempérament ou une division égale, conventionnelles pour un maqam, moyennées pour un gamelan ou un qenet éthiopien, accordés à l'oreille et différents d'un instrument à l'autre.

*   **Éditeur de gammes, import et export**  
    Créez les vôtres : autant de degrés que vous voulez, un écart par touche, et un mute qui garde un degré jouable et accordé pendant que le snap l'ignore. Import et export de fichiers Scala (.scl), ou du JSON GrooveForge pour un aller-retour fidèle. Les gammes personnelles sont stockées à la fois dans la bibliothèque de l'app et dans le fichier de projet : un .gf se joue correctement sur une machine qui n'a jamais vu cette gamme.

*   **Banc de pads**  
    Associez une gamme par CC matériel, plusieurs à la fois, chacun sautant directement à la sienne. SNAP et TUNE sont mappables séparément.

### Boucleur MIDI (instance unique)

*   **Boucleur MIDI multi-pistes**  
    Jacks MIDI IN / MIDI OUT ; enregistrement depuis toute source connectée (clavier GF, piano virtuel, Stylophone, Theremin, MIDI externe), renvoi en boucle vers les instruments, surdub de couches.

*   **Transport**  
    REC, LECTURE, SURDUB (icône couches), STOP, EFFACER. LCD d’état ; grille d’accords par piste (cellules de mesures défilantes). Muet, inversion (R) et vitesse (½× / 1× / 2×) par piste. Quantification fin d’enregistrement (désactivé / 1/4 / 1/8 / 1/16 / 1/32) par piste ; pastille Q dans la barre de transport.

*   **Persistance**  
    Pistes et grilles d’accords enregistrées dans le `.gf` sous `looperSessions`. Assignation CC globale pour les actions du Looper (enregistrer, lire, surdub, stop, effacer) et bandeau « épinglé sous le transport ».

### Hébergement VST3 (bureau)

*   **Charger n’importe quel .vst3**  
    « Parcourir les VST3 » dans la feuille d’ajout. Les paramètres s’affichent en potentiomètres rotatifs par catégorie ; l’éditeur natif du plugin s’ouvre dans une fenêtre séparée (par ex. X11 sous Linux).

*   **Routage audio**  
    Tracez des câbles audio dans la vue patch ; la sortie d’un plugin peut alimenter l’entrée d’un autre plutôt que le bus principal. Ordre de traitement topologique.

*   **Transport**  
    BPM, lecture/arrêt et position dans la mesure sont transmis au VST3 pour que les effets synchronisés au tempo restent alignés.

---

## Transport et contrôles globaux

*   **Barre de transport**  
    BPM (éditable, incréments ±, molette), tempo au tap, ▶ Lecture / ■ Stop, signature rythmique, LED de pulsation, métronome audible. État enregistré dans le projet.

*   **Barre de réglages audio (repliable)**  
    Sous le transport : gain FluidSynth (Linux), sensibilité micro, périphérique micro, périphérique de sortie (Android). Le chevron affiche ou masque la barre.

---

## Théorie musicale et verrouillage de gamme

*   **Détection d’accords en temps réel**  
    Analyse par canal des notes tenues ; l’interface affiche l’accord courant (par ex. Cmaj7, Fa#m11). « Mémoire sustain » : le dernier accord reste visible (atténué) après relâchement.

*   **Verrouillage de gamme (classique)**  
    Sur un clavier ou un piano virtuel, touchez l’affichage d’accord (ou utilisez un CC assigné) pour verrouiller sur le dernier accord détecté. Les nouvelles notes hors gamme sont alignées sur le degré le plus proche. Le type de gamme (standard, blues, pentatonique, etc.) est sélectionnable par canal. La polyphonie superposée est suivie pour que les glissandos s’articulent proprement.

*   **Verrouillage de gamme Jam Mode**  
    Même alignement et types de gammes, pilotés par le maître Jam Mode (accord ou basse). La coloration des touches (fondamentale, dans la gamme, fausses notes) et les bordures/atténuation optionnelles se configurent dans le slot Jam Mode ou les préférences.

---

## Cartographie CC et matériel

*   **Mapper le matériel vers le MIDI ou des actions**  
    Dans les préférences, assignez des CC physiques aux effets MIDI généraux (volume, expression, réverbération, panoramique, etc.) ou aux actions GrooveForge : soundfont suivant/précédent, programme suivant/précédent, balayage absolu de patch, banque suivante/précédente, cycle de gamme globale, Looper enregistrer/lire/surdub/stop/effacer, muet/non muet des canaux (avec liste de canaux). Même canal, omni ou canal cible fixe.

*   **MIDI externe**  
    Branchez des contrôleurs ; notes et expression (pitch bend, CC, pression de canal) traversent le rack et les câbles. Le piano virtuel et d’autres slots peuvent relayer le MIDI vers le VST3, le Looper ou les instruments.

---

## Projets et persistance

*   **Fichiers de projet .gf**  
    Format JSON : plugins du rack, graphe audio, transport (BPM, signature, métronome), sessions du looper, instantanés des paramètres VST3, configuration clavier et Jam/Looper par slot. Ouvrir / Enregistrer / Enregistrer sous dans le menu projet.

*   **Sauvegarde automatique**  
    La dernière session est auto-enregistrée à chaque changement (bureau et mobile) ; rechargée au prochain lancement. Le web n’a pas de stockage persistant ; utilisez « Enregistrer sous… » pour télécharger un `.gf`.

*   **Enregistrer sous sur toutes les plateformes**  
    Android et web utilisent le sélecteur de fichiers avec les octets du projet : sur le web un téléchargement est déclenché ; sur Android le fichier est écrit à l’emplacement choisi. Linux/macOS/Windows utilisent la boîte de dialogue native et le chemin.

---

## Interface et préférences

*   **Tableau de bord du rack**  
    Les slots indiquent l’activité (par ex. lueur bleue lorsque des notes jouent ou que le Looper lit). Touchez un slot pour ouvrir son panneau ou l’assignation patch.

*   **Préférences**  
    Valeurs par défaut globales pour le nombre de touches, la hauteur des touches, les gestes, le CC d’aftertouch ; liste des périphériques MIDI et cartographie CC ; gain FluidSynth (Linux) ; micro et sortie ; bordures Jam Mode et mise en évidence des fausses notes. Les libellés indiquent quand un réglage peut être surchargé par slot.

*   **Localisation**  
    Anglais et français via `AppLocalizations` Flutter ; toutes les chaînes visibles sont localisées.

---

*Dernière mise à jour : 2026-03-25*
