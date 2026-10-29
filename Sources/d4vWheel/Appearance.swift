import AppKit

/// Réglages d'apparence du fond de la roue, gardés dans les préférences de l'appli.
enum Appearance {
    struct MaterialChoice: Identifiable, Equatable {
        let id: String
        let name: String
        let material: NSVisualEffectView.Material
    }

    /// Les matériaux de flou du système, du plus léger au plus marqué.
    static let materials: [MaterialChoice] = [
        MaterialChoice(id: "menu", name: "Menu", material: .menu),
        MaterialChoice(id: "popover", name: "Fenêtre contextuelle", material: .popover),
        MaterialChoice(id: "sidebar", name: "Barre latérale", material: .sidebar),
        MaterialChoice(id: "underWindow", name: "Sous la fenêtre", material: .underWindowBackground),
        MaterialChoice(id: "fullScreen", name: "Plein écran", material: .fullScreenUI),
        MaterialChoice(id: "hud", name: "HUD", material: .hudWindow),
    ]

    static let defaultMaterialID = "popover"
    static let defaultTintOpacity = 0.42

    private static let materialKey = "fondMateriau"
    private static let tintKey = "fondOpacite"

    static var materialID: String {
        get { UserDefaults.standard.string(forKey: materialKey) ?? defaultMaterialID }
        set { UserDefaults.standard.set(newValue, forKey: materialKey) }
    }

    static var material: NSVisualEffectView.Material {
        materials.first { $0.id == materialID }?.material ?? .popover
    }

    /// Opacité de la couche de couleur posée sur le flou : 0 = flou pur, 1 = disque opaque.
    static var tintOpacity: Double {
        get {
            guard UserDefaults.standard.object(forKey: tintKey) != nil else { return defaultTintOpacity }
            return min(1, max(0, UserDefaults.standard.double(forKey: tintKey)))
        }
        set { UserDefaults.standard.set(newValue, forKey: tintKey) }
    }
}
