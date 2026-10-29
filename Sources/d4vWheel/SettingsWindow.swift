import AppKit
import SwiftUI

/// La fenêtre Réglages > d4vWheel. Une seule, rouverte à la demande.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let model = SettingsModel()
    private var window: NSWindow?
    private var watcher: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1

    /// Montre la fenêtre, le fichier relu, sur la place demandée (dans le dossier du chemin donné).
    func show(path: [Int] = [], place: Int? = nil) {
        model.reload()
        if let place { model.open(path: path, place: place) }
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "Réglages de d4vWheel"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 820, height: 680))
            w.center()
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        startWatching()
    }

    func windowWillClose(_ notification: Notification) { stopWatching() }

    /// Surveille le dossier du fichier de configuration : modifié ailleurs, il est relu.
    private func startWatching() {
        guard watcher == nil else { return }
        let dir = ConfigStore.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        watchedFD = open(dir.path, O_EVTONLY)
        guard watchedFD >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: watchedFD, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.model.reloadIfChanged()
                self?.model.refreshProposals()
            }
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.watchedFD, fd >= 0 { close(fd) }
            self?.watchedFD = -1
        }
        src.resume()
        watcher = src
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }
}
