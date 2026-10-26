import AppKit
import Combine

/// État de la roue et de ses animations. Avancé image par image par `tick(now:)`,
/// lu par la vue SwiftUI ; toute entrée (souris, clavier) passe par ici.
///
/// Niveaux : 0 = les huit places de la roue ; 1, 2 = anneaux ouverts par un dossier
/// du niveau précédent, centrés sur l'angle de ce dossier.
@MainActor
final class WheelModel: ObservableObject {
    enum Phase: Equatable { case closed, opening(Double), open, closing(Double) }
    enum Target: Equatable { case center, item(level: Int, index: Int) }

    /// Options de dessin : la fenêtre Réglages réutilise la même roue, sans voile et avec une place choisie.
    struct Style {
        var drawsVeil = true
        /// Fond flouté (la vue hôte place un NSVisualEffectView sous la roue) plutôt qu'un disque opaque.
        var translucent = false
        /// Opacité de la teinte posée sur le flou (0 = flou pur, 1 = opaque).
        var tintOpacity = Appearance.defaultTintOpacity
        var selectedPlace: Int?
        /// Dans Réglages, un dossier ouvert s'affiche au centre à la place de la croix.
        var centerPlace: Place?
    }

    /// Un anneau ouvert : les places remplies d'un dossier, en arc autour de l'angle du dossier.
    struct Ring {
        let level: Int
        /// Index du dossier parent, au niveau `level - 1`.
        let parent: Int
        let parentAngle: CGFloat
        let items: [Place]
        var deploy = Tracker(tau: Geometry.ringTau)
        var halo = Array(repeating: Tracker(tau: Geometry.hoverTau), count: WheelConfig.placeCount)
    }

    /// Ce que le dessin et la vue hôte ont besoin de savoir de la phase courante.
    struct Visual {
        var veil = 0.0
        var discScale = 1.0
        var wheelScale = 1.0
        var alpha = 1.0
    }

    /// Incrémenté à chaque image : c'est ce que la vue observe.
    @Published private(set) var frame = 0
    var style = Style() { didSet { redraw() } }

    var onWake: (() -> Void)?
    var onClosed: (() -> Void)?
    var onLaunch: ((Place) -> Void)?
    /// Place vide choisie : chemin des dossiers ouverts (vide pour la roue) et index de la place → Réglages.
    var onEmptyChosen: ((_ path: [Int], _ place: Int) -> Void)?

    private(set) var places: [Place] = Array(repeating: .empty, count: WheelConfig.placeCount)
    private(set) var center: CGPoint = .zero
    /// Profondeur des dossiers de la configuration (pour réserver la place des anneaux).
    private(set) var depth = 0
    private(set) var phase: Phase = .closed
    private(set) var now: Double = 0
    private var lastTick: Double = 0

    private(set) var hovered: Target?
    private(set) var halo: [Tracker] = Array(repeating: Tracker(tau: Geometry.hoverTau), count: WheelConfig.placeCount)
    private(set) var centerGlow = Tracker(tau: Geometry.hoverTau)
    private(set) var rings: [Ring] = []
    /// Anneau à déployer une fois les anneaux à replier repliés.
    private var pendingRing: (level: Int, parent: Int)?

    private(set) var label = ""
    private(set) var previousLabel = ""
    private(set) var labelChangedAt: Double = -10
    private var pointerLeftCenter = false

    var isVisible: Bool { phase != .closed }
    var acceptsInput: Bool {
        switch phase { case .open, .opening: return true; default: return false }
    }

    /// Niveau actif pour le clavier : l'anneau ouvert le plus profond, sinon la roue.
    var activeLevel: Int { rings.last(where: { $0.deploy.target == 1 })?.level ?? 0 }

    func items(atLevel level: Int) -> [Place] {
        if level == 0 { return places }
        return rings.indices.contains(level - 1) ? rings[level - 1].items : []
    }

    func item(_ t: Target) -> Place? {
        guard case .item(let l, let i) = t else { return nil }
        let list = items(atLevel: l)
        return list.indices.contains(i) ? list[i] : nil
    }

    // MARK: - Ouverture / fermeture

    func open(places: [Place], center: CGPoint, now: Double) {
        self.places = places
        self.center = center
        self.depth = EntryTree.depth(of: places.map { $0.entry })
        self.now = now
        lastTick = now
        phase = .opening(now)
        hovered = nil
        for i in halo.indices { halo[i].reset(0) }
        centerGlow.reset(0)
        rings = []
        pendingRing = nil
        label = ""
        previousLabel = ""
        labelChangedAt = -10
        pointerLeftCenter = false
        wake()
    }

    /// Resserre et efface la roue ; plus aucune entrée n'est prise.
    func close() {
        guard acceptsInput else { return }
        phase = .closing(now)
        hovered = nil
        wake()
    }

