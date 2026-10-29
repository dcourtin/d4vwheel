import Foundation

/// Une place de la roue, telle qu'écrite dans le fichier de configuration.
enum Entry: Equatable {
    /// `app:ID` — identifiant de bundle (`com.apple.Safari`), nom (`Safari`) ou chemin (`/Applications/X.app`).
    case app(String)
    /// `url:…` — ouvre un lien ou un schéma d'URL.
    case url(String)
    /// `sh:…` — exécute une commande dans zsh.
    case shell(String)
    /// `raccourci:NOM` — lance un raccourci de l'app Raccourcis.
    case shortcut(String)
    /// `action:ID:CLÉ` — une action du catalogue pour l'appli ID (ex. `action:com.apple.Notes:nouvelle`).
    case action(app: String, key: String)
    /// `entree:ID` — une entrée proposée par une appli (fichier JSON dans le dossier des propositions).
    case proposal(String)
    /// `dossier:NOM` suivi de ses places en retrait.
    case folder(name: String, children: [Entry])
    /// `-`
    case empty
    /// Ligne gardée telle quelle (ex. `action:` et `entree:` du format Linux, pas encore portés).
    case unsupported(String)

    var isEmpty: Bool { if case .empty = self { return true } else { return false } }
    var isFolder: Bool { if case .folder = self { return true } else { return false } }

    static func parse(_ raw: String) -> Entry {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line == "-" { return .empty }
        func value(after prefix: String) -> String? {
            guard line.lowercased().hasPrefix(prefix) else { return nil }
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        if let v = value(after: "app:") { return .app(v) }
        if let v = value(after: "url:") { return .url(v) }
        if let v = value(after: "sh:") { return .shell(v) }
        if let v = value(after: "raccourci:") { return .shortcut(v) }
        if let v = value(after: "action:") {
            let parts = v.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty { return .action(app: parts[0], key: parts[1]) }
            return .unsupported(line)
        }
        if let v = value(after: "entree:"), Proposals.isValidID(v) { return .proposal(v) }
        if let v = value(after: "dossier:") { return .folder(name: v.isEmpty ? "Dossier" : v, children: []) }
        return .unsupported(line)
    }

    var serialized: String {
        switch self {
        case .app(let v): return "app:\(v)"
        case .url(let v): return "url:\(v)"
        case .shell(let v): return "sh:\(v)"
        case .shortcut(let v): return "raccourci:\(v)"
        case .action(let app, let key): return "action:\(app):\(key)"
        case .proposal(let id): return "entree:\(id)"
        case .folder(let name, _): return "dossier:\(name)"
        case .empty: return "-"
        case .unsupported(let raw): return raw
        }
    }
}

/// Parcours de l'arbre des places : un chemin est la suite des index de dossiers depuis la roue.
enum EntryTree {
    static func children(at path: [Int], in places: [Entry]) -> [Entry]? {
        var current = places
        for i in path {
            guard current.indices.contains(i), case .folder(_, let kids) = current[i] else { return nil }
            current = kids
        }
        return current
    }

    static func setChildren(at path: [Int], to kids: [Entry], in places: [Entry]) -> [Entry] {
        guard let i = path.first else { return kids }
        var out = places
        guard out.indices.contains(i), case .folder(let name, let sub) = out[i] else { return out }
        out[i] = .folder(name: name, children: setChildren(at: Array(path.dropFirst()), to: kids, in: sub))
        return out
    }

    /// Profondeur des dossiers : 0 sans dossier, 1 avec un dossier, 2 avec un dossier dans un dossier.
    static func depth(of places: [Entry]) -> Int {
        places.reduce(0) { acc, e in
            if case .folder(_, let kids) = e { return max(acc, 1 + depth(of: kids)) }
            return acc
        }
    }

    /// Au plus 8 places par niveau ; un dossier trop profond devient une ligne non prise en charge.
    static func normalize(_ places: [Entry], depth: Int) -> [Entry] {
        var out = Array(places.prefix(WheelConfig.placeCount))
        if depth == 0 { while out.count < WheelConfig.placeCount { out.append(.empty) } }
        return out.map { e in
            guard case .folder(let name, let kids) = e else { return e }
            if depth >= WheelConfig.maxDepth { return .unsupported(e.serialized) }
            return .folder(name: name, children: normalize(kids, depth: depth + 1))
        }
    }
}

/// Le contenu de la roue : toujours 8 places, du haut dans le sens horaire.
struct WheelConfig: Equatable {
    static let placeCount = 8
    /// Niveaux de dossiers : 2 = un dossier peut en contenir un autre (roue, 2e anneau, 3e anneau).
    static let maxDepth = 2
    var places: [Entry]

    init(places: [Entry]) {
        self.places = EntryTree.normalize(places, depth: 0)
    }

    var depth: Int { EntryTree.depth(of: places) }
    var hasFolder: Bool { depth > 0 }

