import AppKit
import SwiftUI

/// Pont SwiftUI → éditeur AppKit. Le texte du document est branché directement sur le NSTextView.
struct EditorView: NSViewRepresentable {
    let document: EZDocument
    let controller: EditorController
    @Environment(\.undoManager) private var undoManager

    func makeNSView(context: Context) -> NSScrollView {
        let storage = document.storage
        let layoutManager = ClaudeLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: PageTextView.column, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = PageTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), textContainer: container)
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.usesFontPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 0, height: PageTextView.top)
        textView.insertionPointColor = NSColor(srgb: 0x0A6CFF)
        textView.selectedTextAttributes = [.backgroundColor: NSColor(srgb: 0x0A84FF, alpha: 0.24)]
        textView.typingAttributes = LessonStyle.attributes(.body)
        textView.defaultParagraphStyle = LessonStyle.paragraph(.body)

        let scrollView = PageScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = textView

        controller.attach(textView: textView, storage: storage)
        controller.undoManager = undoManager
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        controller.undoManager = undoManager
    }
}
