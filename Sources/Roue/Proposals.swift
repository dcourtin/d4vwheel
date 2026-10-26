import AppKit

/// Une entrée proposée par une appli. Elle n'entre jamais seule dans la roue : l'utilisateur la place dans Réglages.
struct Proposal: Codable, Identifiable, Equatable {
    var id: String
    var nom: String
    var commande: String
    /// Chemin d'une image, ou nom d'un symbole SF.
    var icone: String?
    var description: String?

    func icon() -> NSImage? {
        guard let icone, !icone.isEmpty else { return nil }
        if icone.hasPrefix("/") || icone.hasPrefix("~") {
            return NSImage(contentsOfFile: (icone as NSString).expandingTildeInPath)
        }
        return NSImage(systemSymbolName: icone, accessibilityDescription: nil)
    }
}

enum Proposals {
    static var directory: URL {
        ConfigStore.preferredURL.deletingLastPathComponent().appendingPathComponent("propositions")
    }

    /// Lettres, chiffres, `.`, `-`, `_` ; 100 caractères au plus.
    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 100 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
    }

    static func url(for id: String) -> URL { directory.appendingPathComponent(id + ".json") }

    static func load(_ id: String) -> Proposal? {
        guard isValidID(id), let data = try? Data(contentsOf: url(for: id)) else { return nil }
        var p = try? JSONDecoder().decode(Proposal.self, from: data)
        p?.id = id
        return p
    }

    static func all() -> [Proposal] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.filter { $0.hasSuffix(".json") }
            .compactMap { load(String($0.dropLast(5))) }
            .sorted { $0.nom.localizedCaseInsensitiveCompare($1.nom) == .orderedAscending }
    }

    static func save(_ p: Proposal) throws {
        guard isValidID(p.id) else { throw ProposalError.invalidID }
        guard !p.nom.isEmpty, !p.commande.isEmpty else { throw ProposalError.incomplete }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(p).write(to: url(for: p.id), options: .atomic)
    }

    @discardableResult
    static func remove(_ id: String) -> Bool {
        guard isValidID(id) else { return false }
        return (try? FileManager.default.removeItem(at: url(for: id))) != nil
    }

    static func run(_ p: Proposal) {
        Launcher.run("/bin/zsh", ["-lc", p.commande])
    }

    enum ProposalError: LocalizedError {
        case invalidID, incomplete
        var errorDescription: String? {
            switch self {
            case .invalidID: return "Identifiant invalide : lettres, chiffres, « . », « - », « _ », 100 caractères au plus."
            case .incomplete: return "Il faut un nom et une commande."
            }
        }
    }

    // MARK: Ligne de commande

    static let usage = """
        Usage :
          Roue proposer --id ID --nom NOM --commande CMD [--icone ICÔNE] [--description TEXTE]
          Roue retirer ID
          Roue liste
          Roue ouvrir | reglages
        """

    /// Traite les verbes de la ligne de commande ; renvoie le code de sortie si un verbe a été reconnu.
    static func handleCommandLine(_ args: [String]) -> Int32? {
        guard args.count > 1 else { return nil }
        switch args[1] {
        case "proposer":
            var opts: [String: String] = [:]
            var i = 2
            while i + 1 < args.count, args[i].hasPrefix("--") {
                opts[String(args[i].dropFirst(2))] = args[i + 1]
                i += 2
            }
            guard let id = opts["id"], let nom = opts["nom"], let commande = opts["commande"] else {
                FileHandle.standardError.write((usage + "\n").data(using: .utf8)!)
                return 2
            }
            do {
                try save(Proposal(id: id, nom: nom, commande: commande, icone: opts["icone"], description: opts["description"]))
                print("Proposition « \(nom) » enregistrée (\(id)). Placez-la dans Réglages > Roue.")
                notify(title: "Nouvelle proposition pour la Roue", body: "« \(nom) » peut être placée dans Réglages.")
                return 0
            } catch {
                FileHandle.standardError.write((error.localizedDescription + "\n").data(using: .utf8)!)
                return 1
            }
        case "retirer":
            guard args.count > 2 else { FileHandle.standardError.write((usage + "\n").data(using: .utf8)!); return 2 }
            if remove(args[2]) { print("Proposition \(args[2]) retirée."); return 0 }
            FileHandle.standardError.write("Aucune proposition \(args[2]).\n".data(using: .utf8)!)
            return 1
        case "liste":
            let (config, source) = ConfigStore.load()
            switch source {
            case .file(let url): print("Roue (\(url.path)) :")
            case .dock: print("Roue (favoris du Dock, aucun fichier) :")
            case .fallback: print("Roue (sélection par défaut, aucun fichier) :")
            }
            func dump(_ entries: [Entry], depth: Int) {
                for (i, e) in entries.enumerated() {
                    print(String(repeating: "  ", count: depth + 1) + "\(i + 1). " + e.serialized)
                    if case .folder(_, let kids) = e { dump(kids, depth: depth + 1) }
                }
            }
            dump(config.places, depth: 0)
            let props = all()
            print(props.isEmpty ? "Aucune proposition." : "Propositions :")
            for p in props { print("  \(p.id) : \(p.nom) — \(p.commande)") }
            return 0
        case "aide", "--help", "-h":
            print(usage)
            return 0
        default:
            return nil
        }
    }

    /// Notification visible sans passer par le centre de notifications de l'appli (qui exige un bundle et une autorisation).
    static func notify(title: String, body: String) {
        let script = "display notification \"\(body.replacingOccurrences(of: "\"", with: "\\\""))\" with title \"\(title)\""
        Launcher.run("/usr/bin/osascript", ["-e", script])
    }
}