    /// Une place par ligne ; lignes vides et `#` ignorées ; les places d'un dossier suivent sa ligne, en retrait
    /// (et celles d'un dossier dans un dossier, plus en retrait encore).
    static func parse(_ text: String) -> WheelConfig {
        var places: [Entry] = []
        // Dossiers ouverts par le retrait ; `path` nil pour un dossier trop profond (ses lignes sont ignorées).
        var open: [(indent: Int, path: [Int]?)] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = rawLine.prefix { $0 == " " || $0 == "\t" }.count
            while let top = open.last, indent <= top.indent { open.removeLast() }
            let parentPath: [Int]? = open.isEmpty ? [] : open[open.count - 1].path
            guard let path = parentPath else { continue }
            guard var siblings = EntryTree.children(at: path, in: places), siblings.count < placeCount else { continue }
            var entry = Entry.parse(trimmed)
            let tooDeep = entry.isFolder && path.count >= maxDepth
            if tooDeep { entry = .unsupported(trimmed) }
            siblings.append(entry)
            places = EntryTree.setChildren(at: path, to: siblings, in: places)
            if entry.isFolder { open.append((indent, path + [siblings.count - 1])) }
            else if tooDeep { open.append((indent, nil)) }
        }
        return WheelConfig(places: places)
    }

    func serialize() -> String {
        var lines: [String] = [
            "# d4vWheel — une place par ligne, depuis le haut, dans le sens horaire.",
            "# app:ID (bundle, nom ou chemin) · action:ID:CLÉ · entree:ID · url:… · sh:… · raccourci:NOM",
            "# dossier:NOM (ses places suivent, en retrait) · - (vide)",
            "",
        ]
        func write(_ entries: [Entry], depth: Int) {
            var kept = entries
            if depth > 0 { while let last = kept.last, last.isEmpty { kept.removeLast() } }
            for entry in kept {
                lines.append(String(repeating: "  ", count: depth) + entry.serialized)
                if case .folder(_, let children) = entry { write(children, depth: depth + 1) }
            }
        }
        write(places, depth: 0)
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Où vit le fichier, et quoi montrer quand il n'existe pas.
enum ConfigStore {
    enum Source { case file(URL), dock, fallback }

    private static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }
    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Le dossier de l'appli dans Application Support : `d4vWheel`, ou `Roue` (ancien nom) s'il existe encore seul.
    static var supportDirectory: URL {
        let current = support.appendingPathComponent("d4vWheel")
        let legacy = support.appendingPathComponent("Roue")
        if !FileManager.default.fileExists(atPath: current.path), FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        return current
    }

    static var preferredURL: URL { support.appendingPathComponent("d4vWheel/wheel") }

    /// Emplacements plus anciens, encore lus : `~/.config/d4vwheel/wheel`, et ceux d'avant le renommage (Roue).
    static var legacyURLs: [URL] {
        [home.appendingPathComponent(".config/d4vwheel/wheel"),
         support.appendingPathComponent("Roue/roue"),
         home.appendingPathComponent(".config/roue/roue")]
    }

    /// Le premier fichier existant, sinon l'emplacement préféré.
    static var fileURL: URL {
        for url in [preferredURL] + legacyURLs where FileManager.default.fileExists(atPath: url.path) { return url }
        return preferredURL
    }

    /// Relu à chaque ouverture : aucun service à relancer.
    static func load() -> (config: WheelConfig, source: Source) {
        let url = fileURL
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return (WheelConfig.parse(text), .file(url))
        }
        if let dock = dockFavorites(), !dock.isEmpty {
            return (WheelConfig(places: dock), .dock)
        }
        return (WheelConfig(places: fallbackApps()), .fallback)
    }

    /// Écrit le contenu courant (favoris du Dock ou sélection) si le fichier manque, et renvoie son URL.
    @discardableResult
    static func createFileIfMissing() -> URL {
        let url = fileURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        let (config, _) = load()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? config.serialize().write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Les favoris du Dock (`persistent-apps` de com.apple.dock).
    static func dockFavorites() -> [Entry]? {
        guard let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] else {
            return nil
        }
        let ignored: Set<String> = ["com.apple.apps.launcher"]
        var ids: [String] = []
        for tile in tiles {
            guard let data = tile["tile-data"] as? [String: Any] else { continue }
            if let id = data["bundle-identifier"] as? String, !id.isEmpty {
                if ignored.contains(id) { continue }
                ids.append(id)
            } else if let file = data["file-data"] as? [String: Any], let s = file["_CFURLString"] as? String,
                      let u = URL(string: s), u.pathExtension == "app" {
                ids.append(u.path)
            }
            if ids.count == WheelConfig.placeCount { break }
        }
        return ids.map { .app($0) }
    }

    /// Sélection d'applis présentes quand ni fichier ni Dock ne donnent rien.
    static func fallbackApps() -> [Entry] {
        let candidates = [
            "com.apple.finder", "com.apple.Safari", "com.apple.Terminal", "com.apple.Notes",
            "com.apple.mail", "com.apple.MobileSMS", "com.apple.iCal", "com.apple.systempreferences",
        ]
        return candidates.filter { AppResolver.url(for: $0) != nil }.map { .app($0) }
    }
}
