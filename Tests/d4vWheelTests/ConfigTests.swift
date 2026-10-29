import Testing
@testable import d4vWheel

@Suite struct ConfigTests {
    @Test func parseTypesAndPadding() {
        let c = WheelConfig.parse("""
        # commentaire
        app:com.apple.Safari
        action:com.apple.Notes:nouvelle
        -
        entree:com.exemple.capture
        url:https://example.org
        sh:open ~
        raccourci:Mon raccourci
        """)
        #expect(c.places.count == 8)
        #expect(c.places[0] == .app("com.apple.Safari"))
        #expect(c.places[1] == .action(app: "com.apple.Notes", key: "nouvelle"))
        #expect(c.places[2] == .empty)
        #expect(c.places[3] == .proposal("com.exemple.capture"))
        #expect(c.places[4] == .url("https://example.org"))
        #expect(c.places[5] == .shell("open ~"))
        #expect(c.places[6] == .shortcut("Mon raccourci"))
        #expect(c.places[7] == .empty)
        #expect(c.depth == 0)
    }

    @Test func nestedFoldersRoundTrip() throws {
        let text = """
        app:com.apple.Safari
        dossier:Bureau
          app:com.apple.mail
          dossier:Outils
            app:com.apple.Terminal
            dossier:Trop profond
              app:com.apple.Console
          app:com.apple.Notes
        -
        """
        let c = WheelConfig.parse(text)
        #expect(c.depth == 2)
        guard case .folder(let name, let kids) = c.places[1] else { Issue.record("dossier attendu"); return }
        #expect(name == "Bureau")
        #expect(kids.count == 3)
        guard case .folder(_, let tools) = kids[1] else { Issue.record("sous-dossier attendu"); return }
        #expect(tools.count == 2, "le dossier trop profond est gardé comme ligne, ses enfants ignorés")
        #expect(tools[1] == .unsupported("dossier:Trop profond"))
        #expect(WheelConfig.parse(c.serialize()) == c, "écriture puis lecture stables")
        #expect(EntryTree.children(at: [1, 1], in: c.places)?.first == .app("com.apple.Terminal"))
    }

    @Test func serializeOmitsTrailingEmptiesInFolders() {
        let c = WheelConfig(places: [.folder(name: "D", children: [.app("a"), .empty, .empty])])
        let lines = c.serialize().components(separatedBy: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }
        #expect(lines == ["dossier:D", "  app:a", "-", "-", "-", "-", "-", "-", "-"])
    }

    @Test func maxEightPerLevel() {
        let many = (1...12).map { "app:a\($0)" }.joined(separator: "\n")
        #expect(WheelConfig.parse(many).places.count == 8)
        let folder = "dossier:D\n" + (1...12).map { "  app:a\($0)" }.joined(separator: "\n")
        guard case .folder(_, let kids) = WheelConfig.parse(folder).places[0] else { Issue.record("dossier attendu"); return }
        #expect(kids.count == 8)
    }

    @Test func entryTreeSetChildren() {
        let places: [Entry] = [.folder(name: "A", children: [.folder(name: "B", children: [])]), .empty]
        let out = EntryTree.setChildren(at: [0, 0], to: [.app("x")], in: places)
        #expect(EntryTree.children(at: [0, 0], in: out) == [.app("x")])
        #expect(EntryTree.children(at: [1], in: out) == nil, "une place vide n'a pas d'enfants")
    }

    @Test func proposalIDs() {
        #expect(Proposals.isValidID("com.exemple.capture-1_a"))
        #expect(!Proposals.isValidID("a b"))
        #expect(!Proposals.isValidID(""))
        #expect(!Proposals.isValidID(String(repeating: "a", count: 101)))
        #expect(Entry.parse("entree:pas valide") == .unsupported("entree:pas valide"))
    }
}
