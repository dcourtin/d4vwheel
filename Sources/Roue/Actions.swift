import AppKit

/// Une action d'application : l'équivalent macOS des `[Desktop Action]` du format Linux.
/// Le catalogue est fixe ; `action:ID:CLÉ` dans le fichier y renvoie.
struct AppAction: Identifiable, Equatable {
    enum Kind: Equatable {
        case appleScript(String)
        case url(String)
        case shell(String)
    }

    /// Identifiant de bundle de l'appli, ou `systeme` pour les actions du système.
    let app: String
    let key: String
    let name: String
    let kind: Kind
    var id: String { "\(app):\(key)" }

    static let systemID = "systeme"
}

enum ActionCatalog {
    static let all: [AppAction] = [
        AppAction(app: "com.apple.Notes", key: "nouvelle", name: "Nouvelle note", kind: .appleScript("""
            tell application "Notes"
                activate
                show (make new note with properties {name:"Nouvelle note"})
            end tell
            """)),
        AppAction(app: "com.apple.mail", key: "nouveau", name: "Nouveau message", kind: .appleScript("""
            tell application "Mail"
                activate
                make new outgoing message with properties {visible:true}
            end tell
            """)),
        AppAction(app: "com.apple.Safari", key: "fenetre", name: "Nouvelle fenêtre", kind: .appleScript("""
            tell application "Safari"
                make new document
                activate
            end tell
            """)),
        AppAction(app: "com.apple.Terminal", key: "fenetre", name: "Nouvelle fenêtre", kind: .appleScript("""
            tell application "Terminal"
                do script ""
                activate
            end tell
            """)),
        AppAction(app: "com.apple.finder", key: "fenetre", name: "Nouvelle fenêtre", kind: .appleScript("""
            tell application "Finder"
                make new Finder window
                activate
            end tell
            """)),
        AppAction(app: "com.apple.finder", key: "perso", name: "Dossier personnel", kind: .shell("open ~")),
        AppAction(app: "com.apple.finder", key: "telechargements", name: "Téléchargements", kind: .shell("open ~/Downloads")),
        AppAction(app: "com.apple.finder", key: "corbeille", name: "Vider la corbeille", kind: .appleScript("""
            tell application "Finder" to empty trash
            """)),
        AppAction(app: "com.apple.TextEdit", key: "nouveau", name: "Nouveau document", kind: .appleScript("""
            tell application "TextEdit"
                make new document
                activate
            end tell
            """)),
        AppAction(app: "com.apple.reminders", key: "nouveau", name: "Nouveau rappel", kind: .appleScript("""
            tell application "Reminders"
                activate
                make new reminder with properties {name:"Nouveau rappel"}
            end tell
            """)),
        AppAction(app: "com.apple.MobileSMS", key: "nouveau", name: "Nouveau message", kind: .url("sms:")),
        AppAction(app: "com.apple.FaceTime", key: "appel", name: "Nouvel appel", kind: .url("facetime:")),
        AppAction(app: "com.apple.Music", key: "lecture", name: "Lecture / pause", kind: .appleScript("""
            tell application "Music" to playpause
            """)),
        AppAction(app: "com.apple.Music", key: "suivant", name: "Morceau suivant", kind: .appleScript("""
            tell application "Music" to next track
            """)),
        AppAction(app: "com.apple.systempreferences", key: "accessibilite", name: "Accessibilité",
                  kind: .url("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")),
        AppAction(app: "com.apple.systempreferences", key: "bluetooth", name: "Bluetooth",
                  kind: .url("x-apple.systempreferences:com.apple.BluetoothSettings")),
        AppAction(app: "com.apple.systempreferences", key: "son", name: "Son",
                  kind: .url("x-apple.systempreferences:com.apple.Sound-Settings.extension")),
        AppAction(app: AppAction.systemID, key: "capture", name: "Capture d'écran", kind: .shell("screencapture -ic")),
        AppAction(app: AppAction.systemID, key: "ecran-veille", name: "Écran en veille", kind: .shell("pmset displaysleepnow")),
        AppAction(app: AppAction.systemID, key: "verrouiller", name: "Verrouiller la session",
                  kind: .shell("'/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession' -suspend")),
    ]

    static func action(app: String, key: String) -> AppAction? {
        all.first { $0.app == app && $0.key == key }
    }

    /// Les actions dont l'appli est installée (celles du système toujours).
    static func available() -> [AppAction] {
        all.filter { $0.app == AppAction.systemID || AppResolver.url(for: $0.app) != nil }
    }

    static func appName(_ app: String) -> String {
        if app == AppAction.systemID { return "Système" }
        guard let url = AppResolver.url(for: app) else { return app }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return name
    }

    static func appIcon(_ app: String) -> NSImage? {
        if app == AppAction.systemID {
            return NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        }
        guard let url = AppResolver.url(for: app) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func run(_ action: AppAction) {
        switch action.kind {
        case .appleScript(let source):
            // osascript plutôt que NSAppleScript : ne bloque pas l'interface ; l'autorisation Automation est demandée à Roue.
            Launcher.run("/usr/bin/osascript", ["-e", source])
        case .url(let s):
            if let u = URL(string: s) { NSWorkspace.shared.open(u) }
        case .shell(let cmd):
            Launcher.run("/bin/zsh", ["-lc", cmd])
        }
    }
}
