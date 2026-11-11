import Foundation
import CoreGraphics

/// PDF per il plotter di taglio: solo la linea di taglio e i segni di registrazione, nella stessa posizione del PDF di stampa.
/// La linea è il colore spot «CutContour» (magenta 100% come anteprima), che Summa GoSign, Roland VersaWorks, Graphtec Studio
/// e la maggior parte dei RIP riconoscono come percorso di taglio. Il PDF è scritto a mano perché CoreGraphics non crea colori spot.
enum PlotterExporter {
    static let k = 72.0 / 25.4

    static func export(settings s: LayoutSettings, result r: LayoutResult, cornerRadius: Double, shape: CutShape? = nil, to url: URL) -> Bool {
        guard r.count > 0 else { return false }
        let H = s.pageHeight
        func f(_ v: Double) -> String { String(format: "%.3f", v) }
        func X(_ x: Double) -> String { f(x * k) }
        func Y(_ y: Double) -> String { f((H - y) * k) }

        var c = ""
        // Linea di taglio (colore spot CutContour, 0,25 pt)
        c += "/CS1 CS 1 SCN 0.25 w 1 J 1 j\n"
        let radius = max(0, cornerRadius)
        if let shape {
            // Forma personalizzata: una per elemento, adattata al suo rettangolo (e girata se gli elementi sono ruotati)
            for p in r.placements {
                let cell = CGRect(x: p.x, y: p.y, width: p.width, height: p.height)
                for seg in shape.segments(in: cell, rotated: r.rotated) {
                    switch seg {
                    case .move(let q): c += "\(X(q.x)) \(Y(q.y)) m "
                    case .line(let q): c += "\(X(q.x)) \(Y(q.y)) l "
                    case .curve(let a, let b, let e): c += "\(X(a.x)) \(Y(a.y)) \(X(b.x)) \(Y(b.y)) \(X(e.x)) \(Y(e.y)) c "
                    case .close: c += "h "
                    }
                }
                c += "S\n"
            }
        } else if s.gap < 0.001 && radius < 0.001 {
            // Elementi attaccati e angoli vivi: una sola linea per ogni lato di rifilo, tutta la griglia, senza tagli doppi.
            let xs = unique(r.placements.flatMap { [$0.x, $0.x + $0.width] })
            let ys = unique(r.placements.flatMap { [$0.y, $0.y + $0.height] })
            for x in xs { c += "\(X(x)) \(Y(r.gridY)) m \(X(x)) \(Y(r.gridY + r.gridHeight)) l S\n" }
            for y in ys { c += "\(X(r.gridX)) \(Y(y)) m \(X(r.gridX + r.gridWidth)) \(Y(y)) l S\n" }
        } else {
            for p in r.placements {
                let rad = min(radius, p.width / 2, p.height / 2)
                let x0 = p.x, y0 = p.y, x1 = p.x + p.width, y1 = p.y + p.height
                if rad < 0.001 {
                    c += "\(X(x0)) \(Y(y1)) \(f(p.width * k)) \(f(p.height * k)) re S\n"
                } else {
                    let b = rad * 0.5523
                    c += "\(X(x0 + rad)) \(Y(y0)) m \(X(x1 - rad)) \(Y(y0)) l "
                    c += "\(X(x1 - rad + b)) \(Y(y0)) \(X(x1)) \(Y(y0 + rad - b)) \(X(x1)) \(Y(y0 + rad)) c "
                    c += "\(X(x1)) \(Y(y1 - rad)) l "
                    c += "\(X(x1)) \(Y(y1 - rad + b)) \(X(x1 - rad + b)) \(Y(y1)) \(X(x1 - rad)) \(Y(y1)) c "
                    c += "\(X(x0 + rad)) \(Y(y1)) l "
                    c += "\(X(x0 + rad - b)) \(Y(y1)) \(X(x0)) \(Y(y1 - rad + b)) \(X(x0)) \(Y(y1 - rad)) c "
                    c += "\(X(x0)) \(Y(y0 + rad)) l "
                    c += "\(X(x0)) \(Y(y0 + rad - b)) \(X(x0 + rad - b)) \(Y(y0)) \(X(x0 + rad)) \(Y(y0)) c h S\n"
                }
            }
        }
        // Segni di registrazione: quadrati neri (K 100%), identici a quelli del PDF di stampa
        c += "0 0 0 1 k\n"
        for m in LayoutEngine.registrationMarks(s) {
            c += "\(X(m.minX)) \(Y(m.maxY)) \(f(m.width * k)) \(f(m.height * k)) re f\n"
        }

        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(f(s.pageWidth * k)) \(f(H * k))] /Resources << /ColorSpace << /CS1 5 0 R >> >> /Contents 4 0 R >>",
            "<< /Length \(c.utf8.count) >>\nstream\n\(c)endstream",
            "[/Separation /CutContour /DeviceCMYK 6 0 R]",
            "<< /FunctionType 2 /Domain [0 1] /C0 [0 0 0 0] /C1 [0 1 0 0] /N 1 >>",
        ]
        var data = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = []
        for (i, body) in objects.enumerated() {
            offsets.append(data.count)
            data.append(Data("\(i + 1) 0 obj\n\(body)\nendobj\n".utf8))
        }
        let xref = data.count
        var tail = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for o in offsets { tail += String(format: "%010d 00000 n \n", o) }
        tail += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        data.append(Data(tail.utf8))
        do { try data.write(to: url, options: .atomic); return true } catch { return false }
    }

    private static func unique(_ v: [Double]) -> [Double] {
        var out: [Double] = []
        for x in v.sorted() where !out.contains(where: { abs($0 - x) < 0.001 }) { out.append(x) }
        return out
    }
}
