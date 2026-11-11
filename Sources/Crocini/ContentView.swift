import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var updater: Updater
    @State private var dropping = false

    var body: some View {
        HStack(spacing: 0) {
            SettingsPanel(dropping: dropping)
                .frame(width: 350)
            Divider()
            PreviewView()
        }
        .ignoresSafeArea(.container, edges: .top)   // senza barra del titolo il contenuto parte dal bordo
        .overlay(alignment: .top) { CMYKBar().frame(height: 4).ignoresSafeArea().allowsHitTesting(false) }
        .overlay { if dropping { DropOverlay() } }
        .animation(Theme.spring, value: dropping)
        // Si può rilasciare un file in qualsiasi punto della finestra.
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            ArtworkDrop.handle(providers, into: store)
        }
        .tint(Theme.magenta)
        .font(Theme.font(.callout))
        .background(WindowChrome())
        .sheet(isPresented: $updater.showSheet) { UpdateSheet(updater: updater) }
        .task {
            // Controllo silenzioso all'avvio: la finestra compare solo se c'è una novità.
            await updater.check()
            if updater.isUpdateAvailable { updater.showSheet = true }
        }
        .alert("Crocini", isPresented: Binding(
            get: { store.message != nil },
            set: { if !$0 { store.message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.message ?? "")
        }
    }
}

