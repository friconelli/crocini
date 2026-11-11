import SwiftUI
import AppKit

/// Tutte le misure sono in millimetri.
struct PaperSize: Identifiable, Hashable {
    let name: String
    let width: Double
    let height: Double
    var id: String { name }
    var title: String { L(name) }

    static let all: [PaperSize] = [
        .init(name: "A4", width: 210, height: 297),
        .init(name: "A3", width: 297, height: 420),
        .init(name: "SRA3", width: 320, height: 450),
        .init(name: "A5", width: 148, height: 210),
        .init(name: "Lettera", width: 215.9, height: 279.4),
    ]
}

struct ItemPreset: Identifiable, Hashable {
    let name: String
    let width: Double
    let height: Double
    var id: String { name }
    var title: String { L(name) }

    static let all: [ItemPreset] = [
        .init(name: "Biglietto da visita 85×55", width: 85, height: 55),
        .init(name: "Biglietto da visita 90×50", width: 90, height: 50),
        .init(name: "Cartolina 100×150", width: 100, height: 150),
        .init(name: "Segnalibro 50×150", width: 50, height: 150),
        .init(name: "Etichetta 50×50", width: 50, height: 50),
        .init(name: "Flyer DL 99×210", width: 99, height: 210),
        .init(name: "Flyer A6", width: 105, height: 148),
        .init(name: "Flyer A5", width: 148, height: 210),
        .init(name: "Locandina A4", width: 210, height: 297),
        .init(name: "Locandina A3", width: 297, height: 420),
    ]
}

enum RotationMode: String, CaseIterable, Identifiable, Codable {
    case auto = "Automatica"
    case never = "No"
    case always = "Sì"
    var id: String { rawValue }
    /// rawValue resta in italiano (è salvato nei preset); il testo mostrato è tradotto.
    var label: String { L(rawValue) }
}

/// Come trattare l'abbondanza rispetto alla grafica importata.
enum BleedMode: String, CaseIterable, Identifiable, Codable {
    case included = "La grafica ha già l'abbondanza"
    case flat = "Aggiungi con colore piatto"
    case stretch = "Aggiungi ingrandendo la grafica"
    var id: String { rawValue }
    var label: String { L(rawValue) }
}

/// Colore salvabile nei preset (Color di SwiftUI non è Codable).
struct RGB: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double

    static let white = RGB(r: 1, g: 1, b: 1)
    static let black = RGB(r: 0, g: 0, b: 0)

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    init(color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }

    /// Per i ColorPicker: legge e scrive un Color tenendo il valore RGB.
    static func binding(_ source: Binding<RGB>) -> Binding<Color> {
        Binding(get: { source.wrappedValue.color }, set: { source.wrappedValue = RGB(color: $0) })
    }
}

struct LayoutSettings: Equatable, Codable {
    // Foglio di stampa
    var paperWidth = 210.0
    var paperHeight = 297.0
    var landscape = false
    var margin = 10.0

    // Elemento da impaginare (misura finita, a rifilo)
    var itemWidth = 85.0
    var itemHeight = 55.0
    var rotation = RotationMode.auto
    var gap = 0.0

    // Abbondanza
    var bleed = 3.0
    var bleedMode = BleedMode.included
    var bleedColor = RGB.white

    // Segni di taglio
    var cropMarks = true
    var markLength = 4.0
    var markWidth = 0.1
    var markColor = RGB.black
    var markOffsetAuto = true
    var markOffsetValue = 3.0

    var pageWidth: Double { landscape ? paperHeight : paperWidth }
    var pageHeight: Double { landscape ? paperWidth : paperHeight }
    /// Distanza tra l'angolo di rifilo e l'inizio del segno di taglio.
    var markOffset: Double { markOffsetAuto ? max(bleed, 1.0) : markOffsetValue }
    /// Margine minimo perché i segni stiano dentro il foglio.
    var effectiveMargin: Double { cropMarks ? max(margin, markOffset + markLength + 1) : margin }
}

