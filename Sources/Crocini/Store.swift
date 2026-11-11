import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class Store: ObservableObject {
    @Published var settings = LayoutSettings()
    @Published var artwork: NSImage?
    @Published var artworkName: String?
    /// Vero se la misura fisica del file è affidabile (PDF, o immagine con DPI reali).
    @Published var artworkHasRealSize = false
    @Published var artworkPixels: CGSize?
    @Published var message: String?

    /// Fronte-retro: seconda grafica per il retro; il PDF ha due pagine (la seconda è specchiata).
    @Published var duplex = false
    @Published var backArtwork: NSImage?
    @Published var backArtworkName: String?
    /// Quale lato mostra l'anteprima.
    @Published var previewBack = false
    /// Correzione del retro in mm (destra e basso positivi, come si vede la pagina del retro): compensa il disallineamento della stampante.
    @Published var backOffsetX = 0.0
    @Published var backOffsetY = 0.0

    /// Plotter di taglio: nel PDF di stampa i segni di registrazione, più un secondo PDF con la linea di taglio.
    @Published var plotter = false
    @Published var plotterRadius = 0.0

    @Published var userPresets: [LayoutPreset] = []

    private static let presetsKey = "userPresets.v1"

    init() {
        // Solo per le prove: --art file.png carica subito una grafica.
        if let i = CommandLine.arguments.firstIndex(of: "--art"), i + 1 < CommandLine.arguments.count {
            loadArtwork(url: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        }
        // Solo per le prove: --back file.png attiva il fronte-retro con quel retro.
        if let i = CommandLine.arguments.firstIndex(of: "--back"), i + 1 < CommandLine.arguments.count {
            duplex = true
            loadBackArtwork(url: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        }
        if let data = UserDefaults.standard.data(forKey: Self.presetsKey),
           let saved = try? JSONDecoder().decode([LayoutPreset].self, from: data) {
            userPresets = saved
        }
    }

    var result: LayoutResult { LayoutEngine.compute(settings) }

    func apply(_ preset: LayoutPreset) { settings = preset.settings }

    func saveCurrentAsPreset(named name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if let i = userPresets.firstIndex(where: { $0.name == clean }) {
            userPresets[i].settings = settings   // stesso nome: aggiorna
        } else {
            userPresets.append(LayoutPreset(name: clean, settings: settings))
        }
        persistPresets()
    }

    func deletePreset(_ preset: LayoutPreset) {
        userPresets.removeAll { $0.id == preset.id }
        persistPresets()
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(userPresets) {
            UserDefaults.standard.set(data, forKey: Self.presetsKey)
        }
    }

    func applyPreset(_ p: ItemPreset) {
        settings.itemWidth = p.width
        settings.itemHeight = p.height
    }

    static let artworkExtensions: Set<String> = ["png", "jpg", "jpeg", "pdf", "tif", "tiff", "heic", "gif", "webp"]

    func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .pdf, .tiff, .heic, .gif, .webP]
        panel.allowsMultipleSelection = false
        panel.message = L("Scegli la grafica da ripetere sul foglio")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadArtwork(url: url)
    }

    /// Carica la grafica da un file (scelto o trascinato). Ritorna false se non è utilizzabile.
    @discardableResult
    func loadArtwork(url: URL) -> Bool {
        guard Self.artworkExtensions.contains(url.pathExtension.lowercased()) else {
            message = L("«%@» non è una grafica supportata. Usa PNG, JPEG, PDF, TIFF, HEIC, GIF o WebP.", url.lastPathComponent)
            return false
        }
        guard let image = NSImage(contentsOf: url), image.size.width > 0 else {
            message = L("Non riesco ad aprire «%@».", url.lastPathComponent)
            return false
        }
        let (reliable, pixels) = Self.inspect(url)
        withAnimation(Theme.spring) {
            artwork = image
            artworkName = url.lastPathComponent
            artworkHasRealSize = reliable
            artworkPixels = pixels
        }
        return true
    }

    /// PDF: misura reale. Immagini: reale solo se il file dichiara dei DPI diversi da 72
    /// (72 è il valore "vuoto" di screenshot ed esportazioni, che renderebbe la misura inventata).
    private static func inspect(_ url: URL) -> (reliable: Bool, pixels: CGSize?) {
        if url.pathExtension.lowercased() == "pdf" { return (true, nil) }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return (false, nil) }
        let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        let dpi = (props[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 0
        return (dpi > 0 && abs(dpi - 72) > 0.5, w > 0 && h > 0 ? CGSize(width: w, height: h) : nil)
    }

    /// Dimensioni del file importato in mm (le immagini a 72 dpi virtuali, i PDF in punti).
    var artworkSizeMM: CGSize? {
        guard let a = artwork, artworkHasRealSize else { return nil }
        let k = 25.4 / 72.0
        return CGSize(width: a.size.width * k, height: a.size.height * k)
    }

    /// Imposta la misura dell'elemento da quella del file (tolta l'abbondanza se già inclusa).
    func fitItemToArtwork() {
        guard let size = artworkSizeMM else { return }
        let b = settings.bleedMode == .included ? 2 * settings.bleed : 0
        settings.itemWidth = max(1, (size.width - b).rounded(toPlaces: 1))
        settings.itemHeight = max(1, (size.height - b).rounded(toPlaces: 1))
    }

    func applyPaper(_ p: PaperSize) {
        settings.paperWidth = p.width
        settings.paperHeight = p.height
    }

    func chooseBackArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .pdf, .tiff, .heic, .gif, .webP]
        panel.allowsMultipleSelection = false
        panel.message = L("Scegli la grafica del retro")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadBackArtwork(url: url)
    }

    @discardableResult
    func loadBackArtwork(url: URL) -> Bool {
        guard Self.artworkExtensions.contains(url.pathExtension.lowercased()) else {
            message = L("«%@» non è una grafica supportata. Usa PNG, JPEG, PDF, TIFF, HEIC, GIF o WebP.", url.lastPathComponent)
            return false
        }
        guard let image = NSImage(contentsOf: url), image.size.width > 0 else {
            message = L("Non riesco ad aprire «%@».", url.lastPathComponent)
            return false
        }
        withAnimation(Theme.spring) { backArtwork = image; backArtworkName = url.lastPathComponent }
        return true
    }

    func clearBackArtwork() {
        withAnimation(Theme.spring) { backArtwork = nil; backArtworkName = nil; previewBack = false }
    }

    func clearArtwork() {
        withAnimation(Theme.spring) {
            artwork = nil
            artworkName = nil
            artworkHasRealSize = false
            artworkPixels = nil
        }
    }

    func exportPDF() {
        let r = result
        guard r.count > 0 else {
            message = L("L'elemento non entra nel foglio: riduci le misure o i margini.")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        if duplex, backArtwork == nil {
            message = L("Carica la grafica del retro, oppure spegni il fronte-retro.")
            return
        }
        panel.nameFieldStringValue = "Crocini \(fmt(settings.itemWidth))x\(fmt(settings.itemHeight))\(duplex ? " fronte-retro" : "").pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !PDFExporter.export(settings: settings, result: r, artwork: artwork,
                               backArtwork: duplex ? backArtwork : nil, duplex: duplex, backOffset: (backOffsetX, backOffsetY), registration: plotter, to: url) {
            message = L("Non sono riuscito a creare il PDF.")
            return
        }
        var files = [url]
        if plotter {
            // PDF di taglio accanto a quello di stampa; se esiste già un file con quel nome non lo sovrascrivo.
            let dir = url.deletingLastPathComponent(), base = url.deletingPathExtension().lastPathComponent
            var cut = dir.appendingPathComponent("\(base) fustella.pdf"), n = 2
            while FileManager.default.fileExists(atPath: cut.path) {
                cut = dir.appendingPathComponent("\(base) fustella \(n).pdf"); n += 1
            }
            if PlotterExporter.export(settings: settings, result: r, cornerRadius: plotterRadius, to: cut) {
                files.append(cut)
            } else {
                message = L("Non sono riuscito a creare il PDF di taglio.")
            }
        }
        NSWorkspace.shared.activateFileViewerSelecting(files)
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

extension Double {
    func rounded(toPlaces n: Int) -> Double {
        let f = pow(10.0, Double(n))
        return (self * f).rounded() / f
    }
}
