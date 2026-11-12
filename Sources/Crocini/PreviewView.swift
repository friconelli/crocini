import SwiftUI

/// Anteprima del foglio con zoom e spostamento come negli editor grafici.
/// Quando la disposizione cambia gli elementi "saltano" dentro uno dopo l'altro.
struct PreviewView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var viewport: ViewportState
    @State private var progress = 1.0

    var body: some View {
        let s = store.settings
        let showBack = store.duplex && store.previewBack
        let r = showBack ? LayoutEngine.shifted(LayoutEngine.mirrored(store.result, pageWidth: s.pageWidth), dx: store.backOffsetX, dy: store.backOffsetY) : store.result
        let page = CGSize(width: s.pageWidth, height: s.pageHeight)
        GeometryReader { geo in
            ZStack {
                PreviewCanvas(progress: progress, zoom: viewport.zoom, offset: viewport.offset,
                              s: s, r: r, artwork: showBack ? store.backArtwork : store.artwork, back: showBack, registration: store.plotter && store.plotterProfile.drawsMarks ? store.registrationStyle : nil,
                              shape: store.plotter ? store.cutShape : nil,
                              numbering: store.numbering.appliesTo(back: showBack, duplex: store.duplex) ? store.numbering : nil)
                if r.count == 0 { EmptyHint() }
                if let m = viewport.marquee { MarqueeView(rect: m) }
                InteractionLayer(viewport: viewport, page: page)
                if store.duplex {
                    Picker("", selection: $store.previewBack.animation(Theme.spring)) {
                        Text("Fronte").tag(false)
                        Text("Retro").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                    .padding(6)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 18)
                }
                ZoomBar(viewport: viewport, viewSize: geo.size, page: page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 18)
            }
        }
        .background(PaperBackdrop().ignoresSafeArea())
        .clipped()
        .onChange(of: r) { _ in replay() }
        .onChange(of: store.artworkName) { _ in replay() }
        .onChange(of: store.backArtworkName) { _ in replay() }
        .onChange(of: store.previewBack) { _ in replay() }
        .onChange(of: store.duplex) { on in if !on { store.previewBack = false } }
        .onChange(of: s.bleedMode) { _ in replay() }
    }

    private func replay() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { progress = 0 }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.6)) { progress = 1 }
        }
    }
}

/// Sfondo: carta chiara con un retino di punti C M Y che sfuma verso l'angolo in alto a destra.
private struct PaperBackdrop: View {
    var body: some View {
        ZStack {
            Theme.canvasBackground
            HalftoneBackdrop()
        }
    }
}

private struct EmptyHint: View {
    @State private var pulse = false
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "scissors")
                .font(Theme.font(size: 34, .bold))
                .foregroundStyle(Theme.brandGradient)
                .scaleEffect(pulse ? 1.12 : 0.94)
                .rotationEffect(.degrees(pulse ? 8 : -8))
            Text("L'elemento non entra nel foglio")
                .font(Theme.font(.headline))
            Text("Riduci le misure, i margini o l'abbondanza.")
                .font(Theme.font(.callout)).foregroundStyle(.secondary)
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

/// View animabile: SwiftUI interpola progresso, zoom e posizione a ogni fotogramma e ridisegna il Canvas.
private struct PreviewCanvas: View, Animatable {
    var progress: Double
    var zoom: CGFloat
    var offset: CGSize
    let s: LayoutSettings
    let r: LayoutResult
    let artwork: NSImage?
    var back = false
    var registration: RegistrationStyle?
    var shape: CutShape?
    var numbering: Numbering?

