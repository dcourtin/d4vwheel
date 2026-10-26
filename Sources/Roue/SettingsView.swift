import SwiftUI

/// Réglages > Roue : la roue telle qu'elle s'ouvre, la fiche de la place choisie, et ce qu'on peut y mettre.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                SettingsWheel(model: model)
                VStack(alignment: .leading, spacing: 16) {
                    PlaceSheet(model: model)
                    Divider()
                    AppearanceSheet(model: model)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(24)
            Divider()
            TriggersSheet(model: model)
                .padding(.horizontal, 24).padding(.vertical, 12)
            Divider()
            CandidateList(model: model)
        }
        .frame(minWidth: 760, minHeight: 760)
        .onAppear { model.loadCandidates(); model.refreshSystemState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshSystemState()
        }
    }
}

/// La roue dessinée par le même peintre que la roue réelle ; un clic choisit une place.
struct SettingsWheel: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var wheel = WheelModel()
    private let side: CGFloat = 2 * Geometry.discRadius + 24

    var body: some View {
        ZStack {
            BlurCircle(material: Appearance.materials.first { $0.id == model.materialID }?.material ?? .popover,
                       radius: Geometry.discRadius)
                .frame(width: side, height: side)
            WheelView(model: wheel)
        }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { p in
                if case .item(let level, let i)? = wheel.hitTest(p), level == 0 { model.selected = i }
            }
            .onAppear(perform: rebuild)
            .onChange(of: model.currentPlaces) { _ in rebuild() }
            .onChange(of: model.openPath) { _ in rebuild() }
            .onChange(of: model.selected) { _ in wheel.style.selectedPlace = model.selected }
            .onChange(of: model.tintOpacity) { v in wheel.style.tintOpacity = v }
            .accessibilityLabel("Roue")
    }

    private func rebuild() {
        let places = model.currentPlaces.map { AppResolver.resolve($0) }
        wheel.open(places: places, center: CGPoint(x: side / 2, y: side / 2), now: 0)
        wheel.settle()
        var style = WheelModel.Style()
        style.drawsVeil = false
        style.translucent = true
        style.tintOpacity = model.tintOpacity
        style.selectedPlace = model.selected
        if let folder = model.openFolderEntry { style.centerPlace = AppResolver.resolve(folder) }
        wheel.style = style
    }
}

/// Un flou du système découpé en disque, derrière la roue des Réglages : l'aperçu du fond réel.
struct BlurCircle: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let radius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        v.material = material
        v.maskImage = mask()
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
    }

    private func mask() -> NSImage {
        let side = 2 * radius + 24
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: CGRect(x: rect.midX - radius, y: rect.midY - radius, width: 2 * radius, height: 2 * radius)).fill()
            return true
        }
    }
}

/// Apparence du fond : matériau du flou et opacité de la teinte.
struct AppearanceSheet: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fond de la roue").font(.headline)
            Picker("Flou", selection: $model.materialID) {
                ForEach(Appearance.materials) { Text($0.name).tag($0.id) }
            }
            .frame(maxWidth: 320)
            HStack {
                Text("Opacité")
                Slider(value: $model.tintOpacity, in: 0...1)
                Text("\(Int((model.tintOpacity * 100).rounded())) %")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .frame(maxWidth: 320)
            Text("0 % : flou pur, comme le Dock. 100 % : disque opaque.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }
}

/// Comment ouvrir la roue, et au démarrage.
struct TriggersSheet: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ouvrir la roue").font(.headline)
                HStack {
                    Text("Raccourci clavier")
                    KeyRecorder(spec: $model.hotKey)
                }
                Toggle("Clic du milieu sur le bureau", isOn: $model.middleClickOnDesktop)
                Picker("Clic du milieu n'importe où avec", selection: $model.middleClickModifier) {
                    ForEach(MiddleClickTap.Modifier.allCases) { Text($0.name).tag($0) }
                }
                .frame(maxWidth: 360)
                if (model.middleClickOnDesktop || model.middleClickModifier != .none), !model.accessibilityTrusted {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text("Le clic du milieu demande l'autorisation Accessibilité.")
                        Button("Autoriser…") { model.requestAccessibility(); MiddleClickTap.openAccessibilitySettings() }
                            .controlSize(.small)
                    }
                    .font(.callout)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Système").font(.headline)
                Toggle("Ouvrir Roue à l'ouverture de session", isOn: $model.launchAtLogin)
                if let e = model.loginItemError {
                    Text(e).font(.caption).foregroundStyle(.secondary)
                }
                Text("Le cyclage des fenêtres d'une appli déjà devant et les actions des applis Apple demandent "
                     + "les autorisations Accessibilité et Automation, demandées à la première utilisation.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 360)
        }
    }
}

/// Un bouton qui enregistre la prochaine combinaison de touches.
struct KeyRecorder: View {
    @Binding var spec: Triggers.HotKeySpec
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(recording ? "Appuyez sur les touches…" : spec.display) { toggle() }
                .frame(minWidth: 150)
            if spec != .default {
                Button { spec = .default } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("Revenir à \(Triggers.HotKeySpec.default.display)")
            }
        }
        .onDisappear { stop() }
    }

    private func toggle() { recording ? stop() : start() }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Échap annule
            if let s = Triggers.spec(from: event) {
                spec = s
                stop()
                return nil
            }
            NSSound.beep()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Fiche de la place choisie.
