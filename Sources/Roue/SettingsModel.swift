import AppKit
import Combine
import ServiceManagement

/// Un élément qu'on peut mettre dans la roue, proposé dans la liste des Réglages.
struct Candidate: Identifiable, Hashable {
    enum Group: String, CaseIterable {
        case proposals = "Propositions des applis", actions = "Actions des applis", shortcuts = "Raccourcis", apps = "Applications"
    }
    let id: String
    let group: Group
    let name: String
    let entry: Entry
    let icon: NSImage?
    let symbol: String?
    static func == (a: Candidate, b: Candidate) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum AppCatalog {
    /// Les raccourcis de l'app Raccourcis (lents à lister : chargés après les applis).
    static func shortcuts() async -> [Candidate] {
        await shortcutNames().map {
            Candidate(id: "raccourci:\($0)", group: .shortcuts, name: $0, entry: .shortcut($0), icon: nil, symbol: "square.2.layers.3d")
        }
    }

    /// Les actions du catalogue dont l'appli est installée.
    static func actions() -> [Candidate] {
        ActionCatalog.available().map { a in
            Candidate(id: "action:" + a.id, group: .actions, name: "\(a.name) · \(ActionCatalog.appName(a.app))",
                      entry: .action(app: a.app, key: a.key),
                      icon: a.app == AppAction.systemID ? nil : ActionCatalog.appIcon(a.app), symbol: "macwindow")
        }
    }

    /// Les entrées proposées par des applis (dossier des propositions).
    static func proposals() -> [Candidate] {
        Proposals.all().map { p in
            let icon = p.icon()
            let isSymbol = icon?.isTemplate ?? true
            return Candidate(id: "entree:" + p.id, group: .proposals, name: p.nom, entry: .proposal(p.id),
                             icon: isSymbol ? nil : icon, symbol: (isSymbol && p.icone?.isEmpty == false) ? p.icone : "sparkles")
        }
    }

    /// Toutes les applis des dossiers habituels.
    static func applications() async -> [Candidate] {
        let fm = FileManager.default
        var seen = Set<String>()
        var out: [Candidate] = []
        for dir in AppResolver.searchDirs {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names {
                let path = dir + "/" + name
                var paths = [path]
                // Un niveau de sous-dossiers dans /Applications (ex. « Utilitaires », suites).
                if !name.hasSuffix(".app"), dir == "/Applications", let sub = try? fm.contentsOfDirectory(atPath: path) {
                    paths = sub.map { path + "/" + $0 }
                }
                for p in paths where p.hasSuffix(".app") {
                    let url = URL(fileURLWithPath: p).standardizedFileURL
                    guard !seen.contains(url.path) else { continue }
                    seen.insert(url.path)
                    let bundleID = Bundle(url: url)?.bundleIdentifier
                    var display = fm.displayName(atPath: url.path)
                    if display.hasSuffix(".app") { display.removeLast(4) }
                    let spec = bundleID ?? url.path
                    out.append(Candidate(id: "app:" + url.path, group: .apps, name: display, entry: .app(spec),
                                         icon: NSWorkspace.shared.icon(forFile: url.path), symbol: nil))
                }
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func shortcutNames() async -> [String] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                p.arguments = ["list"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                do {
                    try p.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    let names = String(data: data, encoding: .utf8)?
                        .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty } ?? []
                    cont.resume(returning: names)
                } catch {
                    cont.resume(returning: [])
                }
            }
        }
    }
}

/// État de la fenêtre Réglages > Roue. Chaque changement est enregistré aussitôt.
@MainActor
final class SettingsModel: ObservableObject {
    @Published private(set) var config: WheelConfig
    /// Place choisie (dans la roue, ou dans le dossier ouvert).
    @Published var selected = 0
    /// Chemin du dossier dont on montre les huit places (index à chaque niveau) ; vide pour la roue.
    @Published private(set) var openPath: [Int] = []
    @Published var search = ""
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var loadingCandidates = true
    /// Saisie d'un nom de dossier en cours (création ou renommage).
    @Published var editingName: String?
    /// Apparence du fond, enregistrée aussitôt.
    @Published var materialID = Appearance.materialID { didSet { Appearance.materialID = materialID } }
    @Published var tintOpacity = Appearance.tintOpacity { didSet { Appearance.tintOpacity = tintOpacity } }

    init() {
        config = ConfigStore.load().config
    }

    func reload() {
        config = ConfigStore.load().config
        if EntryTree.children(at: openPath, in: config.places) == nil { openPath = [] }
    }

    func loadCandidates() {
        guard candidates.isEmpty else { return }
        Task { await loadCandidatesNow() }
    }

    func loadCandidatesNow() async {
        let apps = await AppCatalog.applications()
        candidates = AppCatalog.proposals() + AppCatalog.actions() + apps
        loadingCandidates = false
        let shortcuts = await AppCatalog.shortcuts()
        candidates = AppCatalog.proposals() + AppCatalog.actions() + shortcuts + apps
    }

    /// Relit les propositions (après un ajout par une appli).
    func refreshProposals() {
        candidates = AppCatalog.proposals() + candidates.filter { $0.group != .proposals }
    }

