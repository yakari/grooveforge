# Changelog

Toutes les modifications notables apportées à ce projet seront documentées dans ce fichier.

Le format est basé sur [Keep a Changelog](https://keepachangelog.com/fr/1.0.0/),
et ce projet adhère à la [Gestion Sémantique de Version](https://semver.org/lang/fr/).

## [2.12.7] - 2026-04-13

### Corrigé
- **Le Vocoder joue un son de piano après changement de son canal MIDI** (toutes plateformes). Changer le canal MIDI du plugin GFPA Vocoder depuis l'UI du rack mettait à jour le champ `midiChannel` du plugin mais ne ré-appliquait jamais la carte de canal au moteur audio — donc `AudioEngine.channels[nouveauCanal].soundfontPath` restait à sa valeur par défaut (ou celle du précédent occupant) au lieu d'être basculé sur le marqueur `vocoderMode`. La dispatch de notes dans [audio_engine.dart](lib/services/audio_engine.dart) `playNote` voyait alors un chemin de soundfont non-vocoder sur le nouveau canal et tombait dans `keyboardNoteOn(...)` → FluidSynth → et puisque le `_slot_for_channel` côté C écrase tout canal d'index impair sur le slot FluidSynth 0, les notes du vocoder finissaient par doubler le son de piano que le clavier du slot 0 jouait. Le bug était visible depuis un rack vierge : ajouter un Vocoder, changer son canal, presser une touche, entendre du piano.
  - Correctif dans [rack_state.dart](lib/services/rack_state.dart) `setPluginMidiChannel` : quand le plugin est un `GFpaPluginInstance` (pas seulement un `GrooveForgeKeyboardPlugin`), appeler `_applyGfpaPluginToEngine(plugin)` après la mise à jour de `midiChannel`. Pour la branche Vocoder cela re-exécute `assignSoundfontToChannel(nouveauCanal - 1, vocoderMode)` pour que le nouveau canal soit correctement marqué. Efface aussi le marqueur `vocoderMode` de l'**ancien** canal pour que le canal d'où le vocoder vient de partir ne continue pas à router silencieusement les notes des futurs plugins à travers le DSP vocoder.
  - Le même correctif débloque le Theremin et tout futur plugin GFPA qui aurait besoin d'état par canal — le garde `if (plugin is GrooveForgeKeyboardPlugin)` ignorait tous les autres types de plugins.
  - Découvert en testant l'Harmoniseur Audio dans la session 4 : l'utilisateur essayait de libérer un canal MIDI pour un clavier câblé dans l'harmoniseur, a déplacé le Vocoder pour le mettre hors de portée sur le canal 7, et a découvert que le vocoder s'était silencieusement transformé en voix de piano dupliquée. Le DSP de l'Harmoniseur Audio lui-même fonctionnait correctement tout du long.
- **Linux — le looper audio enregistrait du silence quand un Vocoder y était câblé**. Quand le Vocoder était câblé à un slot de looper audio sous Linux/macOS, le looper enregistrait du silence ou du bruit corrompu au lieu de la sortie du vocoder. Cause racine : le callback JACK enregistre le vocoder à la fois comme **contributeur master-render** (pour qu'on l'entende sur la sortie principale) et comme **source de looper audio** (pour que le looper capture son audio). Les deux inscriptions vivent sur le même thread audio, donc `_vocoder_render_block_impl` dans [native_audio/audio_input.c](native_audio/audio_input.c) était appelée deux fois par bloc audio : une fois via master render, une fois via le pull de source du looper. Chaque appel avançait l'état DSP partagé — enveloppes de voix, phase du LFO, curseur de détection ACF, biquads du banc de filtres, `natReadPos` des oscillateurs — donc le second appel lisait de l'état déjà muté par le premier et produisait une sortie différente, corrompue. C'est cette sortie du second appel que le looper enregistrait. La sortie master restait audible (premier appel) mais le looper capturait n'importe quoi.
  - Correctif : cache de sortie par bloc dans `_vocoder_render_block_impl`. À chaque appel, la fonction s'horodate via `clock_gettime(CLOCK_MONOTONIC)`. Si l'appel précédent était à moins de 1 ms (plus court que toute période de bloc JACK réaliste mais énormément plus long que l'écart microsecond entre les pulls master et looper dans un même callback) et que le nombre de frames correspond, la fonction renvoie la sortie stéréo en cache sans toucher à l'état DSP. Le cache est un simple `float[4096]` par canal — couvre toutes les tailles de bloc JACK pratiques sur desktop Linux. Master-render et looper-source voient de l'audio identique ; l'état DSP avance exactement une fois par bloc. Aucun changement de couche de routage, aucun nouvel atomique, aucun câblage cross-module.
  - Réglage de la fenêtre de cache : 1 ms est la plus petite valeur qui couvre le jitter intra-callback tout en invalidant au prochain vrai bloc (≥ 1,33 ms à 64 frames / 48 kHz, le plus petit buffer JACK réaliste). Les tailles de frame supérieures à 4096 passent outre et recalculent à chaque fois — aucun buffer réaliste n'atteint cette taille, mais si c'était le cas, le bug de double-appel réapparaîtrait gracieusement plutôt que de renvoyer silencieusement de l'audio périmé.
  - Une première tentative dans cette session a essayé de corriger le bug dans la couche de routage Dart en retirant le vocoder du master render quand il n'était câblé qu'à un looper. Cela rendait le vocoder **complètement inaudible** dès que le clip du looper était IDLE (en attente d'armement), parce que le pull de source du looper ne se déclenche qu'en état RECORDING — il n'y avait plus aucun chemin toujours-actif pilotant le DSP du vocoder. Reverté immédiatement. Le cache côté C est la bonne correction parce qu'il fonctionne quel que soit le chemin de rendu qui appelle la fonction.

### Ajouté
- **Mode NATURAL du vocoder — réécriture loop-resample** (toutes plateformes). L'ancien moteur de grains PSOLA dans [native_audio/audio_input.c](native_audio/audio_input.c) produisait une sortie audible hachée dès que la fréquence MIDI cible était inférieure à la hauteur détectée de la voix micro, parce que la période de redéclenchement des grains (`SR/targetHz`) dépassait la longueur du grain Hanning (2 × période détectée), laissant du silence entre les grains. Remplacé par un **re-échantillonneur de grain vocal en boucle** :
  - **Étape de capture** (`capture_natural_loop`). Quand la corrélation du détecteur de hauteur ACF franchit son seuil de confiance (même règle `g_naturalMaxCorr * 0.8f || > 0.5f` qu'avant), un nombre d'échantillons micro validés en pitch égal à `numPeriods × detectedLag` est copié dans `g_natLoopBuf[]`, où `numPeriods` est le plus grand entier tel que le résultat tient dans la capacité de 1024 échantillons. **Le bouclage à nombre entier de périodes est la clé** : pour une onde périodique, l'échantillon N·P égale l'échantillon 0 par définition, donc la couture est continue par construction et aucun cross-fade n'est nécessaire. Les captures qui ne peuvent pas tenir au moins 2 périodes complètes (voix très graves ≲ 95 Hz) sont rejetées pour que le renderer ne joue pas un buzz d'un seul cycle. Normalisation RMS à ~0,4 pour un niveau de porteuse constant dans le banc de filtres.
  - **Étape de rendu** (branche NATURAL dans `renderOscillator`). Chaque voix polyphonique garde un curseur fractionnaire `natReadPos` dans la boucle capturée. Le curseur avance de `targetHz / capturedHz` échantillons par échantillon de sortie, donc une voix capturée à 200 Hz jouée sur une cible MIDI de 100 Hz avance de 0,5 échantillons/échantillon (octave en bas) et à 400 Hz de 2,0 (octave en haut). Interpolation linéaire entre échantillons adjacents — rapide et largement suffisant pour la plage vocale 80–1000 Hz. Le curseur reboucle à `g_natLoopLen` (pas à la taille de buffer compile-time) et clampe défensivement contre les changements de longueur publiés en milieu de sample par le thread de capture.
  - **Démarrage silencieux** — quand aucune boucle n'a encore été capturée (pas de convergence ACF depuis l'initialisation du périphérique), la branche sort zéro. Avant, le moteur PSOLA sortait les données périmées restantes dans le buffer overlap-add, ce qui pouvait produire une légère « queue » audible d'une session précédente.
  - **Mémoire récupérée** : suppression du tableau float `oaBuffer[PSOLA_OA_SIZE=1024]` par voix dans la struct `Oscillator`, économisant 4 Ko × 16 voix = 64 Ko d'état statique. Remplacé par un seul `float natReadPos` par voix. Aussi retirés les champs `pulseTimer` et `oaCursor` devenus inutilisés.
  - **Journal de décision** dans [docs/dev/ROADMAP.md](docs/dev/ROADMAP.md) sous « NATURAL vocoder mode — reality check ». Le roadmap prévoyait à l'origine de remplacer PSOLA par `gf_pv_pitch_shift` de la bibliothèque vocodeur de phase, mais une fois qu'on a cartographié ce que le mode NATURAL fait réellement — générer un son soutenu à la hauteur MIDI depuis un court extrait de micro capturé, potentiellement des secondes après que le micro s'est tu — on a réalisé qu'un vocodeur de phase streaming est le mauvais outil pour ce cas d'usage. La bibliothèque vocodeur de phase reste en place pour son vrai cas d'usage (le futur effet GFPA Harmoniseur Audio). La première tentative de l'approche loop-resample utilisait une boucle fixe de 1024 échantillons avec un cross-fade linéaire à la couture, et sonnait objectivement pire que PSOLA — les deux choix étaient mauvais (le cross-fade fabriquait sa propre discontinuité, et une longueur de boucle arbitraire produisait une modulation sous-harmonique à ~47 Hz par-dessus la fondamentale). Le bouclage à nombre entier de périodes sans cross-fade est la technique correcte.
- **Looper audio — lecture synchronisée au tempo via le vocodeur de phase** (Android, Linux, macOS). Une boucle enregistrée à un BPM donné se lit maintenant au BPM courant du transport sans décalage de hauteur. Avant, le looper avançait d'un échantillon enregistré par frame de sortie ; une boucle à 120 BPM jouée à 140 BPM restait donc à 120 BPM (décalée du transport), ou — si l'hôte la retimait à la volée — montait en hauteur. Avec le vocodeur de phase activé, une boucle de batterie à 120 BPM jouée à 140 BPM devient 16,7 % plus courte tandis que les caisses claires et cymbales gardent leur hauteur d'origine.
  - **Activation automatique** dès que `|1 − recordBpm/bpmCourant| ≥ 0,005` (≈ 0,6 BPM à 120). Dans cette zone morte, l'ancien chemin rapide échantillon-par-échantillon continue de tourner sans modification : les clips joués à leur tempo d'enregistrement ne paient aucun surcoût CPU et sortent bit-à-bit identiques à la version précédente.
  - **État vocodeur par clip** logé dans `ALooperClip` : un `gf_pv_context*` plus des buffers scratch entrelacés, tous alloués sur le thread Dart dans `dvh_alooper_create` pour que le thread audio ne voie jamais de `malloc`. `gf_pv_reset` est déclenché via un flag atomique `pvNeedsReset` à chaque (ré)entrée dans l'état PLAYING — `dvh_alooper_set_state` externe, transitions internes RECORDING→PLAYING et STOPPING→PLAYING dans `dvh_alooper_process`, retour automatique après overdub, et `dvh_alooper_clear_data`. Le flag est consommé par un `exchange` pour garantir au plus un reset par transition.
  - **Boucle feed/drain** dans [audio_looper.cpp](packages/flutter_vst3/dart_vst_host/native/src/audio_looper.cpp) : `_processPlayingStretched` alterne entre drainer la sortie déjà disponible (via `_drainPvInto` → un appel `gf_pv_process_block` avec entrée nulle) et pousser un hop d'analyse d'audio du clip (via `_feedPvOneHop` → entrelacement + `gf_pv_process_block` avec capacité de sortie zéro). Une borne de sécurité de 64 itérations empêche tout cas de démarrage à froid pathologique de bloquer le thread audio. La lecture à l'envers est respectée en miroitant l'index de lecture sur la longueur de boucle avant l'entrelacement.
  - **FFT 2048, hop 512** — bonne résolution spectrale pour la musique sans latence excessive. L'artefact de ring-in du premier bloc (~46 ms à 44,1 kHz) est une limitation connue suivie pour la session 2b ; les boucles de batterie auront un très léger fade-in sur les deux premiers temps juste après l'entrée en PLAYING, puis joueront proprement.
  - **Câblage build** : `gf_phase_vocoder.c` est compilé dans trois cibles via des chemins relatifs depuis la source de vérité à la racine — [linux/CMakeLists.txt](packages/flutter_vst3/dart_vst_host/linux/CMakeLists.txt) et [macos/CMakeLists.txt](packages/flutter_vst3/dart_vst_host/macos/CMakeLists.txt) pour `libdart_vst_host`, et [android/.../cpp/CMakeLists.txt](packages/flutter_midi_pro/android/src/main/cpp/CMakeLists.txt) pour `libnative-lib`. Les CMakeLists Linux et macOS activent maintenant le langage `C` aux côtés de `CXX`/`OBJCXX` pour que le `.c` se compile avec le compilateur C de la plateforme.
  - **Pas encore câblé côté Dart** — aucun nouveau symbole FFI ni toggle. La synchro tempo s'active implicitement quand le stretching est nécessaire, ce qui correspond à l'UX attendue pour un looper synchronisé au transport de l'hôte. Un opt-out (pour les utilisateurs qui veulent une lecture pitchée comme effet créatif) pourra être ajouté plus tard via un flag `dvh_alooper_set_tempo_sync` si demandé.
- **Effet GFPA Harmoniseur Audio** (Linux, macOS, Android). Nouvel effet intégré qui produit jusqu'à 4 voix d'harmonie transposées à partir de n'importe quelle entrée audio, mixées avec le signal sec. Câblez n'importe quelle source dedans (GF Keyboard, Stylophone, Theremin, sortie de looper audio, plugin VST3) et la sortie wet est l'entrée plus des voix parallèles transposées aux intervalles configurés.
  - **DSP** : nouvelle classe C++ `HarmonizerEffect` dans [packages/flutter_vst3/dart_vst_host/native/src/gfpa_dsp.cpp](packages/flutter_vst3/dart_vst_host/native/src/gfpa_dsp.cpp) qui détient 8 contextes vocodeur de phase (4 voix × 2 canaux, mono par canal) préalloués dans le constructeur — aucune allocation sur le thread audio. À chaque bloc, l'entrée est passée à travers les paires de `gf_pv_context*` de chaque voix active avec le décalage en demi-tons par voix appliqué via `gf_pv_set_pitch_semitones`, la sortie transposée résultante est sommée dans le bus de sortie pré-amorcé en sec avec le gain de mix par voix, et le `dry_wet` master contrôle l'équilibre sec/wet. Le bypass et les écritures de paramètres utilisent le pattern `std::atomic<float>` standard partagé avec tous les autres effets GFPA.
  - **La transposition fonctionne enfin** : `gf_pv_pitch_shift` était une API stub à travers les sessions 1–3 — seul le time-stretch était live, et `gf_pv_set_pitch_semitones` était un no-op. Cette release la câble correctement. L'implémentation dans [native_audio/gf_phase_vocoder.c](native_audio/gf_phase_vocoder.c) compose le time-stretch existant avec une étape de ré-échantillonnage côté sortie : `internal_stretch = user_stretch × pitch_ratio` pilote la pipeline FFT (donc l'audio est étiré plus longtemps que demandé), puis l'étape de drain lit le ring de sortie à un curseur fractionnaire avançant de `pitch_ratio` échantillons par frame de sortie avec interpolation linéaire entre échantillons adjacents. Effet net : `output_length = input_length × user_stretch` et chaque composante fréquentielle est multipliée par `pitch_ratio`, exactement comme la transposition par vocodeur de phase classique le prescrit. Le chemin rapide (pitch_ratio == 1) court-circuite entièrement le drain fractionnaire pour que les consommateurs time-stretch existants (looper audio, session 2) restent bit-à-bit identiques et inchangés.
  - **Smoke test étendu** [native_audio/gf_pv_smoke_test.c](native_audio/gf_pv_smoke_test.c) : génère un sinus pur 440 Hz, appelle un nouveau helper offline `gf_pv_pitch_shift_offline` pour le décaler de +12 demi-tons (octave en haut → 880 Hz) et −12 demi-tons (octave en bas → 220 Hz), et vérifie que la magnitude DFT à la fréquence de sortie attendue domine le résidu à 440 Hz d'au moins 3×. Les deux décalages passent avec une marge > 500× sous Linux. Les WAV de sortie sont écrits sous `/tmp/gf_pv_up12.wav` / `/tmp/gf_pv_down12.wav` pour audition.
  - **Câblage build** : aucun changement requis — `gfpa_dsp.cpp` est déjà compilé dans `libdart_vst_host.so` (Linux/macOS) et `libnative-lib.so` (Android), et `gf_phase_vocoder.c` est déjà dans ces mêmes libs depuis l'intégration looper audio de la session 2. L'harmoniseur ajoute juste un nouveau `#include "gf_phase_vocoder.h"` et consomme les symboles existants.
  - **Dispatch** : l'id de plugin `com.grooveforge.audio_harmonizer` est reconnu par `gfpa_dsp_create` (nouvelle branche aux côtés de Reverb / Delay / Wah / EQ / Compressor / Chorus). Une nouvelle valeur d'enum `GfpaEffectType::Harmonizer`, un membre d'union et un case de switch ont été ajoutés au dispatch `GfpaDspInstance` existant dans [gfpa_dsp.cpp](packages/flutter_vst3/dart_vst_host/native/src/gfpa_dsp.cpp). Quand le slot harmoniseur entre dans le rack, `RackState` appelle automatiquement `registerGfpaDsp(slotId, "com.grooveforge.audio_harmonizer")` et la chaîne d'inserts JACK/Oboe câble le callback de processus du nouvel effet exactement comme tous les autres effets intégrés.
  - **Distinct du MIDI FX existant** : enregistré sous `com.grooveforge.audio_harmonizer` (pas `com.grooveforge.harmonizer`, qui est le MIDI FX préexistant qui ajoute des notes d'harmonie au MIDI entrant). Les deux plugins coexistent — l'un opère sur le MIDI avant le synthé, l'autre sur l'audio après. Tuiles utilisateur : **Audio Harmonizer** / **Harmoniseur Audio**.
  - **10 paramètres** : `voice_count` (1..4, défaut 2), `voice{1..4}_semitones` (-24..+24 demi-tons, défauts +7 / +12 / +4 / -5 — quinte, octave, tierce, quarte vers le bas), `voice{1..4}_mix` (0..1, défauts 0,7 / 0,7 / 0,5 / 0,5), `dry_wet` master (0..1, défaut 0,5). Figés par [test/plugins/audio_harmonizer_test.dart](test/plugins/audio_harmonizer_test.dart).
  - **Limitation connue — ring-in du premier bloc** : chaque contexte PV a le warm-up habituel de ~46 ms à FFT 2048 / hop 512 (4 voix × 2 canaux = 8 contextes, tous en train de chauffer en parallèle). Pendant cette fenêtre, les voix wet ne contribuent rien et le signal sec passe sans atténuation, donc l'harmoniseur « fade in » sur les ~46 premières ms après une insertion fraîche ou un reset d'état. Pour des parties d'harmonie tenues c'est inaudible ; pour des stabs staccato la première attaque est sec uniquement. Suivi comme session 4b dans la roadmap, aux côtés de la limitation looper correspondante.

### Architecture
- **Bibliothèque DSP vocodeur de phase** (fondation pour la synchro tempo du looper audio, l'effet harmoniseur, et la correction du mode NATURAL saccadé du vocoder). Nouveau module C sans allocation [native_audio/gf_phase_vocoder.h](native_audio/gf_phase_vocoder.h) + [gf_phase_vocoder.c](native_audio/gf_phase_vocoder.c) implémentant une transformée de Fourier à court terme verrouillée en phase : les pics spectraux sont détectés par trame d'analyse, leur avance de phase en fréquence instantanée est calculée à partir de l'incrément de phase mesuré, et les phases des bins environnants sont verrouillées sur la rotation du pic (Laroche & Dolson 1999). Cela préserve la cohérence de phase verticale entre partiels et garde les transitoires nets sous étirement — important pour les boucles de batterie où un vocodeur de phase classique bave sur les frappes. Inclut une FFT complexe Cooley-Tukey radix-2 itérative autonome avec twiddles précalculés et table de permutation de bits (pas de dépendance KissFFT / pffft pour l'instant — peut être remplacée plus tard si le profilage l'exige). API publique : `gf_pv_create` / `gf_pv_destroy` / `gf_pv_reset` / `gf_pv_set_stretch` / `gf_pv_set_pitch_semitones` / `gf_pv_process_block`, plus un helper offline `gf_pv_time_stretch_offline`. Le contexte possède tous les buffers (buffer de travail FFT, scratch mag/phase, queues overlap-add et ring buffers par canal), donc `gf_pv_process_block` est sûr d'appel depuis le thread audio. La compensation OLA est calculée à partir du recouvrement réel entre fenêtres d'analyse et de synthèse à la création du contexte, donc n'importe quel hop valide (≤ fft_size/4) donne un gain unitaire à travers la chaîne analyse/synthèse. Compilé dans `libaudio_input.so` sur toutes les plateformes desktop ; pas encore branché à un consommateur — les intégrations looper et vocodeur arriveront dans les versions suivantes.
- **Smoke test offline du vocodeur de phase** [native_audio/gf_pv_smoke_test.c](native_audio/gf_pv_smoke_test.c) : génère une boucle de 4 mesures à 120 BPM (sinus 440 Hz plus un clic à chaque temps), étire le tempo à 140 BPM via `gf_pv_time_stretch_offline`, écrit les WAV source et étiré sous `/tmp`, et vérifie trois propriétés : ratio de durée à 5 % près, dérive de gain RMS sous 3 dB, et magnitude DFT à 440 Hz toujours dominante après étirement (préservation de la hauteur). Construit comme cible CMake host-only ; non inclus dans les builds Android/iOS.

## [2.12.6] - 2026-04-12

### Corrigé
- **Android — latence des notes MIDI du GF Keyboard et notes d'accord désynchronisées** : jouer un accord sur le clavier à l'écran ou sur un contrôleur MIDI matériel décalait chaque note de 3 à 9 ms, et les notes seules semblaient nettement « à la traîne » par rapport à l'expérience réactive sous Linux/macOS. Cause racine : chaque `playNote` sur Android passait par trois allers-retours séquentiels Dart → Kotlin → `audioExecutor` → JNI (reset pitch bend, reset CC, note-on), ce qui transformait un accord de 3 notes en une rafale sérialisée de 9 à 27 ms. Le flux AAudio sous-jacent était déjà configuré correctement (`AAUDIO_PERFORMANCE_MODE_LOW_LATENCY` + `AAUDIO_SHARING_MODE_EXCLUSIVE`, ~96–256 frames par burst) — le goulot d'étranglement venait purement de la dispatch par method-channel. Correction en deux temps :
  - **FFI direct dans `libnative-lib.so` pour le chemin critique MIDI.** Nouveaux exports `extern "C"` `gf_native_note_on / note_off / cc / pitch_bend` dans [native-lib.cpp](packages/flutter_midi_pro/android/src/main/cpp/native-lib.cpp) qui font chacun une recherche `synths[sfId]` et un unique appel `fluid_synth_*`. Dart y accède via `DynamicLibrary.lookupFunction` à travers le handle `_looperLib` existant dans [audio_input_ffi_native.dart](lib/services/audio_input_ffi_native.dart) (le même `libnative-lib.so` déjà utilisé pour les symboles du looper audio depuis la v2.12.3). Dans `audio_engine.dart`, `playNote` / `stopNote` / `_sendControlChange` / `_sendPitchBend` branchent désormais sur Android pour appeler directement `AudioInputFFI.gfNativeNoteOn` etc., contournant la chaîne method-channel → audioExecutor Kotlin → JNI de `flutter_midi_pro`. La latence par note chute de ~3 ms (meilleur cas) / ~9 ms (avec les deux resets) à ~0,3 ms — parité avec le chemin FFI direct Linux/macOS via `libaudio_input.so`. Les notes d'accord atteignent désormais `fluid_synth_noteon` synchroniquement dans la même microtâche Dart, donc elles sont simultanées de fait (bien sous le seuil de perception humain).
  - **Suppression des resets pré-emptifs pitch bend / CC de modulation dans `playNote`.** Ces deux appels partaient avant chaque note-on pour remettre l'état du synthé au neutre, mais 99 % du temps l'état était déjà au neutre parce que personne n'était en train de faire un bend ou une modulation. Sur Android, ils étaient le plus gros contributeur à la latence (6 ms sur les 9 ms par note d'accord). Sur Linux, c'étaient des appels FFI directs bon marché mais du travail inutile quand même. Les resets sont maintenant commentés avec une recette de restauration claire au cas où une note-on se retrouverait avec un état bend/mod résiduel — et une implémentation alternative (suivre les dernières valeurs envoyées dans `ChannelState`, ne déclencher que quand non-neutre) est documentée inline pour le cas « restauration conditionnelle ».
  - **`flutter_midi_pro` reste propriétaire du cycle de vie des synthés.** Les entry points JNI method-channel (`loadSoundfont` / `unloadSoundfont` / `selectInstrument` / `setGain`) restent la source de vérité unique pour `synths[]` ; les nouveaux exports FFI sont un pur READ + appel `fluid_synth_*`. FluidSynth est interne-thread-safe entre les événements de note et `fluid_synth_process()` tournant sur le thread audio, et le déchargement de soundfont bloque sur `oboe_stream_remove_synth` qui vide tout callback audio en cours, donc la petite fenêtre de course entre `synths.find` et l'appel direct est astronomiquement improbable. Les entry points JNI existants suivent le même pattern lock-free et sont stables depuis des mois.

## [2.12.5] - 2026-04-12

### Ajouté
- **Looper audio — Stylophone et Vocoder désormais routables sur Android** : câbler un slot Stylophone ou Vocoder vers un looper audio, ou dans n'importe quelle chaîne d'effets GFPA, fonctionne maintenant sur Android. Auparavant, les deux instruments tournaient sur des périphériques `miniaudio` privés qui n'atteignaient jamais le bus Oboe partagé, donc ils apparaissaient dans le sélecteur de source / le panneau arrière mais enregistraient silencieusement du silence — la dernière « limitation connue » restante de la matrice de routage câblé de la v2.12.4. Les deux instruments suivent maintenant le même motif que le Theremin depuis la v2.12.0 : quand un slot entre dans le rack, `NativeInstrumentController` active le mode capture sur le périphérique privé (ce qui coupe la lecture miniaudio) et enregistre une fonction `*_bus_render` sur le bus Oboe partagé (slot 101 pour le stylophone, slot 102 pour le vocoder). L'entrée micro du vocoder reste sur le périphérique de capture miniaudio existant — seul le côté lecture passe sur le bus. Le démontage inverse l'ordre (retrait de la source bus d'abord, puis désactivation du mode capture) pour éviter de déréférencer de l'état DSP libéré depuis le callback audio.
- **Looper audio — routage des sources VST3 sur macOS** : câbler la sortie d'un plugin VST3 dans un slot du looper audio enregistre désormais l'audio du plugin sur macOS, alignant le comportement sur Linux. La boucle de remplissage du looper dans le callback audio macOS n'itérait jusqu'ici que la liste des sources render — elle appelait `dvh_alooper_get_plugin_source_count` uniquement pour l'inclure dans le garde « clip vide → skip », mais ne lisait jamais les sources plugin elles-mêmes, donc tout câble `VST3 → looper` enregistrait silencieusement du silence. Corrigé en ajoutant une deuxième passe qui résout l'ordinal de chaque source plugin en handle `void*` via `ordered[plugIdx]`, le cherche dans la map `bufs` par plugin que `_processPlugins` remplit déjà, et somme la sortie stéréo dans le buffer source privé du clip. Aucune nouvelle allocation sur le thread audio — la map `bufs` existante (déjà un point de churn heap par callback, suivi comme TODO séparé) est réutilisée. Contrôle de borne défensif sur l'ordinal pour qu'une référence de liste de câbles obsolète due à une mutation du rack en cours de callback ne puisse pas faire crasher le callback.
- **Looper audio — avertissement de plafond mémoire** : le moteur du looper audio suit désormais la mémoire totale du pool par rapport à un plafond souple (256 Mo par défaut) et affiche un toast la première fois que le plafond est dépassé dans une session, invitant l'utilisateur à effacer les clips inutiles. Dans la rangée de volume, l'étiquette de mémoire par clip passe à l'ambre à ≥ 75 % et au rouge gras à ≥ 90 % du plafond, pour que l'approche du plafond soit visible avant que le toast ne se déclenche. **Pas un plafond dur** — l'enregistrement continue au-delà du seuil volontairement, pour qu'une performance live ne soit jamais silencieusement tronquée. L'avertissement se réarme quand un clip est détruit, donc libérer de la mémoire puis recroiser produit un nouveau toast.

### Corrigé
- **Looper audio — arrêter une boucle effaçait le PCM enregistré avant que l'autosave puisse le persister** : cause racine du rapport « le wav est enregistré mais pas rechargé à la réouverture ». L'observation de l'utilisateur qui a mis sur la piste : si l'application était tuée pendant que la boucle **jouait**, le clip se restaurait correctement au relancement suivant ; si elle était **arrêtée**, le clip revenait vide. Le bug vivait entièrement dans `dvh_alooper_set_state` (audio_looper.cpp) : la transition `ALOOPER_IDLE` mettait à zéro `clip->length`, `loopLengthFrames` et `loopLengthBeats`. Puisque IDLE est à la fois l'état « en pause, prêt à jouer » ET l'état « vide, prêt à enregistrer », appuyer sur Stop (qui envoie state=IDLE) effaçait silencieusement la longueur enregistrée. Le prochain autosave déclenchait `_exportAudioLooperWavs`, lisait `alooperGetLength` → obtenait 0 → sautait l'export pour ce clip → la passe de nettoyage d'orphelins trouvait l'ancien `loop_$slotId.wav` sur disque non référencé et le **supprimait**. Résultat : les métadonnées JSON du clip survivaient (le côté Dart ne savait pas que la longueur avait disparu) mais l'annexe était effacée, donc le rechargement ne trouvait pas de PCM.
  - Corrigé dans le natif : la branche `ALOOPER_IDLE` ne réinitialise plus que le curseur de lecture et le marqueur de début d'overdub. Elle ne touche plus à `length` ni `loopLengthFrames`, donc un clip arrêté survit à n'importe quel nombre de passes d'autosave.
  - Nouvelle API C `dvh_alooper_clear_data(idx)` qui fournit le chemin explicite « effacer l'audio enregistré » précédemment impliqué par la transition IDLE. Appelée uniquement par le `AudioLooperEngine.clear` Dart (le bouton Clear visible par l'utilisateur), jamais par stop/pause.
  - Le `clear()` Dart appelle maintenant `setState(IDLE)` suivi de `clearData()` pour préserver la sémantique d'effacement du bouton Clear. Les autres appelants de `setState(IDLE)` — `stop()`, `destroyClip()`, la boucle de réinit de `finalizeLoad()` — n'effacent plus le contenu, ce qui est correct.
  - Stubs FFI ajoutés dans `audio_input_ffi_native.dart` (chemin Android) et `dart_vst_host/lib/src/bindings.dart` + `host.dart` (chemin desktop). Stub no-op correspondant dans `audio_input_ffi_stub.dart` pour le web.
  - Affecte toutes les plateformes à égalité — le bug était dans du code C partagé. Les autosaves desktop perdaient silencieusement le contenu à l'arrêt aussi ; c'était juste moins visible parce que les utilisateurs desktop tuent rarement l'application.
- **Looper audio — `saveProjectAs` n'écrivait jamais les WAV annexes** : le flux « Enregistrer sous » nommé écrivait le JSON `.gf` via le chemin `saveFile(bytes: ...)` de `file_picker` puis retournait sans jamais appeler `_exportAudioLooperWavs`, donc rouvrir un projet sauvé ainsi restaurait les métadonnées des clips mais trouvait un répertoire annexe `.audio/` vide et lisait du silence. Corrigé en faisant suivre un `saveProjectAs` réussi d'un export annexe explicite au chemin retourné — mais uniquement quand le chemin ressemble à un vrai chemin système de fichiers (commence par `/`). Sur les fabricants Android qui retournent des URI SAF `content://` depuis leur dialogue d'enregistrement, les annexes ne peuvent toujours pas être écrites ; la méthode logge maintenant un avertissement explicite expliquant que la réouverture ne restaurera que les métadonnées. Une correction complète pour le cas SAF nécessite un picker de projets intégré sous `getApplicationDocumentsDirectory()` et est suivie séparément.
- **Looper audio — `memoryUsedBytes` retournait 0 sur Android** : le getter passait par `VstHostService.instance.host` qui est nul sur Android, donc l'étiquette de mémoire affichait toujours « 0 KB » sur cette plateforme. Corrigé en ajoutant un stub FFI `alooperMemoryUsed` sur `AudioInputFFI` et en branchant sur `_useAndroidPath` dans le getter. Les deux chemins atteignent désormais le même symbole `dvh_alooper_memory_used` (compilé dans `libdart_vst_host.so` sur desktop et `libnative-lib.so` sur Android).
- **Looper audio — `styloSetCaptureMode` manquant du stub web** : lacune préexistante — le binding FFI réel a toujours existé, mais rien sur le chemin non-web ne l'appelait avant la migration du stylophone vers le bus Oboe. Le stub dispose maintenant de la méthode pour que le build web compile quand `NativeInstrumentController.onStylophoneAdded` l'atteint.

### Diagnostics
- **Looper audio — chemin de chargement instrumenté** : `AudioLooperEngine.finalizeLoad`, `VstHostService.importAudioLooperWavs` et `ProjectService._readGfFile` émettent désormais des logs `debugPrint` `[ALOOPER]` / `VstHostService` / `ProjectService` montrant le nombre de clips en attente dans le JSON, le chemin `.gf` passé via `setPendingGfPath`, le chemin et l'existence du répertoire annexe, les vérifications d'existence WAV par clip, et le code de retour natif `alooperLoadData`. Ajouté pour diagnostiquer un rapport où l'autosave écrivait `loop_{slotId}.wav` avec succès mais le lancement suivant de l'application restaurait les métadonnées du clip sans les données PCM — les logs identifient quelle étape sort silencieusement en avance.

### Architecture
- **`audio_input.c` — nouveaux trampolines bus-render** : `stylophone_bus_render(float*, float*, int, void*)` et `vocoder_bus_render(float*, float*, int, void*)`, tous deux correspondant à la signature `AudioSourceRenderFn` attendue par `oboe_stream_add_source`. Chacun est une fine enveloppe autour des implémentations `*_render_block` existantes utilisées par le chemin desktop ; le paramètre `userdata` est inutilisé puisque les deux instruments ont un état DSP singleton. Les exports `*_bus_render_fn_addr()` correspondants retournent l'adresse du trampoline en `intptr_t` pour le FFI Dart.
- **`AudioInputFFI` — nouveaux bindings typés** : `styloBusRenderFnAddr()` et `vocoderBusRenderFnAddr()` reflètent l'entrée `thereminBusRenderFnAddr()` existante. Stubs no-op correspondants ajoutés à `audio_input_ffi_stub.dart` pour la compatibilité web.
- **`NativeInstrumentController` — `onStylophoneAdded/Removed` s'enregistrent maintenant sur le bus Oboe** : auparavant, le stylophone appelait simplement `styloStart()` et jouait via son propre périphérique miniaudio. La méthode appelle aussi désormais `styloSetCaptureMode(true)` + `oboeStreamAddSource(fn, kBusSlotStylophone)` sur Android, reflétant le motif du theremin. Ordre de démontage inversé (retrait bus avant arrêt du périphérique) pour la même raison de drain-wait.
- **`NativeInstrumentController.onVocoderAdded/Removed`** — nouvelles méthodes. Le vocoder n'était pas suivi par le controller auparavant (c'est un `GFpaPluginInstance`, pas un « instrument natif »), donc ce sont des commutateurs de routage purs : bascule du mode capture + enregistrement/retrait de la source bus, sans jamais toucher le périphérique de capture micro (ce cycle de vie est géré globalement par `AudioEngine.startCapture/stopCapture`). Sur les plateformes non-Android les méthodes sont des no-ops parce que le desktop pilote le vocoder via la liste de master-render du VstHost.
- **`RackState.addPlugin/removePlugin` + boucle eager de `SplashScreen`** — bloc `switch` stylophone/theremin étendu pour couvrir `com.grooveforge.vocoder` afin que les nouvelles méthodes du controller se déclenchent sur chaque chemin add/remove, y compris les projets rechargés depuis le disque avant le premier frame.
- **`VstHostService._resolveAndroidBusSlotId`** — étendu pour retourner `kBusSlotStylophone` pour les slots stylophone et `kBusSlotVocoder` pour les slots vocoder. Le resolver de câblage amont Android du looper audio gère désormais les cinq types de sources amont supportées : GF Keyboard, Drum Generator, Theremin, Stylophone, Vocoder. Seuls les plugins VST3 restent non supportés comme sources amont sur Android — et Android n'héberge pas de plugins VST3 du tout, donc c'est un non-problème.

## [2.12.4] - 2026-04-12

### Ajouté
- **Looper audio — sélecteur de source** : le slot du looper audio dispose maintenant d'un sélecteur « Source » compact au-dessus de la zone waveform. L'utilisateur peut choisir n'importe quel slot du rack produisant de l'audio (GF Keyboard, Drum Generator, Theremin, Stylophone, Vocoder, effets audio GFPA, instruments et effets VST3) sans avoir à basculer sur le panneau arrière pour câbler manuellement. Le choix d'une source réécrit les câbles audio : les câbles existants vers le looper sont effacés, et de nouveaux câbles `audioOutL → audioInL` + `audioOutR → audioInR` sont tirés en une seule opération atomique. Choisir « Aucune » efface tous les câbles. Une étiquette « Multiples (N sources) » s'affiche quand l'utilisateur a câblé à la main plusieurs slots amont depuis le panneau arrière — le sélecteur reste fonctionnel et remplace tout à la prochaine sélection. Le sélecteur dérive son état courant du `AudioGraph` à chaque rebuild, donc il n'y a aucun état par clip dupliqué à maintenir synchro avec la vue panneau arrière. La capture du « Master mix » est reportée à un prochain milestone — elle nécessite un nouveau type de routage natif.

### Corrigé
- **Build web cassé par l'import `dart:ffi` dans `project_service.dart`** (régression de la v2.12.3) : le chemin `_exportAudioLooperWavs` ajouté en v2.12.3 importait `dart:ffi` directement (pour le sentinel `nullptr` et l'appel `Pointer<Float>.asTypedList`), ce que `dart2js` et `dart2wasm` rejettent sur la cible web. Le job GitHub Actions `build web` échouait avec `Dart library 'dart:ffi' is not available on this platform`. Corrigé en introduisant un nouveau callback `AudioLooperEngine.wavExporter` (symétrique au `wavImporter` existant) et en déplaçant la plomberie FFI dans `VstHostService.exportAudioLooperWavs` — ce dernier vit déjà derrière un export conditionnel qui insère un stub no-op sur web. `project_service.dart` délègue maintenant via `engine.wavExporter` et n'importe plus `dart:ffi`, `audio_input_ffi.dart` ni `wav_utils.dart`. Helper mort `_audioDir` supprimé.

