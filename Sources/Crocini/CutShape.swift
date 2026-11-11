import Foundation
import CoreGraphics

/// Forma di taglio personalizzata (la fustella) letta da un file SVG.
/// I punti sono normalizzati sul riquadro della forma (0…1, y verso il basso): al momento di usarla si adattano al rettangolo di ogni elemento.
struct CutShape: Equatable {
    enum Seg: Equatable {
        case move(CGPoint), line(CGPoint), curve(CGPoint, CGPoint, CGPoint), close
    }

    var name: String
    var segs: [Seg]
    /// Misura reale della forma in mm, come dichiarata dal file.
    var widthMM: Double
    var heightMM: Double

    /// Punti della forma dentro la cella di un elemento. `rotated`: la cella è girata di 90° (come la grafica).
    /// `cell` è il rettangolo del foglio occupato dall'elemento.
    func segments(in cell: CGRect, rotated: Bool) -> [Seg] {
        func map(_ n: CGPoint) -> CGPoint {
            if !rotated { return CGPoint(x: cell.minX + n.x * cell.width, y: cell.minY + n.y * cell.height) }
            // elemento logico di (cell.height × cell.width), ruotato di +90° attorno al centro
            let u = n.x * cell.height - cell.height / 2, v = n.y * cell.width - cell.width / 2
            return CGPoint(x: cell.midX - v, y: cell.midY + u)
        }
        return segs.map {
            switch $0 {
            case .move(let p): return .move(map(p))
            case .line(let p): return .line(map(p))
            case .curve(let a, let b, let c): return .curve(map(a), map(b), map(c))
            case .close: return .close
            }
        }
    }

    // MARK: lettura SVG

    static func load(url: URL) -> CutShape? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let reader = SVGReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() || !reader.paths.isEmpty, !reader.paths.isEmpty else { return nil }
        return reader.makeShape(name: url.lastPathComponent)
    }
}

// MARK: - parser

private struct Matrix {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0
    func concat(_ m: Matrix) -> Matrix {   // self × m (m si applica per primo)
        Matrix(a: a * m.a + c * m.b, b: b * m.a + d * m.b, c: a * m.c + c * m.d, d: b * m.c + d * m.d,
               e: a * m.e + c * m.f + e, f: b * m.e + d * m.f + f)
    }
    func apply(_ p: CGPoint) -> CGPoint { CGPoint(x: a * p.x + c * p.y + e, y: b * p.x + d * p.y + f) }

    static func parse(_ s: String) -> Matrix {
        var m = Matrix()
        let scanner = Scanner(string: s)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n\t\r")
        while !scanner.isAtEnd {
            guard let name = scanner.scanUpToString("("), scanner.scanString("(") != nil,
                  let body = scanner.scanUpToString(")") else { break }
            _ = scanner.scanString(")")
            let n = body.split(whereSeparator: { " ,\n\t".contains($0) }).compactMap { Double($0) }
            var t = Matrix()
            switch name.trimmingCharacters(in: .whitespaces) {
            case "translate": t.e = n.first ?? 0; t.f = n.count > 1 ? n[1] : 0
            case "scale": t.a = n.first ?? 1; t.d = n.count > 1 ? n[1] : (n.first ?? 1)
            case "rotate":
                let r = (n.first ?? 0) * .pi / 180
                t = Matrix(a: cos(r), b: sin(r), c: -sin(r), d: cos(r), e: 0, f: 0)
                if n.count >= 3 {
                    let pre = Matrix(e: n[1], f: n[2]), post = Matrix(e: -n[1], f: -n[2])
                    t = pre.concat(t).concat(post)
                }
            case "matrix": if n.count == 6 { t = Matrix(a: n[0], b: n[1], c: n[2], d: n[3], e: n[4], f: n[5]) }
            default: break
            }
            m = m.concat(t)
        }
        return m
    }
}

private final class SVGReader: NSObject, XMLParserDelegate {
    var paths: [[CutShape.Seg]] = []          // in unità utente dell'SVG, già trasformate
    private var stack: [Matrix] = [Matrix()]
    private var viewBox: [Double]?
    private var widthAttr: String?, heightAttr: String?
    private var rootSeen = false

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        if name == "svg", !rootSeen {
            rootSeen = true
            viewBox = a["viewBox"]?.split(whereSeparator: { " ,".contains($0) }).compactMap { Double($0) }
            widthAttr = a["width"]; heightAttr = a["height"]
        }
        var m = stack.last ?? Matrix()
        if let t = a["transform"] { m = m.concat(Matrix.parse(t)) }
        stack.append(m)
        if a["display"] == "none" { return }

