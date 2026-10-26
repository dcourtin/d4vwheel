import AppKit
import SwiftUI

/// Panneau sans bordure, non activant, transparent, plein écran sur l'écran du pointeur.
final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        isMovable = false
        animationBehavior = .none
    }
}

/// Reçoit souris et clavier, cadence le modèle sur l'écran, et héberge la vue SwiftUI qui dessine
/// par-dessus un fond flouté (type Dock) découpé à la forme de la roue.
final class WheelHostView: NSView {
    let model: WheelModel
    private let blur = NSVisualEffectView()
    private let hosting: NSHostingView<WheelView>
    private var link: CADisplayLink?
    private var maskRadius: CGFloat = -1

    init(model: WheelModel) {
        self.model = model
        self.hosting = NSHostingView(rootView: WheelView(model: model))
        super.init(frame: .zero)
        wantsLayer = true
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.isHidden = true
        addSubview(blur)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        model.style.translucent = true
        model.onWake = { [weak self] in self?.link?.isPaused = false }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    /// On absorbe tous les événements ; la vue SwiftUI ne fait que dessiner.
    override func hitTest(_ point: NSPoint) -> NSView? { self }

    override func layout() {
        super.layout()
        hosting.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    // MARK: Cadence

    /// Relit les réglages d'apparence (matériau du flou, opacité de la teinte).
    func applyAppearance() {
        blur.material = Appearance.material
        model.style.tintOpacity = Appearance.tintOpacity
    }

    func startDisplayLink() {
        if link == nil {
            let l = displayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }
        link?.isPaused = false
        maskRadius = -1
    }

    func stopDisplayLink() {
        link?.invalidate()
        link = nil
        blur.isHidden = true
    }

    @objc private func tick(_ link: CADisplayLink) {
        model.tick(now: link.targetTimestamp)
        updateBlur()
        if !model.needsFrames { link.isPaused = true }
    }

    /// Le flou suit le bord extérieur de la roue (disque ou anneau le plus large) et son opacité.
    private func updateBlur() {
        guard model.isVisible else { blur.isHidden = true; return }
        let v = model.visual
        let discR = Geometry.discRadius * v.discScale
        let r = max(discR, model.currentOuterRadius) * v.wheelScale
        blur.isHidden = false
        blur.alphaValue = v.alpha
        if abs(r - maskRadius) > 0.25 {
            maskRadius = r
            let side = ceil(2 * r) + 2
            blur.frame = CGRect(x: model.center.x - side / 2, y: model.center.y - side / 2, width: side, height: side)
            blur.maskImage = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
                NSColor.black.setFill()
                NSBezierPath(ovalIn: CGRect(x: rect.midX - r, y: rect.midY - r, width: 2 * r, height: 2 * r)).fill()
                return true
            }
        }
    }

    // MARK: Souris

    private func local(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseMoved(with event: NSEvent) { model.pointerMoved(to: local(event)) }
    override func mouseDragged(with event: NSEvent) { model.pointerMoved(to: local(event)) }
    override func otherMouseDragged(with event: NSEvent) { model.pointerMoved(to: local(event)) }
    override func rightMouseDragged(with event: NSEvent) { model.pointerMoved(to: local(event)) }
    override func mouseDown(with event: NSEvent) { model.click(at: local(event)) }
    override func otherMouseUp(with event: NSEvent) { model.middleReleased(at: local(event)) }
    override func rightMouseDown(with event: NSEvent) { model.close() }

    // MARK: Clavier

    override func keyDown(with event: NSEvent) { model.key(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Les raccourcis ⌘… ne concernent pas la roue, mais on ne les laisse pas passer non plus.
        model.key(event)
        return true
    }
}

/// Ouvre et ferme la roue : une seule instance, redemander la roue ouverte la ferme.
@MainActor
final class WheelController {
    let model = WheelModel()
    private let panel = WheelPanel()
    private let host: WheelHostView

    init() {
        host = WheelHostView(model: model)
        panel.contentView = host
        model.onLaunch = { Launcher.launch($0) }
        model.onClosed = { [weak self] in self?.hide() }
    }

    var isOpen: Bool { model.acceptsInput }

    func toggle() {
        if isOpen { model.close() } else { open() }
    }

    /// Point d'un événement global (repère CoreGraphics, origine en haut à gauche de l'écran principal)
    /// dans le repère de la vue (origine en haut à gauche du panneau).
    func viewPoint(fromGlobal p: CGPoint) -> CGPoint {
        let f = panel.frame
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoaY = mainHeight - p.y
        return CGPoint(x: p.x - f.minX, y: f.maxY - cocoaY)
    }

    /// Geste continu au clic du milieu : glisser puis relâcher.
    func gestureDragged(toGlobal p: CGPoint) { model.pointerMoved(to: viewPoint(fromGlobal: p)) }
    func gestureReleased(atGlobal p: CGPoint) {
        model.pointerMoved(to: viewPoint(fromGlobal: p))
        model.middleReleased(at: viewPoint(fromGlobal: p))
    }

    func open() {
        guard !model.isVisible else { return }
        Geometry.motionReduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let (config, _) = ConfigStore.load()
        let places = AppResolver.resolve(config)

        panel.setFrame(screen.frame, display: false)
        host.frame = CGRect(origin: .zero, size: screen.frame.size)

        // Repère de la vue : origine en haut à gauche de l'écran.
        let f = screen.frame, v = screen.visibleFrame
        var c = CGPoint(x: mouse.x - f.minX, y: f.maxY - mouse.y)
        let outer = Geometry.outerRadius(level: config.depth)
        let m = Geometry.screenMargin
        let labelSpace = Geometry.labelGap + Geometry.labelHeight
        c.x = clamp(c.x, v.minX - f.minX + m + outer, v.maxX - f.minX - m - outer)
        c.y = clamp(c.y, f.maxY - v.maxY + m + outer, f.maxY - v.minY - m - outer - labelSpace)

        host.applyAppearance()
        model.open(places: places, center: c, now: CACurrentMediaTime())
        host.startDisplayLink()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(host)
    }

    private func hide() {
        panel.orderOut(nil)
        host.stopDisplayLink()
    }

    private func clamp(_ x: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        lo <= hi ? min(hi, max(lo, x)) : (lo + hi) / 2
    }
}
