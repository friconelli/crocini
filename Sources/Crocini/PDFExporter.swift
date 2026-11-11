import AppKit
import SwiftUI

enum PDFExporter {
    static let pointsPerMM = 72.0 / 25.4

    /// Scrive un PDF con elementi, abbondanza e segni di taglio: una pagina, o due (fronte e retro) in fronte-retro.
    /// Il retro è specchiato in orizzontale perché le colonne combacino stampando fronte-retro sul lato lungo.
    /// Ritorna false se non riesce a creare il file.
    static func export(settings s: LayoutSettings, result r: LayoutResult, artwork: NSImage?,
                       backArtwork: NSImage? = nil, duplex: Bool = false, backOffset: (x: Double, y: Double) = (0, 0), registration: Bool = false, numbering: Numbering? = nil, to url: URL) -> Bool {
        let k = pointsPerMM
        var box = CGRect(x: 0, y: 0, width: s.pageWidth * k, height: s.pageHeight * k)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return false }

        let sheets = max(1, numbering?.sheets ?? 1)
        for sheet in 0..<sheets {
            page(ctx, box: box, s: s, r: r, artwork: artwork, back: false, registration: registration, numbering: numbering, sheet: sheet, duplex: duplex)
            if duplex {
                page(ctx, box: box, s: s, r: LayoutEngine.shifted(LayoutEngine.mirrored(r, pageWidth: s.pageWidth), dx: backOffset.x, dy: backOffset.y), artwork: backArtwork, back: true, registration: registration, numbering: numbering, sheet: sheet, duplex: duplex)
            }
        }
        ctx.closePDF()
        return true
    }

    private static func page(_ ctx: CGContext, box: CGRect, s: LayoutSettings, r: LayoutResult, artwork: NSImage?, back: Bool, registration: Bool, numbering: Numbering?, sheet: Int, duplex: Bool) {
        let k = pointsPerMM
        ctx.beginPDFPage(nil)
        ctx.translateBy(x: 0, y: box.height)
        ctx.scaleBy(x: k, y: -k) // millimetri, origine in alto a sinistra

        let gc = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc

        for (index, p) in r.placements.enumerated() {
            let g = LayoutEngine.geometry(s, placement: p, rotated: r.rotated, imageSize: artwork?.size ?? .zero)
            ctx.saveGState()
            ctx.translateBy(x: p.x + p.width / 2, y: p.y + p.height / 2)
            // La grafica gira di 90° dentro la propria cella; sul retro in senso opposto, così dopo il giro del foglio si legge dritta.
            if r.rotated { ctx.rotate(by: back ? -.pi / 2 : .pi / 2) }

            if g.flatBackground {
                ctx.setFillColor(NSColor(s.bleedColor.color).cgColor)
                ctx.fill(g.bleed)
            }
            if let artwork {
                ctx.saveGState()
                ctx.clip(to: g.artClip)
                artwork.draw(in: g.art, from: .zero, operation: .sourceOver, fraction: 1,
                             respectFlipped: true, hints: nil)
                ctx.restoreGState()
            }
            if let n = numbering, n.appliesTo(back: back, duplex: duplex) {
                let lw = r.rotated ? p.height : p.width, lh = r.rotated ? p.width : p.height
                let label = n.text(index: sheet * r.count + index)
                let str = NSAttributedString(string: label, attributes: [
                    .font: n.nsFont(size: n.sizeMM), .foregroundColor: NSColor(n.color.color)])
                let size = str.size()
                ctx.saveGState()
                ctx.translateBy(x: -lw / 2 + n.x, y: -lh / 2 + n.y)
                ctx.rotate(by: Double(n.rotation) * .pi / 180)
                str.draw(at: CGPoint(x: -size.width * n.align.unit, y: -size.height / 2))
                ctx.restoreGState()
            }
            ctx.restoreGState()
        }

        ctx.setStrokeColor(NSColor(s.markColor.color).cgColor)
        ctx.setLineWidth(s.markWidth)
        for seg in LayoutEngine.cropMarkSegments(s, r) {
            ctx.move(to: CGPoint(x: seg.x1, y: seg.y1))
            ctx.addLine(to: CGPoint(x: seg.x2, y: seg.y2))
        }
        ctx.strokePath()

        if registration {   // segni di registrazione per il plotter: quadrati neri negli angoli
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            for m in LayoutEngine.registrationMarks(s) { ctx.fill(m) }
        }

        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
    }
}