    func redraw() { frame += 1 }

    /// Avance le temps jusqu'à ce que plus rien ne bouge (rendu hors écran, Réglages).
    func settle() {
        var t = now
        var n = 0
        while needsFrames, n < 600 { t += 1.0 / 60; tick(now: t); n += 1 }
    }

    // MARK: - Cadence

    /// Besoin d'une image de plus ? Sinon la vue peut suspendre le lien d'affichage.
    var needsFrames: Bool {
        switch phase {
        case .closed: return false
        case .opening, .closing: return true
        case .open: break
        }
        if pendingRing != nil || !centerGlow.settled { return true }
        if halo.contains(where: { !$0.settled }) { return true }
        if rings.contains(where: { !$0.deploy.settled || $0.halo.contains { !$0.settled } }) { return true }
        if now - labelChangedAt < Geometry.labelDuration { return true }
        return false
    }

    func tick(now: Double) {
        let dt = min(0.1, max(0, now - lastTick))
        lastTick = now
        self.now = now

        switch phase {
        case .opening(let t0) where now - t0 >= Geometry.openDuration:
            phase = .open
        case .closing(let t0) where now - t0 >= Geometry.closeDuration:
            phase = .closed
            frame += 1
            onClosed?()
            return
        default:
            break
        }

        for i in halo.indices { halo[i].step(dt: dt) }
        centerGlow.step(dt: dt)
        for r in rings.indices {
            rings[r].deploy.step(dt: dt)
            for i in rings[r].halo.indices { rings[r].halo[i].step(dt: dt) }
        }

        // Les anneaux repliés disparaissent, du plus profond au moins profond.
        var changed = false
        while let last = rings.last, last.deploy.target == 0, last.deploy.value == 0 {
            rings.removeLast()
            changed = true
        }
        if let p = pendingRing {
            if rings.count == p.level - 1 {
                pushRing(level: p.level, parent: p.parent)
                pendingRing = nil
                changed = true
            } else if rings.count < p.level - 1 {
                pendingRing = nil // son parent a disparu
            }
        }
        if changed { refreshHaloTargets() }
        frame += 1
    }

    private func wake() { onWake?() }

    /// Voile, échelles et opacité selon la phase.
    var visual: Visual {
        var v = Visual(veil: Geometry.veilOpacity)
        switch phase {
        case .closed:
            v.veil = 0; v.alpha = 0
        case .opening(let t0):
            let u = Easing.outCubic((now - t0) / Geometry.discOpenDuration)
            v.veil *= u
            v.discScale = 0.9 + 0.1 * u
            v.alpha = u
        case .open:
            break
        case .closing(let t0):
            let u = Easing.outCubic((now - t0) / Geometry.closeDuration)
            v.veil *= 1 - u
            v.wheelScale = 1 - 0.06 * u
            v.alpha = 1 - u
        }
        return v
    }

    // MARK: - Souris

    func pointerMoved(to p: CGPoint) {
        guard acceptsInput else { return }
        if Geometry.distance(p, center) > Geometry.centerRadius { pointerLeftCenter = true }
        let t = hitTest(p)
        setHovered(t)
        // Le survol d'un dossier déploie son anneau ; le survol d'une autre place du même niveau le replie.
        if case .item(let l, let i)? = t, let place = item(.item(level: l, index: i)) {
            if place.kind == .folder, l < WheelConfig.maxDepth {
                requestRing(level: l + 1, parent: i)
            } else {
                foldRings(from: l + 1)
            }
        }
    }

    func click(at p: CGPoint) {
        guard acceptsInput else { return }
        if let t = hitTest(p) {
            choose(t)
        } else if Geometry.distance(p, center) > currentOuterRadius {
            close()
        }
    }

    /// Clic du milieu maintenu puis relâché : choisit la place sous le pointeur.
    func middleReleased(at p: CGPoint) {
        guard acceptsInput, pointerLeftCenter, let t = hitTest(p), t != .center else { return }
        if let place = item(t), place.kind == .folder { return } // le laisse ouvert
        choose(t)
    }

    /// Rayon courant d'un anneau : se déploie du bord du niveau précédent à son bord final.
    func ringRadius(_ ring: Ring) -> CGFloat {
        let from = Geometry.outerRadius(level: ring.level - 1)
        let to = Geometry.outerRadius(level: ring.level)
        return from + (to - from) * CGFloat(ring.deploy.value)
    }

    /// Bord extérieur de tout ce qui est dessiné en ce moment.
    var currentOuterRadius: CGFloat {
        rings.reduce(Geometry.discRadius) { max($0, ringRadius($1)) }
    }

