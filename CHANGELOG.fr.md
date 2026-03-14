# Changelog

Toutes les modifications notables apportées à ce projet seront documentées dans ce fichier.

Le format est basé sur [Keep a Changelog](https://keepachangelog.com/fr/1.0.0/),
et ce projet adhère à la [Gestion Sémantique de Version](https://semver.org/lang/fr/).

## [X.x.x]

### Ajouté
- Plugin GFPA **Stylophone** : clavier à lamelles chromatiques monophonique (2 octaves, 25 touches) joué au toucher ou en glissant le doigt. Décalage d'octave de −2 à +2 via les boutons intégrés dans le slot. Routé vers le canal FluidSynth attribué au slot.
- Plugin GFPA **Thérémine** : grand pad tactile dont l'axe vertical contrôle la hauteur (bas = grave, haut = aigu) et l'axe horizontal contrôle le volume (CC 7). Un orbe violet lumineux suit le doigt. Note de base (C2–C5) et plage (1–4 octaves) réglables via les boutons +/− du slot.
- Les deux plugins apparaissent dans la feuille « Ajouter un plugin » avec des icônes dédiées.
- Liste des futurs plugins GFPA enregistrée dans le backlog : Arpégiateur d'accords, Réverb spectrale, Boîte à rythmes / Séquenceur, Harmoniseur de gamme, Bit-crusher / Lo-fi.

## [2.5.3] - 2026-03-14

### Ajouté
- Modal de configuration du clavier par slot : appuyez sur l'icône de réglage (⊞) juste avant le badge de canal MIDI sur tout slot Clavier ou Piano Virtuel.
- Paramètres disponibles par slot : nombre de touches visibles (remplace le défaut global), hauteur des touches (Compact / Normal / Grand / Très grand), actions de geste vertical et horizontal, CC de destination de l'aftertouch.
- Les hauteurs de touches correspondent à des valeurs en pixels fixes (110 / 150 / 175 / 200 px), rendant le piano utilisable sur téléphone sans modifier la mise en page globale.
- La configuration par slot est sauvegardée dans le fichier projet `.gf` et entièrement rétrocompatible.
- Les labels des Préférences pour le nombre de touches, les gestes et l'aftertouch indiquent désormais qu'ils sont des valeurs par défaut modifiables par slot.

## [2.5.2] - 2026-03-14

### Corrigé
- **Contraste et lisibilité des textes** — tailles de police et opacités augmentées dans le rack Jam Mode, le rack MIDI Looper et la vue arrière (panneau de patch) pour améliorer la lisibilité sur fond sombre :
  - **Vue arrière** : libellés de section (MIDI / AUDIO / DATA) passés de 9 à 10 px et d'un gris quasi invisible à un bleu-gris lisible ; libellés de port (MIDI IN, AUDIO OUT L, etc.) passés de 8 à 10 px ; nom d'affichage et bouton [FACE] éclaircis.
  - **Looper** : badge d'état « IDLE » nettement plus visible (white24 → white54) ; icônes de transport inactives éclaircies ; libellés de piste 10 → 11 px ; cellules de grille d'accords, bascules M/R, puces de vitesse et puce Q toutes passées de 9 à 10 px avec des couleurs inactives plus contrastées ; icônes et texte du bouton épingle éclaircis.
  - **Jam Mode** : libellé ON/OFF du bouton LED 8 → 10 px ; libellés de section MASTER et TARGETS 8 → 10 px ; indication SCALE TYPE 7 → 9 px ; libellés DETECT/SYNC 7 → 9 px ; texte inactif des puces sync et BPM relevé de white30/white38 à white54/white60 ; puce BPM 9 → 11 px ; couleurs des espaces réservés des menus déroulants éclaircies ; bouton épingle éclairci.

## [2.5.1] - 2026-03-14

### Ajouté
- **Barre de réglages audio** — une bande escamotable sous la barre de transport expose les contrôles audio les plus utilisés directement à l'écran : potentiomètre de gain FluidSynth (Linux), potentiomètre de sensibilité micro, liste déroulante de sélection du micro, et liste déroulante de sortie audio (Android). Une icône chevron à gauche de la barre de transport affiche ou masque la bande (ainsi que d'éventuelles futures barres supplémentaires) avec une animation de glissement. Les réglages restent synchronisés avec l'écran des Préférences.
- **Gain FluidSynth configurable** — le gain de sortie du moteur FluidSynth intégré est désormais ajustable par l'utilisateur (plage 0–10) et persisté entre les sessions. La valeur par défaut sur Linux passe de 5,0 à 3,0 pour s'aligner sur les niveaux de sortie des plugins VST ; la valeur sauvegardée est appliquée au démarrage (via le flag `-g`) et en temps réel via la commande `gain` sur l'entrée standard de FluidSynth.
- **Assignations CC globales pour le Looper** — cinq nouveaux codes d'action système (1009-1013) peuvent être assignés à n'importe quel bouton ou potentiomètre CC matériel dans l'écran des préférences CC : Enregistrer/Arrêter, Lecture/Pause, Overdub, Stop et Tout effacer. L'action est transmise au slot Looper MIDI actif unique.
- **CC global de sourdine de canaux (1014)** — un nouveau code d'action système permet à un seul CC matériel de basculer l'état muet d'un ensemble de canaux MIDI simultanément. Dans la boîte de dialogue des préférences CC, sélectionner l'action "Couper / Rétablir les canaux" affiche une liste de cases à cocher (Ch 1–16) ; les canaux sélectionnés sont persistés avec l'assignation. Utile, par exemple, pour couper le canal du vocoder tout en maintenant un instrument d'accompagnement actif, sans débrancher les câbles.
- **Instance unique pour le Jam Mode et le Looper MIDI** — le panneau "Ajouter un plugin" vérifie désormais si un Jam Mode ou un Looper est déjà présent avant d'en insérer un nouveau. Si c'est le cas, le panneau se ferme et un SnackBar indique qu'une seule instance est autorisée. Cela évite les configurations incohérentes et simplifie l'assignation des CC.
- **Quantification à l'arrêt d'enregistrement (6.7)** — chaque piste du looper dispose maintenant d'un réglage de quantification individuel (désactivé / 1/4 / 1/8 / 1/16 / 1/32). Lorsqu'il est activé, tous les décalages en temps des événements enregistrés sont alignés sur la grille la plus proche au moment où l'utilisateur appuie sur stop. Un écart minimal d'un pas de grille entre chaque paire note-on / note-off est imposé pour éviter les notes de durée nulle. Le réglage est stocké dans `LoopTrack.quantize`, persisté dans les fichiers de projet `.gf`, et vaut `off` par défaut.
- **Chip de quantification dans la bande de transport** — un chip compact "Q:…" (ambre, cycle au tap) a été ajouté à la bande de transport à côté de CLEAR, au niveau du slot. Réglez-le avant d'enregistrer ; la grille s'applique à chaque passe d'enregistrement suivante (première prise et overdubs).

### Corrigé
- **En-têtes du Jam Mode et du Looper incorrectement mis en surbrillance / jamais mis en surbrillance** — les slots Jam Mode et Looper n'ont pas de canal MIDI (`midiChannel == 0`), les mappant à l'index de canal 0 — le même que tout instrument sur le canal MIDI 1. Appuyer sur une touche d'un Virtual Piano non connecté mettait à jour `channels[0].activeNotes`, faisant clignoter en bleu les deux racks sans câble de connexion, tandis qu'ils ne s'allumaient jamais pour leur propre activité. Corrigé en routant chaque type de plugin vers son propre listener réactif : le Looper s'allume quand `LooperSession.isPlayingActive` est vrai (envoi actif de MIDI aux slots connectés), le Jam Mode s'allume uniquement quand il est activé ET que le canal maître envoie un signal correspondant au réglage Détect (mode note de basse : au moins une touche maintenue ; mode accord : un accord reconnu), et les slots instruments continuent de s'allumer sur `channelState.activeNotes`.
- **Pitch bend / CC non transmis via câble VP → instrument (MIDI externe)** — les messages MIDI de pitch bend (0xE0), de changement de contrôle (0xB0) et de channel pressure (0xD0) reçus sur le canal d'un slot Virtual Piano sont maintenant transmis via son câble MIDI OUT à chaque slot aval connecté. Auparavant, seuls les Note On/Off étaient relayés ; les messages d'expression étaient silencieusement ignorés.
- **Pitch bend / CC non transmis via câble VP → instrument (piano à l'écran)** — les gestes de glissement sur le widget Virtual Piano (pitch bend, vibrato, tout CC) sont désormais aussi transmis via le câble MIDI OUT du VP aux slots connectés. Ces gestes appelaient auparavant directement `AudioEngine` sur le canal du VP, ignorant entièrement le câblage.
- **Pitch bend inopérant sur le Vocoder** — l'oscillateur porteur du Vocoder répond désormais au pitch bend MIDI. Une nouvelle fonction FFI C `VocoderPitchBend` met à jour un multiplicateur `g_pitchBendFactor` appliqué dans `renderOscillator()` pour les quatre modes de forme d'onde (Saw, Square, Choral, Natural/PSOLA). La plage est de ±2 demi-tons (convention VST).
- **Vibrato (CC#1 / molette de modulation) inopérant sur le Vocoder** — ajout d'un LFO à 5,5 Hz sur l'oscillateur porteur du vocoder, contrôlé par CC#1 (molette de modulation). Profondeur 0 = pas de vibrato ; profondeur 127 = ±1 demi-ton de modulation. Une nouvelle fonction FFI C `VocoderControlChange` et la variable `g_vibratoDepth` contrôlent la profondeur ; `g_effectivePitchFactor` combine désormais pitch bend et vibrato en un seul multiplicateur dans `renderOscillator`.
- **Pitch bend / CC non envoyés aux plugins VST3 via câble** — `VstHostService` expose désormais les méthodes `pitchBend()` et `controlChange()` afin que les messages d'expression arrivant via le câblage VP puissent être transmis aux instruments VST3 (effectif une fois le binding natif `dart_vst_host` ajouté).
- **Volume des soundfonts trop faible** — le gain par défaut de FluidSynth (0.2) produisait une amplitude d'environ 0.1, bien inférieure à la sortie typique des VST. Porté à 5.0 sur Linux (option CLI `-g 5`) et Android (`synth.gain` dans native-lib.cpp), alignant ainsi le volume des soundfonts sur le reste du graphe audio.
- **Raccourci Jam Mode "Épingler sous le transport"** — le bouton d'épinglage du slot Jam Mode fonctionne désormais comme prévu. Épingler un slot Jam Mode insère une bande compacte (nom du slot · LED ON/OFF · LCD de gamme en temps réel) directement sous la barre de transport pour un contrôle rapide sans faire défiler jusqu'au rack. L'état d'épinglage est persisté dans les fichiers `.gf`.
- **Raccourci looper "Épingler sous le transport"** — le bouton d'épinglage du slot looper fonctionne désormais comme prévu. Épingler un looper insère une bande de contrôle compacte (nom du slot · LOOP · STOP · CLEAR · chip Q · LCD d'état) directement sous la barre de transport afin que l'utilisateur puisse contrôler le looper depuis n'importe quel endroit sans faire défiler jusqu'à son slot dans le rack.

## [2.5.0] - 2026-03-13

### Ajouté
- **Looper MIDI (Phase 7.1–7.4)** — nouveau slot rack looper MIDI multi-piste (`LooperPluginInstance`) avec prises MIDI IN / MIDI OUT dans la vue de câblage. Enregistrez du MIDI depuis n'importe quelle source connectée, bouclez-le vers des slots d'instruments et superposez des couches supplémentaires en parallèle (overdub).
- **Service LooperEngine** — moteur de lecture précis à 10 ms avec quantisation de longueur de boucle à la mesure, synchro intelligente sur le temps fort, modificateurs de piste indépendants (mute / inversé / demi-vitesse / double vitesse), et détection d'accord par mesure via `ChordDetector`. Machine d'état : idle → armé → enregistrement → lecture → overdub.
- **Modèle LoopTrack** — chronologie d'événements MIDI sérialisable avec horodatages en temps-battement, modificateurs de vitesse, drapeau inversé, état muet et grille d'accords par mesure (`Map<int, String?>`).
- **Interface panneau avant du looper** — panneau de slot style matériel avec boutons transport REC / PLAY / OVERDUB (icône couches ambre) / STOP / CLEAR ; badge LCD d'état ; grille d'accords par piste (cellules de mesure défilables horizontalement) ; contrôles par piste mute (M), inversé (R) et vitesse (½× / 1× / 2×) ; bascule épingler sous le transport.
- **Overdub** — bouton OD dédié (ambre, icône couches) actif uniquement pendant la lecture d'une boucle. Appuyez pour démarrer une nouvelle couche d'overdub ; rappuyez pour arrêter le passage d'overdub et reprendre la lecture normale. Le bouton REC est désactivé pendant la lecture pour éviter l'écrasement accidentel de la première prise.
- **Persistance du looper** — les pistes enregistrées et les grilles d'accords sont sauvegardées dans les fichiers `.gf` sous `"looperSessions"` et restaurées à l'ouverture du projet/rechargement de la sauvegarde automatique.
- **Assignation CC matériel** — liez n'importe quel CC aux actions du looper (bascule enregistrement, bascule lecture, stop, effacer) par slot.
- **Feuille Ajouter un Plugin** — tuile « Looper MIDI » ajoutée (icône boucle verte).
- 20 nouvelles chaînes localisées pour l'interface du looper (EN + FR).

### Corrigé
- **Silence audio Linux après répétition du looper** — La sortie stdout/stderr de FluidSynth n'était jamais drainée, ce qui remplissait le buffer pipe OS (~64 Ko) après une utilisation prolongée du looper. Une fois plein, FluidSynth se bloquait sur ses propres écritures de sortie, cessait de lire depuis stdin, et toutes les commandes note-on/note-off étaient silencieusement perdues — produisant des notes bloquées tenues puis un silence total de toutes les sources (looper, clavier MIDI, piano à l'écran). Corrigé en drainant les deux flux immédiatement après `Process.start` et en ajoutant le drapeau `-q` (mode silencieux) pour réduire le volume de sortie de FluidSynth.
- **Looper n'enregistre pas depuis le clavier GFK à l'écran** — les pressions sur les touches du piano à l'écran pour `GrooveForgeKeyboardPlugin` (et autres slots non-VP, non-VST3) alimentent désormais aussi tout looper connecté via un câble MIDI OUT dans la vue de câblage. Auparavant, seuls les slots `VirtualPianoPlugin` acheminaient via les câbles ; GFK appelait FluidSynth directement et contournait le looper.
- **Looper n'enregistre pas depuis le MIDI externe (clavier matériel) sur le canal GFK** — `_routeMidiToVst3Plugins` dans `rack_screen.dart` recherche désormais aussi les slots GFK pour le canal MIDI entrant et appelle `_feedMidiToLoopers` en effet de bord, de sorte qu'un contrôleur matériel jouant sur un canal GFK est capturé par un looper connecté. FluidSynth joue toujours en parallèle.
- **Grille d'accords du looper non actualisée pendant l'enregistrement** — `LooperEngine._detectBeatCrossings` appelle désormais `notifyListeners()` lors d'un flush d'accord à une limite de mesure, permettant à la grille d'accords de `LooperSlotUI` de se mettre à jour en temps réel.
- **Boucles perdues au redémarrage de l'application** — les rappels de sauvegarde automatique (`rack.onChanged` et `audioGraph.addListener`) sont désormais enregistrés **après** le retour de `loadOrInitDefault` dans `splash_screen.dart`. Auparavant, `audioGraph.notifyListeners()` se déclenchait de manière synchrone pendant `audioGraph.loadFromJson` — avant l'appel de `looperEngine.loadFromJson` — déclenchant une sauvegarde automatique qui capturait un looper vide et écrasait les données de session persistées.
- **Événements de lecture manqués / notes sautées** — la lecture du looper utilise désormais `LooperSession.prevPlaybackBeat` (le temps de transport réel à la fin du tick précédent) pour définir la fenêtre d'événements. Auparavant, une estimation codée en dur `0.01 × bpm / 60` était utilisée, ce qui faisait sauter silencieusement des événements lorsque le timer Dart se déclenchait tard.
- **Notes bloquées et dégradation progressive des accords** — les notes tenues au-delà de la limite de boucle (sans note-off enregistrée) ne sonnent plus indéfiniment. `LoopTrack.activePlaybackNotes` suit les notes « actives » pendant la lecture ; au redémarrage de la boucle les note-offs sont envoyés avant la nouvelle itération ; à l'arrêt/pause/stop transport toutes les notes tenues sont silenciées. Élimine le vol de voix FluidSynth qui faisait perdre une note à chaque itération d'un accord de 3 notes.
- **Décalage d'un temps dans la détection d'accord** — à un temps fort (mesure N → N+1), `_detectBeatCrossings` enregistrait les notes de la mesure N dans le slot de la mesure N+1 car `_currentRelativeBar` retournait déjà le nouvel index. Le correctif calcule la mesure qui vient de se terminer via `(newAbsBar − 1) − recordingBarStart` et le transmet explicitement à `_flushBarChord`.
- **Accord non détecté en temps réel** — la détection d'accord se déclenche désormais immédiatement dans `feedMidiEvent` dès que ≥3 hauteurs distinctes sont entendues dans la mesure courante (« premier accord gagnant »). Le flush en fin de mesure est conservé comme solution de repli et n'écrase pas un accord déjà identifié en temps réel.
- **Mesure en cours de lecture non mise en évidence** — la grille d'accords met désormais en évidence la mesure active avec un halo vert pendant la lecture. `LooperEngine.currentPlaybackBarForTrack` calcule l'index de mesure 0-basé à partir de la phase de boucle (en tenant compte des modificateurs de vitesse). `_detectBeatCrossings` notifie les écouteurs à chaque temps fort même sans enregistrement actif.
- **Crash « Enregistrer sous… »** — `ProjectService` était enregistré en tant que `Provider` au lieu de `ChangeNotifierProvider`, provoquant une exception non gérée. Corrigé.
- **Isolation du ProjectService au démarrage** — le SplashScreen utilise désormais l'instance partagée via `context.read` au lieu d'en créer une locale, assurant la cohérence du chemin de sauvegarde automatique.

## [2.4.0] - 2026-03-12

### Ajouté
- **Graphe de signal audio** — modèle de graphe orienté (`AudioGraph`) connectant les slots du rack via des ports typés : MIDI IN/OUT (jaune), Audio IN/OUT G/D (rouge/blanc), Send/Return (orange), et ports de données accord/gamme (violet, pour le Jam Mode). Valide la compatibilité des ports, empêche les arêtes dupliquées et applique la détection de cycles par DFS.
- **Vue « dos du rack » de câblage** — bascule via l'icône câble dans la barre d'application. Le rack se retourne pour afficher le panneau arrière de chaque slot avec des jacks virtuels colorés. Les câbles MIDI/Audio sont dessinés sous forme de courbes de Bézier avec un affaissement naturel vers le bas ; les câbles de données (routage accord/gamme) sont en violet et restent synchronisés avec les menus déroulants du Jam Mode.
- **Interactions câble** — appui long sur un jack de sortie pour commencer à tirer un câble ; les jacks d'entrée compatibles clignotent ; relâcher sur une cible valide crée la connexion. Appuyer sur un câble permet de le déconnecter via un menu contextuel. Les dépôts incompatibles sont silencieusement ignorés.
- **VirtualPianoPlugin** — nouveau type de slot (via "Ajouter un plugin") avec un vrai canal MIDI, un clavier piano à l'écran, et des jacks MIDI IN / MIDI OUT / Scale IN dans la vue de câblage. Le MIDI OUT est aligné avec celui des autres slots. Les notes du clavier tactile sont transmises via les câbles MIDI dessinés aux slots connectés (VST3 ou FluidSynth). Le Scale OUT du Jam Mode peut être câblé au jack Scale IN pour verrouiller la gamme d'un instrument VST.
- **Persistance du graphe audio** — toutes les connexions câble MIDI/Audio sont sauvegardées et restaurées dans les fichiers `.gf` sous la clé `"audioGraph"`. Les connexions de données continuent d'être stockées par plugin dans `masterSlotId`/`targetSlotIds`.
- **Nettoyage de slot** — la suppression d'un slot déconnecte automatiquement tous ses câbles MIDI/Audio du graphe.
- 20 nouvelles chaînes localisées pour l'interface de câblage (EN + FR).
- **Onglet « Rack & Câbles » dans le guide utilisateur** — cinquième onglet dans le guide intégré couvrant le basculement de la vue de câblage, les types de jacks, le tracé et la déconnexion des câbles, la synchronisation câbles data/Jam Mode, et le slot Piano Virtuel.
- **Badge de déconnexion des câbles** — badge ✕ visible au milieu de chaque câble avec une zone de tap de 48 dp ; `HitTestBehavior.opaque` garantit une réception fiable des taps.
- **Feuille « Ajouter un plugin » défilable** — la feuille utilise désormais `isScrollControlled: true` et `SingleChildScrollView`, évitant le débordement sur les petits écrans.

### Corrigé
- **Verrouillage de gamme sur les taps individuels** — `VirtualPiano._onDown` applique désormais le snapping `_validTarget` avant d'appeler `onNotePressed`, de sorte qu'appuyer sur une touche invalide redirige vers la classe de hauteur valide la plus proche (même comportement que le glissando). Le même correctif s'applique aux transitions de notes en glissando dans `_onMove` : la note snappée est stockée dans `_pointerNote` et transmise au callback au lieu de la touche brute sous le doigt. Cela est particulièrement important pour le routage VP→VST3 par câble, qui contourne le snapping interne du moteur.
- **MIDI externe via Piano Virtuel** — les notes MIDI entrantes sur le canal d'un VP sont désormais transmises via ses connexions câble MIDI OUT (en respectant le verrouillage de gamme/Jam Mode), permettant à un contrôleur MIDI matériel de piloter un instrument VST3 via la chaîne de routage VP. Auparavant, le MIDI externe sur un canal VP tombait dans FluidSynth (son silencieux ou erroné) et n'atteignait jamais le VST en aval.

### Corrigé
- **Verrouillage de gamme sur les taps individuels** — `VirtualPiano._onDown` applique désormais le snapping `_validTarget` avant d'appeler `onNotePressed`, de sorte qu'appuyer sur une touche invalide redirige vers la classe de hauteur valide la plus proche (même comportement que le glissando). Le même correctif s'applique aux transitions de notes en glissando dans `_onMove` : la note snappée est stockée dans `_pointerNote` et transmise au callback au lieu de la touche brute sous le doigt.
- **MIDI externe via Piano Virtuel** — les notes MIDI entrantes sur le canal d'un VP sont désormais transmises via ses connexions câble MIDI OUT (en respectant le verrouillage de gamme/Jam Mode), permettant à un contrôleur MIDI matériel de piloter un instrument VST3 via la chaîne de routage VP. Auparavant, le MIDI externe sur un canal VP tombait dans FluidSynth (son silencieux ou erroné) et n'atteignait jamais le VST en aval.
- **Hauteur des VST3 décalée d'environ 1,5 demi-tons sous Linux** — l'état audio ALSA avait une fréquence d'échantillonnage par défaut codée en dur à 44100 Hz alors que les plug-ins VST3 étaient repris à 48000 Hz, provoquant une lecture audio à la mauvaise vitesse. `dvh_start_alsa_thread` lit désormais `sr` et `maxBlock` depuis la configuration de l'hôte afin qu'ALSA s'ouvre à la même fréquence que celle utilisée par les plug-ins.

### Architecture
- Enum `AudioPortId` avec helpers de couleur, direction, famille et compatibilité.
- Modèle `AudioGraphConnection` avec ID composite canonique (sans dépendance UUID).
- `PatchDragController` ChangeNotifier pour l'état de glisser-déposer en cours.
- `RackState` reçoit désormais `AudioGraph` en paramètre constructeur (`ChangeNotifierProxyProvider3`).
- Les méthodes de `ProjectService` reçoivent un paramètre `AudioGraph` ; la sauvegarde automatique est également déclenchée lors des mutations du graphe.
- `PatchCableOverlay` utilise des zones de tap `Positioned` par point-milieu calculées via `addPostFrameCallback` après chaque peinture ; aucun intercepteur de gestes plein écran.
- `DragCableOverlay` est un `StatefulWidget` avec un `ListenableBuilder` interne qui déclenche les repeints lors des déplacements du pointeur sans `Consumer` parent.
- **Exécution native du graphe audio** — la boucle ALSA/CoreAudio de `dart_vst_host` gagne `dvh_set_processing_order` (ordre topologique) et `dvh_route_audio` / `dvh_clear_routes` (routage de signal). Quand un câble audio VST3 est tracé dans la vue de câblage, la sortie du plugin source est injectée directement dans l'entrée audio du plugin destination ; la source n'est plus mixée dans le bus maître. Les plugins sans câble audio sortant continuent de se mixer directement dans la sortie maître. La synchronisation côté Dart via `VstHostService.syncAudioRouting` est déclenchée dès que l'`AudioGraph` change ou qu'un slot est ajouté/supprimé.
- `GraphImpl::process()` dans `dart_vst_graph` utilise désormais le tri topologique de Kahn pour traiter les nœuds dans l'ordre de dépendance (sources avant effets), remplaçant le parcours naïf par ordre d'index.
- `dvh_graph_add_plugin` ajouté à l'API C de `dart_vst_graph` — enveloppe un `DVH_Plugin` déjà chargé comme nœud non-propriétaire afin que les gestionnaires de plugins externes puissent participer au graphe sans transférer la responsabilité du cycle de vie.

## [2.3.0] - 2026-03-11

### Ajouté
- **Moteur de transport global** : un nouveau service `TransportEngine` suit le BPM (20–300), la signature rythmique, l'état lecture/arrêt et le swing. Les changements sont propagés en temps réel à tous les plugins VST3 chargés via `dvh_set_transport` → `ProcessContext`, de sorte que les effets synchronisés sur le tempo (LFO, délais, arpégiateurs) se calent instantanément sur le BPM de l'application.
- **Barre de transport** dans la barre d'applications de `RackScreen` : champ BPM modifiable (appui pour saisir), **boutons `−` / `+` de nudge** (appui ±1 BPM ; maintien pour répétition rapide — 400 ms de délai initial puis intervalles de 80 ms), **molette de défilement sur l'affichage BPM** (défilement haut/bas ±1 BPM), bouton **Tap Tempo** (moyenne des 4 derniers taps, rejet des valeurs aberrantes), bouton **▶ / ■ Lecture/Arrêt**, **sélecteur de signature rythmique**, **LED de pulsation rythmique** (clignote en ambre à chaque temps, en rouge sur le premier temps avec animation de fondu), et **bascule métronome audible** (icône 🎵 ; clic de percussion GM via FluidSynth / flutter_midi_pro canal 9 — baguette de côté sur le premier temps, bloc de bois aigu sur les autres temps).
- **État du transport sauvegardé/restauré** dans les fichiers projet `.gf` : BPM, signature rythmique, swing et `metronomeEnabled` sont préservés par projet. La clé `transport` absente dans les anciens fichiers prend les valeurs par défaut `120 BPM / 4/4 / métronome désactivé`.
- **Verrouillage BPM du Mode Jam** — entièrement fonctionnel de bout en bout : le réglage de synchronisation `Désactivé / 1 temps / ½ mesure / 1 mesure` de chaque slot Mode Jam bloque désormais les changements de racine de gamme aux frontières de fenêtre rythmique (mesure par horloge murale, dérivée du BPM en direct). L'ombrage du piano et le recalage des notes utilisent le même ensemble de classes de hauteurs verrouillées — ce que vous voyez mis en surbrillance correspond exactement à ce que vous entendez.
- **Persistance de la gamme pour la basse marchante** : lorsque le canal maître n'a pas de notes actives (basse relâchée entre les pas), la dernière gamme de basse connue est mise en cache dans `_lastBassScalePcs` afin que les canaux suiveurs continuent à se recaler correctement entre les transitions de notes.
- **`bpmLockBeats` câblé de bout en bout** : le réglage de verrouillage circule depuis l'interface Mode Jam → `plugin.state` → `RackState._syncJamFollowerMapToEngine` → `GFpaJamEntry.bpmLockBeats` → `AudioEngine._shouldUpdateLockedScale()`.
- **Clés réservées pour la compatibilité future** : `"audioGraph": { "connections": [] }` et `"loopTracks": []` ajoutés aux nouveaux fichiers `.gf` créés (vides — évite les changements de format quand les Phases 5 et 7 arriveront).

### Corrigé
- **Verrouillage de gamme par accord du Mode Jam** : le recalage et l'ombrage du piano utilisent désormais toujours la même fonction `_getScaleInfo(accord, typeGamme)`. Auparavant, un code régressif routait le recalage via `GFJamModePlugin.processMidi` (qui utilisait `chord.scalePitchClasses` — sortie brute du détecteur d'accords) tandis que l'ombrage utilisait la matrice qualité d'accord × type de gamme. Pour Jazz, Pentatonique, Blues, Classique et tous les types non-Standard, les deux divergeaient — les notes jouées ne correspondaient plus aux touches mises en surbrillance. Le recalage passe maintenant directement par `_snapKeyToGfpaJam`, qui appelle `_getScaleInfo` de façon identique à la logique d'ombrage.
- **Verrouillage de l'entrée MIDI du Mode Jam** : les notes d'un clavier MIDI externe sur un canal suiveur sont désormais correctement recalées. Le routage défaillant via le registre de plugins introduit par un refactoring précédent est supprimé ; tous les chemins passent par `_snapKeyToGfpaJam`.
- **Sens de l'algorithme de recalage restauré** : les trois chemins de recalage (verrouillage de gamme, jam GFPA, piano virtuel) utilisent à nouveau la préférence originale vers le bas en cas d'égalité (le voisin le plus bas l'emporte à distance égale), rétablissant le comportement d'avant la régression.

### Architecture
- `TransportEngine` exécute désormais un minuteur `Timer.periodic(10 ms)` en cours de lecture ; il avance `positionInBeats` / `positionInSamples` par temps écoulé en microsecondes, déclenche `onBeat(isDownbeat)` à chaque frontière de temps, incrémente `ValueNotifier<int> beatCount` (pour la pulsation de l'interface) et appelle `_syncToHost()` à chaque tick pour que les plugins VST3 lisent toujours une position précise.
- Le callback `TransportEngine.onBeat` est câblé par `RackState` pour appeler `AudioEngine.playMetronomeClick(isDownbeat)` quand `metronomeEnabled` est vrai.
- `AudioEngine.bpmProvider` / `isPlayingProvider` — callbacks légers par référence de fonction injectés par `RackState` ; le moteur audio lit l'état du transport en direct sans dépendance directe sur `TransportEngine`.
- `AudioEngine._bpmLockedScalePcs` — cache par canal suiveur de l'ensemble de classes de hauteurs verrouillées en cours, partagé entre la propagation de l'ombrage du piano (`_performChordUpdate`) et le recaleur de notes (`_snapKeyToGfpaJam`).
- `AudioEngine._lastScaleLockTime` — horodatage horloge murale par canal suiveur ; `_shouldUpdateLockedScale()` compare le temps écoulé avec `bpmLockBeats × 60 / bpm` ms pour autoriser les mises à jour.

---

## [2.2.1] - 2026-03-11

### Ajouté
- **Plugin VST3 GrooveForge Keyboard** : Bundle `.vst3` distribuable (Linux) fonctionnant dans tout DAW compatible VST3 (Ardour, Reaper, etc.) sans nécessiter l'application GrooveForge. MIDI entrée → FluidSynth → sortie audio stéréo. Paramètres : Gain, Bank, Program.
- **Plugin VST3 GrooveForge Vocoder** : Bundle `.vst3` distribuable (Linux) implémentant le schéma vocoder par sidechain standard dans les DAW professionnels. Routez n'importe quelle piste audio comme signal porteur via le bus sidechain du DAW ; jouez des notes MIDI pour contrôler la hauteur. Paramètres : Waveform, Noise Mix, Bandwidth, Gate Threshold, Env Release, Input Gain.
- **`vocoder_dsp.h/c`** : Bibliothèque DSP vocoder à base de contexte extraite de `audio_input.c` — sans dépendance à un backend audio, utilisable depuis le plugin GFPA et le bundle VST3.
- **Compatibilité DAW Flatpak** : Les deux bundles se chargent correctement dans les versions Flatpak sandbox d'Ardour/Reaper. Obtenu en liant statiquement FluidSynth (compilé depuis les sources avec tous les backends audio désactivés), en inlinant les fonctions mathématiques avec `-ffast-math`, et en corrigeant tous les RPATHs `$ORIGIN` via `scripts/bundle_deps.sh`.
- **`scripts/bundle_deps.sh`** : Script shell qui regroupe récursivement les dépendances de bibliothèques partagées dans un bundle `.vst3` et corrige tous les RPATHs en `$ORIGIN` pour un déploiement autonome.
- **Documentation de build VST3** : `packages/flutter_vst3/vsts/README.md` complet couvrant les propriétés des plugins, les instructions de build, les notes de compatibilité Flatpak, un tableau comparatif GFPA vs VST3, et un guide de dépannage.

### Architecture
- Plugins VST3 en C++ pur utilisant le SDK VST3 de Steinberg (MIT depuis la v3.8) — aucun runtime Dart ou Flutter requis dans le DAW.
- `grooveforge_keyboard.vst3` : unité de compilation unique (`factory.cpp` inclut `processor.cpp` + `controller.cpp`), FluidSynth lié statiquement via CMake `FetchContent` (v2.4.0 compilé depuis les sources), points d'entrée Linux `ModuleEntry`/`ModuleExit` via `linuxmain.cpp`.
- `grooveforge_vocoder.vst3` : même modèle mono-TU, bibliothèque statique `vocoder_dsp` compilée avec `-fPIC -ffast-math`, zéro dépendance externe à l'exécution.
- Les cibles `make keyboard` / `make vocoder` / `make grooveforge` effectuent une vraie copie `cp -rL` vers `~/.vst3/` (pas de liens symboliques — requis pour la compatibilité sandbox Flatpak).

---

## [2.2.0] - 2026-03-09

### Ajouté
- **GrooveForge Plugin API (GFPA)** : Système de plugins extensible en Dart pur, indépendant de la plateforme (Linux, macOS, Windows, Android, iOS). Définit des interfaces typées : `GFInstrumentPlugin` (MIDI entrée → audio sortie), `GFEffectPlugin` (audio entrée → audio sortie), `GFMidiFxPlugin` (MIDI entrée → MIDI sortie). Livré en tant que package autonome `packages/grooveforge_plugin_api/` sans dépendance Flutter, permettant des plugins tiers.
- **`packages/grooveforge_plugin_ui/`** : Package Flutter compagnon exposant des helpers d'interface réutilisables — `RotaryKnob`, `GFParameterKnob`, `GFParameterGrid` — pour le développement rapide d'interfaces de plugins.
- **Vocodeur comme slot GFPA autonome** : Le vocodeur est désormais son propre slot de rack avec un canal MIDI dédié, un piano et des contrôles. Plusieurs vocodeurs peuvent coexister indépendamment dans le même projet.
- **Plugin GFPA Mode Jam** : Une implémentation complète de `GFMidiFxPlugin` avec une refonte complète de l'interface inspirée du Roland RC-20.
  - Rangée de flux de signal : liste déroulante MAÎTRE → LCD ambre (nom de gamme en direct + étiquette de type) → chips CIBLES.
  - Le LCD sert également de sélecteur de type de gamme ; affiche le crochet `[TYPE]` uniquement pour les familles où le nom n'encode pas déjà le type (Standard, Jazz, Classique, Asiatique, Oriental).
  - Bouton d'activation/désactivation LED lumineux avec indicateur ON/OFF.
  - **Cibles multiples** : un slot Mode Jam peut contrôler simultanément n'importe quel nombre de slots clavier et vocodeur.
  - **Mode détection par note basse** : utilise la note active la plus basse sur le canal maître comme racine de gamme — idéal pour les lignes de basse marchante.
  - **Verrouillage de synchronisation BPM** (Désactivé / 1 temps / ½ mesure / 1 mesure) : la racine de gamme ne change qu'aux limites de temps (s'active pleinement à l'arrivée du transport Phase 4).
  - Disposition responsive : panneau deux rangées sur grands écrans (≥480 px) ; colonne empilée sur petits écrans (<480 px).
  - Réglages des bordures de touches et de l'atténuation des fausses notes déplacés des Préférences vers le slot Mode Jam.
- **Modèle de projet par défaut** : les nouveaux projets démarrent avec deux slots clavier et un slot Mode Jam préconfiguré (maître = canal 2, cible = canal 1, inactif par défaut).
- **Modèle `GFpaPluginInstance`** : sérialise/désérialise en `"type": "gfpa"` dans les fichiers `.gf` ; prend en charge plusieurs `targetSlotIds` (compatible avec l'ancien `targetSlotId` chaîne unique).
- **Registre de plugins GFPA** (`GFPluginRegistry`) : registre singleton pour tous les plugins intégrés et futurs plugins tiers.

### Modifié
- L'affichage du nom de gamme dans le rack Jam montre désormais la forme complète `"Do Mineur Blues"` (note fondamentale + nom de gamme) ; le crochet `[TYPE]` n'est affiché que lorsque la famille de gammes n'encode pas déjà le type.
- Le clavier virtuel n'expose plus d'option vocodeur dans son menu déroulant soundfont (le vocodeur est son propre type de slot).
- Le nouveau projet par défaut ne définit plus les rôles maître/esclave sur les slots clavier (concept de rôle remplacé par le slot GFPA Mode Jam).

### Supprimé
- **`JamSessionWidget` hérité** et préférence globale `ScaleLockMode` — tout le routage jam est désormais géré par le slot plugin GFPA Mode Jam.
- **Champs `GrooveForgeKeyboardPlugin.jamEnabled/jamMasterSlotId`** — nettoyage du code mort après migration GFPA.
- **`_buildMasterDropdown` / `_buildSlavesSection`** — remplacés par `GFpaJamModeSlotUI`.
- **Option vocodeur dans le menu soundfont du clavier** — le vocodeur est un type de slot dédié.

### Corrigé
- **Routage MIDI du vocodeur** : suppression du routage omni-mode erroné qui déclenchait le canal vocodeur pour toutes les entrées MIDI quel que soit le slot ciblé.
- **Blocage au démarrage** : ajout d'un verrou `_isConnecting` dans `MidiService` pour éviter les appels concurrents à `connectToDevice` lors de la course entre le timer de 2 secondes et `_tryAutoConnect` sur Linux.
- **Étiquettes de notes sur les touches blanches** : les étiquettes de noms de notes (ex. `C4`, `F#6`) s'affichent désormais correctement sur les touches blanches ainsi que sur les touches noires.
- **Gamme appliquée immédiatement lors du changement** : changer le type de gamme dans un slot Mode Jam se propage désormais à tous les canaux cibles sans nécessiter un cycle arrêt/redémarrage.
- **Vocodeur ciblable par le Mode Jam** : les slots vocodeur peuvent désormais être ajoutés comme cibles du Mode Jam, recevant le verrouillage de gamme de la même façon que les slots clavier.
- **Rembourrage en bas du rack** : ajout d'une marge en bas pour que le FAB ne chevauche plus le dernier slot du rack.

---

## [2.1.0] - 2026-03-08

### Ajouté
- **Hébergement de plugins VST3 externes** (Linux, macOS, Windows) : chargez n'importe quel bundle `.vst3` dans un slot de rack via la tuile « Parcourir VST3 » dans le panneau Ajouter un plugin.
- **Boutons de paramètres** : chaque slot VST3 affiche des chips de catégories (une par groupe de paramètres). Appuyer sur une chip ouvre une grille modale de widgets `RotaryKnob` avec recherche, filtre de sous-groupe et pagination (24 par page).
- **Fenêtre d'éditeur de plugin native** (Linux) : ouvre l'interface graphique propre au plugin VST3 dans une fenêtre X11 flottante. L'éditeur peut être ouvert, fermé et rouvert sans gel ni plantage.
- **Thread de sortie audio ALSA** : `dart_vst_host_alsa.cpp` — thread de lecture ALSA à faible latence consommant la sortie audio VST3 en temps réel.
- **Support VST3 mono-composant** : le contrôleur est interrogé depuis le composant lorsque `getControllerPtr()` retourne null (Aeolus, Guitarix).
- **Support multi-bus de sortie** : tous les bus de sortie audio sont configurés dynamiquement au resume (Surge XT Scene B, etc.).
- **Rechargement au démarrage** : les instances de plugins VST3 d'un projet `.gf` sont rechargées dans `VstHostService` au démarrage via l'écran de démarrage.
- **Persistance des paramètres** : les valeurs des paramètres VST3 sont stockées dans `Vst3PluginInstance.parameters` et sauvegardées dans le projet `.gf`.

### Architecture
- `packages/flutter_vst3/` vendorisé à la racine du projet (BSD-3-Clause, compatible MIT) ; `.git` imbriqué supprimé pour permettre la validation dans le dépôt.
- `dart_vst_host` converti en plugin Flutter FFI (`ffiPlugin: true`) avec des CMakeLists spécifiques par plateforme pour Linux (ALSA + X11), Windows (Win32) et macOS (Cocoa/CoreAudio).
- Import conditionnel par plateforme : `vst_host_service.dart` exporte l'implémentation desktop sur Linux/macOS/Windows et un stub sans opération sur mobile.

### Corrigé
- Plugins basés sur JUCE (Surge XT, DISTRHO) : `setComponentState()` appelé après l'init pour construire la référence interne du processeur.
- Fermeture de l'éditeur via le bouton X : `removed()` appelé sur le thread d'événements pour éviter le deadlock avec le thread GUI de JUCE.
- Réouverture après fermeture : attente des `g_cleanupFutures` pour s'assurer que `removed()` se termine avant un nouvel appel à `createView()`.

---

## [2.0.0] - 2026-03-08

### Ajouté
- **Rack de Plugins** : Le système de canaux fixes est remplacé par un rack de plugins dynamique et réorganisable. Chaque slot est une voie de synthèse indépendante avec son propre canal MIDI, sa soundfont/patch et son rôle en Mode Jam.
- **Plugin GrooveForge Keyboard** : Le synthé/vocodeur intégré est désormais une instance de plugin à part entière, avec une configuration par slot (soundfont, banque, patch, réglages du vocodeur) et une sauvegarde/restauration complète.
- **Glisser-Déposer pour Réordonner** : Les slots du rack peuvent être réordonnés librement en faisant glisser la poignée sur la gauche de chaque en-tête de slot.
- **Ajout / Suppression de Plugins** : Un bouton flottant ouvre un panneau pour ajouter de nouveaux slots GrooveForge Keyboard (ou des plugins VST3 sur ordinateur — Phase 2). Les slots peuvent être supprimés avec confirmation.
- **Rôles Maître / Esclave dans les En-têtes** : Chaque slot possède désormais un badge Maître/Esclave directement dans son en-tête. Un appui bascule le rôle ; le moteur du Mode Jam est mis à jour automatiquement.
- **Badge de Canal MIDI** : Chaque slot affiche son canal MIDI et permet de le modifier via un sélecteur, en évitant les conflits avec les autres slots.
- **Fichiers de Projet (format .gf)** : Les projets sont désormais sauvegardés et chargés sous forme de fichiers JSON `.gf`. Le menu de la barre d'application propose les actions Ouvrir, Enregistrer sous et Nouveau Projet.
- **Sauvegarde Automatique** : Chaque modification du rack est automatiquement persistée dans `autosave.gf` dans le répertoire documents de l'application, restaurant la session au prochain lancement.
- **Configuration par Défaut au Premier Lancement** : Au premier lancement, le rack est préconfiguré avec un slot Esclave sur le canal MIDI 1 et un slot Maître sur le canal MIDI 2.
- **Mode Jam Simplifié** : La barre du Mode Jam n'affiche plus les menus déroulants maître/esclave (gérés par slot dans le rack) ; elle se concentre désormais sur les contrôles démarrage/arrêt JAM et le type de gamme.

### Supprimé
- **Modale des Canaux Visibles** : Le dialogue "Filtrer les Canaux Visibles" est supprimé. Le rack est la liste des canaux — chaque slot est visible.
- **SynthesizerScreen** et **ChannelCard** : Remplacés par `RackScreen` et `RackSlotWidget`.

### Architecture
- Nouveau modèle abstrait `PluginInstance` avec `GrooveForgeKeyboardPlugin` et `Vst3PluginInstance` (stub Phase 2 pour ordinateur).
- Nouveau `RackState` ChangeNotifier qui gère la liste de plugins et synchronise le maître/esclave Jam avec `AudioEngine`.
- Nouveau `ProjectService` pour la gestion des fichiers `.gf` (JSON sauvegarde/chargement/autosave).

## [1.7.1] - 2026-03-07
### Ajouté
- **Avertissement de Larsen du Vocodeur** : Implémentation d'une modale de sécurité qui avertit les utilisateurs des risques de larsen lors de l'utilisation du vocodeur avec les micros et haut-parleurs internes. L'avertissement s'affiche une seule fois et peut être masqué définitivement.

### Corrigé
- **Régression de l'Entrée Audio Android** : Correction d'un problème critique où les micros internes et externes ne fonctionnaient plus sur Android en raison de permissions manquantes et d'une mauvaise gestion des identifiants d'appareils dans la couche native.

## [1.7.0] - 2026-03-07
### Ajouté
- **Vocodeur à Hauteur Absolue (Mode Natural)** : Refonte complète du mode haute fidélité utilisant la synthèse par grains **PSOLA (Pitch Synchronous Overlap and Add)**. Il capture désormais un cycle de votre voix pour déclencher des grains à durée fixe à la **fréquence MIDI exacte**. Cela préserve vos formants naturels et le caractère de vos voyelles, éliminant l'effet "accéléré" et garantissant un verrouillage parfait de la hauteur même si vous chantez faux.
- **Correction de la Persistence Audio (Linux)** : Résolution d'un problème où le périphérique d'entrée préféré n'était pas correctement initialisé au démarrage. Tous les réglages du vocodeur (Forme d'onde, Mixage de bruit, Gain, etc.) sont désormais correctement persistants et appliqués avant l'ouverture du flux audio.
- **Amélioration du Volume du Vocodeur** : Intégration d'une normalisation basée sur la valeur RMS dans le moteur PSOLA pour garantir que le mode Natural corresponde au volume ressenti des autres vocodeurs.
- **Noise Gate du Vocodeur** : Ajout d'un contrôle "GATE" dédié sur le panneau du vocodeur pour éliminer les bruits de fond et les larsens lors des passages silencieux.
- **Aperçu Zoomé des Boutons** : Ajout d'un aperçu agrandi du bouton qui s'affiche lors de l'interaction (maintien de 200ms ou glissement immédiat).
- **Bascule du Défilement Automatique** : Ajout d'une préférence utilisateur pour activer ou désactiver le défilement automatique de la liste des canaux lors de la lecture de notes MIDI (désactivé par défaut).
- **Sélection du périphérique de sortie audio** : Ajout d'un sélecteur de périphérique de sortie dans les Préférences, en complément du sélecteur de micro existant, pour router la sortie du vocodeur vers un haut-parleur ou casque spécifique.
- **Atténuation de la gigue AAudio** : Intégration d'un observateur de santé en arrière-plan qui surveille la stabilité du flux audio et déclenche un redémarrage silencieux du moteur si des problèmes persistants sont détectés.
- **Optimisation de la boucle interne DSP** : Réduction significative de la charge de traitement par échantillon en refactorisant la logique de synthèse audio centrale, améliorant les performances en temps réel sur les appareils mobiles.
- **Stabilité du moteur et Découplage Audio** : Amélioration massive de la stabilité globale de l'application et de la qualité sonore en découplant le cycle de vie audio de bas niveau du thread Flutter UI. Cela élimine le « son haché » et les ralentissements de l'interface qui apparaissaient après une utilisation prolongée.

### Modifié
- **Renommage du mode Vocodeur** : Le mode "Neutre" est désormais **"Natural"** pour mieux refléter son caractère vocal haute fidélité.
- **Réactivité des Boutons Rotatifs** : Amélioration du dimensionnement et de la disposition des boutons pour les écrans étroits/mobiles afin d'améliorer la précision tactile.
- **Disposition Adaptive du Vocodeur** : Optimisation avec bascule intelligente entre icônes et étiquettes pour conserver l'accessibilité sur petits écrans.
- **Redémarrage automatique du micro lors d'un changement d'appareil** : Changer le périphérique d'entrée ou de sortie dans les Préférences redémarre désormais automatiquement le moteur de capture audio sans nécessiter de clic sur « Actualiser le micro ».

### Corrigé
- **Verrouillage MIDI Absolu** : Correction du problème où le vocodeur suivait les imprécisions de hauteur du chanteur au lieu des notes du clavier.
- **Latence du Vocodeur Optimisée** : Performance en temps réel atteinte en découplant la capture du microphone du flux de lecture principal via un tampon circulaire sans verrou. Supprime le délai important (400ms+) causé par la synchronisation duplex d'Android.
- **Précision du Squelch** : Passage du noise gate en mode bypass lorsque des notes sont actives pour éviter l'occlusion sonore au début des phrases vocales.
- **Énumération des périphériques audio USB** : Passage aux requêtes Android `GET_DEVICES_ALL` avec filtrage par capacité, garantissant que les micros USB et les casques filaires sont toujours listés même en partageant un hub USB-C.
- **Périphérique en double dans la liste d'entrée** : Les casques USB bidirectionnels (avec micro et haut-parleur) n'apparaissent plus deux fois dans le sélecteur de micro — seul le côté source/mic est affiché.
- **Identifiant d'appareil obsolète après reconnexion** : Sélectionner un micro ou casque USB puis débrancher/rebrancher le hub (qui réattribue les identifiants) n'affiche plus « Déconnecté » — la sélection se réinitialise automatiquement au périphérique système par défaut.
- **Retour automatique sur déconnexion** : L'application écoute désormais les événements `AudioDeviceCallback` d'Android. Lorsqu'un périphérique d'entrée ou de sortie sélectionné est retiré, la sélection se réinitialise automatiquement au périphérique système par défaut.
- **Boucle de redémarrage du moteur audio** : Ajout d'un verrou de réentrée (`_isRestartingCapture`) avec un délai de refroidissement de 500 ms sur `restartCapture()` pour empêcher les événements de récupération Oboe de Fluidsynth de déclencher une boucle de redémarrage infinie.

## [1.6.1] - 2026-03-06
### Ajouté
- **Guide de l'utilisateur repensé** : Onglets réorganisés (Fonctionnalités, Connectivité MIDI, Soundfonts, Conseils musicaux).
- **Documentation du Vocodeur** : Ajout d'instructions détaillées sur l'utilisation des nouvelles fonctionnalités du vocodeur.
- **Conseils d'improvisation musicale** : Ajout d'une nouvelle section avec des notions théoriques pour aider les débutants à improviser avec les gammes.
- **Accueil automatique** : Le guide s'affiche désormais automatiquement au premier lancement ou après une mise à jour majeure.

## [1.6.0] - 2026-03-05
### Ajouté
- **Refonte du Vocodeur** : Vocodeur polyphonique à 32 bandes avec sélection de la forme d'onde porteuse (incluant le nouveau mode 'Neutre').
- **Entrée Audio Native** : Capture audio haute performance via miniaudio + FFI.
- **Contrôle UI Rotatif** : Nouveau widget personnalisé `RotaryKnob` pour une expérience plus tactile.
- **Contrôles Avancés du Vocodeur** : Ajout des paramètres de Bande Passante et d'injection de Sibilance.
- **Gestion de Session Audio** : Intégration avec `audio_session` pour un meilleur support du Bluetooth et du routage.
- **Indicateurs de Niveau Améliorés** : Retour visuel en temps réel pour les niveaux d'entrée et de sortie du vocodeur.

### Modifié
- **Optimisations de Performance** : Profil audio à faible latence et relâchement de notes optimisé.

## [1.5.2] - 2026-03-04
### Corrigé
- **Stabilisation du Relâchement d'Accord** : Optimisation de la logique de relâchement d'accord en mode Jam avec une fenêtre de stabilisation anti-rebond de 50ms, évitant le "scintillement" de l'identité de l'accord lors du levé naturel des doigts.

## [1.5.1] - 2026-03-04
### Ajouté
- **Connexion Instantanée d'appareils MIDI** : Lorsqu'un nouvel appareil MIDI est branché sur l'écran principal du synthétiseur, une invite automatique s'affiche permettant une connexion instantanée.
- **Reconnexion Automatique Améliorée** : Les appareils MIDI se reconnectent désormais de manière fiable même s'ils sont débranchés et rebranchés pendant l'exécution de l'application.

## [1.5.0] - 2026-03-04
### Ajouté
- **Internationalisation (i18n)** : Ajout d'un support complet pour la localisation de l'application.
- **Langue Française** : Traduction de l'intégralité de l'interface utilisateur et ajout d'un changelog en français (`CHANGELOG.fr.md`).
- **Préférences de Langue** : Les utilisateurs peuvent désormais changer dynamiquement la langue de l'application depuis l'écran des Préférences (Système, Anglais, Français).

## [1.4.5] - 2026-03-04
### Ajouté
- **Bascule des Bordures en Mode Jam** : Ajout d'une préférence utilisateur pour activer ou désactiver la visibilité des bordures autour des groupes de touches associées à la gamme en Mode Jam.
- **Mise en évidence des fausses notes en mode Jam** : Appuyer sur une touche physique hors gamme en mode Jam colore désormais la mauvaise touche initialement enfoncée en rouge et met en évidence la note cible correctement mappée en bleu, avec une préférence utilisateur pour désactiver optionnellement la coloration rouge.

## [1.4.4] - 2026-03-03
### Ajouté
- **Zones de clic en Mode Jam** : Les touches du piano virtuel en Mode Jam sont désormais regroupées avec les touches valides sur lesquelles elles se fixent, formant des zones cliquables unifiées entourées de bordures colorées subtiles.

## [1.4.3] - 2026-03-02
### Corrigé
- **Artéfacts du Piano Virtuel** : Correction d'un bug où l'ombrage du piano virtuel ne se mettait pas à jour immédiatement lors du démarrage ou de l'arrêt du Mode Jam.
- **Interférence de défilement** : Empêchement du défilement vertical de l'écran principal lors de l'exécution de gestes sur les touches du piano virtuel.

## [1.4.2] - 2026-03-02
### Ajouté
- **Synchronisation réactive du Mode Jam** : Les étiquettes de gamme et les visuels du piano virtuel (touches grisées) se mettent désormais à jour en temps réel lorsque la gamme maître change ou lorsque les configurations des canaux esclaves sont modifiées.

### Modifié
- **Évolutivité du Piano Virtuel** : Les canaux esclaves grisent désormais visuellement les touches qui n'appartiennent pas à la gamme actuelle du canal maître.
- **Performances de l'interface utilisateur améliorées** : Correction des problèmes d'imbrication complexe des widgets dans `ChannelCard` pour garantir des constructions de l'interface utilisateur propres et réactives.

### Corrigé
- **Comportement des Glissandos** : Les notes en dehors de la gamme actuelle continuent de sonner si elles font partie d'un glissando en cours au lieu d'être arrêtées brusquement.
- **Artéfacts du Piano Virtuel** : Résolution des artéfacts de transparence du clavier en utilisant des couleurs unies pour les touches désactivées.

## [1.4.1] - 2026-02-28
### Ajouté
- **Gestes expressifs configurables** : Les utilisateurs peuvent désormais affecter indépendamment des actions (Aucune, Pitch Bend, Vibrato, Glissando) aux gestes verticaux et horizontaux sur les touches.
- **Préférences de gestes unifiées** : Configuration de haut niveau dans l'écran des Préférences avec de nouveaux menus déroulants spécifiques aux axes.
- **Optimisation des permissions Android** : Découplage du Bluetooth de la Localisation pour Android 12+. L'accès à la localisation n'est plus requis sur les appareils modernes.
- **Amélioration de la réactivité de l'interface utilisateur** : Refonte de l'écran des Préférences avec une disposition adaptative pour éviter l'écrasement du texte sur les appareils mobiles étroits.

### Modifié
- **Optimisation des performances** : La détection d'accords en mode Jam est désormais asynchrone, ce qui réduit considérablement la latence de l'interface utilisateur lors du suivi intensif des performances.

### Corrigé
- Résolution d'un crash d'exécution `Provider` au démarrage de l'application.
- Correction d'un avertissement de linting mineur dans la logique de `VirtualPiano`.

## [1.4.0] - 2026-02-28
### Ajouté
- **Gestes expressifs** : Introduction du Pitch Bend vertical et du Vibrato horizontal sur le piano virtuel.
- **Verrouillage du défilement par les gestes** : Suppression automatique du défilement de la liste de pianos pendant l'exécution de gestes expressifs pour éviter les mouvements accidentels.
- **Accords Jam indépendants** : Chaque canal détecte et affiche désormais son propre accord indépendamment en mode Jam.
- **Visibilité dynamique des esclaves** : Les noms d'accords des canaux esclaves se masquent désormais automatiquement lorsqu'ils ne jouent pas activement.

### Modifié
- Affinage des badges d'accords en mode Jam en supprimant le préfixe "JAM:" pour une esthétique plus épurée.
- Les noms de gammes sur tous les canaux font correctement référence au contexte d'accord du Maître pour un retour de performance synchronisé.

## [1.3.6] - 2026-02-28
### Ajouté
- Nouvelle section "À propos" dans l'écran des Préférences.
- Intégration du visualiseur de Changelog pour voir l'historique des modifications directement dans l'application.

## [1.3.5] - 2026-02-28
### Ajouté
- Optimisation de l'espace vertical pour les touches du piano virtuel. Réduction du remplissage et des marges sur l'écran principal et les cartes de canaux pour améliorer la jouabilité sur les appareils mobiles/tablettes.

## [1.3.4] - 2026-02-28
### Modifié
- Le "Glissando" du piano virtuel (Glisser pour Jouer) est désormais activé par défaut pour les nouvelles installations et les réinitialisations de préférences.

## [1.3.3] - 2026-02-28
### Ajouté
- Style "en boîte" unifié pour le Maître Jam, les Esclaves et les contrôles de Gamme dans les dispositions horizontales et verticales.
- Disposition de la barre latérale Jam centrée verticalement avec un encombrement plus compact (95px de largeur).
- Nouvelles icônes interactives pour les listes déroulantes pour signaler clairement la cliquabilité.

### Corrigé
- Erreur d'assertion Flutter lorsque `itemHeight` était défini trop bas dans les listes déroulantes Jam.
- La barre latérale verticale se centre désormais correctement verticalement sur le bord gauche.

## [1.3.2] - 2026-02-27

### Ajouté
- **Interface utilisateur Jam en mode double:** Refonte du widget de session Jam avec une isolation de disposition stricte. Le paysage mobile dispose désormais d'une barre latérale verticale premium et étiquetée, tandis que les affichages portrait/étroits utilisent une barre horizontale ultra-compacte et correctement ordonnée.
- **Étiquettes subtiles:** Ajout de minuscules étiquettes à contraste élevé aux modes d'interface utilisateur Jam horizontaux et verticaux pour une meilleure clarté lors des performances.

### Corrigé
- **Cadrage de l'écran de démarrage:** Modification de la mise à l'échelle de l'image de l'écran de démarrage pour empêcher le cadrage sur les affichages portrait.
- **Restauration de la barre Jam:** Restauration de l'ordre hérité des widgets (Jam, Master, Slaves, Scale) et du dimensionnement compact des conteneurs dans l'en-tête horizontal.
- **Redondance des étiquettes:** Suppression des étiquettes en double dans la barre latérale verticale pour une esthétique plus épurée.

## [1.3.1] - 2026-02-27

### Ajouté
- **Guide d'utilisation interactif:** Un guide complet à plusieurs onglets intégré à l'application remplaçant l'ancienne modale d'aide CC. Il couvre la connectivité, les soundfonts, le mapping CC et le mode Jam.
- **Actions système exhaustives:** Les 8 actions CC MIDI de niveau système (1001-1008) sont désormais entièrement implémentées et documentées, y compris les balayages Patch/Bank absolus.

### Modifié
- **Renommage des actions système:** "Basculer le verrouillage de la gamme" (1007) a été renommé en "Démarrer/Arrêter le mode Jam" pour mieux refléter son rôle principal lors des performances.
- **Descriptions des actions améliorées:** Les descriptions dans le service de mapping CC et le Guide sont désormais plus descriptives et précises.

## [1.3.0] - 2026-02-27

### Ajouté
- **Noms de gammes musicaux:** De vrais noms descriptifs (par exemple, Dorien, Mixolydien, Gamme altérée) sont désormais affichés dans l'interface utilisateur au lieu d'étiquettes génériques.
- **Mode Jam intelligent:** Refonte majeure du moteur du mode Jam pour prendre en charge le verrouillage des gammes multi-canaux et le calcul dynamique du mode en fonction de l'accord du Maître.
- **Propagation de l'interface utilisateur améliorée:** Les noms descriptifs des gammes sont désormais propagés à tous les composants de l'interface utilisateur, offrant un meilleur retour musical lors des performances.

### Modifié
- **Mode de verrouillage par défaut:** Le "Mode Jam" est désormais la préférence de verrouillage de gamme par défaut.

### Corrigé
- **Stabilisation du relâchement d'accord:** Implémentation d'une logique de préservation des pics avec une période de grâce de 30 ms pour empêcher le "scintillement" de l'identité de l'accord lors des transitions de relâchement.
## [1.2.1] - 2026-02-27

### Ajouté
- **Réinitialiser les préférences:** Ajout d'une fonctionnalité "Réinitialiser toutes les préférences" dans l'écran des Préférences avec une boîte de dialogue de confirmation pour restaurer les paramètres d'usine.
- **Interface utilisateur Soundfont améliorée:** La soundfont par défaut s'affiche désormais comme "Soundfont par défaut", apparaît en premier dans les listes et est protégée contre la suppression.

### Corrigé
- **Stabilité Linux:** Résolution d'un plantage et d'entrées de soundfont dupliquées causés par des erreurs logiques dans l'état de chargement de la soundfont.
- **Pipeline audio macOS:** Refonte complète du moteur audio macOS pour utiliser un seul `AVAudioEngine` partagé avec 16 bus de mixage, offrant de meilleures performances et corrigeant les problèmes de "pas de son".
- **Soundfonts personnalisées macOS:** Suppression d'une boucle de copie de fichiers redondante qui provoquait `PathNotFoundException` et ajout d'un repli automatique de banque (MSB 0) pour corriger l'erreur de chargement `-10851`.
- **Améliorations audio:** Augmentation du volume audio par défaut sur macOS de 15 dB pour une meilleure parité avec les autres plates-formes.
- **Migration de chemin:** Implémentation d'une couche de migration robuste pour déplacer automatiquement les anciens chemins de soundfonts vers le nouveau stockage interne sécurisé.


## [1.2.0] - 2026-02-26

### Ajouté
- Implémentation d'une icône d'application personnalisée pour toutes les plates-formes.
- Ajout d'un écran de démarrage natif (Android, iOS) pour une expérience de démarrage fluide.
- Création d'un écran de démarrage Flutter dynamique en plein écran qui affiche la progression de l'initialisation (chargement des préférences, démarrage des backends, etc.).

## [1.1.0] - 2026-02-26

### Ajouté
- Intégration d'une Soundfont General MIDI par défaut et légère (`TimGM6mb.sf2`) pour que l'application produise des sons prêts à l'emploi sur toutes les plates-formes sans nécessiter de téléchargement manuel.
- Ajout d'une barre de défilement horizontale au piano virtuel.
- Ajout d'une préférence pour personnaliser le nombre par défaut de touches de piano visibles à l'écran.

### Modifié
- Le piano virtuel s'initialise désormais centré sur le Do central (C4) au lieu de tout à gauche.
- Réarchitecture du défilement automatique du piano virtuel pour suivre les notes actives de manière robuste.
- La vue synthétiseur s'adapte gracieusement aux rapports d'aspect ultra-larges/courts (par exemple, les téléphones portables en paysage) en affichant un canal unique verticalement.

## [1.0.1] - 2026-02-26

### Modifié
- Remplacement du mode de configuration du canal par des listes déroulantes interactives pour la Soundfont, le Patch et la Bank directement sur la `ChannelCard`.
- Rendu adaptatif de la disposition de la liste déroulante en fonction de la largeur de l'écran.

## [1.0.0] - 2026-02-26

### Ajouté
- Version initiale du projet.
- Capacité de base à analyser le MIDI.
- Compatibilité Bluetooth LE.
- Piano virtuel interactif via la souris/le toucher.
- Analyse et identification des accords en temps réel.
- Écran des préférences de l'utilisateur pour sélectionner les périphériques MIDI de sortie ou les Soundfonts internes.
- Analyse automatique des canaux et architecture des composants de l'interface utilisateur `ChannelCard`.
- Fonctionnalité d'accords de verrouillage de gamme pour contraindre les touches jouées.