## [2.12.3] - 2026-04-12

### Ajouté
- **Looper audio — persistance WAV en fichiers annexes sur Android** : les clips du looper audio sont maintenant sauvegardés et restaurés sous forme de fichiers `loop_{slotId}.wav` dans le répertoire `.gf.audio/` sur Android, comme sur desktop. Auparavant, `ProjectService._exportAudioLooperWavs` et `VstHostService.importAudioLooperWavs` sortaient immédiatement sur Android parce qu'ils passaient par un hôte VST qui est nul sur cette plateforme — chaque boucle enregistrée était perdue au redémarrage de l'application.

### Corrigé
- **Looper audio — l'enregistrement Android produisait des clips silencieux quand câblé depuis un clavier** : tous les sites d'appel de `VstHostService.syncAudioRouting` autres que `RackState._onAudioGraphChanged` l'appelaient sans passer le paramètre `keyboardSfIds`. La valeur par défaut est `const {}`, donc sur Android le nouveau helper `_syncAudioLooperSourcesAndroid` ne pouvait résoudre aucun slot clavier vers son ID de slot bus Oboe — `_resolveAndroidBusSlotId` retournait null pour chaque GF Keyboard et Drum Generator, et la liste de sources bus du clip restait vide. Le callback AAudio voyait alors `dvh_alooper_get_bus_source_count(c) == 0`, passait un buffer source NULL au clip, et `_recordSample` écrivait des zéros pendant que le compteur `length` du clip avançait normalement. Résultat : l'utilisateur voyait « Câblez un instrument sur Audio IN » se transformer en clip « enregistrement » avec la bonne durée, mais le buffer PCM ne contenait que des zéros — la lecture était silencieuse et l'aperçu waveform restait vide.
  - **`RackState.buildKeyboardSfIds`** (nouvelle méthode publique) : expose le builder privé existant `_buildKeyboardSfIds` afin que les sites d'appel externes n'aient pas à réimplémenter le lookup canal → sfId.
  - **Cinq sites d'appel corrigés** : deux dans [splash_screen.dart](lib/screens/splash_screen.dart) (la sync de démarrage et la deuxième sync après `initializeAudioEffects`), un dans [audio_looper_slot_ui.dart](lib/widgets/rack/audio_looper_slot_ui.dart) (callback post-frame de `initState`), deux dans [vst3_slot_ui.dart](lib/widgets/rack/vst3_slot_ui.dart) (ajout et suppression d'effet), et un dans [rack_screen.dart](lib/screens/rack_screen.dart) (réinitialisation de nouveau projet). Tous passent maintenant `keyboardSfIds: rack.buildKeyboardSfIds()`.
  - **Avertissement défensif** dans la branche Android de `VstHostService.syncAudioRouting` : `debugPrint` un message bruyant quand `keyboardSfIds` est vide alors que le rack contient des slots `GrooveForgeKeyboardPlugin`. Remonte l'erreur « l'appelant a oublié le paramètre » immédiatement au lieu de produire des enregistrements silencieux.
