// Dessine l'icône de Roue (une roue de huit places) et écrit un .iconset ; iconutil en fait le .icns.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(size: Int, scale: Int, name: String) {
    let px = size * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let s = CGFloat(px)
    // Fond : carré arrondi (proportions des icônes macOS), dégradé bleu nuit.
    let inset = s * 0.1
    let square = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: square, xRadius: square.width * 0.22, yRadius: square.width * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.30, blue: 0.62, alpha: 1),
                        NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.34, alpha: 1)])!
        .draw(in: bg, angle: -90)
    // Disque clair.
    let c = CGPoint(x: s / 2, y: s / 2)
    let r = square.width * 0.36
    NSColor(calibratedWhite: 1, alpha: 0.96).setFill()
    NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
    // Huit places.
    let accent = NSColor(calibratedRed: 0.22, green: 0.52, blue: 0.96, alpha: 1)
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4 + .pi / 2
        let p = CGPoint(x: c.x + r * 0.66 * cos(a), y: c.y + r * 0.66 * sin(a))
        let d = r * 0.2
        (i == 0 ? accent : NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.34, alpha: 0.85)).setFill()
        NSBezierPath(roundedRect: CGRect(x: p.x - d, y: p.y - d, width: 2 * d, height: 2 * d), xRadius: d * 0.45, yRadius: d * 0.45).fill()
    }
    // Centre.
    NSColor(calibratedWhite: 0, alpha: 0.08).setFill()
    let cr = r * 0.22
    NSBezierPath(ovalIn: CGRect(x: c.x - cr, y: c.y - cr, width: 2 * cr, height: 2 * cr)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

for size in [16, 32, 128, 256, 512] {
    draw(size: size, scale: 1, name: "icon_\(size)x\(size).png")
    draw(size: size, scale: 2, name: "icon_\(size)x\(size)@2x.png")
}
print("iconset écrit : \(out.path)")