    var animatableData: AnimatablePair<Double, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get { .init(progress, .init(zoom, .init(offset.width, offset.height))) }
        set {
            progress = newValue.first
            zoom = newValue.second.first
            offset = CGSize(width: newValue.second.second.first, height: newValue.second.second.second)
        }
    }

    var body: some View {
        Canvas { ctx, size in draw(&ctx, size) }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let page = CGSize(width: s.pageWidth, height: s.pageHeight)
        let scale = ViewportState.fitScale(view: size, page: page) * zoom
        // Origine del foglio: centro della vista + spostamento, meno metà foglio.
        ctx.translateBy(x: size.width / 2 + offset.width - page.width * scale / 2,
                        y: size.height / 2 + offset.height - page.height * scale / 2)

        let paper = Path(CGRect(x: 0, y: 0, width: page.width * scale, height: page.height * scale))
        ctx.drawLayer { l in
            l.addFilter(.shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 8))
            l.addFilter(.shadow(color: Theme.magenta.opacity(0.12), radius: 30, x: 0, y: 12))
            l.fill(paper, with: .color(.white))
        }

        let n = max(r.count, 1)
        for (i, p) in r.placements.enumerated() {
            // Ogni elemento parte un attimo dopo il precedente.
            let t = min(1, max(0, progress * 1.6 - Double(i) / Double(n) * 0.6))
            let eased = 1 - pow(1 - t, 3)
            let pop = 0.82 + 0.18 * eased
            let g = LayoutEngine.geometry(s, placement: p, rotated: r.rotated,
                                          imageSize: artwork?.size ?? .zero)
            var cell = ctx
            cell.opacity = eased
            cell.translateBy(x: (p.x + p.width / 2) * scale, y: (p.y + p.height / 2) * scale)
            if r.rotated { cell.rotate(by: .degrees(back ? -90 : 90)) }
            cell.scaleBy(x: scale * pop, y: scale * pop) // da qui in poi si lavora in mm

            if g.flatBackground {
                cell.fill(Path(g.bleed), with: .color(s.bleedColor.color))
            }
            if let artwork {
                var inner = cell
                inner.clip(to: Path(g.artClip))
                inner.draw(Image(nsImage: artwork), in: g.art)
            } else {
                cell.fill(Path(g.trim), with: .color(Theme.magenta.opacity(0.10)))
            }

            var lines = ctx
            lines.opacity = eased
            if s.bleed > 0 {
                lines.stroke(rect(g.bleed, p, pop, scale),
                             with: .color(Theme.magenta.opacity(0.65)),
                             style: StrokeStyle(lineWidth: 0.6, dash: [3, 2]))
            }
            if let shape {
                lines.stroke(shapePath(shape, p, pop, scale), with: .color(Theme.cyan.opacity(0.9)), lineWidth: 0.8)
            } else {
                lines.stroke(rect(g.trim, p, pop, scale), with: .color(Theme.cyan.opacity(0.9)), lineWidth: 0.6)
            }
            if let n = numbering {
                let lw = r.rotated ? p.height : p.width, lh = r.rotated ? p.width : p.height
                let label = n.text(index: i)
                var t = cell
                t.translateBy(x: -lw / 2 + n.x, y: -lh / 2 + n.y)
                t.rotate(by: .degrees(Double(n.rotation)))
                let font = Font(n.nsFont(size: n.sizeMM) as CTFont)
                t.draw(Text(label).font(font).foregroundColor(n.color.color), at: .zero,
                       anchor: UnitPoint(x: n.align.unit, y: 0.5))
            }
        }

        var marks = Path()
        for seg in LayoutEngine.cropMarkSegments(s, r) {
            marks.move(to: CGPoint(x: seg.x1 * scale, y: seg.y1 * scale))
            marks.addLine(to: CGPoint(x: seg.x2 * scale, y: seg.y2 * scale))
        }
        if let registration {
            for m in LayoutEngine.registrationMarks(s, style: registration) {
                ctx.fill(Path(CGRect(x: m.minX * scale, y: m.minY * scale, width: m.width * scale, height: m.height * scale)), with: .color(.black))
            }
        }
        var m = ctx
        m.opacity = min(1, max(0, progress * 2 - 0.6))
        // Spessore reale in anteprima, ma mai sotto mezzo pixel per restare visibili.
        m.stroke(marks, with: .color(s.markColor.color), lineWidth: max(0.5, s.markWidth * scale))
    }

    /// La forma di taglio personalizzata dentro la cella di un elemento, con lo stesso "salto" dell'elemento.
    private func shapePath(_ shape: CutShape, _ p: Placement, _ pop: Double, _ scale: CGFloat) -> Path {
        let cx = (p.x + p.width / 2), cy = (p.y + p.height / 2)
        func tf(_ q: CGPoint) -> CGPoint {
            CGPoint(x: (cx + (q.x - cx) * pop) * scale, y: (cy + (q.y - cy) * pop) * scale)
        }
        var path = Path()
        for seg in shape.segments(in: CGRect(x: p.x, y: p.y, width: p.width, height: p.height), rotated: r.rotated) {
            switch seg {
            case .move(let q): path.move(to: tf(q))
            case .line(let q): path.addLine(to: tf(q))
            case .curve(let a, let b, let e): path.addCurve(to: tf(e), control1: tf(a), control2: tf(b))
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    /// Rettangolo locale (centrato, eventualmente ruotato) riportato in coordinate di foglio scalate.
    private func rect(_ local: CGRect, _ p: Placement, _ pop: Double, _ scale: CGFloat) -> Path {
        let cx = (p.x + p.width / 2) * scale, cy = (p.y + p.height / 2) * scale
        let w = (r.rotated ? local.height : local.width) * scale * pop
        let h = (r.rotated ? local.width : local.height) * scale * pop
        return Path(CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
    }
}