- **Looper audio — aperçu waveform et export WAV cassés sur Android à cause du dispatch dynamique sur `Pointer<Float>`** : l'aperçu waveform affichait « Aucun audio enregistré » après un enregistrement réussi, et `ProjectService._exportAudioLooperWavs` lançait `NoSuchMethodError: Class 'Pointer<Never>' has no instance method '[]'` à chaque autosave. Trois sites d'appel touchés, tous la même cause sous-jacente — `FloatPointer.operator []` **et** `FloatPointer.asTypedList` sont des méthodes d'extension statiques sur `Pointer<Float>`, donc les invoquer via un receveur typé `dynamic` échoue silencieusement. La correction :
  - **Nouveaux helpers typés** dans `audio_input_ffi_native.dart` : `alooperGetDataAsListL(idx, length)` et `alooperGetDataAsListR(idx, length)` enveloppent le `Pointer<Float>` brut dans une vue `Float32List` zéro-copie *à l'intérieur* du fichier FFI (le seul fichier de ce sous-arbre autorisé à importer `dart:ffi`). Ils retournent `null` quand le buffer natif est `nullptr` ou quand la longueur est non positive, ce qui rend le contrôle nullptr trivial pour chaque appelant. Stubs no-op correspondants ajoutés dans `audio_input_ffi_stub.dart`.
  - **Chemin d'export** (`project_service.dart._exportAudioLooperWavs`) : enveloppe maintenant le `Pointer<Float>` brut retourné par `alooperGetDataL/R` dans une `Float32List` via `ptr.asTypedList(length)` sur le site d'appel (desktop et Android) avant de passer le buffer à `writeWavFile`. Les paramètres `dataL`/`dataR` du helper sont `dynamic` (intentionnellement, pour garder `dart:ffi` hors de `wav_utils.dart`), donc `Float32List` est le seul type qui supporte l'indexation `[]` via le dispatch dynamique. Plus des contrôles `nullptr` défensifs sur chaque pointeur.
  - **Chemin waveform** (`audio_looper_engine.dart.updateWaveform`) : appelle maintenant `AudioInputFFI.alooperGetDataAsListL/R` sur Android au lieu de passer par `VstHostService.instance.host` (nul sur Android). Auparavant la méthode sortait tôt et laissait `clip.waveformRms` vide pour toujours — l'UI affichait alors le placeholder vide même avec un clip PCM valide. Une première tentative de correctif essayait de faire l'enveloppement `asTypedList` dans `audio_looper_engine.dart` via un helper `dynamic` — cela échouait silencieusement pour la même raison de dispatch d'extension. Les nouveaux helpers typés sur `AudioInputFFI` déplacent l'enveloppement à l'endroit où `dart:ffi` est statiquement disponible.
