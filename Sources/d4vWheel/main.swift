import AppKit
import SwiftUI

/// d4vWheel : lanceur circulaire autour du pointeur. Appli de barre des menus, sans Dock.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: WheelController!
    private var hotKey: GlobalHotKey?
    private let tap = MiddleClickTap()
    private var statusItem: NSStatusItem?
    private let settings = SettingsWindowController()
    private var signalSource: DispatchSourceSignal?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:_:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--rendu"), i + 1 < args.count {
            renderPreview(to: URL(fileURLWithPath: args[i + 1]), withFolder: args.contains("--dossier"))
            exit(0)
        }
        if let i = args.firstIndex(of: "--rendu-reglages"), i + 1 < args.count {
            let url = URL(fileURLWithPath: args[i + 1])
            Task { @MainActor in
                let m = SettingsModel()
                await m.loadCandidatesNow()
                m.selected = 3
                let renderer = ImageRenderer(content: SettingsView(model: m).frame(width: 820, height: 680)
                    .background(Color(nsColor: .windowBackgroundColor)))
                renderer.scale = 2
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: url)
                    print("Rendu écrit : \(url.path)")
                }
                exit(0)
            }
            return
        }

        controller = WheelController()
        controller.model.onEmptyChosen = { [weak self] path, place in
            self?.settings.show(path: path, place: place)
        }
        configureTriggers()
        NotificationCenter.default.addObserver(forName: Triggers.changed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.configureTriggers() }
        }
        installStatusItem()
        installSignalHandler()
    }

    // MARK: Déclencheurs

    /// (Re)lit les réglages : raccourci global, clic du milieu.
    func configureTriggers() {
        hotKey = nil
        hotKey = GlobalHotKey(spec: Triggers.hotKey) { [weak self] in self?.controller.toggle() }
        if hotKey == nil { NSLog("d4vWheel : impossible d'enregistrer le raccourci \(Triggers.hotKey.display)") }

        tap.onDesktop = Triggers.middleClickOnDesktop
        tap.modifier = Triggers.middleClickModifier
        tap.isWheelOpen = { [weak self] in self?.controller.model.isVisible ?? false }
        tap.onOpen = { [weak self] in
            guard let self, !self.controller.model.isVisible else { return false }
            self.controller.open()
            return true
        }
        tap.onDrag = { [weak self] p in self?.controller.gestureDragged(toGlobal: p) }
        tap.onRelease = { [weak self] p in self?.controller.gestureReleased(atGlobal: p) }
        if Triggers.middleClickWanted, MiddleClickTap.isTrusted {
            if !tap.start() { NSLog("d4vWheel : impossible d'écouter la souris") }
        } else {
            tap.stop()
        }
    }

    // MARK: Barre des menus

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "d4vWheel")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector?, key: String = "") {
            let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
            it.target = self
            menu.addItem(it)
        }
        add("Ouvrir la roue\t\(Triggers.hotKey.display)", #selector(openWheel))
        menu.addItem(.separator())
        add("Réglages…", #selector(openSettings), key: ",")
        add("Modifier le fichier de configuration…", #selector(editConfig))
        add("Afficher dans le Finder", #selector(revealConfig))
        menu.addItem(.separator())
        if Triggers.middleClickWanted, !MiddleClickTap.isTrusted {
            add("Autoriser le clic du milieu (Accessibilité)…", #selector(requestAccessibility))
            menu.addItem(.separator())
        }
        add("À propos de d4vWheel", #selector(about))
        add("Quitter d4vWheel", #selector(NSApplication.terminate(_:)), key: "q")
    }

    @objc private func openWheel() {
        // Le menu vient de se fermer : on laisse le pointeur se poser avant d'ouvrir.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.controller.open() }
    }

    @objc private func openSettings() { settings.show() }
    @objc private func editConfig() { Launcher.openConfigFile() }
    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func revealConfig() {
        let url = ConfigStore.createFileIfMissing()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func requestAccessibility() {
        MiddleClickTap.requestTrust()
        // Une fois l'autorisation donnée, on réessaie régulièrement sans relancer l'appli.
        pollTrust(remaining: 60)
    }

    private func pollTrust(remaining: Int) {
        guard remaining > 0, !MiddleClickTap.isTrusted else { configureTriggers(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.pollTrust(remaining: remaining - 1) }
    }

    /// `kill -USR1 <pid>` bascule la roue : pratique pour l'essayer depuis un terminal.
    private func installSignalHandler() {
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in self?.controller.toggle() }
        source.resume()
        signalSource = source
    }

    // MARK: Schéma d'URL d4vwheel://

    /// `d4vwheel://ouvrir`, `d4vwheel://reglages`, `d4vwheel://proposer?id=…&nom=…&commande=…[&icone=…&description=…]`, `d4vwheel://retirer?id=…`
    @objc private func handleURL(_ event: NSAppleEventDescriptor, _ reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: s), url.scheme == "d4vwheel" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch url.host {
        case "ouvrir":
            controller.open()
        case "reglages":
            settings.show()
        case "proposer":
            guard let id = q("id"), let nom = q("nom"), let commande = q("commande") else { return }
            let p = Proposal(id: id, nom: nom, commande: commande, icone: q("icone"), description: q("description"))
            confirmProposal(p)
        case "retirer":
            if let id = q("id") { Proposals.remove(id) }
        default:
            break
        }
    }

    /// Une appli propose une entrée : on demande avant d'enregistrer, sans jamais la placer dans la roue.
    private func confirmProposal(_ p: Proposal) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Nouvelle proposition pour d4vWheel"
        alert.informativeText = "« \(p.nom) » (\(p.id)) propose la commande :\n\(p.commande)"
            + (p.description.map { "\n\n\($0)" } ?? "")
            + "\n\nElle n'entre pas dans la roue toute seule : vous pourrez la placer dans Réglages."
        alert.addButton(withTitle: "Enregistrer et ouvrir les Réglages")
        alert.addButton(withTitle: "Enregistrer")
        alert.addButton(withTitle: "Refuser")
        let r = alert.runModal()
        guard r != .alertThirdButtonReturn else { return }
        do {
            try Proposals.save(p)
            if r == .alertFirstButtonReturn { settings.show() }
        } catch {
            let e = NSAlert(error: error)
            e.runModal()
        }
    }

    // MARK: Rendu hors écran (`--rendu sortie.png [--dossier]`)

    private func renderPreview(to url: URL, withFolder: Bool) {
        var config = ConfigStore.load().config
        if withFolder {
            config = WheelConfig(places: [
                .app("com.apple.Safari"), .app("com.apple.Notes"), .app("com.apple.Terminal"),
                .folder(name: "Bureau", children: [.app("com.apple.mail"), .app("com.apple.iCal"),
                                                    .folder(name: "Outils", children: [.app("com.apple.Terminal"), .app("com.apple.Console")]),
                                                    .app("com.apple.MobileSMS"), .app("com.apple.systempreferences")]),
                .url("https://example.org"), .app("com.apple.finder"), .empty, .action(app: "com.apple.Notes", key: "nouvelle"),
            ])
        }
        let model = WheelModel()
        let size = CGSize(width: 900, height: 820)
        model.open(places: AppResolver.resolve(config), center: CGPoint(x: 450, y: 380), now: 0)
        model.settle()
        model.pointerMoved(to: model.finalPosition(level: 0, index: withFolder ? 3 : 1, lifted: false))
        model.settle()
        if withFolder {
            model.pointerMoved(to: model.finalPosition(level: 1, index: 2, lifted: false))
            model.settle()
        }

        let renderer = ImageRenderer(content: WheelView(model: model).frame(width: size.width, height: size.height)
            .background(Color(nsColor: .underPageBackgroundColor)))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
            NSLog("d4vWheel : rendu impossible")
            return
        }
        try? png.write(to: url)
        print("Rendu écrit : \(url.path)")
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu(menu) }
}

// Verbes de la ligne de commande (proposer, retirer, liste…) : pas d'interface.
if let code = Proposals.handleCommandLine(CommandLine.arguments) { exit(code) }
if CommandLine.arguments.count > 1, ["ouvrir", "reglages"].contains(CommandLine.arguments[1]) {
    // Relayé à l'instance qui tourne, par le schéma d'URL.
    NSWorkspace.shared.open(URL(string: "d4vwheel://\(CommandLine.arguments[1])")!)
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
