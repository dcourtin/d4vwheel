import SwiftUI

/// Dessine la roue d'après l'état du modèle. Aucune animation implicite : tout est fonction du temps du modèle.
struct WheelView: View {
    @ObservedObject var model: WheelModel
    @Environment(\.displayScale) private var scale

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            _ = model.frame
            var painter = WheelPainter(m: model, scale: scale, size: size)
            painter.draw(&ctx)
        }
        .font(.system(size: 20, weight: .medium))
        .ignoresSafeArea()
    }
}

@MainActor
struct WheelPainter {
    let m: WheelModel
    let scale: CGFloat
    let size: CGSize

    let panel = Color(nsColor: .windowBackgroundColor)
    let accent = Color(nsColor: .controlAccentColor)
    let separator = Color(nsColor: .separatorColor)
    let labelColor = Color(nsColor: .labelColor)
    let secondary = Color(nsColor: .secondaryLabelColor)
    let tertiary = Color(nsColor: .tertiaryLabelColor)

    private func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
    private func snapped(_ r: CGRect) -> CGRect { CGRect(x: snap(r.minX), y: snap(r.minY), width: r.width, height: r.height) }
    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    mutating func draw(_ ctx: inout GraphicsContext) {
        guard m.phase != .closed else { return }
        let c = m.center
        let v = m.visual

        if m.style.drawsVeil {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(v.veil)))
            if m.style.translucent {
                // Le voile s'arrête au bord de la roue : dessous, le flou de la vue hôte.
                ctx.blendMode = .destinationOut
                ctx.fill(circle(c, m.currentOuterRadius * v.wheelScale), with: .color(.black))
                ctx.blendMode = .normal
            }
        }

        ctx.drawLayer { layer in
            layer.opacity = v.alpha
            layer.translateBy(x: c.x, y: c.y)
            layer.scaleBy(x: v.wheelScale, y: v.wheelScale)
            layer.translateBy(x: -c.x, y: -c.y)
            // Du plus profond au moins profond : chaque anneau, puis ses icônes, sous le niveau précédent.
            for ring in m.rings.reversed() {
                drawRing(&layer, ring)
                drawItems(&layer, level: ring.level)
            }
            drawDisc(&layer, scale: v.discScale)
            drawCenter(&layer)
            drawItems(&layer, level: 0)
            if let s = m.style.selectedPlace, m.places.indices.contains(s) {
                let p = m.position(level: 0, index: s, lifted: true)
                layer.stroke(circle(p, Geometry.haloRadius - 1), with: .color(accent), lineWidth: 2.5)
            }
        }
        drawLabel(&ctx)
    }

    // MARK: Disque et anneaux

    /// Un disque de panneau : opaque, ou (translucide) seulement son ombre et une teinte sur le flou.
    private func drawPanelCircle(_ ctx: inout GraphicsContext, center c: CGPoint, radius r: CGFloat, shadow: CGFloat) {
        ctx.drawLayer { sh in
            sh.addFilter(.shadow(color: .black.opacity(0.28), radius: shadow, y: shadow * 0.4))
            sh.fill(circle(c, r), with: .color(.black))
        }
        ctx.blendMode = .destinationOut
        ctx.fill(circle(c, r), with: .color(.black))
        ctx.blendMode = .normal
        ctx.fill(circle(c, r), with: .color(panel.opacity(m.style.translucent ? m.style.tintOpacity : 0.97)))
        ctx.stroke(circle(c, r - 0.5), with: .color(separator), lineWidth: 1)
    }

    private func drawDisc(_ ctx: inout GraphicsContext, scale s: Double) {
        let c = m.center
        ctx.drawLayer { l in
            l.translateBy(x: c.x, y: c.y)
            l.scaleBy(x: s, y: s)
            l.translateBy(x: -c.x, y: -c.y)
            drawPanelCircle(&l, center: c, radius: Geometry.discRadius, shadow: 18)
        }
    }

    private func drawRing(_ ctx: inout GraphicsContext, _ ring: WheelModel.Ring) {
        guard ring.deploy.value > 0.001 else { return }
        ctx.drawLayer { l in
            l.opacity = min(1, ring.deploy.value * 2)
            drawPanelCircle(&l, center: m.center, radius: m.ringRadius(ring), shadow: 14)
        }
    }

    private func drawCenter(_ ctx: inout GraphicsContext) {
        let g = m.centerGlow.value
        let c = m.center
        ctx.fill(circle(c, Geometry.centerRadius), with: .color(labelColor.opacity(0.05 + 0.08 * g)))
        if let place = m.style.centerPlace {
            drawIcon(&ctx, place, at: c)
            return
        }
        var cross = Path()
        let a: CGFloat = 7
        cross.move(to: CGPoint(x: c.x - a, y: c.y - a)); cross.addLine(to: CGPoint(x: c.x + a, y: c.y + a))
        cross.move(to: CGPoint(x: c.x + a, y: c.y - a)); cross.addLine(to: CGPoint(x: c.x - a, y: c.y + a))
        ctx.stroke(cross, with: .color(secondary.opacity(0.55 + 0.45 * g)),
                   style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
    }

    // MARK: Icônes

    private func drawHalo(_ ctx: inout GraphicsContext, at p: CGPoint, amount h: Double) {
        guard h > 0.005 else { return }
        let r = Geometry.haloRadius * (0.75 + 0.25 * h)
        ctx.fill(circle(p, r), with: .color(accent.opacity(0.22 * h)))
    }

    private func drawItems(_ ctx: inout GraphicsContext, level: Int) {
        for (i, place) in m.items(atLevel: level).enumerated() {
            let progress = level == 0 ? m.iconProgress(i) : m.itemProgress(level: level, index: i)
            guard progress > 0.001 else { continue }
            let pos = m.position(level: level, index: i, lifted: true)
            drawHalo(&ctx, at: pos, amount: m.haloValue(level: level, index: i))
            ctx.drawLayer { l in
                l.opacity = progress
                drawIcon(&l, place, at: pos)
            }
        }
    }

    private func drawIcon(_ ctx: inout GraphicsContext, _ place: Place, at pos: CGPoint) {
        let s = Geometry.iconSize
        let rect = snapped(CGRect(x: pos.x - s / 2, y: pos.y - s / 2, width: s, height: s))
        switch place.kind {
        case .app:
            if let icon = place.icon {
                ctx.draw(Image(nsImage: icon), in: rect)
            } else {
                drawInitial(&ctx, place.name, in: rect)
            }
            if place.isRunning {
                ctx.fill(circle(CGPoint(x: rect.midX, y: rect.maxY + 5), 2), with: .color(secondary))
            }
        case .command, .unsupported:
            if let icon = place.icon {
                // Action d'une appli : l'icône de l'appli, avec la pastille d'accent.
                ctx.draw(Image(nsImage: icon), in: rect)
            } else {
                ctx.fill(Path(roundedRect: rect, cornerRadius: 10), with: .color(labelColor.opacity(0.08)))
                var symbol = ctx.resolve(Image(systemName: place.symbol ?? "questionmark"))
                symbol.shading = .color(place.kind == .command ? labelColor : secondary)
                ctx.draw(symbol, at: CGPoint(x: rect.midX, y: rect.midY))
            }
            if place.kind == .command {
                let b = CGPoint(x: rect.maxX - 3, y: rect.maxY - 3)
                ctx.fill(circle(b, 6), with: .color(panel))
                ctx.fill(circle(b, 4.5), with: .color(accent))
            }
        case .folder:
            drawFolderTile(&ctx, place, in: rect)
        case .empty:
            ctx.draw(Text("+").font(.system(size: 22, weight: .light)).foregroundColor(tertiary),
                     at: CGPoint(x: rect.midX, y: rect.midY))
        }
    }

    /// Tuile d'accent avec les 4 premières icônes du dossier en mini.
    private func drawFolderTile(_ ctx: inout GraphicsContext, _ place: Place, in rect: CGRect) {
        let corner = Geometry.folderCorner * rect.width / Geometry.iconSize
        ctx.fill(Path(roundedRect: rect, cornerRadius: corner), with: .color(accent.opacity(0.2)))
        let mini = Geometry.miniIcon * rect.width / Geometry.iconSize
        let gap = Geometry.miniGap * rect.width / Geometry.iconSize
        let grid = mini * 2 + gap
        let ox = rect.midX - grid / 2, oy = rect.midY - grid / 2
        for (k, child) in place.children.prefix(4).enumerated() {
            let r = snapped(CGRect(x: ox + CGFloat(k % 2) * (mini + gap), y: oy + CGFloat(k / 2) * (mini + gap),
                                   width: mini, height: mini))
            if let icon = child.icon {
                ctx.draw(Image(nsImage: icon), in: r)
            } else if child.kind == .app {
                drawInitial(&ctx, child.name, in: r)
            } else if child.kind == .folder {
                ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(accent.opacity(0.45)))
            } else {
                var symbol = ctx.resolve(Image(systemName: child.symbol ?? "questionmark"))
                symbol.shading = .color(labelColor)
                ctx.draw(symbol, in: r.insetBy(dx: 2, dy: 2))
            }
        }
        if place.children.isEmpty {
            ctx.draw(Text("+").font(.system(size: 22, weight: .light)).foregroundColor(accent),
                     at: CGPoint(x: rect.midX, y: rect.midY))
        }
    }

    /// Appli sans icône : son initiale sur une pastille de couleur tirée de son nom.
    private func drawInitial(_ ctx: inout GraphicsContext, _ name: String, in rect: CGRect) {
        let hue = Double(name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) } & 0xFFFF) / 65536
        ctx.fill(circle(CGPoint(x: rect.midX, y: rect.midY), rect.width / 2),
                 with: .color(Color(hue: hue, saturation: 0.55, brightness: 0.75)))
        let initial = String(name.prefix(1)).uppercased()
        ctx.draw(Text(initial).font(.system(size: rect.width * 0.45, weight: .semibold)).foregroundColor(.white),
                 at: CGPoint(x: rect.midX, y: rect.midY))
    }

    // MARK: Étiquette

    private func drawLabel(_ ctx: inout GraphicsContext) {
        let u = Easing.clamp01((m.now - m.labelChangedAt) / Geometry.labelDuration)
        let y = m.center.y + Geometry.outerRadius(level: m.depth) + Geometry.labelGap + Geometry.labelHeight / 2
        let alphaScale = m.visual.alpha
        if u < 1, !m.previousLabel.isEmpty {
            drawPill(&ctx, m.previousLabel, at: CGPoint(x: m.center.x, y: y - 4 * u), alpha: (1 - u) * alphaScale)
        }
        if !m.label.isEmpty {
            drawPill(&ctx, m.label, at: CGPoint(x: m.center.x, y: y + 4 * (1 - u)), alpha: u * alphaScale)
        }
    }

    private func drawPill(_ ctx: inout GraphicsContext, _ text: String, at p: CGPoint, alpha: Double) {
        guard alpha > 0.005 else { return }
        let resolved = ctx.resolve(
            Text(text).font(.system(size: Geometry.labelFontSize, weight: .medium)).foregroundColor(labelColor)
        )
        let measured = resolved.measure(in: CGSize(width: 10_000, height: Geometry.labelHeight))
        let w = min(measured.width.rounded(.up), Geometry.labelMaxWidth)
        let rect = CGRect(x: snap(p.x - w / 2 - 12), y: snap(p.y - Geometry.labelHeight / 2),
                          width: w + 24, height: Geometry.labelHeight)
        ctx.drawLayer { l in
            l.opacity = alpha
            l.drawLayer { sh in
                sh.addFilter(.shadow(color: .black.opacity(0.2), radius: 8, y: 3))
                sh.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(panel.opacity(0.97)))
            }
            l.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: rect.height / 2),
                     with: .color(separator), lineWidth: 1)
            // Tronquée à 360 : on coupe le dessin et on efface en dégradé le bord droit.
            let textRect = CGRect(x: rect.minX + 12, y: rect.minY, width: w, height: rect.height)
            l.drawLayer { t in
                t.clip(to: Path(textRect))
                t.draw(resolved, at: CGPoint(x: textRect.minX, y: textRect.midY), anchor: .leading)
                if measured.width > Geometry.labelMaxWidth {
                    t.fill(Path(CGRect(x: textRect.maxX - 24, y: textRect.minY, width: 24, height: textRect.height)),
                           with: .linearGradient(Gradient(colors: [panel.opacity(0), panel.opacity(0.97)]),
                                                 startPoint: CGPoint(x: textRect.maxX - 24, y: 0),
                                                 endPoint: CGPoint(x: textRect.maxX, y: 0)))
                }
            }
        }
    }
}