- **UI du looper audio — couverture l10n complète (EN/FR)** : les placeholders de la zone waveform (`Enregistrement…`, `Câblez un instrument sur Audio IN`, `Aucun audio enregistré`), toutes les infobulles de la barre de transport (enregistrer / lecture / annuler / arrêter l'enregistrement & lire / complément jusqu'à la mesure / overdub / arrêter l'overdub / stop / inverser / synchro mesure on-off / effacer) et toutes les étiquettes du chip de statut (`VIDE` / `ARMÉ` / `REC` / `LECT` / `ODUB` / `PAD`) passent maintenant par `AppLocalizations`. Plus aucune chaîne en dur dans `audio_looper_slot_ui.dart`.

### Architecture
- **`AudioInputFFI.alooperGetDataL/R/LoadData`** : nouvelles passerelles FFI pour les trois symboles `dvh_alooper_*` déjà compilés dans `libnative-lib.so` mais jusqu'ici inaccessibles depuis Dart sur Android. Le desktop accédait aux mêmes symboles via `libdart_vst_host.so` — les deux chemins convergent maintenant.
- **`VstHostService.importAudioLooperWavs` — branche par plateforme** : le callback wavImporter partagé gère désormais à la fois le chemin desktop via `VstHost` et le chemin Android via `AudioInputFFI`, en branchant sur `Platform.isAndroid`. Les deux chemins allouent une paire de buffers scratch `dart:ffi` avec `malloc`, y copient le PCM décodé du WAV, la passent au loader et libèrent immédiatement afin que la durée de vie reste bornée à l'appel.
- **`ProjectService._exportAudioLooperWavs` — branche par plateforme** : reflète le split plateforme de l'importeur. Sur Android, la longueur du clip et les pointeurs natifs sont résolus via `AudioInputFFI.alooperGetLength/DataL/DataR` au lieu de `VstHost.getAudioLooper*`. `writeWavFile` accepte déjà un buffer `dynamic` qui supporte l'indexation `[]`, donc `Pointer<Float>` ou toute autre source indexable fonctionnent de manière interchangeable.
- **Clés l10n** ajoutées dans `app_en.arb` / `app_fr.arb` : `audioLooperWaveformRecording`, `audioLooperWaveformCableInstrument`, `audioLooperWaveformEmpty`, `audioLooperTooltipStop/Reverse/BarSyncOn/BarSyncOff/Clear/Record/Play/Cancel/StopRecordingAndPlay/PaddingToBar/Overdub/StopOverdub`, `audioLooperStatusIdle/Armed/Recording/Playing/Overdubbing/Stopping`.
- **`_loopButtonProps` prend maintenant `AppLocalizations` en paramètre** au lieu de le récupérer dans chaque branche du switch — une seule lookup par build, aligné sur le pattern GFPA existant.

## [2.12.2] - 2026-04-12

### Ajouté
- **Looper audio — routage des entrées câblées sur Android** : le looper audio Android n'enregistre désormais que les instruments câblés sur ses ports Audio IN, comme c'était déjà le cas sous Linux. Auparavant, chaque clip actif enregistrait l'ensemble du mixage master, ce qui faisait que les overdubs se réenregistraient eux-mêmes et qu'il était impossible d'enregistrer un seul instrument. Sources amont supportées sur Android : les slots GF Keyboard, les slots Drum Generator (qui passent par le bus FluidSynth de leur canal MIDI), et le Theremin. Le stylophone et le vocoder restent non supportés comme sources amont sur Android car ils tournent sur des périphériques miniaudio séparés qui n'atteignent jamais le bus Oboe partagé.

### Architecture
- **`audio_looper.h/.cpp` — liste de sources bus** : troisième type de source par clip `busSources[ALOOPER_MAX_SOURCES]` (IDs de slot bus Oboe int32) en parallèle des `renderSources` et `pluginSources` existants. Nouvelle API C : `dvh_alooper_add_bus_source`, `dvh_alooper_get_bus_source_count`, `dvh_alooper_get_bus_source`. `dvh_alooper_clear_sources` efface maintenant les trois listes d'un coup, pour que chaque sync de routage reparte d'une ardoise propre.
- **`oboe_stream_android.cpp` — capture à sec** : nouveaux buffers scratch par source `g_srcDryL/R[kMaxSources]`. Le callback AAudio `memcpy` la sortie du render de chaque source dans le buffer dry AVANT l'appel à `gfpa_android_apply_chain_for_sf`, pour que le looper audio enregistre le signal brut de l'instrument plutôt que son signal post-FX — alignement sur la sémantique Linux `renderCapture[m]`.
- **`oboe_stream_android.cpp` — boucle de remplissage câblée** : l'ancien bloc « alimenter chaque clip avec le mixage master » est remplacé par un remplissage par clip qui itère `dvh_alooper_get_bus_source`, trouve la source correspondante dans le snapshot par `busSlotId` et additionne son signal dry stéréo dans `g_alooperSrcL/R[c]`. Un clip sans source bus est ignoré (enregistre du silence). Zéro allocation, zéro verrou, comparaisons de pointeurs uniquement.
- **`VstHostService._syncAudioLooperSourcesAndroid`** : appelée depuis `_syncAudioRoutingAndroid` à chaque reconstruction du routage. Parcourt les câbles audio entrants de chaque `AudioLooperPluginInstance`, résout chaque slot amont en son ID de slot bus Oboe (map `keyboardSfIds` pour les claviers et drum generators, `kBusSlotTheremin` pour le theremin) et transmet la liste via `alooperAddBusSource`. La discipline de routage « pull » existante (clear + ré-ajout à chaque sync) gère automatiquement les changements de soundfont : un nouveau soundfont produit un nouveau sfId et le prochain `_onAudioGraphChanged` reconstruit la liste.
- **`RackState._buildKeyboardSfIds` couvre aussi les drum generators** : les slots drum héritent du sfId FluidSynth de l'instance clavier de leur canal MIDI, donc la même map résout le câblage clavier et drum sur Android.

## [2.12.1] - 2026-04-12

### Ajouté
- **Looper audio — bouton d'assignation CC** : le slot du looper audio dispose désormais du bouton d'assignation CC par slot (icône télécommande) dans son en-tête, comme tous les autres modules. Supporte « Loop Button » (cycle armer/enregistrer/jouer/overdub) et « Stop » comme paramètres assignables via le dialogue standard `SlotCcAssignDialog` avec mode apprentissage.

### Corrigé
- **Modules du rack muets tant qu'on n'a pas scrollé jusqu'à eux** : le rack est un `ReorderableListView.builder` paresseux, donc tout le travail audio-critique vivant dans le `initState()` d'un slot — enregistrement de session, allocation de ressources natives, création de handles DSP, câblage du bus AAudio Android — était silencieusement ignoré tant que le slot n'était pas à l'écran. Une action CC « démarrer » ciblant un module hors écran lançait le transport mais produisait du silence jusqu'à ce que l'utilisateur scrolle manuellement jusqu'au slot. Tous les types de modules audio étaient concernés :
  - **Drum Generator** : l'enregistrement de session (`DrumGeneratorEngine.ensureSession`) est maintenant appelé immédiatement dans `SplashScreen` pour chaque slot drum persisté, avant même le premier frame.
  - **Looper MIDI** : même traitement — `LooperEngine.ensureSession` est appelé immédiatement pour chaque slot looper persisté.
  - **Looper Audio (PCM)** : `AudioLooperEngine.finalizeLoad` est invoqué immédiatement dans `SplashScreen` juste après `vstSvc.startAudio()` pour que les clips natifs existent avant même que le widget ne soit monté ; une seconde passe crée tout clip manquant pour les slots fraîchement ajoutés.
  - **Effets audio GFPA descripteur** (reverb, delay, EQ, compresseur, chorus, wah) : la propriété du plugin a été sortie de `GFpaDescriptorSlotUI` pour être placée dans `RackState`. Un nouveau registre `_audioEffectInstances` + `initializeAudioEffects()` est appelé depuis `SplashScreen` une fois l'hôte VST démarré. `RackState` possède désormais la durée de vie du `GFDescriptorPlugin`, le handle DSP natif et le notifier de paramètres partagé ; le widget est purement cosmétique et lit tout via `audioEffectInstanceForSlot` / `audioEffectParamNotifierForSlot`, en miroir du schéma des MIDI FX.
  - **Stylophone / Theremin** : nouveau service `NativeInstrumentController` qui compte les références aux oscillateurs natifs globaux en fonction de la présence dans le rack. `RackState.addPlugin` / `removePlugin` démarrent/arrêtent le synthé natif — plus le widget. `initState` / `dispose` ne touchent plus `AudioInputFFI.styloStart/Stop` ni `thereminStart/Stop` ni le bus AAudio Android, donc scroller le slot hors écran ne coupe plus l'instrument.

## [2.12.0] - 2026-04-11

### Ajouté
- **Looper Audio (PCM)** : nouveau module de rack qui enregistre et boucle de l'audio stéréo en temps réel avec synchro de mesure, overdub et reverse. Câbler les sorties audio des instruments dans les ports Audio IN du looper sur le panneau arrière — seules les sources câblées sont enregistrées (pas de métronome, pas d'instruments indésirables). Workflow à un seul bouton : idle → arm → enregistrement → lecture → overdub → lecture, identique au looper MIDI.
- **Looper audio — routage d'entrée par câbles** : plusieurs instruments peuvent être câblés à un même looper simultanément. `syncAudioRouting` connecte les sources de rendu (clavier GF, vocoder, theremin, stylophone, générateur de batterie) et les sorties VST3 aux tampons source par clip, mixés dans le callback JACK. Aucune source connectée = silence.
- **Looper audio — enregistrement synchronisé avec remplissage de silence** : en mode synchro mesure, l'enregistrement démarre au sample exact du temps fort. À l'arrêt, l'état `ALOOPER_STOPPING` remplit de silence jusqu'à la prochaine limite de mesure pour que la boucle soit toujours alignée sur des mesures complètes.
- **Looper audio — synchro de mesure optionnelle** : bascule par clip entre mode synchronisé (attente du temps fort) et mode libre (démarrage immédiat). Bouton icône chronomètre sur la carte du looper.
- **Looper audio — overdub en un seul passage** : l'overdub enregistre un tour complet de la boucle puis revient automatiquement en lecture, comme le looper MIDI.
- **Looper audio — aperçu de forme d'onde** : `_WaveformPainter` dessine l'enveloppe RMS depuis les tampons PCM natifs via FFI avec curseur de lecture et indicateur de progression d'enregistrement.
- **Looper audio — persistance WAV sidecar** : les clips sont sauvegardés en fichiers WAV stéréo float 32 bits dans un répertoire `.gf.audio/` à côté du JSON projet. Architecture de chargement différé (`finalizeLoad`) pour gérer le timing JACK-pas-encore-prêt au démarrage.
- **Looper audio — assignations CC** : codes d'action 1015 (bouton Loop) et 1016 (Stop) dans les préférences CC, reliés via le callback `onAudioLooperSystemAction`.
- **Intégration du vocoder dans le pipeline JACK** : `vocoder_render_block()` et `vocoder_set_capture_mode()` ajoutés à `audio_input.c`. Quand le vocoder est câblé au looper audio ou à un effet GFPA, la lecture miniaudio sort du silence et le thread JACK pilote le DSP. L'audio du vocoder peut désormais être capturé par le looper.
- **Isolation de la percussion (FluidSynth slot 2)** : `MAX_KB_SLOTS` augmenté à 3 ; le canal 9 (percussion GM) routé vers le slot dédié 2 au lieu de partager le slot 1 avec le clavier GF 2. Empêche les clics du métronome de contaminer les captures clavier.

