import AppKit
import SwiftUI

// MARK: - MeshBackground

/// Fond vivant : trois taches floutées qui dérivent (22 à 31 s par cycle) et changent de teinte en 0,9 s.
struct MeshBackground: View {
    var mood: Mood
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = [false, false, false]

    var body: some View {
        GeometryReader { geo in
            let cw = geo.size.width * 1.5, ch = geo.size.height * 1.5
            ZStack {
                blob(0, size: CGSize(width: cw * 0.62, height: ch * 0.72),
                     center: CGPoint(x: cw * 0.25, y: ch * 0.28), to: (0.18, 0.10, 1.12))
                blob(1, size: CGSize(width: cw * 0.56, height: ch * 0.66),
                     center: CGPoint(x: cw * 0.80, y: ch * 0.41), to: (-0.16, 0.14, 0.90))
                blob(2, size: CGSize(width: cw * 0.66, height: ch * 0.60),
                     center: CGPoint(x: cw * 0.51, y: ch * 0.84), to: (0.12, -0.16, 0.92))
            }
            .frame(width: cw, height: ch)
            .blur(radius: 64)
            .saturation(1.5)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .background(UY.surfaceBase)
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            for (i, duration) in [22.0, 27.0, 31.0].enumerated() {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    drift[i] = true
                }
            }
        }
    }

    private func blob(_ i: Int, size: CGSize, center: CGPoint, to: (Double, Double, Double)) -> some View {
        let moved = drift[i]
        return Ellipse()
            .fill(mood.colors[i])
            .opacity(scheme == .dark ? 0.5 : 0.62)
            .frame(width: size.width, height: size.height)
            .scaleEffect(moved ? to.2 : 1)
            .position(x: center.x + (moved ? size.width * to.0 : 0),
                      y: center.y + (moved ? size.height * to.1 : 0))
            .animation(UY.mood, value: mood)
    }
}

// MARK: - Verre

extension View {
    /// Surface de verre UY : Liquid Glass natif.
    func uyGlass(radius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        var glass: Glass = tint.map { Glass.regular.tint($0) } ?? .regular
        if interactive { glass = glass.interactive() }
        return self.glassEffect(glass, in: shape)
    }
}

extension View {
    /// Fondu en haut et en bas d'une zone qui défile, pour que le contenu ne soit pas coupé net.
    func uyEdgeFade(_ size: CGFloat = UY.space22) -> some View {
        mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: size)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: size)
            }
        }
    }
}

// MARK: - Icônes centrées

/// Centrage optique automatique des SF Symbols : on rend le symbole une fois, on mesure où tombe
/// réellement l'encre, et on compense le décalage pour qu'il soit centré dans tous les sens.
@MainActor
enum SymbolCentering {
    private static var cache: [String: CGSize] = [:]

    static func offset(_ name: String, size: CGFloat, weight: Font.Weight = .semibold) -> CGSize {
        let key = "\(name)#\(size)#\(weight)"
        if let cached = cache[key] { return cached }
        let scale: CGFloat = 4, box: CGFloat = 48
        let renderer = ImageRenderer(content: Image(systemName: name)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(.black)
            .frame(width: box, height: box))
        renderer.scale = scale
        var result = CGSize.zero
        if let cg = renderer.cgImage,
           let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
           let data = { ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height)); return ctx.data }() {
            let w = cg.width, h = cg.height
            let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
            var minX = w, maxX = -1, minY = h, maxY = -1
            for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 80 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            } }
            if maxX >= 0 {
                let dx = (CGFloat(minX + maxX + 1) / 2 - CGFloat(w) / 2) / scale
                let dy = (CGFloat(minY + maxY + 1) / 2 - CGFloat(h) / 2) / scale
                result = CGSize(width: (-dx * 4).rounded() / 4, height: (-dy * 4).rounded() / 4)
            }
        }
        cache[key] = result
        return result
    }
}

/// SF Symbol centré optiquement (voir `SymbolCentering`). À utiliser pour toute icône dans un bouton.
struct UYSymbol: View {
    let name: String
    var size: CGFloat = 15
    var weight: Font.Weight = .semibold
    /// Avec un libellé à côté, on ne corrige que la hauteur.
    var verticalOnly = false

    var body: some View {
        let o = SymbolCentering.offset(name, size: size, weight: weight)
        Image(systemName: name)
            .font(.system(size: size, weight: weight))
            .offset(x: verticalOnly ? 0 : o.width, y: o.height)
    }
}

// MARK: - Champ

/// Champ de saisie UY : arrondi, texte centré, anneau de focus teinté.
struct GlassField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text)
            } else {
                TextField("", text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(UY.body)
        .foregroundStyle(UY.ink)
        .multilineTextAlignment(.center)
        .focused($focused)
        .overlay {
            if text.isEmpty {
                Text(placeholder).font(UY.body).foregroundStyle(UY.inkSecondary).allowsHitTesting(false)
            }
        }
        .accessibilityLabel(placeholder)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: UY.radiusField, style: .continuous).fill(UY.track))
        .overlay {
            RoundedRectangle(cornerRadius: UY.radiusField, style: .continuous)
                .strokeBorder(UY.focusRing, lineWidth: 2)
                .opacity(focused ? 1 : 0)
        }
        .animation(UY.ease(0.2), value: focused)
    }
}

// MARK: - Capsule d'information

struct GlassCapsuleLabel<Leading: View>: View {
    let text: String
    var color: Color = UY.ink
    var tint: Color?
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 8) {
            leading
            Text(text)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .uyGlass(radius: UY.radiusCapsule, tint: tint)
    }
}

// MARK: - Interaction

/// Style neutre pour les lignes et tuiles cliquables : légère atténuation à l'appui, estompé si désactivé.
struct UYPressStyle: ButtonStyle {
    var radius: CGFloat = UY.radiusCapsule

    func makeBody(configuration: Configuration) -> some View {
        PressBody(radius: radius, pressed: configuration.isPressed) { configuration.label }
    }

    private struct PressBody<Content: View>: View {
        let radius: CGFloat
        let pressed: Bool
        @ViewBuilder let content: Content
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            content
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .opacity(!enabled ? 0.45 : (pressed ? 0.75 : 1))
        }
    }
}

// MARK: - Fenêtre active

extension View {
    /// Rend active la fenêtre (ou la feuille) qui affiche cette vue dès son apparition, pour que le clavier
    /// (Échap, Retour, raccourcis) lui parvienne sans avoir à cliquer dedans.
    func uyMakeKeyOnAppear() -> some View { background(KeyWindowMaker()) }
}

private struct KeyWindowMaker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.window?.makeKey() }
        }
    }
}
