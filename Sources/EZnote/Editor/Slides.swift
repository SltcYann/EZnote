import AppKit
import PDFKit

/// Diapositives du professeur insérées en PDF : leurs pages sont envoyées à l'IA comme images.
enum Slides {
    /// Au plus 30 pages, pour garder une demande raisonnable.
    static let maxPages = 30

    static func isPDF(_ data: Data) -> Bool { data.starts(with: Array("%PDF".utf8)) }

    /// Les pages d'un PDF joint, rendues en images (nil si la pièce jointe n'est pas un PDF).
    static func pages(of attachment: NSTextAttachment) -> [NSImage]? {
        guard let data = attachment.fileWrapper?.regularFileContents ?? attachment.contents, isPDF(data),
              let document = PDFDocument(data: data) else { return nil }
        return (0..<min(document.pageCount, maxPages)).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale = 1568 / max(bounds.width, bounds.height)
            return page.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        }
    }
}