### Architecture
- **`audio_looper.h` / `audio_looper.cpp`** : nouveau module C avec structure `ALooperClip` (tampons stéréo pré-alloués, machine d'état atomique), cycle de vie à 5 états (idle/armed/recording/playing/overdubbing + stopping), mixage multi-source par clip (jusqu'à 8 fonctions de rendu + indices plugin), détection de limite de mesure à la précision du sample.
- **Callback JACK — tampons source par clip** : `alooperSrcL/R[8]` pré-alloués dans `AudioState`. Sources remplies depuis `renderCapture[m]` (sorties de rendu master/chaîne pré-capturées) ou `pluginBuf[]` (VST3). Pas de double rendu FluidSynth.
- **`AudioLooperEngine`** (`ChangeNotifier`) : plan de contrôle Dart pour le looper C++ — cycle de vie des clips, transitions d'état, polling natif à 30 Hz, chargement différé de projet (`finalizeLoad`), import/export WAV, hook autosave `onDataChanged`.
- **`AudioLooperPluginInstance`** : modèle de slot rack (`type: 'audio_looper'`), enregistré dans `PluginInstance.fromJson`, panneau arrière expose `audioInL`/`audioInR`.
- **Capture de rendu à triple couche** : les sources des chaînes d'insert capturées dans `renderCapture[m]` pendant la passe chaîne, les rendus master nus capturés pendant la passe master. Le looper lit depuis les captures par correspondance de pointeur de fonction — n'appelle jamais les fonctions de rendu une seconde fois.
- **`wav_utils.dart`** : `writeWavFile()` / `readWavFile()` pour les fichiers WAV sidecar stéréo float 32 bits.

## [2.11.0] - 2026-04-08

