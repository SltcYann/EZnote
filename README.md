# EZnote

Un traitement de texte pour Mac, pensé pour prendre des notes de cours, avec un bouton **EZifier** : Claude transforme tes notes en une leçon complète, rédigée et prête à lire.

Interface en verre (Liquid Glass natif, design system **UY**) sur un fond animé aux couleurs de Claude.

## EZifier

1. Prends tes notes comme elles viennent : mots-clés, abréviations, flèches.
2. Appuie sur **EZifier** (ou ⇧⌘E, menu Claude).
3. La leçon s'écrit en direct à la place des notes.

- **Texte normal** : tes notes reformulées en phrases, sans aucune information en plus.
- **Contour orange « Claude · Exemple »** : tout ce que Claude ajoute (précision, définition, exemple, explication, mise en garde), y compris ce qu'il a trouvé sur le web.
- ⌘Z remet tes notes d'origine, ⇧⌘Z remet la leçon. **Arrêter** annule et remet les notes.
- Retour sur une ligne vide à la fin d'un ajout de Claude : on sort du contour.

## Contexte

L'IA (EZifier, fiches, quiz, questions) et la dictée tiennent compte du contexte :

- **Réglages › Mes études** : ton niveau, tes études et une zone de texte libre (école, cours, profs…).
- **Contexte du document** (bouton livre, à gauche de la barre d'outils) : matière, **niveau d'explication** (simple, normal, approfondi) et contexte du cours (professeur, chapitre, livre, mots techniques). La matière est remplie toute seule au premier EZifier si tu ne l'as pas indiquée.
- Si la recherche web est autorisée (Réglages › Claude), l'IA peut chercher ce contexte sur internet (programme, école, vocabulaire du domaine).
- La dictée reçoit le vocabulaire du contexte et les noms propres du document pour mieux les reconnaître.

## Enregistrer un cours

Le bouton micro (⌥⌘R) écoute le cours et écrit ce que dit le professeur à la fin du document, sous un titre « Cours enregistré · date ». La transcription se fait sur le Mac, sans limite de durée ; tu peux continuer à taper pendant ce temps. Les mots encore incertains s'affichent en gris.

- **Marque-pages** pendant le cours : boutons **Important** (⌃⌘I) et **Pas compris** (⌃⌘U) de la capsule d'enregistrement ; ils se placent après la phrase prononcée à ce moment-là. Quand le prof dit « ça tombe à l'examen », « retenez bien », « c'est important »…, un marque-page Important se pose tout seul. À l'EZification, un passage important reçoit un encadré « À retenir », un passage pas compris une explication.
- **Plan en direct** : pendant l'enregistrement, un panneau à droite montre le plan du cours, mis à jour par l'IA toutes les 90 secondes (bouton Plan pour le masquer).
- **Réécouter** : l'audio est gardé sur le Mac (~/Library/Application Support/EZnote/Audio). ⌥-clic sur une phrase transcrite, ou clic droit › Réécouter à partir d'ici.
- Ensuite, **EZifier** en fait une leçon : l'IA enlève les hésitations et, quand un passage est mal transcrit, devine ce que le professeur voulait dire grâce au contexte. S'il n'est pas sûr, il le signale dans un encadré « Attention ».

## Photos du tableau et diapositives

Glisse ou colle une photo dans le texte, ou Insertion › Image ou PDF de diapos… (⌥⌘I). À l'EZification, l'IA lit l'image (tableau, diapo, schéma), intègre son contenu à la leçon et la replace au bon endroit. Le **PDF des diapositives du prof** est envoyé page par page (30 pages au plus) : l'IA croise les diapos avec tes notes et la transcription, et cite la diapo d'où vient une information. Les grosses photos sont compressées à l'enregistrement.

## Schémas

Quand le cours s'y prête, l'IA ajoute des schémas dessinés par l'app dans un encadré « Schéma » : **frise chronologique**, **tableau comparatif** ou **carte mentale**.

## Réviser

Bouton chapeau de la barre d'outils, ou menu Claude :

- **Fiches et quiz** (⇧⌘R), en cinq onglets :
  - **Fiches** : l'IA écrit des fiches question / réponse, gardées dans le document et révisées en **répétition espacée** (une fiche sue revient de plus en plus tard : 1, 3, 7, 16, 35 jours ; une fiche ratée revient tout de suite).
  - **Quiz** : 10 questions à choix multiples avec la correction expliquée.
  - **Oral** : l'IA pose une question à voix haute, tu réponds au micro, elle note ta réponse sur 10 et la commente.
  - **Points faibles** : les fiches souvent ratées et les questions de quiz manquées, avec « Voir dans le cours » et « M'expliquer ».
  - **Planning** : la date de l'examen (aucune fiche n'est programmée après la veille) et la répartition des fiches jour par jour ; rappel chaque matin à 8 h des fiches à revoir et des examens qui approchent.
- **Fiche de synthèse** : l'essentiel de la leçon sur une page, à imprimer, exporter en PDF ou ajouter au document.
- **Poser une question** (⌥⌘E, ou clic droit sur une sélection) : l'IA explique le passage ; la réponse peut être ajoutée dans un encadré.

## Bibliothèque

Fenêtre › Bibliothèque (⇧⌘L) : les cours du dossier de sauvegarde, rangés par matière, avec une recherche dans le texte de tous les cours, les fiches à réviser aujourd'hui et les examens. Double-clic pour ouvrir.

