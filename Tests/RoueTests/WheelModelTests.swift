import AppKit
import Testing
@testable import Roue

@MainActor
@Suite struct WheelModelTests {
    private func place(_ name: String, kind: Place.Kind = .app, children: [Place] = []) -> Place {
        Place(entry: kind == .folder ? .folder(name: name, children: []) : .app(name), kind: kind, name: name,
              subtitle: nil, icon: nil, symbol: nil, appURL: nil, isRunning: false, children: children)
    }

    private func makeModel() -> WheelModel {
        let inner = place("Interne", kind: .folder, children: [place("Console")])
        let outer = place("Bureau", kind: .folder, children: [place("Mail"), inner, place("Notes")])
        var places = (0..<8).map { place("A\($0)") }
        places[3] = outer
        let m = WheelModel()
        m.open(places: places, center: CGPoint(x: 400, y: 400), now: 0)
        m.settle()
        return m
    }

    @Test func openingSettles() {
        let m = makeModel()
        #expect(m.phase == .open)
        #expect(!m.needsFrames)
        #expect(m.iconProgress(7) == 1)
    }

    @Test func hoverFolderOpensRingsAndFoldsThem() {
        let m = makeModel()
        m.pointerMoved(to: m.finalPosition(level: 0, index: 3, lifted: false))
        m.settle()
        #expect(m.rings.count == 1)
        #expect(m.rings[0].items.map(\.name) == ["Mail", "Interne", "Notes"])
        #expect(m.label == "Bureau · dossier")

        // Le dossier du deuxième anneau ouvre un troisième anneau.
        m.pointerMoved(to: m.finalPosition(level: 1, index: 1, lifted: false))
        m.settle()
        #expect(m.rings.count == 2)
        #expect(m.activeLevel == 2)
        #expect(m.rings[1].items.map(\.name) == ["Console"])

        // Survoler une autre place de la roue replie tout.
        m.pointerMoved(to: m.finalPosition(level: 0, index: 0, lifted: false))
        m.settle()
        #expect(m.rings.isEmpty)
        #expect(m.label == "A0")
    }

    @Test func keyboardDigitsAndEscape() {
        let m = makeModel()
        var launched: [String] = []
        m.onLaunch = { launched.append($0.name) }
        m.key(fakeKey(21)) // 4 → place 4 (index 3) : le dossier s'ouvre
        m.settle()
        #expect(m.rings.count == 1)
        m.key(fakeKey(53)) // Échap replie l'anneau
        m.settle()
        #expect(m.rings.isEmpty)
        #expect(m.phase == .open)
        m.key(fakeKey(18)) // 1 → lance A0 et ferme
        #expect(launched == ["A0"])
        guard case .closing = m.phase else { Issue.record("fermeture attendue"); return }
        m.settle()
        #expect(m.phase == .closed)
    }

    @Test func clickOutsideCloses() {
        let m = makeModel()
        m.click(at: CGPoint(x: 10, y: 10))
        guard case .closing = m.phase else { Issue.record("fermeture attendue"); return }
    }

    @Test func emptyPlaceReportsPath() {
        let m = makeModel()
        var reported: ([Int], Int)?
        m.onEmptyChosen = { reported = ($0, $1) }
        // Un dossier vide montre une seule place vide dans son anneau.
        var places = (0..<8).map { place("A\($0)") }
        places[5] = place("Vide", kind: .folder)
        m.open(places: places, center: CGPoint(x: 400, y: 400), now: 10)
        m.settle()
        m.pointerMoved(to: m.finalPosition(level: 0, index: 5, lifted: false))
        m.settle()
        #expect(m.rings[0].items.first?.kind == .empty)
        m.choose(.item(level: 1, index: 0))
        #expect(reported?.0 == [5])
        #expect(reported?.1 == 0)
    }

    private func fakeKey(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }
}