    /// Relit le fichier s'il a changé ailleurs (éditeur, ligne de commande).
    func reloadIfChanged() {
        let fresh = ConfigStore.load().config
        guard fresh != config else { return }
        config = fresh
        if EntryTree.children(at: openPath, in: config.places) == nil { openPath = [] }
    }

    // MARK: Déclencheurs et système

    @Published var hotKey = Triggers.hotKey { didSet { Triggers.hotKey = hotKey; notifyTriggers() } }
    @Published var middleClickOnDesktop = Triggers.middleClickOnDesktop {
        didSet { Triggers.middleClickOnDesktop = middleClickOnDesktop; notifyTriggers() }
    }
    @Published var middleClickModifier = Triggers.middleClickModifier {
        didSet { Triggers.middleClickModifier = middleClickModifier; notifyTriggers() }
    }
    @Published private(set) var accessibilityTrusted = MiddleClickTap.isTrusted
    @Published var launchAtLogin = LoginItem.isEnabled { didSet { loginItemError = LoginItem.set(launchAtLogin) } }
    @Published private(set) var loginItemError: String?

    private func notifyTriggers() {
        NotificationCenter.default.post(name: Triggers.changed, object: nil)
    }

    func refreshSystemState() {
        accessibilityTrusted = MiddleClickTap.isTrusted
        let enabled = LoginItem.isEnabled
        if enabled != launchAtLogin { launchAtLogin = enabled }
    }

    func requestAccessibility() {
        MiddleClickTap.requestTrust()
    }

    /// Un lien ou une commande saisi dans la fenêtre.
    func placeCustom(kind: CustomKind, text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        switch kind {
        case .url: place(.url(t))
        case .shell: place(.shell(t))
        }
    }

    enum CustomKind: String, CaseIterable, Identifiable {
        case url = "Lien", shell = "Commande"
        var id: String { rawValue }
    }

    // MARK: Lecture

    /// Les huit places du niveau affiché (roue ou dossier ouvert), toujours 8.
    var currentPlaces: [Entry] {
        var c = EntryTree.children(at: openPath, in: config.places) ?? config.places
        while c.count < WheelConfig.placeCount { c.append(.empty) }
        return c
    }

    var selectedEntry: Entry { currentPlaces[selected] }

    /// Le dossier ouvert, s'il y en a un.
    var openFolderEntry: Entry? {
        guard !openPath.isEmpty, let parent = EntryTree.children(at: Array(openPath.dropLast()), in: config.places),
              let last = openPath.last, parent.indices.contains(last) else { return nil }
        return parent[last]
    }

    /// Noms des dossiers ouverts, du premier au plus profond.
    var openFolderNames: [String] {
        var names: [String] = []
        var level = config.places
        for i in openPath {
            guard level.indices.contains(i), case .folder(let name, let kids) = level[i] else { break }
            names.append(name)
            level = kids
        }
        return names
    }

    /// Peut-on créer ou ouvrir un dossier à ce niveau ? (profondeur limitée)
    var canNestFolder: Bool { openPath.count < WheelConfig.maxDepth }

    /// Nature de la place choisie, pour la fiche.
    var selectedNature: String {
        switch selectedEntry {
        case .app: return "Application"
        case .url: return "Lien"
        case .shell: return "Commande"
        case .shortcut: return "Raccourci"
        case .action(let app, _): return "Action de \(ActionCatalog.appName(app))"
        case .proposal: return "Proposée par une appli"
        case .folder(_, let children): return "Dossier · \(children.filter { !$0.isEmpty }.count) places"
        case .empty: return "Place vide"
        case .unsupported: return "Non pris en charge"
        }
    }

    /// Clé d'identité d'un élément : un élément n'occupe qu'une place dans toute la roue.
    static func key(_ entry: Entry) -> String? {
        switch entry {
        case .app(let spec): return "app:" + (AppResolver.url(for: spec)?.standardizedFileURL.path ?? spec)
        case .empty, .folder: return nil
        default: return entry.serialized
        }
    }

    /// Où se trouve déjà un élément : « Place 3 », « Artcraft · 2 » ou « Artcraft · Outils · 2 ».
    var locations: [String: String] {
        var map: [String: String] = [:]
        func walk(_ entries: [Entry], prefix: [String]) {
            for (i, entry) in entries.enumerated() {
                if case .folder(let name, let children) = entry {
                    walk(children, prefix: prefix + [name])
                } else if let key = Self.key(entry) {
                    map[key] = prefix.isEmpty ? "Place \(i + 1)" : (prefix + ["\(i + 1)"]).joined(separator: " · ")
                }
            }
        }
        walk(config.places, prefix: [])
        return map
    }

