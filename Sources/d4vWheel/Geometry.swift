import CoreGraphics
import Foundation

/// Toutes les valeurs de la spécification, en points logiques.
enum Geometry {
    static let discRadius: CGFloat = 148
    static let iconSize: CGFloat = 40
    static let iconRadius: CGFloat = 100
    static let haloRadius: CGFloat = 34
    static let centerRadius: CGFloat = 36
    static let ringIconRadius: CGFloat = 196
    static let ringOuterRadius: CGFloat = 242
    /// Chaque anneau supplémentaire est 96 pt plus loin (icônes) et 94 pt plus large (bord).
    static let ringIconStep: CGFloat = 96
    static let ringOuterStep: CGFloat = 94
    /// Rotation des icônes à l'ouverture (elles tournent dans le sens horaire jusqu'à leur place).
    static let openingSpin: CGFloat = 30 * .pi / 180
    static let hoverLift: CGFloat = 5
    static let folderCorner: CGFloat = 12
    static let miniIcon: CGFloat = 15
    static let miniGap: CGFloat = 3
    /// Légende du nom sous une tuile de dossier.
    static let captionFontSize: CGFloat = 10
    static let captionMaxWidth: CGFloat = 84
    static let captionHeight: CGFloat = 15
    static let captionGap: CGFloat = 4
    static let labelFontSize: CGFloat = 13.5
    static let labelMaxWidth: CGFloat = 360
    static let labelHeight: CGFloat = 26
    static let labelGap: CGFloat = 22
    static let screenMargin: CGFloat = 16
    static let veilOpacity: Double = 0.10

    /// Réglage d'accessibilité « Réduire les animations » : tout devient quasi instantané.
    static var motionReduced = false
    private static func d(_ seconds: Double) -> Double { motionReduced ? 0.001 : seconds }

    // Durées (secondes)
    static var openDuration: Double { d(0.220) }
    static var discOpenDuration: Double { d(0.180) }
    static var iconStagger: Double { d(0.010) }
    static var iconDuration: Double { d(0.150) }
    static let hoverTau = 0.050
    static let ringTau = 0.065
    static var labelDuration: Double { d(0.090) }
    static var closeDuration: Double { d(0.140) }

    /// Angle de la place `i` (0 = midi, sens horaire), en radians, repère y vers le bas.
    static func angle(ofPlace i: Int) -> CGFloat {
        (CGFloat(i) * 45 - 90) * .pi / 180
    }

    static func point(center: CGPoint, angle: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Rayon des icônes du niveau `level` (0 = la roue, 1 = premier anneau…).
    static func iconRadius(level: Int) -> CGFloat {
        iconRadius + ringIconStep * CGFloat(level)
    }

    /// Bord extérieur du niveau `level` (0 = le disque).
    static func outerRadius(level: Int) -> CGFloat {
        discRadius + ringOuterStep * CGFloat(level)
    }
}

enum Easing {
    static func clamp01(_ t: Double) -> Double { min(1, max(0, t)) }
    static func outCubic(_ t: Double) -> Double { 1 - pow(1 - clamp01(t), 3) }
    static func outBack(_ t: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        let x = clamp01(t)
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t))
    }
}

/// Suivi exponentiel d'une valeur vers sa cible (constante de temps `tau`).
struct Tracker {
    var value: Double
    var target: Double
    let tau: Double

    init(_ value: Double = 0, tau: Double) {
        self.value = value
        self.target = value
        self.tau = tau
    }

    var settled: Bool { value == target }

    mutating func step(dt: Double) {
        guard !settled else { return }
        if Geometry.motionReduced { value = target; return }
        value += (target - value) * (1 - exp(-dt / tau))
        if abs(target - value) < 0.0015 { value = target }
    }

    mutating func reset(_ v: Double) { value = v; target = v }
}