    func hitTest(_ p: CGPoint) -> Target? {
        if Geometry.distance(p, center) <= Geometry.centerRadius { return .center }
        for i in places.indices where Geometry.distance(p, position(level: 0, index: i, lifted: false)) <= Geometry.haloRadius {
            return .item(level: 0, index: i)
        }
        for ring in rings where ring.deploy.value > 0.5 {
            for k in ring.items.indices
            where Geometry.distance(p, finalPosition(level: ring.level, index: k, lifted: false)) <= Geometry.haloRadius {
                return .item(level: ring.level, index: k)
            }
        }
        return nil
    }

    // MARK: - Clavier

    func key(_ event: NSEvent) {
        guard acceptsInput else { return }
        let code = Int(event.keyCode)
        let shift = event.modifierFlags.contains(.shift)
        let level = activeLevel
        if let n = Self.digitKeys[code] {
            if n < items(atLevel: level).count { choose(.item(level: level, index: n)) }
            return
        }
        switch code {
        case 53: // Échap
            if level > 0 { foldRings(from: level) } else { close() }
        case 51: // Retour arrière
            if level > 0 { foldRings(from: level) }
        case 36, 76, 49: // Entrée, Entrée du pavé, Espace
            if let h = hovered { choose(h) } else if level > 0 { foldRings(from: level) } else { close() }
        case 48: // Tab
            move(shift ? -1 : 1)
        case 124, 125: // → ↓
            move(1)
        case 123, 126: // ← ↑
            move(-1)
        default:
            break
        }
    }

    /// Rangée du haut par touche physique (juste en AZERTY) et pavé numérique.
    static let digitKeys: [Int: Int] = [
        18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7,
        83: 0, 84: 1, 85: 2, 86: 3, 87: 4, 88: 5, 89: 6, 91: 7,
    ]

    private func move(_ delta: Int) {
        let level = activeLevel
        let n = items(atLevel: level).count
        guard n > 0 else { return }
        var cur = -1
        if case .item(let l, let i) = hovered, l == level { cur = i }
        let next = cur < 0 ? (delta > 0 ? 0 : n - 1) : (cur + delta + n) % n
        setHovered(.item(level: level, index: next))
    }

    // MARK: - Choix

    func choose(_ t: Target) {
        guard acceptsInput else { return }
        switch t {
        case .center:
            close()
        case .item(let l, let i):
            guard let place = item(t) else { return }
            switch place.kind {
            case .folder:
                setHovered(t)
                if l < WheelConfig.maxDepth { requestRing(level: l + 1, parent: i) }
            case .empty:
                onEmptyChosen?(folderPath(toLevel: l), i)
                close()
            default:
                onLaunch?(place)
                close()
            }
        }
    }

    /// Chemin des dossiers (index à chaque niveau) qui mènent au niveau `level`.
    private func folderPath(toLevel level: Int) -> [Int] {
        rings.prefix(level).map { $0.parent }
    }

    // MARK: - Survol et anneaux

    private func setHovered(_ t: Target?) {
        guard t != hovered else { return }
        hovered = t
        refreshHaloTargets()
        setLabel(labelText(for: t))
        wake()
    }

    /// Un item garde son halo s'il est survolé ou si son anneau est ouvert (ou en attente).
    private func refreshHaloTargets() {
        func keepsRing(level: Int, index: Int) -> Bool {
            if let p = pendingRing, p.level == level + 1, p.parent == index { return true }
            return rings.contains { $0.level == level + 1 && $0.parent == index && $0.deploy.target == 1 }
        }
        for i in places.indices {
            halo[i].target = (hovered == .item(level: 0, index: i) || keepsRing(level: 0, index: i)) ? 1 : 0
        }
        for r in rings.indices {
            let level = rings[r].level
            for i in rings[r].halo.indices {
                rings[r].halo[i].target = (hovered == .item(level: level, index: i) || keepsRing(level: level, index: i)) ? 1 : 0
            }
        }
        centerGlow.target = hovered == .center ? 1 : 0
    }

    private func pushRing(level: Int, parent: Int) {
        let parentItems = items(atLevel: level - 1)
        guard parentItems.indices.contains(parent), parentItems[parent].kind == .folder else { return }
        let kids = parentItems[parent].children
        var ring = Ring(level: level, parent: parent, parentAngle: angle(level: level - 1, index: parent),
                        items: kids.isEmpty ? [.empty] : kids)
        ring.deploy.target = 1
        rings.append(ring)
    }