    /// Filtre sans tenir compte de la casse ni des accents ; les noms qui commencent par la recherche d'abord.
    var filteredCandidates: [Candidate] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return candidates }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var starts: [Candidate] = [], contains: [Candidate] = []
        for c in candidates {
            guard let r = c.name.range(of: q, options: opts) else { continue }
            if r.lowerBound == c.name.startIndex { starts.append(c) } else { contains.append(c) }
        }
        return starts + contains
    }

    // MARK: Modifications

    private func update(_ places: [Entry]) {
        config = WheelConfig(places: EntryTree.setChildren(at: openPath, to: places, in: config.places))
        save()
    }

    private func save() {
        let url = ConfigStore.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { try config.serialize().write(to: url, atomically: true, encoding: .utf8) } catch { NSLog("Roue : enregistrement impossible : \(error)") }
    }

    /// Met l'élément à la place choisie (en le retirant d'ailleurs), puis passe à la suivante libre.
    /// Si la place choisie est un dossier, l'élément entre dans le dossier, à sa première place libre.
    func place(_ entry: Entry) {
        removeEverywhere(entry)
        if case .folder = currentPlaces[selected] {
            var kids = EntryTree.children(at: openPath + [selected], in: config.places) ?? []
            if let slot = kids.firstIndex(where: { $0.isEmpty }) {
                kids[slot] = entry
            } else if kids.count < WheelConfig.placeCount {
                kids.append(entry)
            } else {
                NSSound.beep() // dossier plein
                return
            }
            config = WheelConfig(places: EntryTree.setChildren(at: openPath + [selected], to: kids, in: config.places))
            save()
            return
        }
        var places = currentPlaces
        places[selected] = entry
        update(places)
        advanceToFree()
    }

    private func removeEverywhere(_ entry: Entry) {
        guard let key = Self.key(entry) else { return }
        func strip(_ entries: [Entry]) -> [Entry] {
            entries.map { e in
                if case .folder(let name, let kids) = e { return .folder(name: name, children: strip(kids)) }
                return Self.key(e) == key ? .empty : e
            }
        }
        config = WheelConfig(places: strip(config.places))
    }

    private func advanceToFree() {
        let places = currentPlaces
        for step in 1..<WheelConfig.placeCount {
            let i = (selected + step) % WheelConfig.placeCount
            if places[i].isEmpty { selected = i; return }
        }
    }

    func remove() {
        var places = currentPlaces
        places[selected] = .empty
        update(places)
    }

    /// Déplace la place choisie d'un cran autour de la roue.
    func move(_ delta: Int) {
        var places = currentPlaces
        let j = (selected + delta + WheelConfig.placeCount) % WheelConfig.placeCount
        places.swapAt(selected, j)
        update(places)
        selected = j
    }

    /// La place devient aussitôt un dossier (« Dossier », « Dossier 2 »…) ; ce qu'elle tenait y entre.
    func makeFolder() {
        guard canNestFolder, !currentPlaces[selected].isFolder else { return }
        let old = currentPlaces[selected]
        var places = currentPlaces
        places[selected] = .folder(name: nextFolderName(), children: old.isEmpty ? [] : [old])
        update(places)
    }

    /// Nom du dossier choisi, s'il y en a un (sinon celui du dossier ouvert).
    var editableFolderName: String? {
        if case .folder(let name, _) = selectedEntry { return name }
        if case .folder(let name, _)? = openFolderEntry { return name }
        return nil
    }

    private func nextFolderName() -> String {
        var names = Set<String>()
        func walk(_ entries: [Entry]) {
            for e in entries { if case .folder(let n, let kids) = e { names.insert(n); walk(kids) } }
        }
        walk(config.places)
        if !names.contains("Dossier") { return "Dossier" }
        var n = 2
        while names.contains("Dossier \(n)") { n += 1 }
        return "Dossier \(n)"
    }

    func rename(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if case .folder(_, let children) = selectedEntry {
            var places = currentPlaces
            places[selected] = .folder(name: name, children: children)
            update(places)
        } else if let last = openPath.last, case .folder(_, let children)? = openFolderEntry {
            let parentPath = Array(openPath.dropLast())
            var parent = EntryTree.children(at: parentPath, in: config.places) ?? []
            parent[last] = .folder(name: name, children: children)
            config = WheelConfig(places: EntryTree.setChildren(at: parentPath, to: parent, in: config.places))
            save()
        }
    }

    func openSelectedFolder() {
        guard canNestFolder, selectedEntry.isFolder else { return }
        openPath.append(selected)
        selected = currentPlaces.firstIndex { $0.isEmpty } ?? 0
    }

    func open(path: [Int], place: Int) {
        guard EntryTree.children(at: path, in: config.places) != nil else { return }
        openPath = path
        selected = min(max(0, place), WheelConfig.placeCount - 1)
    }

    func backToWheel() {
        guard let last = openPath.popLast() else { return }
        selected = last
    }

    func resetFromDock() {
        guard let dock = ConfigStore.dockFavorites(), !dock.isEmpty else { return }
        openPath = []
        config = WheelConfig(places: dock)
        save()
        selected = 0
    }
}

/// Ouverture à l'ouverture de session (SMAppService, macOS 13+). Demande un bundle d'appli.
enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    /// Renvoie un message d'erreur, ou nil.
    static func set(_ on: Bool) -> String? {
        guard #available(macOS 13, *) else { return "macOS 13 requis." }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return on ? "Disponible seulement depuis Roue.app (pas en swift run)." : nil
        }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
