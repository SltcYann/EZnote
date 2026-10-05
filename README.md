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

## Éditeur

- Moteur de texte natif d'Apple (TextKit, comme TextEdit et Pages) : fluide même sur de longs documents.
- Styles Titre, Section, Sous-section, Texte ; gras, italique, souligné ; listes à puces et numérotées.
- Polices et couleurs (menu Format), correcteur orthographique, recherche (⌘F), annulation illimitée.
- Format `.eznote` (garde les ajouts de Claude) ; ouvre aussi le RTF et le texte brut, enregistre en RTF.
- Mode clair et sombre.

## Compiler

```bash
./build-app.sh
```

Le script compile, crée `build/EZnote.app`, la signe et l'installe dans `/Applications/EZnote.app`.

## Clé API

Au premier EZifier, EZnote demande une clé API Anthropic ([en créer une](https://platform.claude.com/settings/keys)). Elle est rangée dans le trousseau macOS et modifiable dans Réglages (⌘,), où l'on peut aussi couper la recherche web.

> Sans certificat de signature local, l'app est signée en ad hoc : macOS peut redemander l'accès au trousseau après une recompilation. Pour l'éviter, crée un certificat « EZnote » (Trousseaux d'accès › Assistant de certification › Créer un certificat, type « Signature de code »).

Modèle utilisé : Claude Opus 5.5 (`claude-opus-5-5`), en streaming, avec la recherche web côté serveur.

## Prérequis

- macOS 26 ou plus récent (Liquid Glass).
- Une clé API Anthropic (l'EZification est facturée sur ton compte API).

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
│   ├── LessonPrompt.swift     consignes d'EZifier
│   ├── LessonRenderer.swift   Markdown de Claude → texte mis en forme (et l'inverse)
│   └── Keychain.swift
├── UY/                        tokens et composants du design system UY
└── Views/                     fenêtre, barre d'outils, réglages
```
