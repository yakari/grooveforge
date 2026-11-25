# Toutes les fonctionnalités

Tout ce que fait GrooveForge, une ligne par fonction. Pour l'aide pas à pas, voyez le [guide de démarrage](../guide/).

Les limites sont indiquées sur la ligne concernée : *ordinateur uniquement*, *Android uniquement*, *pas dans la démo web*.

---

## Jouer

### Claviers et gammes

- **GrooveForge Keyboard** joue une soundfont (.sf2) sur son propre canal MIDI. Chaque clavier choisit sa soundfont, sa banque et son son.
- Réglez sa soundfont sur **Aucune (MIDI seulement)** : le clavier ne sonne plus et envoie seulement ses notes aux autres modules. [Comment](../guide/#guitare)
- L'icône de réglage à côté du badge CANAL MIDI règle, pour un seul clavier : le nombre de touches affichées, leur hauteur (de Petit à Très grand), l'effet d'un glissé vertical ou horizontal (pitch bend, vibrato, glissando) et le CC envoyé par l'aftertouch.
- Le clavier affiche le nom de l'accord tenu (Cmaj7, F#m11). Touchez ce nom pour verrouiller le clavier sur la gamme de cet accord.
- Ajoutez vos soundfonts dans les Préférences, avec **Charger une Soundfont (.sf2)**.

### Xen : jouer dans une gamme

- Tenez une touche et touchez une gamme : la touche devient la tonique, et chaque note jouée tombe dans la gamme. [Comment](../guide/#gamme)
- 92 gammes en 11 familles : Occidental, Maqam, Persan, Raga, Extrême-Orient, Asie du SE, Gamelan, Afrique, Europe, Tempéraments et Expérimental (divisions égales de 13 à 31 notes, Bohlen-Pierce, alpha, bêta et gamma de Wendy Carlos).
- Les gammes qui ont des notes entre les touches du piano réaccordent les touches qu'elles utilisent. Chaque note d'un accord garde son propre accordage.
- Les touches grises sont hors gamme ; les touches réaccordées portent une bande turquoise et leur écart en cents.
- **SNAP** (ramener les fausses notes dans la gamme) et **TUNE** (appliquer l'accordage de la gamme) s'activent séparément, et chacun a sa prise.
- L'**Éditeur de gamme** crée vos propres gammes, rangées dans **Mes gammes**. Il importe et exporte des fichiers Scala (.scl) et des fichiers .json GrooveForge.
- Un projet garde une copie des gammes perso qu'il utilise : il joue juste sur un autre appareil.
- Un nouveau projet démarre avec un clavier et un module Xen, éteint tant que vous n'avez pas choisi de gamme.

### Mode Jam : suivre un autre musicien

- Un clavier (le guide) joue des accords ou une ligne de basse ; les claviers ajoutés comme cibles restent dans la gamme qui va avec. Un seul Mode Jam par projet.
- **DÉTECTION** choisit ce qui fixe la gamme : l'accord tenu par le guide, ou sa note la plus grave.
- 14 types de gamme, de Standard, Blues et Pentatonique à Dorien, Mineure harm. et Par tons.
- **SYNC** ne change la gamme que sur le temps, la demi-mesure ou la mesure.
- Des bordures de touches et un surlignage des fausses notes, en option, montrent ce qui va.
- **Épingler sous le transport** affiche une ligne Mode Jam sous la barre de transport.

### Instruments

- **Riff** est une guitare électrique modélisée corde par corde. Elle n'a pas de touches : un clavier ou un contrôleur lui envoie les notes. [Comment](../guide/#guitare)
- Le palm mute, la position du médiator, les micros, la tonalité et le sustain de Riff agissent sur les cordes qui sonnent déjà. Le Legato joue hammer-ons et pull-offs ; Feedback fait monter les notes tenues vers une harmonique. *Pas dans la démo web.*
- **Vocodeur** : chantez dans le micro en jouant des touches, votre voix prend la hauteur des notes. Quatre modes : Dent de scie, Carrée, Choral et Harmonie (votre propre voix, transposée sur chaque touche). *Pas dans la démo web.*
- **Stylophone** : une bande de 25 touches jouée d'un doigt, une note à la fois. Quatre formes d'onde, changement d'octave, vibrato (VIB), et des réglages chiptune (largeur d'impulsion, bruit, bit crusher, sous-octave, arpège rapide d'accords).
- **Thérémine** : un pad tactile, la hauteur de haut en bas, le volume de gauche à droite. Note de base, tessiture, vibrato et hauteur du pad se règlent.
- Le mode **CAM** du Thérémine règle la hauteur selon la distance entre votre main et la caméra. *Android et macOS.*
- Stylophone et Thérémine ont une prise MIDI OUT, et un bouton MUTE qui coupe leur propre son pour jouer un autre instrument.
- **Live Input** fait entrer un micro ou une entrée ligne dans le rack, pour le passer dans des effets ou l'enregistrer dans un looper. *Pas dans la démo web.*
- Sur un téléphone, Live Input se coupe tout seul quand le haut-parleur reviendrait dans le micro (larsen). **Réactiver quand même** passe outre. *Android uniquement.*
- **Instruments VST3** : chargez un instrument VST3 installé, ou allez chercher un fichier .vst3. Ses réglages s'affichent en potards. *Ordinateur uniquement.*
- La fenêtre du plugin s'ouvre depuis son module. *Linux et macOS ; sous Windows, utilisez les potards.*

---

## Travailler le son

Pour placer un effet après un instrument, câblez-les dans la vue de câblage : [Ajouter un effet](../guide/#effet). Un module d'effet traite un seul instrument ; ajoutez un deuxième module pour un deuxième instrument.

### Effets audio

*Pas dans la démo web.*

- **Ampli** : une pédale de saturation (Overdrive ou Distorsion), trois modèles d'ampli (US, Brit, AC) et trois baffles. Chaque section s'allume et s'éteint. [Comment](../guide/#ampli)
- L'Ampli peut charger une réponse impulsionnelle de baffle (IR) depuis un fichier .wav, à la place de ses baffles. L'IR est enregistrée avec le projet.
- **Réverb à plaque** : réverbération stéréo.
- **Delay Ping-Pong** : écho stéréo qui peut suivre le tempo.
- **Wah** : en mode Auto, le filtre balaie tout seul, en rythme ; en mode Manuel, il suit une pédale ou un potard de votre contrôleur.
- **EQ 4 bandes** : graves, deux bandes de médiums et aigus.
- **Compresseur** : égalise les passages forts et doux.
- **Chorus / Flanger** : chorus stéréo qui peut suivre le tempo.
- **Harmoniseur Audio** : ajoute jusqu'à 4 voix d'harmonie à n'importe quel son. Avec **Verrou gamme**, les voix suivent la gamme de Xen ou du Mode Jam.
- **Autotune** : ramène une voix sur les notes d'une tonalité et d'une gamme, de la correction discrète à la voix de robot. Il affiche la note chantée et son écart en cents.
- Les **effets VST3** se placent après n'importe quel instrument ou effet. *Ordinateur uniquement.*

### Effets MIDI : changer les notes

Les effets MIDI modifient les notes avant qu'un instrument les joue. Plus de détails sur la [page MIDI FX](../midi-fx/).

- **Harmoniseur** : ajoute jusqu'à 4 notes au-dessus de chaque note jouée. Branchez-y l'ACCORD OUT d'un clavier : l'accord tenu fixe les intervalles.
- **Chord Expand** : transforme chaque note en accord complet (11 types d'accords, serré, ouvert ou large).
- **Arpégiateur** : joue les notes tenues l'une après l'autre, avec 6 motifs et 12 vitesses, sur 1 à 3 octaves.
- **Transposeur** : décale toutes les notes, jusqu'à 24 demi-tons vers le haut ou le bas.
- **Courbe de vélocité** : change la façon dont la force de jeu se traduit en volume.
- **Gate** : ne laisse passer que les notes dans une plage de vélocité ou de hauteur.
- **Microtone** : joue les notes tenues ensemble comme une seule note située entre elles, par pitch bend.
- Chaque effet MIDI a un bouton marche/arrêt qu'on peut associer à un contrôleur.
- **Charger un fichier .gfpd…** ajoute un module décrit dans un descripteur de plugin. Voyez [Descripteurs de plugins](../gfpd/).

### Vue de câblage

- L'icône de câble en haut montre l'arrière de chaque module. Appuyez longuement sur une prise et glissez vers une autre pour les relier. [Comment le son circule](../guide/)
- Couleurs des prises : jaune pour les notes (MIDI), rouge et blanc pour le son, orange pour les boucles d'effet, violet pour l'accord et la gamme, turquoise pour l'accordage. [Couleurs des prises](../guide/#prises)
- Touchez le ✕ d'un câble pour le retirer. [Comment](../guide/#retirer)

---

## Rythme et boucles

- La barre de transport règle le tempo (de 20 à 300 BPM, tapé au clavier, ajusté avec − et +, ou battu avec **Tap**), la signature rythmique, lecture et arrêt, et le métronome.
- Batterie, loopers, effets synchronisés et plugins VST3 suivent tous ce même tempo.

### Générateur de batterie

- Joue un rythme de batterie calé sur le transport. [Comment](../guide/#batterie)
- 35 rythmes fournis : rock, funk, disco, jazz, latin, brésilien, celtique, marches, techno, dub, R&B, metal, et des rythmes arabes, turcs, persans, indiens, japonais et chinois.
- **Swing** et **Feeling humain** changent le groove, de la grille stricte au batteur en chair et en os.
- **Décompte**, **Fill tous les** (un fill toutes les quelques mesures), crash après le fill et montée dynamique.
- **Charger un .gfdrum…** joue vos propres rythmes. Voyez [Patterns (.gfdrum)](../gfdrum/).

### Looper MIDI

- Enregistre les notes jouées, les renvoie en boucle vers un instrument, et superpose de nouvelles couches. Un seul par projet.
- Chaque piste a sa coupure, sa lecture à l'envers, sa demi ou double vitesse, son volume et sa quantification (de off à 1/32).
- Affiche l'accord de chaque mesure.
- **Épingler sous le transport** place ses commandes sous la barre de transport.

### Looper Audio

*Pas dans la démo web.*

- Enregistre le son de n'importe quel module câblé dessus, effets compris, et le joue en boucle. [Comment](../guide/#boucle)
- Avec la synchro de mesure, l'enregistrement démarre à la mesure suivante et la boucle est arrondie à des mesures entières.
- Overdub, lecture à l'envers, et un menu **Source** pour choisir ce qu'il enregistre sans ouvrir la vue de câblage.
- Changez le tempo : les boucles le suivent sans changer de hauteur.
- Les boucles sont enregistrées en fichiers WAV à côté du projet. Le module prévient quand elles dépassent 256 Mo de mémoire.

---

## Jouer ensemble : les répétitions

L'onglet **Répéter**. Chaque musicien enregistre sa partie d'un morceau sur son propre appareil. Tout le détail sur la [page Répétitions](../rehearsals/).

- **Lancer un morceau** avec un tempo, une signature et un décompte, ou **Rejoindre un morceau** depuis un autre appareil. [Comment](../guide/#repetition)
- Chacun ajoute une partie pour son instrument et l'enregistre sur un clic commun. Vous pouvez réenregistrer ou supprimer vos parties, jamais celles des autres.
- Les prises tombent sur le temps : **Calibrer** mesure le retard de votre appareil à jouer et à enregistrer, et chaque prise est recalée d'autant. Le haut-parleur, un casque filaire et chaque casque Bluetooth sont mesurés à part.
- **Enregistrer depuis le rack** : une partie peut enregistrer directement un instrument du rack au lieu du micro.
- Importez un enregistrement pour jouer dessus (MP3, FLAC, WAV ; sur Android aussi M4A, AAC et le son d'une vidéo). Battez le tempo et glissez un repère sur le premier temps pour caler la grille.
- **Vitesse de travail** ralentit le morceau jusqu'à 50 % sans le faire descendre. Seul votre appareil est concerné.
- **Accords** : écrivez la grille mesure par mesure, jusqu'à quatre accords par mesure. La mesure jouée s'allume.
- **Partitions** : ajoutez un PDF, une grille ou la photo d'une page, et chaque musicien en reçoit une copie.
- Les parties passent d'un appareil à l'autre par le Wi-Fi local, chiffrées, sans serveur, sans compte et sans internet. On rejoint une fois avec un QR code ou un lien ; ensuite les appareils se retrouvent seuls.
- Un point sur chaque partie indique si son musicien est connecté. Un avertissement signale une prise qui n'est pas encore arrivée chez tout le monde.
- **Enlever la fuite du haut-parleur** retire le clic d'une prise enregistrée avec le haut-parleur du téléphone. L'original est gardé. *Android uniquement.*
- Scanner un QR code demande la caméra d'un téléphone. Sur ordinateur, collez le lien.

---

## Contrôleurs

- Branchez un clavier ou un contrôleur à pads MIDI en USB (avec un adaptateur OTG sur téléphone), ou en Bluetooth sur Android, via **Préférences** > **Connecter un appareil MIDI**. [Comment](../guide/#controleur)
- Votre contrôleur joue le module dont le badge CANAL MIDI correspond à son canal (1 à 16).
- Pitch bend, molette de modulation, CC et aftertouch arrivent aux instruments, à travers câbles et effets MIDI.
- Associez un potard, un fader ou un pad à n'importe quel réglage d'un module : l'icône de curseurs sur le module, puis **Learn**. [Comment](../guide/#learn)
- **Préférences de mapping CC** associe un CC à : les contrôles MIDI standard (volume, panoramique, expression, sustain, envoi de réverb...), le pitch bend, n'importe quel réglage de module, les loopers, lecture/arrêt, Tap, le métronome ou le volume système.
- Un seul potard peut piloter plusieurs cibles à la fois.
- Actions système : soundfont et son suivants ou précédents, balayage des sons, démarrer ou arrêter le Mode Jam, changer de type de gamme, et couper ou rétablir un groupe de canaux d'un seul bouton.
- Un pad peut rappeler un son précis de la soundfont (**Select Patch**) ou une gamme Xen. Plusieurs pads, plusieurs sons ou gammes.
- **Échange de canaux** : un bouton échange les canaux MIDI de deux instruments, avec leurs câbles et effets si vous le voulez.
- **Valeur neutre au relâchement**, pour les rubans et bandes tactiles qui retombent à 0 quand on lève le doigt.
- Le contrôle du volume système marche sur Android, Linux et macOS.
- Les associations sont enregistrées dans le projet.

---

## Projets et réglages

- Un projet (fichier .gf) garde vos modules, câbles, réglages, tempo, associations, boucles MIDI et gammes perso. [Comment](../guide/#projets)
- L'icône de dossier propose **Nouveau projet**, **Ouvrir un projet** et **Enregistrer sous…**.
- L'app garde votre session en cours d'un lancement à l'autre. *Pas dans la démo web : utilisez* **Enregistrer sous…** *pour télécharger un fichier .gf.*
- Les boucles audio sont enregistrées en WAV à côté du projet ; l'IR de l'Ampli est enregistrée dedans.
- **Préférences** : réglages par défaut des claviers, soundfonts, appareils MIDI, choix du micro et de la sortie, langue (anglais ou français).
- La barre audio sous le transport règle le gain des claviers, la sensibilité du micro et le micro. Sur Android, elle choisit aussi la sortie.
- L'icône point d'interrogation ouvre le guide intégré, avec les nouveautés de la dernière version.

---

## Plateformes

- **Android** : tout, sauf le VST3. Sur [Google Play](https://play.google.com/store/apps/details?id=com.grooveforge.grooveforge), [F-Droid](https://f-droid.org/packages/com.grooveforge.grooveforge/) et la page des releases GitHub.
- **Linux** : tout, VST3 compris. Paquets .deb, .rpm, Arch, Flatpak et .zip. Le son passe par PipeWire ou JACK : vous pouvez le relier à d'autres applis audio.
- **macOS** : tout, VST3 et leurs fenêtres compris.
- **Windows** : tout, VST3 compris, mais les fenêtres des plugins VST3 ne s'ouvrent pas encore : utilisez les potards de GrooveForge.
- **Démo web** : à essayer dans le navigateur, sans installation. Vocodeur, Riff, Looper Audio, Live Input et les effets audio y sont grisés avec un badge **Applis uniquement**, et le VST3 n'est pas proposé. Votre session n'est pas gardée.
- **iOS** : non pris en charge. La version iOS n'a jamais été testée.

### Android uniquement

- **Sortie USB directe** (Préférences > Sortie Audio) joue par une carte son USB qu'Android abandonnerait quand un micro USB est branché en même temps.
- Quand la sortie retombe sur un chemin lent, un avertissement apparaît avec un bouton **Rétablir la faible latence**.
- Le son peut aller vers une carte son USB choisie ; si elle est débranchée, il revient sur la sortie par défaut.

---

*Dernière mise à jour : 2026-11-25*
