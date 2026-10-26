import AppKit
import ApplicationServices

/// Ramène la fenêtre d'une appli déjà ouverte : la suivante si la sienne est déjà devant, une fenêtre réduite revient.
/// Demande l'autorisation Accessibilité ; sans elle, l'appli est seulement activée.
enum WindowCycler {
    /// Renvoie vrai si l'appli tournait déjà et a été ramenée.
    static func bringForward(appAt url: URL) -> Bool {
        let target = url.standardizedFileURL.path
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.standardizedFileURL.path == target
        }) else { return false }

        let isFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        if AXIsProcessTrusted() {
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            let windows = standardWindows(of: ax)
            if !windows.isEmpty {
                let minimized = windows.filter { isMinimized($0) }
                if isFront {
                    // Déjà devant : la fenêtre suivante (une réduite d'abord s'il y en a).
                    let focused = focusedWindow(of: ax)
                    let ordered = windows
                    let current = ordered.firstIndex { w in focused.map { CFEqual($0, w) } ?? false } ?? -1
                    let next = minimized.first ?? ordered[(current + 1) % ordered.count]
                    raise(next)
                } else if minimized.count == windows.count, let first = minimized.first {
                    raise(first) // tout est réduit : on en ramène une
                }
            }
        }
        if app.isHidden { app.unhide() }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
        return true
    }

    private static func standardWindows(of app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list.filter { w in
            var sub: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &sub)
            return (sub as? String) == kAXStandardWindowSubrole
        }
    }

    private static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success else { return nil }
        return (value as! AXUIElement?)
    }

    private static func isMinimized(_ w: AXUIElement) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &value)
        return (value as? Bool) ?? false
    }

    private static func raise(_ w: AXUIElement) {
        AXUIElementSetAttributeValue(w, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(w, kAXRaiseAction as CFString)
    }
}