struct PlaceSheet: View {
    @ObservedObject var model: SettingsModel
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.openFolderNames.isEmpty {
                HStack(spacing: 8) {
                    Button(model.openPath.count > 1 ? "Retour" : "Retour à la roue", systemImage: "chevron.left") { model.backToWheel() }
                    Text(model.openFolderNames.joined(separator: " › ")).font(.headline).lineLimit(1)
                }
            }
            Text("Place \(model.selected + 1)")
                .font(.caption).foregroundStyle(.secondary)
            Text(AppResolver.resolve(model.selectedEntry).name)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
            Text(model.selectedNature).foregroundStyle(.secondary)
            if model.selectedEntry.isFolder {
                Text("Un clic dans la liste ajoute l'élément au dossier.")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            if model.editingName != nil {
                nameField
            }

            HStack(spacing: 8) {
                Button { model.move(-1) } label: { Image(systemName: "arrow.counterclockwise") }
                    .help("Déplacer d'une place vers la gauche")
                Button { model.move(1) } label: { Image(systemName: "arrow.clockwise") }
                    .help("Déplacer d'une place vers la droite")
                if !model.selectedEntry.isEmpty {
                    Button("Retirer", role: .destructive) { model.remove() }
                }
            }

            HStack(spacing: 8) {
                if model.selectedEntry.isFolder {
                    Button("Ouvrir") { model.openSelectedFolder() }
                    Button("Renommer") { startNaming() }
                } else if model.canNestFolder {
                    Button("En faire un dossier") {
                        model.makeFolder()
                        startNaming()
                    }
                }
            }
            Spacer()
            Button("Reprendre les favoris du Dock") { model.resetFromDock() }
                .controlSize(.small)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: model.selected) { _ in model.editingName = nil }
        .onChange(of: model.openPath) { _ in model.editingName = nil }
    }

    /// Saisie du nom du dossier choisi : Entrée valide, Échap garde le nom actuel.
    private func startNaming() {
        guard let name = model.editableFolderName else { return }
        model.editingName = name
        DispatchQueue.main.async { nameFocused = true }
    }

    private func commitName() {
        guard let name = model.editingName else { return }
        model.rename(name)
        model.editingName = nil
    }

    private var nameField: some View {
        TextField("Nom du dossier", text: Binding(
            get: { model.editingName ?? "" }, set: { model.editingName = $0 }))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 260)
            .focused($nameFocused)
            .onSubmit { commitName() }
            .onExitCommand { model.editingName = nil }
            .onChange(of: nameFocused) { focused in if !focused { commitName() } }
    }
}

/// Ce qu'on peut mettre dans la roue, par groupes ; un clic met l'élément à la place choisie.
struct CandidateList: View {
    @ObservedObject var model: SettingsModel
    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Rechercher une application, une action ou un raccourci", text: $model.search)
                    .textFieldStyle(.roundedBorder)
                if model.loadingCandidates { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 24).padding(.top, 12)
            CustomEntryForm(model: model)
                .padding(.horizontal, 24).padding(.vertical, 8)
            ScrollView {
                let locations = model.locations
                let filtered = model.filteredCandidates
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Candidate.Group.allCases, id: \.self) { group in
                        let items = filtered.filter { $0.group == group }
                        if !items.isEmpty {
                            Text(group.rawValue)
                                .font(.headline)
                                .padding(.horizontal, 24)
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                                ForEach(items) { c in
                                    CandidateRow(candidate: c, location: SettingsModel.key(c.entry).flatMap { locations[$0] })
                                        .onTapGesture { model.place(c.entry) }
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    if !model.loadingCandidates, filtered.isEmpty {
                        Text("Aucun résultat").foregroundStyle(.secondary).padding(.horizontal, 24)
                    }
                }
                .padding(.vertical, 8)
                .animation(nil, value: model.search)
            }
        }
    }
}

/// Un lien ou une commande saisi à la main, mis à la place choisie.
struct CustomEntryForm: View {
    @ObservedObject var model: SettingsModel
    @State private var kind = SettingsModel.CustomKind.url
    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $kind) {
                ForEach(SettingsModel.CustomKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)
            TextField(kind == .url ? "https://… ou schéma d'URL" : "commande zsh", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            Button("Mettre à la place choisie", action: add)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func add() {
        model.placeCustom(kind: kind, text: text)
        text = ""
    }
}

struct CandidateRow: View {
    let candidate: Candidate
    let location: String?
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            if let icon = candidate.icon {
                Image(nsImage: icon).resizable().frame(width: 24, height: 24)
            } else {
                Image(systemName: candidate.symbol ?? "questionmark").frame(width: 24, height: 24)
            }
            Text(candidate.name).lineLimit(1)
            Spacer(minLength: 4)
            if let location {
                Text(location)
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(hover ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .help("Mettre à la place choisie")
    }
}
