// Génère Resources/AppIcon.icns : verre clair sur fond orange, feuille et stylo,
// avec une étoile rayonnante (à la manière de Claude) au bout de la plume.
import AppKit

func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)

    // Carré arrondi macOS : 824 pt centrés, rayon ~185, ombre portée.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    c(0xD97757).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Fond : dégradé orange chaud et deux lueurs.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [c(0xF6B26B), c(0xE5835A), c(0xC8553D)])!.draw(in: body, angle: -65)
    for (hex, a, x, y, r) in [(0xFFD6A0, 0.7, 260.0, 820.0, 420.0), (0xB8432E, 0.55, 860.0, 180.0, 380.0)] {
        let center = NSPoint(x: x, y: y)
        NSGradient(colors: [c(UInt32(hex), a), c(UInt32(hex), 0)])!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: r, options: [])
    }
    // Reflet du verre en haut.
    NSGradient(colors: [.white.withAlphaComponent(0.35), .white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: 100, y: 620, width: 824, height: 304), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    // Liseré lumineux du verre.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 3, dy: 3), xRadius: 182, yRadius: 182)
    rim.lineWidth = 6
    NSColor.white.withAlphaComponent(0.45).setStroke()
    rim.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // Feuille de verre clair, légèrement inclinée, avec des lignes de texte.
    NSGraphicsContext.saveGraphicsState()
    ctx.translateBy(x: 470, y: 500)
    ctx.rotate(by: 0.07)
    let sheet = NSRect(x: -230, y: -290, width: 460, height: 580)
    let sheetShadow = NSShadow()
    sheetShadow.shadowColor = c(0x7A2A18, 0.35)
    sheetShadow.shadowBlurRadius = 30
    sheetShadow.shadowOffset = NSSize(width: 0, height: -14)
    NSGraphicsContext.saveGraphicsState()
    sheetShadow.set()
    NSColor.white.withAlphaComponent(0.92).setFill()
    NSBezierPath(roundedRect: sheet, xRadius: 48, yRadius: 48).fill()
    NSGraphicsContext.restoreGraphicsState()
    let sheetRim = NSBezierPath(roundedRect: sheet.insetBy(dx: 2, dy: 2), xRadius: 46, yRadius: 46)
    sheetRim.lineWidth = 4
    NSColor.white.setStroke()
    sheetRim.stroke()
    for (i, width) in [300.0, 360, 330, 360, 220].enumerated() {
        let line = NSRect(x: -170, y: 170 - Double(i) * 78, width: width, height: 26)
        c(0xE5835A, i == 0 ? 0.55 : 0.28).setFill()
        NSBezierPath(roundedRect: line, xRadius: 13, yRadius: 13).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    // Stylo en diagonale, plume vers le bas à gauche.
    let tip = NSPoint(x: 395, y: 330)
    NSGraphicsContext.saveGraphicsState()
    ctx.translateBy(x: tip.x, y: tip.y)
    ctx.rotate(by: -.pi / 4)   // l'axe +y du stylo pointe vers le haut à droite
    let penShadow = NSShadow()
    penShadow.shadowColor = .black.withAlphaComponent(0.3)
    penShadow.shadowBlurRadius = 22
    penShadow.shadowOffset = NSSize(width: 10, height: -14)
    NSGraphicsContext.saveGraphicsState()
    penShadow.set()
    // Corps.
    let barrel = NSBezierPath(roundedRect: NSRect(x: -52, y: 190, width: 104, height: 420), xRadius: 52, yRadius: 52)
    c(0x2B2B30).setFill()
    barrel.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [.white.withAlphaComponent(0.28), .white.withAlphaComponent(0)])!
        .draw(in: barrel, angle: 0)
    // Bague.
    c(0xF2C29A).setFill()
    NSBezierPath(roundedRect: NSRect(x: -54, y: 180, width: 108, height: 34), xRadius: 10, yRadius: 10).fill()
    // Plume.
    let nib = NSBezierPath()
    nib.move(to: NSPoint(x: 0, y: 0))
    nib.curve(to: NSPoint(x: -50, y: 185), controlPoint1: NSPoint(x: -18, y: 50), controlPoint2: NSPoint(x: -50, y: 120))
    nib.line(to: NSPoint(x: 50, y: 185))
    nib.curve(to: NSPoint(x: 0, y: 0), controlPoint1: NSPoint(x: 50, y: 120), controlPoint2: NSPoint(x: 18, y: 50))
    nib.close()
    NSGradient(colors: [c(0xD9DAE0), c(0x9C9DA6)])!.draw(in: nib, angle: 0)
    c(0x6E6F78).setStroke()
    nib.lineWidth = 5
    nib.stroke()
    let slit = NSBezierPath()
    slit.move(to: NSPoint(x: 0, y: 22))
    slit.line(to: NSPoint(x: 0, y: 120))
    slit.lineWidth = 6
    slit.lineCapStyle = .round
    slit.stroke()
    NSBezierPath(ovalIn: NSRect(x: -11, y: 112, width: 22, height: 22)).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Étoile rayonnante au bout de la plume : rayons irréguliers, couleur de Claude, halo clair.
    NSGraphicsContext.saveGraphicsState()
    ctx.translateBy(x: tip.x, y: tip.y)
    let glow = NSPoint.zero
    NSGradient(colors: [.white.withAlphaComponent(0.95), .white.withAlphaComponent(0)])!
        .draw(fromCenter: glow, radius: 0, toCenter: glow, radius: 130, options: [])
    let lengths: [CGFloat] = [92, 70, 86, 64, 96, 74, 82, 66, 90, 72, 80, 64]
    for (i, length) in lengths.enumerated() {
        ctx.saveGState()
        ctx.rotate(by: CGFloat(i) * .pi * 2 / CGFloat(lengths.count) + 0.12)
        let ray = NSBezierPath(roundedRect: NSRect(x: -9, y: 10, width: 18, height: length), xRadius: 9, yRadius: 9)
        c(0xD97757).setFill()
        ray.fill()
        ctx.restoreGState()
    }
    c(0xD97757).setFill()
    NSBezierPath(ovalIn: NSRect(x: -20, y: -20, width: 40, height: 40)).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try! render(size * scale).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
try! render(1024).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("Resources/AppIcon-preview.png"))
print("iconset prêt")