struct Placement: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct LayoutResult: Equatable {
    var placements: [Placement] = []
    var columns = 0
    var rows = 0
    var rotated = false
    var gridX = 0.0
    var gridY = 0.0
    var gridWidth = 0.0
    var gridHeight = 0.0
    var count: Int { placements.count }
}

/// Dove disegnare la grafica di un elemento. Coordinate in mm, centrate sull'elemento
/// e già nel sistema ruotato (se gli elementi sono ruotati, chi disegna ruota di 90° prima).
struct ArtworkGeometry {
    var trim: CGRect
    var bleed: CGRect
    var art: CGRect
    var artClip: CGRect
    var flatBackground: Bool
}

enum LayoutEngine {
    static func compute(_ s: LayoutSettings) -> LayoutResult {
        let straight = grid(s, itemW: s.itemWidth, itemH: s.itemHeight, rotated: false)
        let turned = grid(s, itemW: s.itemHeight, itemH: s.itemWidth, rotated: true)
        switch s.rotation {
        case .never: return straight
        case .always: return turned
        case .auto: return turned.count > straight.count ? turned : straight
        }
    }

    private static func grid(_ s: LayoutSettings, itemW: Double, itemH: Double, rotated: Bool) -> LayoutResult {
        guard itemW > 0, itemH > 0 else { return LayoutResult(rotated: rotated) }
        let m = s.effectiveMargin
        let usableW = s.pageWidth - 2 * m
        let usableH = s.pageHeight - 2 * m
        // 1e-9: evita che 3 × 70 mm "non entrino" in 210 per errori di virgola mobile.
        let cols = max(0, Int(floor((usableW + s.gap) / (itemW + s.gap) + 1e-9)))
        let rows = max(0, Int(floor((usableH + s.gap) / (itemH + s.gap) + 1e-9)))
        guard cols > 0, rows > 0 else { return LayoutResult(rotated: rotated) }

        let gridW = Double(cols) * itemW + Double(cols - 1) * s.gap
        let gridH = Double(rows) * itemH + Double(rows - 1) * s.gap
        let x0 = (s.pageWidth - gridW) / 2
        let y0 = (s.pageHeight - gridH) / 2

        var placements: [Placement] = []
        for r in 0..<rows {
            for c in 0..<cols {
                placements.append(Placement(
                    x: x0 + Double(c) * (itemW + s.gap),
                    y: y0 + Double(r) * (itemH + s.gap),
                    width: itemW, height: itemH))
            }
        }
        return LayoutResult(placements: placements, columns: cols, rows: rows, rotated: rotated,
                            gridX: x0, gridY: y0, gridWidth: gridW, gridHeight: gridH)
    }

    /// Rettangoli di rifilo, abbondanza e grafica per un elemento, in base alla modalità scelta.
    static func geometry(_ s: LayoutSettings, placement p: Placement, rotated: Bool, imageSize: CGSize) -> ArtworkGeometry {
        let lw = rotated ? p.height : p.width
        let lh = rotated ? p.width : p.height
        let trim = CGRect(x: -lw / 2, y: -lh / 2, width: lw, height: lh)
        let bleed = trim.insetBy(dx: -s.bleed, dy: -s.bleed)
        switch s.bleedMode {
        case .included, .stretch:
            return ArtworkGeometry(trim: trim, bleed: bleed, art: fill(imageSize, in: bleed),
                                   artClip: bleed, flatBackground: false)
        case .flat:
            return ArtworkGeometry(trim: trim, bleed: bleed, art: fill(imageSize, in: trim),
                                   artClip: trim, flatBackground: s.bleed > 0)
        }
    }

