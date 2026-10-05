#if DEBUG
import AppKit

/// Outil de développement : `EZnote --snapshot fichier.png [dark]` rend une leçon d'exemple dans l'éditeur
/// et l'enregistre en image, sans ouvrir de fenêtre.
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dark = args.contains("dark")
        let markdown = """
        # La photosynthèse
        La photosynthèse est le processus par lequel les plantes fabriquent leur matière organique à partir de la lumière.
        :::claude Définition
        Une **matière organique** est une matière fabriquée par un être vivant et qui contient du *carbone*.
        :::
        ## Les ingrédients
        - de l'eau, puisée par les racines ;
        - du dioxyde de carbone, capté par les feuilles ;
        - de la lumière.
        :::claude Exemple
        Un chêne adulte capte environ 20 kg de CO₂ par an.

        1. premier point
        2. second point
        :::
        La réaction a lieu dans les chloroplastes.
        """
        let storage = NSTextStorage(attributedString: LessonRenderer.render(markdown))
        LessonStyle.normalizeSpacing(storage, around: NSRange(location: 0, length: storage.length))
        let layoutManager = ClaudeLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: PageTextView.column, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        let view = PageTextView(frame: NSRect(x: 0, y: 0, width: 960, height: 1100), textContainer: container)
        view.drawsBackground = false
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.layoutColumn()
        layoutManager.ensureLayout(for: container)

        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        let backdrop = NSImage(size: view.bounds.size, flipped: false) { rect in
            (dark ? NSColor(srgb: 0x0B0B10) : NSColor(srgb: 0x9FC7F0)).setFill()
            rect.fill()
            return true
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        backdrop.draw(in: view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
        exit(0)
    }
}
#endif