### Ajouté
- **Écran de débogage audio USB (Android)** : nouvel écran `UsbAudioDebugScreen` accessible depuis les Préférences, affichant chaque `AudioDeviceInfo` du système — identifiant, type, direction, fréquences d'échantillonnage, nombre de canaux, encodages et adresse. Utilisé pour investiguer le routage multi-USB sur différents constructeurs.
- **Routage de sortie AAudio (Android)** : le flux de sortie synthétiseur (claviers FluidSynth, Theremin, Stylophone, Vocoder) peut désormais être dirigé vers un périphérique audio USB spécifique via `oboe_stream_set_output_device()` utilisant `AAudioStreamBuilder_setDeviceId()`. Auparavant, seul le chemin capture/lecture du vocoder (miniaudio) supportait la sélection de périphérique ; désormais les deux chemins audio respectent le choix de l'utilisateur.
- **Notification de déconnexion de périphérique** : lorsqu'un périphérique audio sélectionné est débranché en cours de session, `_resetDisconnectedDevices()` bascule sur le périphérique par défaut et affiche un snackbar via `toastNotifier`. Le `errorCallback` AAudio rouvre également le flux sur le périphérique par défaut automatiquement.
- **Filtre par niveau d'API pour le sélecteur de périphérique** : le menu déroulant de sortie dans `AudioSettingsBar` est masqué sur Android < 28, où `setDeviceId()` d'AAudio n'est pas fiable (OpenSL ES l'ignore silencieusement).
- **Macro d'échange de canaux** : mapper un CC matériel pour échanger les canaux MIDI de deux slots instruments et optionnellement toute leur chaîne de signal (câbles audio, références Jam Mode, mappings CC). `RackState.swapSlots()` effectue l'échange ; `AudioGraph.swapSlotReferences()` réécrit les câbles de façon atomique ; `CcMappingService.swapSlotReferences()` maintient la cohérence des mappings CC. Anti-rebond de 250 ms avec notification toast affichant les noms des slots échangés.
- **Préférences CC — catégorie « Échange de canaux »** : renommée depuis « Macros » pour plus de clarté. Les sélecteurs de slot affichent désormais le canal MIDI et la position dans le rack pour distinguer les doublons (ex. « GF Keyboard (Ch 1, #1) » vs « GF Keyboard (Ch 2, #3) »).
- **Packaging Linux** : le workflow GitHub Actions produit désormais des paquets `.rpm` (Fedora), `.pkg.tar.zst` (Arch/Manjaro) et `.flatpak` en plus du `.deb` et `.zip` existants. Les trois reconditionnent le bundle Flutter construit sur Ubuntu avec les métadonnées de dépendances propres à chaque distribution. Fichier desktop partagé, métainfo AppStream, spec RPM/PKGBUILD/manifeste Flatpak ajoutés sous `packaging/`.

### Corrigé
- **Dépendances runtime manquantes dans le paquet `.deb`** : le champ `Depends` liste désormais les noms de paquets vérifiés sur packages.debian.org (`libgtk-3-0 | libgtk-3-0t64`, `libasound2 | libasound2t64`, `libjack-jackd2-0`, `libfluidsynth3`, `libpulse0`, `libmpv2`). La pile PipeWire est ajoutée en `Recommends`.
- **Mappings CC non persistés entre les redémarrages** : `ProjectService` accédait à `CcMappingService` via `AudioEngine.ccMappingService` qui était null pendant l'écran de démarrage (assigné plus tard dans `RackScreen.initState`). Les mappings n'étaient jamais chargés depuis le fichier `.gf` au lancement. Corrigé en donnant à `ProjectService` une référence directe vers `CcMappingService` depuis le Provider. Ajout d'un listener sur `mappingsNotifier` pour déclencher la sauvegarde auto à chaque mutation CC.
- **Préférences CC — crash à la sélection de la catégorie Looper** : `_systemAction` valait 1001 par défaut, mais les actions looper ne contiennent que {1009, 1012}. Le `DropdownButtonFormField` recevait une `initialValue` absente de la liste. Corrigé en réinitialisant `_systemAction` à la première entrée valide lors du changement de catégorie.
- **Android — Clavier GF 1 muet après le démarrage** : `_applyAllPluginsToEngine()` lançait un `createKeyboardSlotSynth()` concurrent (fire-and-forget) pour chaque clavier, en concurrence avec l'appel séquentiel `initAndroidKeyboardSlots()` exécuté juste après par `_readGfFile()`. Les deux appels voyaient `_channelSlotSfId[channel] == null` et créaient des instances FluidSynth en double — la première restait orpheline sur le bus AAudio sans routage MIDI, rendant le clavier muet. Corrigé en passant `skipAndroidSlotCreation: true` dans `_applyAllPluginsToEngine()` pour que seul `initAndroidKeyboardSlots()` crée les synthétiseurs dédiés.

### Architecture
- **Réécriture du modèle CC — hiérarchie scellée `CcMappingTarget`** : remplacement du champ entier surchargé `targetCc` par une hiérarchie de classes scellées à six types : `GmCcTarget`, `SystemTarget`, `SlotParamTarget`, `SwapTarget`, `TransportTarget`, `GlobalTarget`. Supporte plusieurs mappings par numéro CC (un potard peut contrôler plusieurs cibles). Sérialisation JSON pour les fichiers `.gf`. Le stockage passe de `Map<int, CcMapping>` à `List<CcMapping>` avec un index pré-construit en O(1).
- **Stockage CC par projet** : les mappings CC sont désormais sauvegardés/chargés dans les fichiers `.gf` via `ProjectService`, remplaçant le stockage global `SharedPreferences`. Changer de projet change toute la configuration CC. Les mappings existants sont migrés automatiquement au premier chargement d'un ancien fichier `.gf`.
- **Refactoring du dispatch CC** : le cas CC de `AudioEngine.processMidiPacket` est réécrit pour dispatcher via pattern matching scellé (`_dispatchCcMapping`). Chaque type de cible est routé vers son handler : `GmCcTarget` → `_sendRemappedCc`, `SystemTarget` → `_handleSystemCommand`, nouveaux types → callbacks stub pour les Phases C-E.
- **Nettoyage des orphelins CC** : `RackState.removePlugin()` appelle désormais `CcMappingService.removeOrphanedSlotMappings()` pour supprimer tout `SlotParamTarget` ou `SwapTarget` référençant un slot supprimé.
- **`oboe_stream_android.cpp` — routage de périphérique de sortie** : ajout de `g_outputDeviceId`, `oboe_stream_set_output_device()` et `oboe_stream_get_output_device()`. Le builder du flux appelle `AAudioStreamBuilder_setDeviceId()` quand un périphérique non par défaut est sélectionné. Une garde anti-changement évite les redémarrages inutiles du flux.
- **`oboe_stream_android.cpp` — récupération d'erreur** : le `errorCallback` rouvre désormais le flux sur le périphérique par défaut via un thread détaché au lieu de simplement journaliser l'erreur.
- **`native-lib.cpp` — JNI `setOutputDevice`** : nouveau point d'entrée JNI reliant le method channel Kotlin à `oboe_stream_set_output_device()`.
- **`flutter_midi_pro` — API `setOutputDevice()`** : nouvelle méthode dans l'interface de plateforme, le method channel, le stub web et la classe publique `MidiPro`.
- **`MainActivity.kt` — `getAudioDeviceDetails`** : nouvel appel method channel renvoyant les données complètes de `AudioDeviceInfo` (id, productName, type, isSource, isSink, sampleRates, channelCounts, encodings, address) pour l'écran de débogage. Extraction du helper `deviceTypeString()` partagé avec `enumerateDevices()`.
- **`AudioEngine` — `androidSdkVersion`** : mis en cache une seule fois à l'initialisation via method channel ; utilisé par l'interface pour conditionner les fonctionnalités dépendantes du niveau d'API.
- **Callback audio JACK — réécriture zéro allocation** : remplacement des allocations heap par frame (6 copies `std::vector`/`std::unordered_map` à chaque bloc audio) par une architecture `RoutingSnapshot` à triple tampon. Le thread Dart publie des snapshots plats à taille fixe via `std::atomic` ; le callback JACK les lit par un simple chargement atomique — pas de mutex, pas de copie, pas de heap. Élimine la fragmentation de tas qui causait les crashs lors des cycles rapides de création/destruction DSP GFPA.
- **`dvh_process_stereo_f32` — buffers de traitement pré-alloués** : déplacement des vecteurs `scratch`, `outPtrs`, `outBufs`, `inBufs` de l'allocation par appel vers des champs pré-alloués dans `DVH_PluginState`, dimensionnés une seule fois dans `dvh_resume()`.
- **`gfpa_dsp.cpp` — correction de l'ordre d'initialisation des membres C++** : `ChorusEffect` et `DelayEffect` déclaraient `bufL`/`bufR` avant `maxDelaySamples`, causant la construction des lignes à retard avec des tailles non initialisées (le C++ initialise dans l'ordre de déclaration, pas dans l'ordre de la liste d'initialisation). Réordonnancement des membres pour que `maxDelaySamples` et `sampleRate` soient déclarés en premier. Ajout de `-Wreorder` au CMake pour détecter ce type de bug à la compilation.

## [2.10.0] - 2026-04-06

### Ajouté
- **Looper — curseur de volume par piste** : chaque `LoopTrack` dispose désormais d'un champ `volumeScale` (0.0–1.0, persisté dans `.gf`). La vélocité des note-on est multipliée par ce facteur dans `_fireEventsInRange` pendant la lecture. Un curseur compact `_VolumeSlider` apparaît dans chaque `_TrackRow`.
- **Looper — interface d'assignation CC** : nouveau widget `_CcAssignStrip` dans `LooperSlotUI` affichant les assignations CC → action sous forme de puces supprimables. Le bouton « Assigner CC » ouvre `_CcAssignDialog` : choisir une action (Enregistrer/Lire, Lecture/Pause, Stop, Effacer, Overdub), puis bouger un potard ou fader matériel pour l'assigner. Mode apprentissage via le callback `LooperEngine.onCcLearn`.
- **Looper — routage CC** : `feedMidiEvent` détecte désormais les messages CC (status `0xB0`) et les transmet à `handleCc`, de sorte que les assignations CC matérielles fonctionnent sans câblage séparé dans le rack.
- **Backend audio PipeWire / JACK (Linux)** : remplacement du backend ALSA PCM direct (`dart_vst_host_alsa.cpp`) par un client JACK (`dart_vst_host_jack.cpp`) utilisant `jack_client_open` / `jack_set_process_callback`. GrooveForge s'enregistre désormais comme un vrai client JACK avec des ports de sortie stéréo nommés (`out_L`, `out_R`) et se connecte automatiquement à `system:playback_1` / `system:playback_2`. Compatible PipeWire (shim JACK) et JACK2 natif. La latence cible passe de ~50 ms (contournement ALSA dmix) à < 10 ms.
- **Routage audio inter-applications** : l'audio de GrooveForge peut désormais être routé vers/depuis d'autres applications audio Linux (Ardour, Bitwig, Carla) via les connexions JACK standard — visible dans Helvum, qjackctl ou le patchbay de Carla.
- **Compteur XRUN** : `dvh_jack_get_xrun_count` / `VstHost.getXrunCount()` expose le nombre cumulé de XRUNs signalés par le serveur JACK, prêt à être affiché comme avertissement de latence dans l'interface.

### Corrigé
- **Clavier GF — instrument du Slot 1 non restauré au redémarrage** : le second clavier GF (canaux MIDI impairs) jouait toujours le piano (patch 0) après redémarrage de l'application, bien que l'interface affichait le bon instrument. `_restoreState()` dans `AudioEngine.init()` envoyait les program changes pour les 16 canaux, mais le Slot 1 FluidSynth n'existait pas encore — `keyboard_program_select()` ignorait silencieusement l'appel quand `slot->synth` était NULL. Corrigé en initialisant le Slot 1 via `keyboardInitSlot(1)` immédiatement après `keyboardInit()`, avant l'exécution de `_restoreState()`.
- **Build Web / WASM cassé par le correctif Slot 1** : `audio_input_ffi_stub.dart` (le stub no-op pour le web) ne contenait pas la méthode `keyboardInitSlot` ajoutée pour le correctif d'initialisation du Slot 1, provoquant l'échec de la compilation `dart2wasm` et `dart2js`. Ajout du stub no-op manquant.

### Architecture
- **Backend audio JACK** : `dart_vst_host_jack.cpp` remplace `dart_vst_host_alsa.cpp`. La boucle ALSA `while(running) { snd_pcm_writei }` est remplacée par un `jack_set_process_callback` qui écrit directement en float natif dans les buffers des ports JACK (pas de conversion int16). La taille de buffer est négociée dynamiquement via `jack_set_buffer_size_callback`. Les dépendances CMake passent de `find_package(ALSA)` à `pkg_check_modules(JACK REQUIRED jack)`. Renommage FFI Dart : `startAlsaThread` → `startJackClient`, `stopAlsaThread` → `stopJackClient`.
- **Looper — détection d'accords supprimée** : suppression de `chordPerBar`, `detectAndStoreChord`, `_flushBarChord`, la branche enregistrement de `_detectBeatCrossings`, `notesInBar` et `prevRelativeBar` de `LoopTrack` et `LooperEngine`. L'interface grille d'accords est remplacée par une bande de numéros de mesures (`_BarStrip`). `ChordDetector` reste dans le code (utilisé par Jam Mode / clavier).
- **Looper — enregistrement aligné sur les mesures** : `_beginRecordingPass` cale désormais `recordingStartBeat` sur le temps fort de la mesure précédente, de sorte que les offsets des événements sont relatifs à la mesure dès le départ. `_activatePlayback` définit `recordingStartBeat = anchorBeat`, garantissant un alignement identique entre stop/relance et sauvegarde/rechargement.
- **Looper — `LoopTrack.barCount(beatsPerBar)`** : nouveau helper remplaçant l'ancien `chordPerBar.keys` ; calcule le nombre de mesures à partir de `lengthInBeats` et de la signature rythmique du transport.
- **Looper — getter `LooperEngine.beatsPerBar`** : expose `timeSigNumerator` pour que l'interface puisse calculer le nombre de mesures sans importer `TransportEngine`.

## [2.9.0] - 2026-03-25

### Ajouté
- **Site de documentation GitHub Pages** : page marketing et manuel statique à la racine du site (héros, captures, prise en main, modules, MIDI FX, VST3 Linux/macOS, guides `.gfdrum` / `.gfpd` avec liens de téléchargement bruts depuis `main`) ; build Flutter WASM déplacé sous `/demo/`. Le workflow de déploiement assemble `website/`, `docs/features.md` + `docs/privacy.md`, splash, icône et captures.
- **Emplacement des captures du manuel** : la page d’accueil n’affiche qu’une seule vue principale ; les autres captures sont intégrées en figures contextuelles sur les pages prise en main, modules, MIDI FX, VST, `.gfdrum` et `.gfpd` (anglais et miroir `/fr/`).
- **Miroir du site en français** (`/fr/`) : pages statiques traduites ainsi que `docs/features.fr.md` et `docs/privacy.fr.md` pour `/fr/features/` et `/fr/privacy/` ; sélecteur de langue EN/FR dans l’en-tête de toutes les pages du manuel.
- **Manuel — UX et message** : en-tête mobile compact avec bouton **Menu** (case à cocher) ouvrant la navigation dans un panneau court défilant au lieu d’empiler tous les liens ; texte d’accueil centré sur le **Jam Mode** (pratique harmonie/gammes, MIDI matériel), les grooves **`.gfdrum`** plutôt qu’un métronome nu, et **Looper + batterie** partageant le même transport.
- **Générateur de batterie** : nouveau module de rack avec programmation de tempo synchronisée au transport, moteur d'humanisation (jitter de vélocité, microtiming, notes fantômes), curseur de swing, et structure fills/breaks configurable.
- **Format de pattern `.gfdrum`** : patterns de batterie déclaratifs YAML avec grilles de pas (X/x/o/g/.), configuration de vélocité et timing par instrument, types de section `loop` et `sequence`. Les utilisateurs peuvent créer et charger leurs propres patterns.
- **Dix patterns inclus** : Classic Rock, Jazz Swing, Bossa Nova, Tight Funk, Irish Jig, Breton An Dro, Reel Écossais (caisse claire pipe-band, 150–220 BPM), Batucada (ensemble de percussions samba avec interlock surdos + carreteiro tamborim), Marche Militaire (backbeat à flam, variation roulement), Jazz Half-Time Shuffle (shuffle Rosanna/Purdie : caisse claire uniquement sur le temps 3, hi-hat swing « trip »).
- Breton An Dro utilise `type: sequence` pour une variation authentique mesure par mesure.
- `DrumPatternRegistry` singleton pour la découverte des patterns dans l'application.
- **Générateur de batterie — synchronisation de la mesure** : lorsqu'un pattern de batterie est chargé, le transport adopte automatiquement la signature rythmique du pattern pour que le métronome LED et le compteur de mesures restent synchronisés avec le style (ex. 6/8 pour la Bossa Nova, 4/4 pour le Rock).
- **Générateur de batterie — tous les patterns réécrits** à partir de sources musicologiques : Classic Rock (kick hémiolique de Bonham + variante AC/DC), Jazz Swing (ride spang-a-lang authentique), Bossa Nova (séquence clave sur 4 mesures avec variation hi-hat ouvert/fermé), Tight Funk (5 variations : Funky Drummer, Cissy Strut, Sly Stone, kick syncopé, version légère), Irish Jig (modèle bodhran DOWN/UP + variation cross-stick « tip »), Breton An Dro (double grosse caisse signature), Reel Écossais (refonte complète : la caisse claire en croches en continu à 150–220 BPM est remplacée par une hi-hat en croches + backbeat — bien plus musical), Batucada (ensemble 5 voix avec agogô cowbell, chamada tamborim, appel repique et fill chamada), Country (plage BPM étendue à 170 + variation « speedy_wagon »), Jazz Waltz (résolution 9 feel binaire pour un chabada trio naturel sans algo de swing).
- **Générateur de batterie — sauvegarde automatique des paramètres** : le swing, l'humanisation, la soundfont, le pattern, le compte-à-rebours et la fréquence des fills sont désormais persistés automatiquement à chaque changement (via `DrumGeneratorEngine.onChanged` connecté à `ProjectService.autosave`) et sauvegardés dans les fichiers de projet `.gf`.

### Corrigé
- **Web / WASM — générateur de batterie et percussion GM** : le pont audio navigateur ignorait la banque MIDI 128 et n’utilisait que les samples mélodiques Gleitz, ce qui faisait sonner les notes de batterie comme un piano. Le pont suit désormais banque et programme par canal, envoie la banque 128 vers une batterie TR-808 chargée à la demande (smplr), et impose la banque percussion sur le canal MIDI 10 après chargement de la soundfont par défaut pour aligner le métronome sur le comportement SF2 natif.

### Architecture
- **Générateur de batterie — boucle de reconstruction à 100 Hz éliminée** : `RackSlotWidget` enveloppait le slot Générateur de batterie dans un `ValueListenableBuilder(channelState.activeNotes)` — les notes de batterie se déclenchant à la cadence du tick 10 ms provoquaient ~100 reconstructions de widgets par seconde, dégradant le rythme en mode économie d'énergie et ajoutant de la latence aux accords des autres slots. Le Générateur de batterie contourne désormais entièrement ce `ValueListenableBuilder` (il n'affiche jamais de lueur de note). L'écouteur multi-canaux de Jam Mode est remplacé par une approche à deux niveaux : `ListenableBuilder(gfpaJamEntries)` externe pour les changements de configuration, `ValueListenableBuilder` interne sur le seul canal maître concerné.
- **Générateur de batterie — `ensureSession()` ne déclenche plus `notifyListeners()` sans changement** : l'appel était inconditionnel, causant une reconstruction supplémentaire à chaque `addPostFrameCallback`. Désormais, la notification n'est émise qu'à la première inscription ou lors d'un changement de pattern chargé.
- **Générateur de batterie — replanification du lookahead sur changement de paramètre** : `markDirty()` appelle `session.refreshSchedule()` sur toutes les sessions actives, vidant le cache d'anticipation de 2 mesures pour que les modifications de swing et d'humanisation prennent effet en ≤ 10 ms.

## [2.8.1] - 2026-03-24

### Ajouté
- **Bypass des plugins MIDI FX** : bouton marche/arrêt dans l'en-tête de chaque slot MIDI FX. Désactivé, le plugin est entièrement ignoré — aucun événement ne le traverse, les arpégiateurs s'arrêtent.
- **Assignation CC MIDI pour le bypass** : icône télécommande MIDI à côté du bouton de bypass ; déplacer n'importe quel bouton/potard du contrôleur pour associer son CC. Le CC assigné s'affiche en puce ; supprimable depuis la même boîte de dialogue.

### Corrigé
- **Incohérence du bypass MIDI FX** : désactiver un plugin MIDI FX fonctionnait correctement pour les contrôleurs MIDI matériels, mais le clavier GF à l'écran et le Vocoder traversaient encore l'effet bypassé. Les deux chemins partagent désormais la même vérification de bypass.
- **MIDI FX non appliqués aux contrôleurs MIDI matériels** : les effets câblés en patch (Harmoniseur, Transposeur, …) étaient silencieusement ignorés pour les contrôleurs matériels ; seul le chemin `targetSlotIds` était vérifié.
- **Latence des accords avec contrôleur MIDI matériel** : trois causes racines éliminées — les événements Note ne déclenchent plus de reconstruction dans `CcMappingService` ; la détection d'accord est différée après les octets MIDI en attente ; l'appel audio est émis avant toute mise à jour `ValueNotifier` (auparavant une reconstruction des touches du piano s'intercalait entre chaque note d'un accord). Défilement automatique anti-rebond (60 ms) pour les rafales CC.
- **Latence des accords sur Android** : `playNote`/`stopNote`/`controlChange`/`pitchBend` s'exécutaient sur le thread principal Android, partagé avec le Choreographer vsync — un rendu de frame pouvait retarder une note d'accord de 10 à 20 ms. Tous les appels JNI audio temps réel s'exécutent désormais sur un thread dédié à priorité maximale (`GrooveForge-Audio`).
- **Gain Android** : gain maître FluidSynth par défaut abaissé de `5.0` à `3.0` (comme sur Linux) pour éviter la saturation ; le gain est désormais correctement appliqué à chaque nouvelle instance FluidSynth (auparavant le listener se déclenchait avant qu'aucun synthé n'existe, les nouvelles instances héritaient de la valeur par défaut interne).
- **Vue patch — câbles invisibles quand un connecteur est hors de l'écran** : passage à un défilement non-virtualisé pour que toutes les `GlobalKey` de jacks restent montées.
- **Vue patch — défilement automatique lors du glisser de câble** : approcher le bord supérieur ou inférieur fait défiler le rack ; les câbles se repeignent correctement pendant le défilement.
- **Vue patch — disposition des jacks sur téléphone** : les sections de jacks s'empilent verticalement (< 480 dp) au lieu de déborder horizontalement.
- **Barre de transport sur téléphones étroits** (< 500 dp) : mise en page compacte sur une seule ligne — cluster gauche (LED / lecture / BPM) et cluster droit (TAP / signature / métronome).
- **Barre de réglages audio** : les menus déroulants de périphériques ne débordent plus — placés dans des `Expanded` pour partager la largeur restante après les boutons rotatifs.

### Architecture
- **Chemin MIDI sans allocation par note** : cache de routage par canal (`_routingCache`) pré-classifiant les slots VST3, MIDI-only et synth ; caches `_looperTargets` / `_looperPlaybackTargets` remplaçant les scans `connectionsFrom()` ; `AudioGraph.hasMidiOutTo()` testant les connexions sans allouer de `List` ; `_cachedTransport` calculé une fois par changement de transport ; toutes les références de services stockées en champs dans `_RackScreenState`, éliminant les traversées `context.read<T>()` depuis le callback MIDI. En l'absence de slots MIDI FX, le pipeline FX est entièrement court-circuité sans aucune allocation.

## [2.8.0] - 2026-03-24

### Ajouté
- **Système de plugins MIDI FX** (`type: midi_fx` dans `.gfpd`) : chaîne de traitement MIDI 100 % Dart — `GFMidiNode` / `GFMidiGraph` / `GFMidiNodeRegistry` — en miroir du système de nœuds DSP audio. Les plugins se connectent aux slots instruments via des câbles MIDI OUT → MIDI FX MIDI IN dans le panneau arrière. Six types de nœuds intégrés : `transpose`, `harmonize`, `chord_expand`, `arpeggiate`, `velocity_curve`, `gate`.
- **Harmoniseur** (`com.grooveforge.harmonizer`) : ajoute jusqu'à deux voix d'harmonie au-dessus de chaque note. Intervalles configurables de 0 à 24 demi-tons ; le verrou de gamme ajuste les voix à la gamme Jam Mode active.
- **Chord Expand** (`com.grooveforge.chord`) : développe chaque note en un accord complet. 11 qualités (Majeur jusqu'à Dim7) ; trois modes d'écartement — Serré (dans une octave), Ouvert (style drop-2), Large (toutes les voix +1 octave) ; verrou de gamme.
- **Arpégiateur** (`com.grooveforge.arpeggiator`) : remplace les notes maintenues par une séquence rythmique. 6 motifs (Montant / Descendant / Aller-Retour × 2 / Dans l'ordre / Aléatoire), 9 divisions (1/4 → 1/32T), gate 10–100 %, 1–3 octaves. Horloge murale — joue indépendamment de l'état du transport.
- **Transposeur** (`com.grooveforge.transposer`) : décale toutes les notes de ±24 demi-tons. Le viewport du piano virtuel ne défile pas vers la hauteur transposée — seules les touches physiquement pressées déclenchent le défilement (logique `_pointerNote`).
- **Courbe de vélocité** (`com.grooveforge.velocity_curve`) : remappage des vélocités de note-on. Trois modes — Power (exposant 0,25–4,0 via un seul potentiomètre Amount ; centre = linéaire), Sigmoid (courbe en S centrée à la vélocité 64, raideur 4–20), Fixed (vélocité de sortie constante 1–127). Les note-offs et événements non-notes passent sans modification.
- **Gate** (`com.grooveforge.gate`) : filtre les notes hors d'une fenêtre de vélocité (Vel Min/Max 0–127) et/ou d'une plage de hauteur (Note Min/Max 0–127). Les note-ons supprimés sont mémorisés afin que les note-offs correspondants le soient aussi — pas de notes bloquées même si les paramètres changent pendant qu'une note est tenue.
- **Jack MIDI OUT sur le Vocoder** : le panneau arrière du Vocoder expose désormais un jack MIDI OUT permettant de câbler n'importe quel plugin MIDI FX dans la vue patch. Le piano virtuel du vocoder passait déjà par `_applyMidiChain()` — le jack était la seule pièce manquante.
- **UI de plugin responsive avec groupes** (Phase 10) : la clé optionnelle `groups:` dans le bloc `ui:` des `.gfpd` organise les contrôles en sections étiquetées. Sur les écrans ≥ 600 px tous les groupes s'affichent côte à côte ; sur téléphone chaque groupe se replie en `ExpansionTile`. Les 12 `.gfpd` intégrés (6 effets audio + 6 MIDI FX) mis à jour avec des regroupements logiques.

### Corrigé
- **Arpégiateur : trois divisions supplémentaires** — le sélecteur de Division propose désormais 9 options dont 1/64, 1/16T et 1/32T (à 120 BPM : respectivement 31 ms, 83 ms et 42 ms par pas).
- **Arpégiateur : le piano ne défile plus vers les notes de l'arp** — `didUpdateWidget` ne suit désormais que les touches physiquement pressées (`_pointerNote`) ; les pas traversant plusieurs octaves ne volent plus le viewport en pleine performance.
- **Arpégiateur : touches bloquées après un glissando** — deux causes racines corrigées : (1) le sentinel `_arpNoteOns` laissé non consommé après un `_fireStep` inline dans `_handleUserNoteOn`, causant l'identification erronée d'un note-on retour comme événement arp et l'abandon du note-off correspondant ; (2) `_onNotePressed` transmettait tous les événements de `_applyMidiChain` à `engine.playNote`, y compris les gate note-offs injectés par `tick()` qui ajoutaient des hauteurs obsolètes à `activeNotes`.
- **MIDI FX actifs même hors de l'écran** — tous les slots MIDI FX sont désormais initialisés de façon anticipée par `RackState` au chargement du projet, indépendamment du rendu des widgets. Auparavant un slot sorti de la liste lazy n'était jamais monté et les notes contournaient entièrement sa chaîne MIDI FX.
- **Tous les effets audio intégrés ont une mise en page responsive** — les six descripteurs `.gfpd` (Réverb, Delay, Wah, EQ, Compresseur, Chorus) déclarent désormais des sections `groups:`, activant la mise en page responsive sur tous les formats d'écran.

### Architecture
- `GFMidiDescriptorPlugin` implémente `GFMidiFxPlugin` via un `GFMidiGraph` interne, exactement comme `GFDescriptorPlugin` encapsule un `GFDspGraph`.
- `RackState._midiFxTicker` : `Timer.periodic` de 10 ms pilote les nœuds temporels (arpégiateur) sur tous les canaux instruments même en l'absence d'événements entrants — permet les arpèges soutenus en accord maintenu.
- `RackState._initMidiFxPlugin` : initialisation anticipée de chaque slot MIDI FX au chargement ; `midiFxInstanceForSlot` expose l'instance active à `_applyMidiChain`.
- `GateNode` étendu avec les paramètres `maxVelocity`, `minPitch`, `maxPitch` (rétrocompatible — les valeurs par défaut laissent le gate entièrement ouvert).

## [2.7.0] - 2026-03-22

### Ajouté
- **Effets DSP GFPA natifs** (Android, Linux, macOS) : six effets intégrés — Auto-Wah, Réverb à plaque, Délai Ping-Pong, Égaliseur 4 bandes, Compresseur, Chorus/Flanger — implémentés en C++ natif sans allocation sur le thread audio temps réel. Les chaînes multi-effets et le routage vers le Theremin/Stylophone sont pris en charge sur toutes les plateformes.
- **Format de descripteur `.gfpd`** : format YAML déclaratif pour créer des plugins GFPA sans écrire de code Dart — métadonnées, graphe DSP, paramètres automatisables et disposition de l’interface. Six effets propriétaires fournis sous forme de fichiers `.gfpd`.
- **Contrôles UI pour plugins GFPA** : GFSlider (fader), GFVuMeter (vumètre stéréo animé 20 segments avec indicateur de crête), GFToggleButton (bouton LED style pédale d’effet), GFOptionSelector (sélecteur segmenté pour paramètres discrets).
- **GF Keyboard sur macOS via FluidSynth** : remplace le fallback `flutter_midi_pro` précédent ; les effets GFPA et la lecture MIDI fonctionnent désormais de façon identique sur Linux et macOS.
- **`HOW_TO_CREATE_A_PLUGIN.md`** : guide complet de création de plugins `.gfpd`.
- **Reconstruction automatique des bibliothèques natives C/C++ sur macOS** : ajout de `scripts/build_native_macos.sh` et d'une phase Run Script Xcode en pré-build afin que `libaudio_input.dylib` et `libdart_vst_host.dylib` soient reconstruites automatiquement (de façon incrémentale via CMake) à chaque `flutter run` ou build Xcode du target Runner. Plus besoin d'un `cmake && make` manuel après modification des sources natives.

### Corrigé
- **Plantage de la sauvegarde automatique sur Linux** (ENOENT au renommage) : des changements de paramètres rapides déclenchaient des écritures concurrentes sur le même fichier `.tmp`. Résolu par un anti-rebond de 500 ms.
- **Clavier GF muet sans plugin VST3 dans le rack (Linux)** : le thread de rendu ALSA démarre désormais systématiquement lorsque l’hôte VST3 est pris en charge.
- **Son de « pédale de sustain constamment enfoncée » sur macOS** : FluidSynth 2.5.3 (Homebrew) ignorait `synth.reverb.active=0` ; ajout d’appels runtime `fluid_synth_reverb_on` / `fluid_synth_chorus_on` après la création du synth.
- **Deuxième clavier GF nettement moins fort que le premier** : les slots clavier créés à la demande héritent désormais du gain de l’application au lieu du gain par défaut de FluidSynth (0,2 → 3,0).
- **Dialogue de configuration du clavier** : la description de l’aftertouch/CC de pression et le menu déroulant s’empilent désormais verticalement au lieu d’être côte à côte.
- **Build CI macOS** : `libaudio_input.dylib` est recompilé depuis les sources et embarqué avec toutes les dépendances Homebrew de FluidSynth via `dylibbundler`.

### Modifié
- **Slot Virtual Piano supprimé** : le même comportement est disponible via le **GF Keyboard** avec la soundfont *Aucune (MIDI seulement)*. Les projets existants migrent automatiquement au chargement.

## [2.6.0] - 2026-03-19

### Ajouté
- **Support des effets VST3** : enum `Vst3PluginType` (instrument / effet / analyseur) stocké dans le modèle et persisté dans les fichiers `.gf`. Le panneau « Ajouter un plugin » propose désormais des tuiles séparées pour les instruments VST3 et les effets VST3.
- `Vst3EffectSlotUI` : corps de slot dédié aux effets — accent violet, chip de catégorie auto-détectée (Réverbération / Compresseur / EQ / Delay / Modulation / Distorsion / Dynamique), grille de boutons rotatifs avec recherche, détection de sous-groupes et pagination identiques à l'interface instrument.
- **Inserts FX** : chip collapsible « FX ▸ (N) » en bas de chaque slot instrument VST3. Liste les effets dont les entrées audio sont câblées sur les sorties de l'instrument. Le bouton + charge un effet comme slot de premier rang et câble automatiquement `audioOutL/R → audioInL/R` dans le graphe audio.
- Les panneaux arrière des effets VST3 exposent désormais `AUDIO IN L/R + AUDIO OUT L/R + SEND + RETURN` au lieu de `MIDI IN + audio`.
- Les slots effets VST3 n'affichent plus de badge canal MIDI, de piano virtuel ni de lueur d'activité de note.

### Corrigé
- **Routage audio GF Keyboard non restauré au chargement d'un projet** : au démarrage, `syncAudioRouting` était appelé alors que `VstHost` n'était pas encore initialisé (`_host == null`), la méthode retournait immédiatement sans câbler l'audio du clavier à travers les effets VST3 sauvegardés. Un second appel à `syncAudioRouting` est maintenant effectué dans `SplashScreen` après le chargement de tous les plugins VST3 et le démarrage du thread ALSA, ce qui rétablit correctement la table de routage complète.
- **Crash de l'éditeur VST3 sous XWayland (GLX BadAccess)** : les plugins VST3 basés sur JUCE (ex. Dragonfly Hall Reverb) faisaient planter toute l'application lors de l'ouverture de leur interface native sous une session Wayland. Le gestionnaire d'erreurs fatal par défaut de Xlib appelait `exit()` quand `glXMakeCurrent` retournait `BadAccess`, car le thread de rendu Flutter possédait déjà le contexte GLX. Un `XSetErrorHandler` non fatal est maintenant installé autour de `createView()` + `attached()` dans `dart_vst_host_editor_linux.cpp` ; en cas d'erreur GLX, l'ouverture est annulée proprement et une snackbar guide l'utilisateur à relancer avec `LIBGL_ALWAYS_SOFTWARE=1` ou en session X11 pure.
- **Section des paramètres VST3 repliée par défaut** : l'accordéon de paramètres dans les slots VST3 (instrument et effet) est maintenant fermé au chargement initial, réduisant l'encombrement visuel.

### Architecture
- **Routage audio Theremin / Stylophone → effets VST3** : les instruments intégrés (Theremin, Stylophone) peuvent désormais alimenter des effets VST3 via le graphe audio. Le routage repose sur trois couches coordonnées : (1) `native_audio/audio_input.c` expose les fonctions C `theremin_render_block()` / `stylophone_render_block()` et un drapeau de mode capture qui silence la sortie miniaudio directe vers ALSA quand une route est active ; (2) `dart_vst_host_alsa.cpp` ajoute un registre de rendu externe (`dvh_set_external_render` / `dvh_clear_external_render`) pour que la boucle ALSA appelle la fonction de rendu comme entrée stéréo du plugin à chaque bloc ; (3) `VstHostService.syncAudioRouting` détecte les connexions non-VST3 → VST3 dans l'`AudioGraph`, enregistre la fonction de rendu appropriée et bascule le mode capture en conséquence.
- **Routage audio GF Keyboard → effets VST3** : le sous-processus FluidSynth (`/usr/bin/fluidsynth -a alsa`) est remplacé sur Linux par libfluidsynth liée directement dans `libaudio_input.so`. FluidSynth fonctionne désormais en mode « pas de pilote audio » et est rendu manuellement via `keyboard_render_block()`. Un nouveau slot de rendu maître dans la boucle ALSA de dart_vst_host (`dvh_add_master_render` / `dvh_remove_master_render`) permet au clavier de sonner normalement via le thread ALSA sans route VST3, et de rediriger l'audio vers l'entrée de l'effet quand une connexion est établie. Toutes les commandes MIDI (note on/off, sélection de programme, pitch bend, CC, gain) sont désormais envoyées par FFI au lieu de pipes stdin.

## [2.5.8] - 2026-03-17

### Corrigé
- **Enregistrer sous (Android et web)** : l’option « Enregistrer sous… » du menu projet ne faisait rien sur Android et sur le web. Sur le web, `FilePicker.platform.saveFile` exige des `bytes` et renvoie `null` après avoir déclenché un téléchargement ; sur Android/iOS le plugin exige aussi des `bytes`. Le projet est désormais sérialisé en octets JSON et passé à `saveFile` sur toutes les plateformes. Sur le web, le résultat vide est considéré comme un succès (téléchargement démarré) ; sur mobile et desktop le plugin écrit le fichier et renvoie le chemin. L’interface affiche « Projet enregistré » dans tous les cas.

### Ajouté
- Pages HTML statiques pour les routes `/features` et `/privacy` dans `web/features/index.html` et `web/privacy/index.html`, restaurant ces pages sur GitHub Pages après que le déploiement Flutter web ait remplacé l'ancien site statique.

## [2.5.7] - 2026-03-17

### Corrigé
- **Cascade de reconstructions clavier dans le rack** : les notes sur n'importe quel canal MIDI déclenchaient une reconstruction complète de chaque slot clavier du rack (O(N×16) repeintures par appui de touche). Le `ListenableBuilder` extérieur dans `_RackSlotPiano` et `GrooveForgeKeyboardSlotUI` fusionnait inconditionnellement les notificateurs `activeNotes` et `lastChord` des 16 canaux, que le slot soit ou non un suiveur GFPA Jam. Remplacé par une architecture à trois couches : la couche 1 écoute uniquement la configuration, la couche 2 (nouveaux widgets `_PianoBody` / `_GfkFollowerBody`) souscrit à exactement un notificateur du canal maître pour les suiveurs, et la couche 3 (`ValueListenableBuilder<Set<int>>`) gère la mise en évidence des notes du canal propre. Les slots non-suiveurs ne souscrivent désormais à aucun notificateur inter-canaux, réduisant le travail de reconstruction à l'appui d'une touche de O(N) à O(1).

### Ajouté
- **Cible web** : GrooveForge peut désormais être compilé en application Flutter web et déployé sur GitHub Pages.
- **Audio web (GF Keyboard)** : lecture de soundfonts SF2 sur le web via un pont JavaScript SpessaSynth (`web/js/grooveforge_audio.js`). Le pont est chargé en tant que `<script type="module">` dans `web/index.html` et exposé sous `window.grooveForgeAudio`. Une nouvelle classe Dart `FlutterMidiProWeb` (utilisant les extension types de `dart:js_interop`) délègue tous les appels MIDI à ce pont.
- **Audio web (Stylophone et Theremin)** : synthèse par oscillateur sur le web via l'API Web Audio, exposée sous `window.grooveForgeOscillator`. La forme d'onde, le vibrato, le portamento et le comportement de l'amplitude correspondent à l'implémentation native en C.
- **Workflow GitHub Actions** (`.github/workflows/web_deploy.yml`) : compile automatiquement la version web Flutter et déploie sur GitHub Pages (branche `gh-pages`) à chaque push sur `main`.

### Architecture
- `lib/services/audio_input_ffi.dart` converti en ré-export conditionnel : les plateformes natives utilisent `audio_input_ffi_native.dart` (code FFI inchangé) ; le web utilise `audio_input_ffi_stub.dart` (pont JS interop, toutes les méthodes Vocoder sont des no-ops).
- La condition d'export conditionnel de `lib/services/vst_host_service.dart` est passée de `dart.library.io` à `dart.library.js_interop` — `dart:io` étant partiellement disponible sur Flutter web 3.x, l'ancienne condition sélectionnait incorrectement l'implémentation desktop (chargée en FFI) sur le web.
- L'import de `lib/services/rack_state.dart` est passé du fichier concret `vst_host_service_desktop.dart` au ré-export conditionnel `vst_host_service.dart`, garantissant l'utilisation du stub sans FFI sur le web.
- `lib/services/vst_host_service_stub.dart` enrichi d'un no-op `syncAudioRouting` pour correspondre à l'interface desktop.
- Gardes `kIsWeb` ajoutées dans `audio_engine.dart`, `midi_service.dart` et `project_service.dart` pour ignorer toutes les opérations `dart:io` fichiers/répertoires sur le web.
- `packages/flutter_midi_pro` : contrainte SDK relevée à `>=3.3.0` (extension types), dépendance `flutter_web_plugins` ajoutée, enregistrement du plugin web (`FlutterMidiProWeb`) ajouté dans `pubspec.yaml`. `loadSoundfontAsset` contourne les opérations sur fichiers temporaires sur le web et passe le chemin d'asset directement au pont JS.
- `packages/flutter_midi_pro/analysis_options.yaml` mis à jour pour exclure `flutter_midi_pro_web.dart` de l'analyse non-web (le fichier utilise des extension types `dart:js_interop` uniquement valides dans un contexte de compilation web).

## [2.5.6] - 2026-03-16

### Corrigé
- **Plantage sur macOS au démarrage** : Recompilation de la bibliothèque `libaudio_input.dylib` pour macOS afin d'inclure les symboles C FFI `VocoderPitchBend` et `VocoderControlChange`, empêchant un plantage `symbol not found` au lancement de l'application.
- **Plantage sur macOS lors de l'ajout de modules** : Correction du symbole `dvh_set_processing_order` manquant dans `libdart_vst_host.dylib` en incluant les fichiers sources natifs manquants dans la configuration de construction macOS et en recompilant la bibliothèque. Cela restaure la fonctionnalité de routage VST3 sur macOS.
- **Erreur de permission caméra sur macOS** : Correction d'une `MissingPluginException` pour `permission_handler` sur macOS en implémentant une requête de permission caméra native directement dans `ThereminCameraPlugin.swift` et en contournant le plugin défaillant sur cette plateforme.

## [2.5.5] - 2026-03-16

### Ajouté
- **Configuration du clavier du Vocoder** : le slot Vocoder expose désormais le même bouton ⊞ que le GF Keyboard et le Piano Virtuel — appuyez dessus pour régler indépendamment le nombre de touches visibles et la hauteur des touches, sans toucher aux préférences globales.
- **Mode Naturel du Vocoder repensé en autotune** : l'ancienne forme d'onde Naturelle passait par le banc de filtres du vocoder et sonnait robotique. Elle est remplacée par un décaleur de hauteur PSOLA (Pitch-Synchronous Overlap-Add) qui lit le signal brut du micro, détecte la hauteur source par ACF, et retime les grains à la fréquence MIDI cible — contournant complètement le banc de filtres pour préserver le timbre de la voix.

## [2.5.4] - 2026-03-15

### Ajouté
- **Thérémine et Stylophone** : deux nouveaux plugins d'instruments GFPA. Le Thérémine est un grand pad tactile (vertical = hauteur, horizontal = volume) avec un oscillateur C natif sinusoïdal — portamento (τ ≈ 42 ms), LFO vibrato à 6,5 Hz (0–100 %), note de base et plage ajustables. Le Stylophone est un clavier à lamelles chromatiques monophonique de 25 touches avec quatre formes d'onde (SQR/SAW/SIN/TRI), legato sans clic et décalage d'octave ±2.
- **Mode CAM du Thérémine** (Android / iOS / macOS) : la proximité de la main mesurée par l'autofocus contrôle la hauteur. Repli automatique sur l'analyse luminosité/contraste pour les caméras à focale fixe (pas d'erreur sur les webcams). Aperçu caméra semi-transparent affiché derrière l'orbe à ≈ 10 fps.
- **Bouton VIB du Stylophone** : active un LFO à 5,5 Hz de ±0,5 demi-ton pour l'effet « tape-wobble » vintage. L'état persiste.
- **Prise MIDI OUT** sur les deux instruments (vue arrière du rack) : branchez un câble vers un GF Keyboard, un VST3 ou un Looper. Le Thérémine envoie note-on/off à chaque changement de demi-ton ; le Stylophone à chaque touche pressée/relâchée.
- **Bouton MUTE** sur les deux instruments : coupe le synthétiseur intégré tout en laissant le MIDI OUT circuler — idéal pour les utiliser comme contrôleurs MIDI expressifs sans doubler le son.
- **Hauteur du pad du Thérémine** : quatre tailles (S/M/L/XL) via un nouveau contrôle HAUTEUR dans la barre latérale. Persiste dans le fichier projet.
- **Miroir de l'aperçu CAM** : l'aperçu s'affiche en miroir selfie ; la rotation tient compte de l'orientation de l'appareil (Android). Lag de l'EMA réduit de ~400 ms à ~67 ms.
- **Verrouillage du défilement sur le pad du Thérémine** : toucher le pad ne fait plus défiler le rack accidentellement.

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
- **MIDI externe via Piano Virtuel** — les notes MIDI entrantes sur le canal d'un VP sont désormais transmises via ses connexions câble MIDI OUT (en respectant le verrouillage de gamme/Jam Mode), permettant à un contrôleur MIDI matériel de piloter un instrument VST3 via la chaîne de routage VP. Auparavant, le MIDI externe sur un canal VP était acheminé vers FluidSynth (son silencieux ou erroné) et n'atteignait jamais le VST en aval.

### Corrigé
- **Verrouillage de gamme sur les taps individuels** — `VirtualPiano._onDown` applique désormais le snapping `_validTarget` avant d'appeler `onNotePressed`, de sorte qu'appuyer sur une touche invalide redirige vers la classe de hauteur valide la plus proche (même comportement que le glissando). Le même correctif s'applique aux transitions de notes en glissando dans `_onMove` : la note snappée est stockée dans `_pointerNote` et transmise au callback au lieu de la touche brute sous le doigt.
- **MIDI externe via Piano Virtuel** — les notes MIDI entrantes sur le canal d'un VP sont désormais transmises via ses connexions câble MIDI OUT (en respectant le verrouillage de gamme/Jam Mode), permettant à un contrôleur MIDI matériel de piloter un instrument VST3 via la chaîne de routage VP. Auparavant, le MIDI externe sur un canal VP était acheminé vers FluidSynth (son silencieux ou erroné) et n'atteignait jamais le VST en aval.
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