        func num(_ k: String) -> Double { Double((a[k] ?? "0").trimmingCharacters(in: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz% "))) ?? 0 }
        var segs: [CutShape.Seg] = []
        switch name {
        case "path": segs = PathParser.parse(a["d"] ?? "")
        case "rect":
            let x = num("x"), y = num("y"), w = num("width"), h = num("height")
            var rx = num("rx"), ry = num("ry")
            if a["rx"] != nil && a["ry"] == nil { ry = rx } else if a["ry"] != nil && a["rx"] == nil { rx = ry }
            rx = min(rx, w / 2); ry = min(ry, h / 2)
            if w > 0, h > 0 {
                if rx > 0 && ry > 0 {
                    let kx = rx * 0.5523, ky = ry * 0.5523
                    segs = [.move(CGPoint(x: x + rx, y: y)), .line(CGPoint(x: x + w - rx, y: y)),
                            .curve(CGPoint(x: x + w - rx + kx, y: y), CGPoint(x: x + w, y: y + ry - ky), CGPoint(x: x + w, y: y + ry)),
                            .line(CGPoint(x: x + w, y: y + h - ry)),
                            .curve(CGPoint(x: x + w, y: y + h - ry + ky), CGPoint(x: x + w - rx + kx, y: y + h), CGPoint(x: x + w - rx, y: y + h)),
                            .line(CGPoint(x: x + rx, y: y + h)),
                            .curve(CGPoint(x: x + rx - kx, y: y + h), CGPoint(x: x, y: y + h - ry + ky), CGPoint(x: x, y: y + h - ry)),
                            .line(CGPoint(x: x, y: y + ry)),
                            .curve(CGPoint(x: x, y: y + ry - ky), CGPoint(x: x + rx - kx, y: y), CGPoint(x: x + rx, y: y)), .close]
                } else {
                    segs = [.move(CGPoint(x: x, y: y)), .line(CGPoint(x: x + w, y: y)), .line(CGPoint(x: x + w, y: y + h)), .line(CGPoint(x: x, y: y + h)), .close]
                }
            }
        case "circle": segs = Self.ellipse(cx: num("cx"), cy: num("cy"), rx: num("r"), ry: num("r"))
        case "ellipse": segs = Self.ellipse(cx: num("cx"), cy: num("cy"), rx: num("rx"), ry: num("ry"))
        case "polygon", "polyline":
            let n = (a["points"] ?? "").split(whereSeparator: { " ,\n\t".contains($0) }).compactMap { Double($0) }
            var pts: [CGPoint] = []
            var i = 0
            while i + 1 < n.count { pts.append(CGPoint(x: n[i], y: n[i + 1])); i += 2 }
            if pts.count >= 2 {
                segs = [.move(pts[0])] + pts.dropFirst().map { .line($0) }
                if name == "polygon" { segs.append(.close) }
            }
        default: break
        }
        if !segs.isEmpty { paths.append(segs.map { Self.apply(m, $0) }) }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if stack.count > 1 { stack.removeLast() }
    }

    private static func apply(_ m: Matrix, _ s: CutShape.Seg) -> CutShape.Seg {
        switch s {
        case .move(let p): return .move(m.apply(p))
        case .line(let p): return .line(m.apply(p))
        case .curve(let a, let b, let c): return .curve(m.apply(a), m.apply(b), m.apply(c))
        case .close: return .close
        }
    }

    private static func ellipse(cx: Double, cy: Double, rx: Double, ry: Double) -> [CutShape.Seg] {
        guard rx > 0, ry > 0 else { return [] }
        let kx = rx * 0.5523, ky = ry * 0.5523
        return [.move(CGPoint(x: cx + rx, y: cy)),
                .curve(CGPoint(x: cx + rx, y: cy + ky), CGPoint(x: cx + kx, y: cy + ry), CGPoint(x: cx, y: cy + ry)),
                .curve(CGPoint(x: cx - kx, y: cy + ry), CGPoint(x: cx - rx, y: cy + ky), CGPoint(x: cx - rx, y: cy)),
                .curve(CGPoint(x: cx - rx, y: cy - ky), CGPoint(x: cx - kx, y: cy - ry), CGPoint(x: cx, y: cy - ry)),
                .curve(CGPoint(x: cx + kx, y: cy - ry), CGPoint(x: cx + rx, y: cy - ky), CGPoint(x: cx + rx, y: cy)), .close]
    }

    /// Millimetri per unità utente, dalle dimensioni dichiarate (se mancano: 1 unità = 1 px a 96 dpi).
    private func mmPerUnit() -> Double {
        func mm(_ s: String?) -> Double? {
            guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
            let units: [(String, Double)] = [("mm", 1), ("cm", 10), ("in", 25.4), ("pt", 25.4 / 72), ("pc", 25.4 / 6), ("px", 25.4 / 96)]
            for (u, k) in units where s.hasSuffix(u) { return Double(s.dropLast(u.count).trimmingCharacters(in: .whitespaces)).map { $0 * k } }
            return Double(s).map { $0 * 25.4 / 96 }
        }
        if let vb = viewBox, vb.count == 4, vb[2] > 0 {
            if let w = mm(widthAttr) { return w / vb[2] }
            if let h = mm(heightAttr), vb[3] > 0 { return h / vb[3] }
        }
        return 25.4 / 96
    }

    func makeShape(name: String) -> CutShape? {
        // riquadro della forma: si campionano le curve, non i punti di controllo
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        func add(_ p: CGPoint) { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        for path in paths {
            var cur = CGPoint.zero
            for s in path {
                switch s {
                case .move(let p), .line(let p): add(p); cur = p
                case .curve(let a, let b, let c):
                    for i in 1...16 {
                        let t = Double(i) / 16, u = 1 - t
                        add(CGPoint(x: u*u*u*cur.x + 3*u*u*t*a.x + 3*u*t*t*b.x + t*t*t*c.x,
                                    y: u*u*u*cur.y + 3*u*u*t*a.y + 3*u*t*t*b.y + t*t*t*c.y))
                    }
                    cur = c
                case .close: break
                }
            }
        }
        let w = maxX - minX, h = maxY - minY
        guard w > 0.0001, h > 0.0001, w.isFinite, h.isFinite else { return nil }
        func n(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - minX) / w, y: (p.y - minY) / h) }
        let segs: [CutShape.Seg] = paths.flatMap { $0 }.map {
            switch $0 {
            case .move(let p): return .move(n(p))
            case .line(let p): return .line(n(p))
            case .curve(let a, let b, let c): return .curve(n(a), n(b), n(c))
            case .close: return .close
            }
        }
        let k = mmPerUnit()
        return CutShape(name: name, segs: segs, widthMM: w * k, heightMM: h * k)
    }
}

/// Dati di un attributo `d` di un tracciato SVG (M L H V C S Q T A Z, maiuscoli e minuscoli).
private enum PathParser {
    static func parse(_ d: String) -> [CutShape.Seg] {
        var out: [CutShape.Seg] = []
        let chars = Array(d.unicodeScalars)
        var i = 0
        var cur = CGPoint.zero, start = CGPoint.zero
        var lastC: CGPoint?, lastQ: CGPoint?
        var cmd: Character = " "

        func skip() { while i < chars.count, " ,\n\t\r".unicodeScalars.contains(chars[i]) { i += 1 } }
        func number() -> Double? {
            skip()
            var s = ""
            var seenDot = false, seenExp = false
            while i < chars.count {
                let c = Character(chars[i])
                if c.isNumber { s.append(c) }
                else if c == "." { if seenDot || seenExp { break }; seenDot = true; s.append(c) }
                else if (c == "-" || c == "+") && (s.isEmpty || s.last == "e" || s.last == "E") { s.append(c) }
                else if (c == "e" || c == "E") && !seenExp && !s.isEmpty { seenExp = true; s.append(c) }
                else { break }
                i += 1
            }
            return Double(s)
        }
        func flag() -> Bool? { skip(); guard i < chars.count else { return nil }; let c = Character(chars[i]); i += 1; return c == "1" }

        while true {
            skip()
            guard i < chars.count else { break }
            let c = Character(chars[i])
            if c.isLetter { cmd = c; i += 1 }
            else if cmd == " " { break }
            let rel = cmd.isLowercase
            let up = Character(cmd.uppercased())
            func pt(_ x: Double, _ y: Double) -> CGPoint { rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y) }
            switch up {
            case "Z":
                out.append(.close); cur = start; lastC = nil; lastQ = nil
                cmd = " "   // dopo Z serve un nuovo comando
            case "M":
                guard let x = number(), let y = number() else { return out }
                cur = pt(x, y); start = cur; out.append(.move(cur)); lastC = nil; lastQ = nil
                cmd = rel ? "l" : "L"
            case "L":
                guard let x = number(), let y = number() else { return out }
                cur = pt(x, y); out.append(.line(cur)); lastC = nil; lastQ = nil
            case "H":
                guard let x = number() else { return out }
                cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y); out.append(.line(cur)); lastC = nil; lastQ = nil
            case "V":
                guard let y = number() else { return out }
                cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y); out.append(.line(cur)); lastC = nil; lastQ = nil
            case "C":
                guard let x1 = number(), let y1 = number(), let x2 = number(), let y2 = number(), let x = number(), let y = number() else { return out }
                let a = pt(x1, y1), b = pt(x2, y2), e = pt(x, y)
                out.append(.curve(a, b, e)); cur = e; lastC = b; lastQ = nil
            case "S":
                guard let x2 = number(), let y2 = number(), let x = number(), let y = number() else { return out }
                let a = lastC.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let b = pt(x2, y2), e = pt(x, y)
                out.append(.curve(a, b, e)); cur = e; lastC = b; lastQ = nil
            case "Q", "T":
                var q: CGPoint
                var e: CGPoint
                if up == "Q" {
                    guard let x1 = number(), let y1 = number(), let x = number(), let y = number() else { return out }
                    q = pt(x1, y1); e = pt(x, y)
                } else {
                    guard let x = number(), let y = number() else { return out }
                    q = lastQ.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                    e = pt(x, y)
                }
                let a = CGPoint(x: cur.x + 2.0 / 3 * (q.x - cur.x), y: cur.y + 2.0 / 3 * (q.y - cur.y))
                let b = CGPoint(x: e.x + 2.0 / 3 * (q.x - e.x), y: e.y + 2.0 / 3 * (q.y - e.y))
                out.append(.curve(a, b, e)); cur = e; lastQ = q; lastC = nil
            case "A":
                guard let rx = number(), let ry = number(), let rot = number(), let fa = flag(), let fs = flag(), let x = number(), let y = number() else { return out }
                let e = pt(x, y)
                out.append(contentsOf: arc(from: cur, rx: abs(rx), ry: abs(ry), phi: rot, large: fa, sweep: fs, to: e))
                cur = e; lastC = nil; lastQ = nil
            default:
                return out
            }
        }
        return out
    }

    /// Arco ellittico SVG → curve di Bézier cubiche.
    private static func arc(from p0: CGPoint, rx rxIn: Double, ry ryIn: Double, phi: Double, large: Bool, sweep: Bool, to p1: CGPoint) -> [CutShape.Seg] {
        guard p0 != p1 else { return [] }
        var rx = rxIn, ry = ryIn
        guard rx > 0, ry > 0 else { return [.line(p1)] }
        let phiR = phi * .pi / 180, cp = cos(phiR), sp = sin(phiR)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cp * dx + sp * dy, y1 = -sp * dx + cp * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = den == 0 ? 0 : sqrt(max(0, num / den))
        if large == sweep { coef = -coef }
        let cxp = coef * rx * y1 / ry, cyp = -coef * ry * x1 / rx
        let cx = cp * cxp - sp * cyp + (p0.x + p1.x) / 2, cy = sp * cxp + cp * cyp + (p0.y + p1.y) / 2
        func ang(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy); return a
        }
        let th1 = ang(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
        var dth = ang((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
        if !sweep && dth > 0 { dth -= 2 * .pi } else if sweep && dth < 0 { dth += 2 * .pi }
        let n = max(1, Int(ceil(abs(dth) / (.pi / 2) - 1e-9)))
        let step = dth / Double(n)
        let t = 4.0 / 3 * tan(step / 4)
        var out: [CutShape.Seg] = []
        var a = th1
        func point(_ a: Double, _ dx: Double = 0) -> CGPoint {
            let ex = rx * cos(a), ey = ry * sin(a)
            return CGPoint(x: cp * ex - sp * ey + cx, y: sp * ex + cp * ey + cy)
        }
        func deriv(_ a: Double) -> CGPoint {
            let ex = -rx * sin(a), ey = ry * cos(a)
            return CGPoint(x: cp * ex - sp * ey, y: sp * ex + cp * ey)
        }
        for _ in 0..<n {
            let b = a + step
            let pa = point(a), pb = point(b), da = deriv(a), db = deriv(b)
            out.append(.curve(CGPoint(x: pa.x + t * da.x, y: pa.y + t * da.y), CGPoint(x: pb.x - t * db.x, y: pb.y - t * db.y), pb))
            a = b
        }
        return out
    }
}
