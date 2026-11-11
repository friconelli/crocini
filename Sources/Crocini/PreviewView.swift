import SwiftUI

/// Anteprima del foglio con zoom e spostamento come negli editor grafici.
/// Quando la disposizione cambia gli elementi "saltano" dentro uno dopo l'altro.
struct PreviewView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var viewport: ViewportState
    @State private var progress = 1.0

    var body: some View {
        let s = store.settings
        let r = store.result
        let page = CGSize(width: s.pageWidth, height: s.pageHeight)
        GeometryReader { geo in
            ZStack {
                PreviewCanvas(progress: progress, zoom: viewport.zoom, offset: viewport.offset,
                              s: s, r: r, artwork: store.artwork)
                if r.count == 0 { EmptyHint() }
                if let m = viewport.marquee { MarqueeView(rect: m) }
                InteractionLayer(viewport: viewport, page: page)
                ZoomBar(viewport: viewport, viewSize: geo.size, page: page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 18)
            }
        }
        .background(PaperBackdrop())
        .clipped()
        .onChange(of: r) { _ in replay() }
        .onChange(of: store.artworkName) { _ in replay() }
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

/// Sfondo: tinta calda con una griglia di piccoli crocini.
private struct PaperBackdrop: View {
    var body: some View {
        ZStack {
            Theme.canvasBackground
            LinearGradient(colors: [Theme.magenta.opacity(0.10), .clear, Theme.cyan.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { ctx, size in
                let step: CGFloat = 36
                var p = Path()
                var y: CGFloat = step / 2
                while y < size.height {
                    var x: CGFloat = step / 2
                    while x < size.width {
                        p.move(to: CGPoint(x: x - 3, y: y)); p.addLine(to: CGPoint(x: x + 3, y: y))
                        p.move(to: CGPoint(x: x, y: y - 3)); p.addLine(to: CGPoint(x: x, y: y + 3))
                        x += step
                    }
                    y += step
                }
                ctx.stroke(p, with: .color(Theme.magenta.opacity(0.16)), lineWidth: 0.8)
            }
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
            if r.rotated { cell.rotate(by: .degrees(90)) }
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
            lines.stroke(rect(g.trim, p, pop, scale), with: .color(Theme.cyan.opacity(0.9)), lineWidth: 0.6)
        }

        var marks = Path()
        for seg in LayoutEngine.cropMarkSegments(s, r) {
            marks.move(to: CGPoint(x: seg.x1 * scale, y: seg.y1 * scale))
            marks.addLine(to: CGPoint(x: seg.x2 * scale, y: seg.y2 * scale))
        }
        var m = ctx
        m.opacity = min(1, max(0, progress * 2 - 0.6))
        // Spessore reale in anteprima, ma mai sotto mezzo pixel per restare visibili.
        m.stroke(marks, with: .color(s.markColor.color), lineWidth: max(0.5, s.markWidth * scale))
    }

    /// Rettangolo locale (centrato, eventualmente ruotato) riportato in coordinate di foglio scalate.
    private func rect(_ local: CGRect, _ p: Placement, _ pop: Double, _ scale: CGFloat) -> Path {
        let cx = (p.x + p.width / 2) * scale, cy = (p.y + p.height / 2) * scale
        let w = (r.rotated ? local.height : local.width) * scale * pop
        let h = (r.rotated ? local.width : local.height) * scale * pop
        return Path(CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
    }
}
