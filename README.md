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

## Enregistrer un cours

Le bouton micro de la barre d'outils écoute le cours et écrit ce que dit le professeur à la fin du document, sous un titre « Cours enregistré · date ». La transcription se fait sur le Mac, sans limite de durée ; tu peux continuer à taper pendant ce temps. Les mots encore incertains s'affichent en gris.

Ensuite, **EZifier** en fait une leçon : Claude enlève les hésitations et, quand un passage est mal transcrit, devine ce que le professeur voulait dire grâce au contexte (matière déduite des notes et du nom du document, ton niveau et tes études). S'il n'est pas sûr, il le signale dans un encadré « Attention ».

## Éditeur

- Moteur de texte natif d'Apple (TextKit, comme TextEdit et Pages) : fluide même sur de longs documents.
- Styles Titre, Section, Sous-section, Texte ; gras, italique, souligné ; listes à puces et numérotées. Les boutons s'allument en orange quand le format est actif à l'endroit du curseur.
- Un nouveau document porte la date du jour (« 5 octobre 2026 »), proposée comme nom à l'enregistrement.
- Polices et couleurs (menu Format), correcteur orthographique, recherche (⌘F), annulation illimitée.
- Format `.eznote` (garde les ajouts de Claude) ; ouvre aussi le RTF et le texte brut, enregistre en RTF.
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
├── Document/EZDocument.swift  document .eznote (RTF + ajouts de Claude)
├── Editor/
│   ├── PageTextView.swift     feuille de papier, colonne centrée, contours orange
│   ├── EditorView.swift       pont SwiftUI → NSTextView
│   ├── EditorController.swift mise en forme, EZifier, annulation
│   └── LessonStyle.swift      typographie, listes, espacement automatique
├── Claude/
│   ├── ClaudeClient.swift     API Messages en streaming (SSE), recherche web
│   ├── ClaudeCodeClient.swift abonnement Claude via Claude Code
│   ├── LocalModelClient.swift modèle local (Ollama, LM Studio)
│   ├── LessonPrompt.swift     consignes d'EZifier
│   ├── LessonRenderer.swift   Markdown de Claude → texte mis en forme (et l'inverse)
│   └── Keychain.swift
├── Audio/LectureRecorder.swift micro → transcription en direct (SpeechAnalyzer)
├── UY/                        tokens et composants du design system UY
└── Views/                     fenêtre, barre d'outils, réglages
```
