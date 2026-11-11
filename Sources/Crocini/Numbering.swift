import AppKit
import SwiftUI

/// Numero progressivo stampato su ogni elemento (abbonamenti, biglietti numerati, tessere).
struct Numbering: Equatable {
    enum Side: String, CaseIterable, Identifiable {
        case front, back, both
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self { case .front: return "Fronte"; case .back: return "Retro"; case .both: return "Entrambi" }
        }
    }
    enum Align: String, CaseIterable, Identifiable {
        case leading, center, trailing
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self { case .leading: return "Sinistra"; case .center: return "Centro"; case .trailing: return "Destra" }
        }
        var unit: CGFloat { self == .leading ? 0 : (self == .center ? 0.5 : 1) }
    }

    var enabled = false
    var start = 1
    var step = 1
    /// Cifre minime, con zeri davanti (0 = nessuno).
    var digits = 3
    var prefix = ""
    var suffix = ""
    var family = "Helvetica Neue"
    var bold = true
    var sizePt = 10.0
    var color = RGB.black
    /// Posizione del punto di ancoraggio dall'angolo in alto a sinistra dell'elemento (a rifilo, elemento dritto), in mm.
    var x = 5.0
    var y = 5.0
    var align = Align.leading
    /// 0, 90, 180, 270 (in senso orario).
    var rotation = 0
    var side = Side.front
    /// Fogli da produrre: i numeri continuano da un foglio al successivo.
    var sheets = 1

    func text(index: Int) -> String {
        let n = start + step * index
        let body = digits > 0 ? String(format: "%0\(digits)d", n) : String(n)
        return prefix + body + suffix
    }

    var sizeMM: Double { sizePt * 25.4 / 72 }

    func nsFont(size: Double) -> NSFont {
        let fm = NSFontManager.shared
        return fm.font(withFamily: family, traits: bold ? .boldFontMask : [], weight: bold ? 9 : 5, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    func appliesTo(back: Bool, duplex: Bool) -> Bool {
        guard enabled else { return false }
        if !duplex { return !back }
        switch side { case .front: return !back; case .back: return back; case .both: return true }
    }
}