- **Demander à l'IA** (✦) : une question en langage naturel sur tous tes cours (« où le prof a parlé de la souveraineté ? ») renvoie les passages qui en parlent.
- **Fusionner** : coche plusieurs cours d'une matière, l'IA en fait un chapitre unique sans doublons, enregistré à côté.
- **Liens entre cours** : sélectionne une notion, clic droit › « … dans mes autres cours » pour ouvrir les autres cours qui en parlent.

Pour retrouver tes cours sur tous tes appareils, choisis **iCloud Drive** comme dossier (Réglages › Général).

## Éditeur

- Moteur de texte natif d'Apple (TextKit, comme TextEdit et Pages) : fluide même sur de longs documents.
- Styles Titre, Section, Sous-section, Texte ; gras, italique, souligné ; listes à puces et numérotées. Les boutons s'allument en orange quand le format est actif à l'endroit du curseur.
- Un nouveau document porte la date du jour (« 5 octobre 2026 »), proposée comme nom à l'enregistrement.
- Polices et couleurs (menu Format), correcteur orthographique, recherche (⌘F), annulation illimitée.
- **Formules** : tape du LaTeX simple entre `$…$` ; au `$` final, `$x^2 + \sqrt{y} \leq \frac{a}{b}$` devient « x² + √y ≤ a⁄b ».
- **Export** : Fichier › Exporter › PDF ou Word (.docx), et impression (⌘P), avec les encadrés de l'IA.
- Format `.eznote` (garde images, ajouts de l'IA, transcription, audio, marque-pages, matière, contexte et fiches) ; ouvre aussi le RTF, le RTFD et le texte brut.
- Mode clair, sombre ou comme le système (Réglages › Général).

## Compiler

```bash
./build-app.sh
```

Le script compile, crée `build/EZnote.app`, la signe et l'installe dans `/Applications/EZnote.app`.

## Réglages (⌘,)

- **Claude** :
  - *Abonnement Claude* (par défaut) passe par Claude Code, installé et connecté à ton compte claude.ai : pas de clé API, l'EZification compte dans les limites de ton abonnement.
  - *Clé API* utilise une clé Anthropic ([en créer une](https://platform.claude.com/settings/keys)), rangée dans le trousseau.
  - *Modèle local* fait rédiger la leçon sur ton Mac par un modèle comme Qwen, via [Ollama](https://ollama.com) (lancé automatiquement) ou LM Studio : sans internet, mais plus lent, moins précis et sans recherche web. Les ajouts portent alors le nom du modèle.
  - On peut aussi couper la recherche web.
- **Mes études** : ton niveau et tes études, pour aider Claude à comprendre tes notes.
- **Général** : apparence (système, clair, sombre) et dossier de sauvegarde proposé par défaut.

> Sans certificat de signature local, l'app est signée en ad hoc : macOS peut redemander l'accès au trousseau après une recompilation. Pour l'éviter, crée un certificat « EZnote » (Trousseaux d'accès › Assistant de certification › Créer un certificat, type « Signature de code »).

Modèle utilisé : Claude Opus 5.5 (`claude-opus-5-5`), en streaming, avec la recherche web côté serveur.

## Prérequis

- macOS 26 ou plus récent (Liquid Glass).
- Un abonnement Claude avec Claude Code installé et connecté, une clé API Anthropic, ou un modèle local (Ollama, LM Studio).

## Structure

```
Sources/EZnote/
├── EZnoteApp.swift            point d'entrée, menus
├── Document/
│   ├── EZDocument.swift       document .eznote (RTFD + passages marqués + infos du cours + fiches)
│   ├── DocumentInfo.swift     matière, contexte, niveau, examen, fiches (révision espacée)
│   ├── LibraryIndex.swift     lecture des cours du dossier (bibliothèque, liens, rappels)
│   ├── ReviewReminders.swift  rappels de révision du matin
│   ├── Exporter.swift         PDF, Word, impression
│   ├── SaveFolder.swift       dossier par défaut, iCloud Drive
│   └── DateNames.swift        nom du jour pour les nouveaux documents
├── Editor/
│   ├── PageTextView.swift     feuille de papier, colonne centrée, contours orange
│   ├── EditorView.swift       pont SwiftUI → NSTextView
│   ├── EditorController*.swift mise en forme, EZifier, enregistrement, outils, insertion, export
│   ├── MathText.swift         LaTeX simple → Unicode
│   ├── Slides.swift           PDF de diapositives → images pour l'IA
│   └── LessonStyle.swift      typographie, listes, espacement automatique
├── Claude/
│   ├── AI.swift               point d'entrée unique vers l'IA choisie
│   ├── StudyContext.swift     contexte de l'élève et du cours
│   ├── ClaudeClient.swift     API Messages en streaming (SSE), recherche web
│   ├── ClaudeCodeClient.swift abonnement Claude via Claude Code
│   ├── LocalModelClient.swift modèle local (Ollama, LM Studio)
│   ├── LessonPrompt.swift     consignes d'EZifier, des fiches, du quiz, de la synthèse et des questions
│   ├── LessonRenderer.swift   Markdown de Claude → texte mis en forme (et l'inverse)
│   ├── Schema.swift           frises, tableaux et cartes mentales dessinés
│   └── Keychain.swift
├── Audio/LectureRecorder.swift micro → audio + transcription en direct (SpeechAnalyzer), réécoute
├── UY/                        tokens et composants du design system UY
└── Views/                     fenêtre, révision (fiches, quiz, oral, points faibles, planning), bibliothèque, réglages
```
