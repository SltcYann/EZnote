import AppKit
import SwiftUI

/// Schéma proposé par l'IA dans une leçon, écrit en texte simple puis dessiné par l'app :
///
///     :::schema frise Les étapes de la Révolution      :::schema tableau Girondins et Montagnards
///     1789 | Prise de la Bastille                      | | Girondins | Montagnards |
///     1792 | Proclamation de la République             | Base | Province | Paris |
///     :::                                              :::
///
///     :::schema carte La photosynthèse
///     - Ingrédients
///       - eau
///     - Lieu
///     :::
struct Schema: Hashable {
    enum Kind: String { case timeline = "frise", table = "tableau", map = "carte" }

    let kind: Kind
    let title: String
    let lines: [String]

    init?(header: String, lines: [String]) {
        let words = header.split(separator: " ", maxSplits: 1)
        guard let first = words.first, let kind = Kind(rawValue: first.lowercased()) else { return nil }
        self.kind = kind
        title = words.count > 1 ? String(words[1]) : ""
        self.lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: Image

    private static var cache: [Schema: NSImage] = [:]

    /// Image du schéma (mise en cache : la leçon est réaffichée ~15 fois par seconde pendant l'écriture).
    @MainActor
    func image() -> NSImage? {
        if let cached = Self.cache[self] { return cached }
        let renderer = ImageRenderer(content: SchemaView(schema: self).environment(\.colorScheme, .light))
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: 640, height: nil)
        guard let image = renderer.nsImage else { return nil }
        Self.cache[self] = image
        return image
    }

    /// Pièce jointe prête à insérer dans le texte (PNG, pour être enregistrée avec le document).
    @MainActor
    func attachment() -> NSTextAttachment? {
        guard let image = image(), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let wrapper = FileWrapper(regularFileWithContents: png)
        wrapper.preferredFilename = "schema.png"
        // Seulement le fichier PNG (une image en mémoire en plus ferait réencoder l'image à l'enregistrement).
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        attachment.bounds = CGRect(origin: .zero, size: image.size)
        return attachment
    }

    // MARK: Données

    /// Frise : « date | événement ».
    var events: [(date: String, text: String)] {
        lines.map { line in
            let parts = line.trimmingCharacters(in: CharacterSet(charactersIn: "-• ")).split(separator: "|", maxSplits: 1)
            return parts.count == 2
                ? (parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces))
                : ("", line.trimmingCharacters(in: .whitespaces))
        }
    }

    /// Tableau : lignes « | a | b | » (la ligne de tirets du Markdown est ignorée).
    var rows: [[String]] {
        lines.compactMap { line in
            let cells = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) ? nil : cells
        }
    }

    /// Carte mentale : branches « - » et sous-branches indentées.
    var branches: [(title: String, items: [String])] {
        var result: [(String, [String])] = []
        for line in lines {
            let indented = line.hasPrefix(" ") || line.hasPrefix("\t")
            let text = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-•* "))
            if indented, !result.isEmpty { result[result.count - 1].1.append(text) } else { result.append((text, [])) }
        }
        return result
    }
}

/// Dessin d'un schéma : carte claire aux couleurs de Claude, lisible aussi en mode sombre et à l'impression.
private struct SchemaView: View {
    let schema: Schema
    private let orange = Color(hex: 0xD97757)
    private let ink = Color(hex: 0x1D1D1F)

    var body: some View {
        VStack(spacing: 14) {
            if !schema.title.isEmpty {
                Text(schema.title).font(.system(size: 17, weight: .bold)).foregroundStyle(ink)
                    .multilineTextAlignment(.center)
            }
            switch schema.kind {
            case .timeline: timeline
            case .table: table
            case .map: map
            }
        }
        .padding(20)
        .frame(width: 640)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0xFFF8F4)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(orange.opacity(0.35), lineWidth: 1))
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(schema.events.enumerated()), id: \.offset) { index, event in
                HStack(alignment: .top, spacing: 14) {
                    Text(event.date)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(orange)
                        .frame(width: 110, alignment: .trailing)
                    VStack(spacing: 0) {
                        Circle().fill(orange).frame(width: 11, height: 11).padding(.top, 3)
                        if index < schema.events.count - 1 {
                            Rectangle().fill(orange.opacity(0.35)).frame(width: 2).frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 11)
                    Text(event.text)
                        .font(.system(size: 13))
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 14)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var table: some View {
        let rows = schema.rows
        let columns = rows.map(\.count).max() ?? 0
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { c in
                        Text(c < row.count ? row[c] : "")
                            .font(.system(size: 12.5, weight: r == 0 || c == 0 ? .semibold : .regular))
                            .foregroundStyle(r == 0 ? Color.white : ink)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                    }
                }
                .background(r == 0 ? orange : (r.isMultiple(of: 2) ? orange.opacity(0.07) : Color.white))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(orange.opacity(0.3), lineWidth: 1))
    }

    private var map: some View {
        let branches = schema.branches
        return VStack(spacing: 12) {
            if schema.title.isEmpty, let first = branches.first {
                Text(first.title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(orange))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                ForEach(Array(branches.enumerated()), id: \.offset) { _, branch in
                    VStack(spacing: 6) {
                        Text(branch.title).font(.system(size: 13, weight: .bold)).foregroundStyle(orange)
                            .multilineTextAlignment(.center)
                        ForEach(branch.items, id: \.self) { item in
                            Text(item).font(.system(size: 12)).foregroundStyle(ink).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(orange.opacity(0.4), lineWidth: 1))
                }
            }
        }
    }
}
