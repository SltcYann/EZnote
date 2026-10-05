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
- **Contexte du document** (bouton livre, à gauche de la barre d'outils) : matière et contexte du cours (professeur, chapitre, livre, mots techniques). La matière est remplie toute seule au premier EZifier si tu ne l'as pas indiquée.
- Si la recherche web est autorisée (Réglages › Claude), l'IA peut chercher ce contexte sur internet (programme, école, vocabulaire du domaine).
- La dictée reçoit le vocabulaire du contexte et les noms propres du document pour mieux les reconnaître.

## Enregistrer un cours

Le bouton micro (⌥⌘R) écoute le cours et écrit ce que dit le professeur à la fin du document, sous un titre « Cours enregistré · date ». La transcription se fait sur le Mac, sans limite de durée ; tu peux continuer à taper pendant ce temps. Les mots encore incertains s'affichent en gris.

- **Marque-pages** pendant le cours : boutons **Important** (⌃⌘I) et **Pas compris** (⌃⌘U) de la capsule d'enregistrement. À l'EZification, un passage important reçoit un encadré « À retenir », un passage pas compris une explication.
- **Réécouter** : l'audio est gardé sur le Mac (~/Library/Application Support/EZnote/Audio). ⌥-clic sur une phrase transcrite, ou clic droit › Réécouter à partir d'ici.
- Ensuite, **EZifier** en fait une leçon : l'IA enlève les hésitations et, quand un passage est mal transcrit, devine ce que le professeur voulait dire grâce au contexte. S'il n'est pas sûr, il le signale dans un encadré « Attention ».

## Photos du tableau

Glisse ou colle une photo dans le texte, ou Insertion › Image… (⌥⌘I). À l'EZification, l'IA lit l'image (tableau, diapo, schéma), intègre son contenu à la leçon et la replace au bon endroit. Les photos sont réduites et compressées à l'enregistrement.

## Réviser

Bouton chapeau de la barre d'outils, ou menu Claude :

- **Fiches et quiz** (⇧⌘R) : l'IA écrit des fiches question / réponse, gardées dans le document et révisées en **répétition espacée** (une fiche sue revient de plus en plus tard : 1, 3, 7, 16, 35 jours ; une fiche ratée revient tout de suite). Le **quiz** pose 10 questions à choix multiples avec la correction expliquée.
- **Fiche de synthèse** : l'essentiel de la leçon sur une page, à imprimer, exporter en PDF ou ajouter au document.
- **Poser une question** (⌥⌘E, ou clic droit sur une sélection) : l'IA explique le passage ; la réponse peut être ajoutée dans un encadré.

## Bibliothèque

Fenêtre › Bibliothèque (⇧⌘L) : les cours du dossier de sauvegarde, rangés par matière, avec une recherche dans le texte de tous les cours et le nombre de fiches à réviser. Double-clic pour ouvrir.

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
│   ├── Exporter.swift         PDF, Word, impression
│   ├── SaveFolder.swift       dossier par défaut, iCloud Drive
│   └── DateNames.swift        nom du jour pour les nouveaux documents
├── Editor/
│   ├── PageTextView.swift     feuille de papier, colonne centrée, contours orange
│   ├── EditorView.swift       pont SwiftUI → NSTextView
│   ├── EditorController*.swift mise en forme, EZifier, enregistrement, outils, insertion, export
│   ├── MathText.swift         LaTeX simple → Unicode
│   └── LessonStyle.swift      typographie, listes, espacement automatique
├── Claude/
│   ├── AI.swift               point d'entrée unique vers l'IA choisie
│   ├── StudyContext.swift     contexte de l'élève et du cours
│   ├── ClaudeClient.swift     API Messages en streaming (SSE), recherche web
│   ├── ClaudeCodeClient.swift abonnement Claude via Claude Code
│   ├── LocalModelClient.swift modèle local (Ollama, LM Studio)
│   ├── LessonPrompt.swift     consignes d'EZifier, des fiches, du quiz, de la synthèse et des questions
│   ├── LessonRenderer.swift   Markdown de Claude → texte mis en forme (et l'inverse)
│   └── Keychain.swift
├── Audio/LectureRecorder.swift micro → audio + transcription en direct (SpeechAnalyzer), réécoute
├── UY/                        tokens et composants du design system UY
└── Views/                     fenêtre, révision, bibliothèque, réglages
```