private struct SettingsPanel: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var updater: Updater
    let dropping: Bool
    @State private var showSaveSheet = false
    @State private var newPresetName = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    ArtworkDropZone(isTargeted: dropping)
                        .padding(.bottom, 2)
                    BackSideCard()
                    presetCard
                    paperCard
                    itemCard
                    bleedCard
                    marksCard
                    plotterCard
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .sheet(isPresented: $showSaveSheet) { saveSheet }
    }

    // MARK: intestazione e piede

    private var header: some View {
        HStack(spacing: 12) {
            LogoMark()
            VStack(alignment: .leading, spacing: 1) {
                Text("Crocini")
                    .font(Theme.font(size: 24, .heavy))
                    .foregroundStyle(Theme.brandGradient)
                Text("impagina per il taglio")
                    .font(Theme.font(.caption, .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if updater.isUpdateAvailable {
                Button { updater.showSheet = true } label: {
                    Label("Aggiorna", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(ChipButtonStyle())
                .help("È disponibile una nuova versione")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(Theme.spring, value: updater.isUpdateAvailable)
        .padding(.horizontal, 16).padding(.top, 34).padding(.bottom, 12)   // sotto i pallini del sistema
    }

    private var footer: some View {
        let r = store.result
        return VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(r.count)")
                    .font(Theme.font(size: 46, .heavy))
                    .foregroundStyle(r.count > 0 ? Theme.ink : Color.secondary)
                    .contentTransition(.numericText())
                    // evidenziatore giallo sotto il numero, come sul sito
                    .background(alignment: .bottom) {
                        Rectangle().fill(r.count > 0 ? Theme.yellow : .clear).frame(height: 15).offset(y: -5)
                    }
                Text(L(r.count == 1 ? "pezzo per foglio" : "pezzi per foglio"))
                    .font(Theme.font(.callout, .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if r.count > 0 {
                    VStack(alignment: .trailing, spacing: 3) {
                        pill("\(r.columns) × \(r.rows)", "square.grid.2x2", .cyan)
                        if r.rotated { pill("ruotati", "rotate.right", .yellow) }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(Theme.spring, value: r.count)
            .animation(Theme.spring, value: r.rotated)

            Button("Esporta PDF") { store.exportPDF() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut("e", modifiers: .command)
                .disabled(r.count == 0)
        }
        .padding(16)
        .background(
            Rectangle().fill(.regularMaterial)
                .overlay(alignment: .top) { Divider() }
        )
    }

    private func pill(_ text: LocalizedStringKey, _ symbol: String, _ plate: Plate) -> some View {
        Label(text, systemImage: symbol)
            .font(Theme.font(.caption, .bold))
            .foregroundStyle(plate.onColor == .white ? Color.white : Theme.ink)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(plate.color.opacity(0.45)))
            .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.55), lineWidth: 1))
    }

    // MARK: sezioni

    private var presetCard: some View {
        SectionCard(title: "Preset", symbol: "sparkles", plate: .yellow) {
            HStack(spacing: 8) {
                Menu {
                    Section("Predefinite") {
                        ForEach(LayoutPreset.builtIn) { p in
                            Button(p.title) { withAnimation(Theme.spring) { store.apply(p) } }
                        }
                    }
                    if !store.userPresets.isEmpty {
                        Section("Mie") {
                            ForEach(store.userPresets) { p in
                                Button(p.title) { withAnimation(Theme.spring) { store.apply(p) } }
                            }
                        }
                        Menu("Elimina preset") {
                            ForEach(store.userPresets) { p in
                                Button(p.title, role: .destructive) { store.deletePreset(p) }
                            }
                        }
                    }
                } label: {
                    Label("Scegli", systemImage: "list.bullet.rectangle")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(Theme.ink)
                .font(Theme.font(.callout, .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Theme.cyan.opacity(0.32)))

                Button {
                    newPresetName = ""
                    showSaveSheet = true
                } label: {
                    Label("Salva questo", systemImage: "plus")
                }
                .buttonStyle(ChipButtonStyle(plate: .yellow))
            }
        }
    }

    private var paperCard: some View {
        SectionCard(title: "Foglio di stampa", symbol: "doc.plaintext", plate: .cyan) {
            FieldRow("Formato") {
                Picker("", selection: paperBinding) {
                    Text("Personalizzato").tag(Optional<PaperSize>.none)
                    ForEach(PaperSize.all) { Text($0.title).tag(Optional($0)) }
                }
                .labelsHidden().fixedSize()
            }
            MMField("Larghezza", value: $store.settings.paperWidth)
            MMField("Altezza", value: $store.settings.paperHeight)
            Picker("", selection: $store.settings.landscape.animation(Theme.spring)) {
                Label("Verticale", systemImage: "rectangle.portrait").tag(false)
                Label("Orizzontale", systemImage: "rectangle").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden()
            MMField("Margine", value: $store.settings.margin)
        }
    }

    private var itemCard: some View {
        SectionCard(title: "Elemento da impaginare", symbol: "rectangle.on.rectangle", plate: .magenta) {
            FieldRow("Formato") {
                Picker("", selection: itemBinding) {
                    Text("Personalizzato").tag(Optional<ItemPreset>.none)
                    ForEach(ItemPreset.all) { Text($0.title).tag(Optional($0)) }
                }
                .labelsHidden().fixedSize()
            }
            MMField("Larghezza", value: $store.settings.itemWidth)
            MMField("Altezza", value: $store.settings.itemHeight)
            MMField("Distanza", value: $store.settings.gap)
            FieldRow("Ruota") {
                Picker("", selection: $store.settings.rotation) {
                    ForEach(RotationMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
            }
        }
    }

    private var bleedCard: some View {
        SectionCard(title: "Abbondanza", symbol: "square.dashed.inset.filled", plate: .yellow) {
            MMField("Abbondanza", value: $store.settings.bleed)
            HStack(spacing: 6) {
                ForEach([0.0, 2, 3, 5], id: \.self) { v in
                    Button(v == 0 ? "Nessuna" : "\(Int(v)) mm") {
                        withAnimation(Theme.spring) { store.settings.bleed = v }
                    }
                    .buttonStyle(ChipButtonStyle(plate: .cyan))
                }
            }
            ForEach(BleedMode.allCases) { mode in
                ChoiceRow(title: mode.label, selected: store.settings.bleedMode == mode) {
                    withAnimation(Theme.spring) { store.settings.bleedMode = mode }
                }
            }
            if store.settings.bleedMode == .flat {
                FieldRow("Colore di sfondo") {
                    ColorPicker("", selection: RGB.binding($store.settings.bleedColor), supportsOpacity: false)
                        .labelsHidden()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var marksCard: some View {
        SectionCard(title: "Segni di taglio", symbol: "scissors", plate: .black) {
            Toggle("Mostra i crocini", isOn: $store.settings.cropMarks.animation(Theme.spring))
                .toggleStyle(.switch)
                .font(Theme.font(.callout, .semibold))
            if store.settings.cropMarks {
                VStack(alignment: .leading, spacing: 10) {
                    Menu {
                        ForEach(MarkStyle.all) { m in
                            Button(m.title) {
                                store.settings.markWidth = m.width
                                store.settings.markLength = m.length
                            }
                        }
                    } label: {
                        Label("Stili predefiniti", systemImage: "slider.horizontal.3")
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tint(Theme.ink)
                .font(Theme.font(.callout, .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Theme.yellow.opacity(0.5)))

                    MMField("Spessore", value: $store.settings.markWidth, digits: 2)
                    MMField("Lunghezza", value: $store.settings.markLength)
                    FieldRow("Colore") {
                        ColorPicker("", selection: RGB.binding($store.settings.markColor), supportsOpacity: false)
                            .labelsHidden()
                    }
                    Toggle("Distanza automatica dal rifilo", isOn: $store.settings.markOffsetAuto.animation(Theme.spring))
                        .toggleStyle(.switch).font(Theme.font(.callout))
                    if !store.settings.markOffsetAuto {
                        MMField("Distanza", value: $store.settings.markOffsetValue)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var plotterCard: some View {
        SectionCard(title: "Plotter di taglio", symbol: "rectangle.dashed", plate: .cyan, startsOpen: false) {
            Toggle("Esporta anche la fustella", isOn: $store.plotter.animation(Theme.spring))
                .toggleStyle(.switch)
                .font(Theme.font(.callout, .semibold))
            if store.plotter {
                MMField("Angoli arrotondati", value: $store.plotterRadius)
                Text("Il PDF di stampa ha quattro segni di registrazione negli angoli; un secondo PDF, «fustella», contiene la linea di taglio (colore spot CutContour, per Summa, Roland, Graphtec e la maggior parte dei RIP) e gli stessi segni, nella stessa posizione.")
                    .font(Theme.font(.caption)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: preset personali

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Salva come preset")
                .font(Theme.font(.title3, .heavy))
            TextField("Nome del preset", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { showSaveSheet = false }
                Button("Salva", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
    }

    private func save() {
        store.saveCurrentAsPreset(named: newPresetName)
        showSaveSheet = false
    }

    /// Mostra il formato corrispondente alle misure correnti; scegliendone uno applica le misure.
    private var itemBinding: Binding<ItemPreset?> {
        Binding(
            get: { ItemPreset.all.first { $0.width == store.settings.itemWidth && $0.height == store.settings.itemHeight } },
            set: { if let p = $0 { store.applyPreset(p) } }
        )
    }

    private var paperBinding: Binding<PaperSize?> {
        Binding(
            get: { PaperSize.all.first { $0.width == store.settings.paperWidth && $0.height == store.settings.paperHeight } },
            set: { if let p = $0 { store.applyPaper(p) } }
        )
    }
}

/// Riga a scelta singola con spunta animata.
private struct ChoiceRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(Theme.font(size: 16, .semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.secondary.opacity(0.6)))
                    .scaleEffect(selected ? 1.1 : 1)
                Text(title).font(Theme.font(.callout))
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.magenta.opacity(selected ? 0.12 : (hovering ? 0.06 : 0)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.spring, value: selected)
    }
}

/// Finestra senza barra del titolo: contenuto a tutta altezza, pallini del sistema in alto a sinistra,
/// e finestra trascinabile da qualsiasi punto dello sfondo.
private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.isMovableByWindowBackground = true
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
