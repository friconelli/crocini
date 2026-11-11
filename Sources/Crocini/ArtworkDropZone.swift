import SwiftUI
import UniformTypeIdentifiers

/// Gestisce il rilascio di file sulla finestra: prende il primo file e lo carica come grafica.
enum ArtworkDrop {
    static func handle(_ providers: [NSItemProvider], into store: Store) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) })
        else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in store.loadArtwork(url: url) }
        }
        return true
    }
}

/// Zona di caricamento: trascina un file o clicca. Dopo il caricamento mostra anteprima e dati.
struct ArtworkDropZone: View {
    @EnvironmentObject var store: Store
    let isTargeted: Bool
    @State private var hovering = false
    @State private var bounce = false
    @State private var dashPhase: CGFloat = 0

    var body: some View {
        Group {
            if let art = store.artwork {
                loaded(art)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else {
                empty
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
    }

    private var active: Bool { isTargeted || hovering }

    /// Millimetri con un decimale, con la virgola o il punto della lingua del sistema.
    private static func mm(_ v: CGFloat) -> String {
        Double(v).formatted(.number.precision(.fractionLength(1)))
    }

    // MARK: vuota

    private var empty: some View {
        Button { store.chooseArtwork() } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Theme.magenta.opacity(active ? 0.22 : 0.12))
                        .frame(width: 64, height: 64)
                        .scaleEffect(isTargeted ? 1.25 : 1)
                    Image(systemName: isTargeted ? "arrow.down.doc.fill" : "photo.badge.plus")
                        .font(Theme.font(size: 26, .semibold))
                        .foregroundStyle(Theme.brandGradient)
                        .offset(y: bounce && !isTargeted ? -3 : 0)
                        .scaleEffect(isTargeted ? 1.15 : 1)
                }
                Text(L(isTargeted ? "Rilascia per caricare" : "Trascina qui la tua grafica"))
                    .font(Theme.font(.callout, .bold))
                Text(isTargeted ? " " : L("oppure clicca per scegliere · PNG, JPEG, PDF"))
                    .font(Theme.font(.caption))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.magenta.opacity(isTargeted ? 0.14 : (hovering ? 0.08 : 0.04)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    // bordo in quadricromia: ciano, magenta e giallo (fisso: un gradiente che gira consuma CPU di continuo)
                    .strokeBorder(LinearGradient(colors: [Theme.cyan, Theme.magenta, Theme.yellow],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing),
                                  style: StrokeStyle(lineWidth: isTargeted ? 3 : 2,
                                                     dash: isTargeted ? [] : [7, 5], dashPhase: dashPhase))
                    .opacity(active ? 1 : 0.8)
            )
            .scaleEffect(isTargeted ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.spring, value: isTargeted)
        .animation(.easeOut(duration: 0.15), value: hovering)
        // il tratteggio scorre solo quando serve (hover o trascinamento), così a riposo l'app non ridisegna di continuo
        .onChange(of: active) { on in
            if on { withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { dashPhase = -24 } }
            else { withAnimation(.easeOut(duration: 0.2)) { dashPhase = 0 } }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { bounce = true }
        }
    }

    // MARK: caricata

    private func loaded(_ art: NSImage) -> some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 130)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.magenta.opacity(isTargeted ? 1 : 0.25), lineWidth: isTargeted ? 2.5 : 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

                Button { store.clearArtwork() } label: {
                    Image(systemName: "xmark")
                        .font(Theme.font(size: 9, .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Theme.magentaDeep))
                }
                .buttonStyle(.plain)
                .padding(6)
                .help("Rimuovi la grafica")
            }

            VStack(spacing: 2) {
                Text(store.artworkName ?? "")
                    .font(Theme.font(.callout, .bold))
                    .lineLimit(1).truncationMode(.middle)
                if let size = store.artworkSizeMM {
                    Text("\(Self.mm(size.width)) × \(Self.mm(size.height)) mm")
                        .font(Theme.font(.caption)).foregroundStyle(.secondary)
                } else if let px = store.artworkPixels {
                    Text("\(Int(px.width)) × \(Int(px.height)) px")
                        .font(Theme.font(.caption)).foregroundStyle(.secondary)
                    Text("misura reale non indicata nel file")
                        .font(Theme.font(.caption)).foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 8) {
                if store.artworkSizeMM != nil {
                    Button { store.fitItemToArtwork() } label: {
                        Label("Misura elemento", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(ChipButtonStyle(plate: .cyan))
                    .transition(.scale.combined(with: .opacity))
                }
                Button { store.chooseArtwork() } label: {
                    Label("Cambia", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(ChipButtonStyle(plate: .yellow))
            }
            .help("Imposta l'elemento sulla misura del file · cambia file (o trascinane un altro)")
        }
        .scaleEffect(isTargeted ? 1.02 : 1)
        .animation(Theme.spring, value: isTargeted)
    }
}

/// Velo a tutta finestra mentre si trascina un file: dice cosa succede al rilascio.
struct DropOverlay: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Theme.magenta.opacity(0.10))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.magenta, style: StrokeStyle(lineWidth: 4, dash: [14, 9]))
                .padding(14)
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(Theme.font(size: 54, .semibold))
                    .foregroundStyle(Theme.brandGradient)
                Text("Rilascia per impaginare")
                    .font(Theme.font(.title2, .heavy))
                Text("La grafica verrà ripetuta su tutto il foglio")
                    .foregroundStyle(.secondary)
            }
            .padding(30)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .scale(scale: 1.04)))
    }
}

/// Fronte-retro: interruttore e grafica del retro. Il PDF avrà due pagine, la seconda specchiata.
struct BackSideCard: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Fronte-retro", isOn: $store.duplex.animation(Theme.spring))
                .toggleStyle(.switch)
                .font(Theme.font(.callout, .semibold))
            if store.duplex {
                if let art = store.backArtwork {
                    HStack(spacing: 10) {
                        Image(nsImage: art)
                            .resizable().scaledToFit()
                            .frame(width: 56, height: 40)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.magenta.opacity(0.25)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Retro").font(Theme.font(.caption, .bold)).foregroundStyle(.secondary)
                            Text(store.backArtworkName ?? "").font(Theme.font(.callout, .bold))
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                        Button { store.chooseBackArtwork() } label: { Label("Cambia", systemImage: "arrow.triangle.2.circlepath") }
                            .buttonStyle(ChipButtonStyle(plate: .yellow))
                        Button { store.clearBackArtwork() } label: { Image(systemName: "xmark") }
                            .buttonStyle(ChipButtonStyle(plate: .magenta))
                            .help("Rimuovi il retro")
                    }
                } else {
                    Button { store.chooseBackArtwork() } label: { Label("Scegli il retro", systemImage: "photo.badge.plus") }
                        .buttonStyle(ChipButtonStyle(plate: .magenta))
                }
                Text("Il PDF ha due pagine: stampalo fronte-retro girando sul lato lungo. Il retro è già specchiato.")
                    .font(Theme.font(.caption)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.10)))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard store.duplex,
                  let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in store.loadBackArtwork(url: url) }
            }
            return true
        }
    }
}
