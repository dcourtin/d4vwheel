import AppKit

/// Une place résolue : ce qu'elle tient, son nom, son icône, son état.
struct Place {
    enum Kind { case app, command, folder, empty, unsupported }

    let entry: Entry
    let kind: Kind
    let name: String
    /// Ce qui suit le nom dans l'étiquette (« Commande », « Lien »…). Nil pour une appli.
    let subtitle: String?
    let icon: NSImage?
    /// Nom du symbole SF à dessiner quand il n'y a pas d'icône d'appli.
    let symbol: String?
    let appURL: URL?
    let isRunning: Bool
    /// Pour un dossier : ses places remplies, dans l'ordre.
    let children: [Place]

    static let empty = Place(entry: .empty, kind: .empty, name: "Vide", subtitle: "ouvrir la configuration",
                             icon: nil, symbol: nil, appURL: nil, isRunning: false, children: [])

    /// Texte de l'étiquette sous la roue.
    var label: String {
        switch kind {
        case .app: return name
        case .folder: return "\(name) · dossier"
        case .empty: return "Vide · ouvrir la configuration"
        case .command, .unsupported: return subtitle.map { "\(name) · \($0)" } ?? name
        }
    }

    var hasFolderChildren: Bool { kind == .folder && !children.isEmpty }
}

enum AppResolver {
    static let searchDirs: [String] = [
        NSHomeDirectory() + "/Applications",
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices",
    ]

    /// Identifiant de bundle, chemin, ou simple nom d'appli → URL du bundle.
    static func url(for spec: String) -> URL? {
        let s = spec.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("/") || s.hasPrefix("~") {
            let path = (s as NSString).expandingTildeInPath
            return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        if s.contains("."), let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: s) { return u }
        let name = s.hasSuffix(".app") ? s : s + ".app"
        for dir in searchDirs {
            let path = dir + "/" + name
            if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: s) { return u }
        return nil
    }

    static func isRunning(_ url: URL) -> Bool {
        let target = url.standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL.path == target }
    }

    static func resolve(_ config: WheelConfig) -> [Place] {
        config.places.map { resolve($0) }
    }

    static func resolve(_ entry: Entry) -> Place {
        switch entry {
        case .empty:
            return .empty
        case .app(let spec):
            if let url = url(for: spec) {
                var name = FileManager.default.displayName(atPath: url.path)
                if name.hasSuffix(".app") { name.removeLast(4) }
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                return Place(entry: entry, kind: .app, name: name, subtitle: nil, icon: icon, symbol: nil,
                             appURL: url, isRunning: isRunning(url), children: [])
            }
            return Place(entry: entry, kind: .unsupported, name: spec, subtitle: "introuvable", icon: nil,
                         symbol: "questionmark.app", appURL: nil, isRunning: false, children: [])
        case .url(let s):
            let name = URL(string: s)?.host ?? s
            return Place(entry: entry, kind: .command, name: name, subtitle: "Lien", icon: nil, symbol: "link",
                         appURL: nil, isRunning: false, children: [])
        case .shell(let cmd):
            let name = cmd.split(separator: " ").first.map(String.init) ?? cmd
            return Place(entry: entry, kind: .command, name: name, subtitle: "Commande", icon: nil, symbol: "terminal",
                         appURL: nil, isRunning: false, children: [])
        case .shortcut(let name):
            return Place(entry: entry, kind: .command, name: name, subtitle: "Raccourci", icon: nil, symbol: "square.2.layers.3d",
                         appURL: nil, isRunning: false, children: [])
        case .action(let app, let key):
            guard let action = ActionCatalog.action(app: app, key: key),
                  app == AppAction.systemID || url(for: app) != nil else {
                return Place(entry: entry, kind: .unsupported, name: "\(app):\(key)", subtitle: "action introuvable", icon: nil,
                             symbol: "questionmark.app", appURL: nil, isRunning: false, children: [])
            }
            let icon = app == AppAction.systemID ? nil : ActionCatalog.appIcon(app)
            return Place(entry: entry, kind: .command, name: action.name, subtitle: ActionCatalog.appName(app), icon: icon,
                         symbol: "macwindow", appURL: nil, isRunning: false, children: [])
        case .proposal(let id):
            guard let p = Proposals.load(id) else {
                return Place(entry: entry, kind: .unsupported, name: id, subtitle: "proposition introuvable", icon: nil,
                             symbol: "questionmark.circle", appURL: nil, isRunning: false, children: [])
            }
            let icon = p.icon()
            let isSymbol = icon?.isTemplate ?? true
            return Place(entry: entry, kind: .command, name: p.nom, subtitle: "Proposition", icon: isSymbol ? nil : icon,
                         symbol: (p.icone?.isEmpty == false && isSymbol) ? p.icone : "sparkles",
                         appURL: nil, isRunning: false, children: [])
        case .folder(let name, let children):
            let kids = children.filter { !$0.isEmpty }.map { resolve($0) }
            return Place(entry: entry, kind: .folder, name: name, subtitle: "dossier", icon: nil, symbol: nil,
                         appURL: nil, isRunning: false, children: kids)
        case .unsupported(let raw):
            return Place(entry: entry, kind: .unsupported, name: raw, subtitle: "non pris en charge", icon: nil,
                         symbol: "questionmark.circle", appURL: nil, isRunning: false, children: [])
        }
    }
}

/// Lance ce que tient une place. Appelé aussitôt au choix, avant l'animation de fermeture.
enum Launcher {
    static func launch(_ place: Place) {
        switch place.entry {
        case .app:
            guard let url = place.appURL else { return }
            if WindowCycler.bringForward(appAt: url) { return }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error { NSLog("Roue : impossible de lancer \(url.lastPathComponent) : \(error.localizedDescription)") }
            }
        case .url(let s):
            if let u = URL(string: s) { NSWorkspace.shared.open(u) }
        case .shell(let cmd):
            run("/bin/zsh", ["-lc", cmd])
        case .shortcut(let name):
            run("/usr/bin/shortcuts", ["run", name])
        case .action(let app, let key):
            if let a = ActionCatalog.action(app: app, key: key) { ActionCatalog.run(a) }
        case .proposal(let id):
            if let p = Proposals.load(id) { Proposals.run(p) }
        case .empty, .unsupported:
            openConfigFile()
        case .folder:
            break
        }
    }

    /// Ouvre le fichier de configuration dans l'éditeur par défaut, en le créant au besoin.
    static func openConfigFile() {
        let url = ConfigStore.createFileIfMissing()
        NSWorkspace.shared.open(url)
    }

    static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do { try p.run() } catch { NSLog("Roue : échec de \(path) \(args) : \(error)") }
    }
}
