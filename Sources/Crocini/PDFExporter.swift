import AppKit
import SwiftUI

enum PDFExporter {
    static let pointsPerMM = 72.0 / 25.4

    /// Scrive un PDF a una pagina con elementi, abbondanza e segni di taglio.
    /// Ritorna false se non riesce a creare il file.
    static func export(settings s: LayoutSettings, result r: LayoutResult, artwork: NSImage?, to url: URL) -> Bool {
        let k = pointsPerMM
        var box = CGRect(x: 0, y: 0, width: s.pageWidth * k, height: s.pageHeight * k)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return false }

        ctx.beginPDFPage(nil)
        ctx.translateBy(x: 0, y: box.height)
        ctx.scaleBy(x: k, y: -k) // millimetri, origine in alto a sinistra

        let gc = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc

        for p in r.placements {
            let g = LayoutEngine.geometry(s, placement: p, rotated: r.rotated, imageSize: artwork?.size ?? .zero)
            ctx.saveGState()
            ctx.translateBy(x: p.x + p.width / 2, y: p.y + p.height / 2)
            if r.rotated { ctx.rotate(by: .pi / 2) } // la grafica gira di 90° dentro la propria cella

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
            ctx.restoreGState()
        }

        ctx.setStrokeColor(NSColor(s.markColor.color).cgColor)
        ctx.setLineWidth(s.markWidth)
        for seg in LayoutEngine.cropMarkSegments(s, r) {
            ctx.move(to: CGPoint(x: seg.x1, y: seg.y1))
            ctx.addLine(to: CGPoint(x: seg.x2, y: seg.y2))
        }
        ctx.strokePath()

        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
        return true
    }
}
