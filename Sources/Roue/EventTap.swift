import AppKit
import ApplicationServices

/// Écoute le clic du milieu partout (CGEventTap, autorisation Accessibilité) :
/// sur le bureau, ou avec un modificateur n'importe où, il ouvre la roue et n'est pas transmis dessous.
/// Le geste continu (maintenir, glisser, relâcher) est relayé au modèle tant que le bouton est tenu.
final class MiddleClickTap {
    enum Modifier: String, CaseIterable, Identifiable {
        case none, option, control, command, shift
        var id: String { rawValue }
        var name: String {
            switch self {
            case .none: return "Aucun (désactivé)"
            case .option: return "Option ⌥"
            case .control: return "Contrôle ⌃"
            case .command: return "Commande ⌘"
            case .shift: return "Majuscule ⇧"
            }
        }
        var flag: CGEventFlags? {
            switch self {
            case .none: return nil
            case .option: return .maskAlternate
            case .control: return .maskControl
            case .command: return .maskCommand
            case .shift: return .maskShift
            }
        }
    }

    /// Ouvrir au clic du milieu sur le bureau ?
    var onDesktop = true
    /// Ouvrir avec ce modificateur + clic du milieu, n'importe où.
    var modifier: Modifier = .option
    /// La roue est-elle ouverte ? (alors le clic lui revient par le panneau)
    var isWheelOpen: () -> Bool = { false }
    /// Ouvre la roue ; renvoie vrai si elle s'est ouverte (le geste continue alors ici).
    var onOpen: () -> Bool = { false }
    var onDrag: (CGPoint) -> Void = { _ in }
    var onRelease: (CGPoint) -> Void = { _ in }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gestureActive = false

    var isRunning: Bool { tap != nil }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Demande l'autorisation Accessibilité (ouvre la fenêtre du système la première fois).
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(u)
        }
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask = (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDragged.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: { _, type, event, userInfo in
                                               guard let userInfo else { return Unmanaged.passUnretained(event) }
                                               let me = Unmanaged<MiddleClickTap>.fromOpaque(userInfo).takeUnretainedValue()
                                               return me.handle(type: type, event: event)
                                           }, userInfo: userInfo) else {
            return false
        }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        source = nil
        tap = nil
        gestureActive = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .otherMouseDown:
            guard event.getIntegerValueField(.mouseEventButtonNumber) == 2, !isWheelOpen() else {
                return Unmanaged.passUnretained(event)
            }
            let withModifier = modifier.flag.map { event.flags.contains($0) } ?? false
            let wanted = withModifier || (onDesktop && Self.isDesktop(at: event.location))
            guard wanted, onOpen() else { return Unmanaged.passUnretained(event) }
            gestureActive = true
            return nil
        case .otherMouseDragged:
            guard gestureActive else { return Unmanaged.passUnretained(event) }
            onDrag(event.location)
            return nil
        case .otherMouseUp:
            guard gestureActive else { return Unmanaged.passUnretained(event) }
            gestureActive = false
            onRelease(event.location)
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// « Sur le bureau » : aucune fenêtre visible d'une appli sous le pointeur (le fond d'écran et les icônes du bureau
    /// ne comptent pas, ni nos propres fenêtres).
    static func isDesktop(at point: CGPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        let ignoredOwners: Set<String> = ["Window Server", "WindowManager", "Wallpaper", "Notification Center", "Control Center"]
        for w in list {
            if (w[kCGWindowOwnerPID as String] as? Int32) == me { continue }
            if let alpha = w[kCGWindowAlpha as String] as? Double, alpha < 0.01 { continue }
            if let owner = w[kCGWindowOwnerName as String] as? String, ignoredOwners.contains(owner) { continue }
            guard let layer = w[kCGWindowLayer as String] as? Int, layer >= 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let wd = b["Width"], let ht = b["Height"] else { continue }
            if CGRect(x: x, y: y, width: wd, height: ht).contains(point) { return false }
        }
        return true
    }
}