    /// Rettangolo in cui disegnare l'immagine perché riempia `rect` (ritaglio al bordo).
    static func fill(_ imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    /// Segmenti dei segni di taglio (coordinate in mm, origine in alto a sinistra).
    /// I segni stanno solo sul bordo della griglia: valgono per un taglio a ghigliottina.
    static func cropMarkSegments(_ s: LayoutSettings, _ r: LayoutResult) -> [(x1: Double, y1: Double, x2: Double, y2: Double)] {
        guard s.cropMarks, r.count > 0 else { return [] }
        let off = s.markOffset
        let len = s.markLength
        var xs: [Double] = []
        var ys: [Double] = []
        for p in r.placements {
            xs.append(contentsOf: [p.x, p.x + p.width])
            ys.append(contentsOf: [p.y, p.y + p.height])
        }
        xs = unique(xs)
        ys = unique(ys)
        let top = r.gridY, bottom = r.gridY + r.gridHeight
        let left = r.gridX, right = r.gridX + r.gridWidth

        var out: [(Double, Double, Double, Double)] = []
        for x in xs {
            out.append((x, top - off, x, top - off - len))
            out.append((x, bottom + off, x, bottom + off + len))
        }
        for y in ys {
            out.append((left - off, y, left - off - len, y))
            out.append((right + off, y, right + off + len, y))
        }
        return out
    }

    private static func unique(_ v: [Double]) -> [Double] {
        var out: [Double] = []
        for x in v.sorted() where !out.contains(where: { abs($0 - x) < 0.001 }) { out.append(x) }
        return out
    }
}

/// Una configurazione completa (foglio, elemento, abbondanza, segni), predefinita o salvata dall'utente.
struct LayoutPreset: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var settings: LayoutSettings
    /// I preset predefiniti si traducono; quelli dell'utente restano com'è (non hanno una traduzione).
    var title: String { L(name) }

    static let builtIn: [LayoutPreset] = [
        make("Biglietti da visita 85×55 su A4", paper: (210, 297), item: (85, 55)),
        make("Biglietti da visita 90×50 su A4", paper: (210, 297), item: (90, 50)),
        make("Cartoline 100×150 su A4", paper: (210, 297), item: (100, 150)),
        make("Segnalibri 50×150 su A4", paper: (210, 297), item: (50, 150)),
        make("Flyer A6 su A4", paper: (210, 297), item: (105, 148)),
        make("Flyer DL su A3", paper: (297, 420), item: (99, 210)),
        make("Flyer A5 su A3", paper: (297, 420), item: (148, 210)),
        make("Locandine A3 su SRA3", paper: (320, 450), item: (297, 420), margin: 6),
        make("Etichette 50×50 su A4 (senza abbondanza)", paper: (210, 297), item: (50, 50), bleed: 0),
    ]

    private static func make(_ name: String, paper: (Double, Double), item: (Double, Double),
                             bleed: Double = 3, margin: Double = 10) -> LayoutPreset {
        var s = LayoutSettings()
        s.paperWidth = paper.0; s.paperHeight = paper.1
        s.itemWidth = item.0; s.itemHeight = item.1
        s.bleed = bleed; s.margin = margin
        return LayoutPreset(id: stableID(name), name: name, settings: s)
    }

    /// ID fissi per i preset predefiniti, così la selezione resta riconoscibile tra un avvio e l'altro.
    private static func stableID(_ name: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, b) in name.utf8.enumerated() { bytes[i % 16] = bytes[i % 16] &* 31 &+ b }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// Preset dei soli segni di taglio.
struct MarkStyle: Identifiable, Hashable {
    let name: String
    let width: Double
    let length: Double
    var id: String { name }
    var title: String { L(name) }

    static let all: [MarkStyle] = [
        .init(name: "Standard (0,1 mm · 4 mm)", width: 0.1, length: 4),
        .init(name: "Sottili (0,05 mm · 3 mm)", width: 0.05, length: 3),
        .init(name: "Marcati (0,25 mm · 5 mm)", width: 0.25, length: 5),
        .init(name: "Lunghi (0,1 mm · 8 mm)", width: 0.1, length: 8),
    ]
}
