import AppKit
import Carbon.HIToolbox

/// Réglages des déclencheurs (raccourci clavier, clic du milieu), gardés dans les préférences.
enum Triggers {
    static let changed = Notification.Name("fr.odysseus.roue.declencheurs")

    private static let keyCodeKey = "raccourciCode"
    private static let modifiersKey = "raccourciModificateurs"
    private static let displayKey = "raccourciTexte"
    private static let desktopKey = "clicMilieuBureau"
    private static let modifierKey = "clicMilieuModificateur"

    struct HotKeySpec: Equatable {
        var keyCode: UInt32
        var modifiers: UInt32
        var display: String
        static let `default` = HotKeySpec(keyCode: GlobalHotKey.defaultKeyCode, modifiers: GlobalHotKey.defaultModifiers,
                                          display: GlobalHotKey.defaultDescription)
    }

    static var hotKey: HotKeySpec {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: keyCodeKey) != nil, let text = d.string(forKey: displayKey) else { return .default }
            return HotKeySpec(keyCode: UInt32(d.integer(forKey: keyCodeKey)), modifiers: UInt32(d.integer(forKey: modifiersKey)),
                              display: text)
        }
        set {
            let d = UserDefaults.standard
            d.set(Int(newValue.keyCode), forKey: keyCodeKey)
            d.set(Int(newValue.modifiers), forKey: modifiersKey)
            d.set(newValue.display, forKey: displayKey)
        }
    }

    static var middleClickOnDesktop: Bool {
        get { UserDefaults.standard.object(forKey: desktopKey) == nil ? true : UserDefaults.standard.bool(forKey: desktopKey) }
        set { UserDefaults.standard.set(newValue, forKey: desktopKey) }
    }

    static var middleClickModifier: MiddleClickTap.Modifier {
        get { MiddleClickTap.Modifier(rawValue: UserDefaults.standard.string(forKey: modifierKey) ?? "") ?? .option }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modifierKey) }
    }

    /// Le clic du milieu sert-il à quelque chose ?
    static var middleClickWanted: Bool { middleClickOnDesktop || middleClickModifier != .none }

    // MARK: Lecture d'un raccourci depuis un événement clavier

    /// Modificateurs Carbon d'un événement ; nil si aucun (un raccourci global sans modificateur gênerait la frappe),
    /// sauf pour une touche de fonction.
    static func spec(from event: NSEvent) -> HotKeySpec? {
        let f = event.modifierFlags
        var mods: UInt32 = 0
        if f.contains(.command) { mods |= UInt32(cmdKey) }
        if f.contains(.option) { mods |= UInt32(optionKey) }
        if f.contains(.control) { mods |= UInt32(controlKey) }
        if f.contains(.shift) { mods |= UInt32(shiftKey) }
        let code = Int(event.keyCode)
        let isFunctionKey = functionKeys[code] != nil
        guard mods != 0 || isFunctionKey else { return nil }
        guard let name = keyName(code: code, event: event) else { return nil }
        var text = ""
        if f.contains(.control) { text += "⌃" }
        if f.contains(.option) { text += "⌥" }
        if f.contains(.shift) { text += "⇧" }
        if f.contains(.command) { text += "⌘" }
        return HotKeySpec(keyCode: UInt32(code), modifiers: mods, display: text + name)
    }

    private static let functionKeys: [Int: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static let specialKeys: [Int: String] = [
        49: "␣", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]

    private static func keyName(code: Int, event: NSEvent) -> String? {
        if let f = functionKeys[code] { return f }
        if let s = specialKeys[code] { return s }
        guard let chars = event.charactersIgnoringModifiers, let c = chars.first, !c.isWhitespace else { return nil }
        return String(c).uppercased()
    }
}