    /// Ouvre l'anneau `level` sous le dossier `parent` ; replie d'abord ce qui doit l'être.
    private func requestRing(level: Int, parent: Int) {
        if let existing = rings.firstIndex(where: { $0.level == level }) {
            if rings[existing].parent == parent {
                // Même dossier : on annule un repli en cours, et on replie ce qui est plus profond.
                rings[existing].deploy.target = 1
                for r in rings.indices where rings[r].level > level { rings[r].deploy.target = 0 }
                if let p = pendingRing, p.level > level { pendingRing = nil }
            } else {
                for r in rings.indices where rings[r].level >= level { rings[r].deploy.target = 0 }
                pendingRing = (level, parent)
            }
        } else if rings.count == level - 1 {
            pushRing(level: level, parent: parent)
            pendingRing = nil
        } else {
            pendingRing = (level, parent)
        }
        dropStaleHover()
        refreshHaloTargets()
        wake()
    }

    /// Replie les anneaux de niveau `level` et plus profonds.
    private func foldRings(from level: Int) {
        var changed = false
        for r in rings.indices where rings[r].level >= level && rings[r].deploy.target != 0 {
            rings[r].deploy.target = 0
            changed = true
        }
        if let p = pendingRing, p.level >= level { pendingRing = nil; changed = true }
        guard changed else { return }
        dropStaleHover()
        refreshHaloTargets()
        wake()
    }

    /// Un survol dans un anneau qui se replie ne vaut plus.
    private func dropStaleHover() {
        if case .item(let l, _) = hovered, l > 0,
           let ring = rings.first(where: { $0.level == l }), ring.deploy.target == 0 {
            setHovered(nil)
        }
    }

    private func labelText(for t: Target?) -> String {
        switch t {
        case .none: return ""
        case .center: return "Fermer"
        case .item: return item(t!)?.label ?? ""
        }
    }

    private func setLabel(_ text: String) {
        guard text != label else { return }
        previousLabel = label
        label = text
        labelChangedAt = now
    }

    // MARK: - Positions (partagées avec la vue)

    /// Progression d'apparition de l'icône `i` de la roue à l'ouverture (0…1).
    func iconProgress(_ i: Int) -> Double {
        guard case .opening(let t0) = phase else { return 1 }
        let start = t0 + Double(i) * Geometry.iconStagger
        return Easing.clamp01((now - start) / Geometry.iconDuration)
    }

    /// Angle final d'un item.
    func angle(level: Int, index: Int) -> CGFloat {
        if level == 0 { return Geometry.angle(ofPlace: index) }
        guard rings.indices.contains(level - 1) else { return 0 }
        let ring = rings[level - 1]
        let n = ring.items.count
        return ring.parentAngle + (CGFloat(index) - CGFloat(n - 1) / 2) * 45 * .pi / 180
    }

    func haloValue(level: Int, index: Int) -> Double {
        if level == 0 { return halo[index].value }
        guard rings.indices.contains(level - 1) else { return 0 }
        return rings[level - 1].halo[index].value
    }

    /// Éventail : les places du milieu partent d'abord.
    func itemProgress(level: Int, index: Int) -> Double {
        guard level > 0, rings.indices.contains(level - 1) else { return 1 }
        let ring = rings[level - 1]
        let n = ring.items.count
        guard n > 1 else { return ring.deploy.value }
        let mid = Double(n - 1) / 2
        let delay = 0.35 * abs(Double(index) - mid) / mid
        return Easing.clamp01((ring.deploy.value - delay) / (1 - delay))
    }

    /// Position d'arrivée d'un item (sans animation).
    func finalPosition(level: Int, index: Int, lifted: Bool) -> CGPoint {
        var r = Geometry.iconRadius(level: level)
        if lifted { r += Geometry.hoverLift * CGFloat(haloValue(level: level, index: index)) }
        return Geometry.point(center: center, angle: angle(level: level, index: index), radius: r)
    }

    /// Position courante d'un item : à l'ouverture, les icônes de la roue sortent du centre en tournant ;
    /// celles d'un anneau tournent de la place du dossier à la leur, en s'éloignant.
    func position(level: Int, index: Int, lifted: Bool) -> CGPoint {
        let lift = lifted ? Geometry.hoverLift * CGFloat(haloValue(level: level, index: index)) : 0
        if level == 0 {
            let p = iconProgress(index)
            let r = Geometry.iconRadius * (0.45 + 0.55 * Easing.outBack(p)) + lift
            let a = Geometry.angle(ofPlace: index) - Geometry.openingSpin * CGFloat(1 - Easing.outCubic(p))
            return Geometry.point(center: center, angle: a, radius: r)
        }
        guard rings.indices.contains(level - 1) else { return center }
        let ring = rings[level - 1]
        let t = CGFloat(Easing.outCubic(itemProgress(level: level, index: index)))
        let a = Easing.lerp(ring.parentAngle, angle(level: level, index: index), t)
        let r = Easing.lerp(Geometry.iconRadius(level: level - 1), Geometry.iconRadius(level: level), t) + lift
        return Geometry.point(center: center, angle: a, radius: r)
    }
}
