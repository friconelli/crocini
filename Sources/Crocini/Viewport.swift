import SwiftUI
import AppKit

enum ViewTool { case hand, zoom }

/// Zoom e posizione dell'anteprima. `zoom` è relativo all'adattamento al foglio (1 = foglio intero),
/// `offset` è lo spostamento del centro del foglio dal centro della vista, in punti.
@MainActor
final class ViewportState: ObservableObject {
    @Published var zoom: CGFloat = 1
    @Published var offset: CGSize = .zero
    @Published var tool: ViewTool = .hand
    @Published var spaceDown = false
    @Published var optionDown = false
    @Published var panning = false
    @Published var marquee: CGRect?

    /// Aggiornati dalla vista AppKit; non pubblicati per non innescare aggiornamenti durante il disegno.
    var viewSize: CGSize = .zero
    var pageSize = CGSize(width: 210, height: 297)

    static let pad: CGFloat = 36
    static let minZoom: CGFloat = 0.2
    static let maxZoom: CGFloat = 64
    /// 100% = grandezza reale: 1 mm = 72/25,4 punti.
    static let actualScale: CGFloat = 72.0 / 25.4

    init() {
        // Solo per le prove: --zoom 3 --pan 40,-20
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--zoom"), i + 1 < a.count, let z = Double(a[i + 1]) { zoom = CGFloat(z) }
        if let i = a.firstIndex(of: "--pan"), i + 1 < a.count {
            let p = a[i + 1].split(separator: ",").compactMap { Double($0) }
            if p.count == 2 { offset = CGSize(width: p[0], height: p[1]) }
        }
    }

    static func fitScale(view: CGSize, page: CGSize) -> CGFloat {
        guard page.width > 0, page.height > 0 else { return 1 }
        return max(0.01, min((view.width - 2 * pad) / page.width, (view.height - 2 * pad) / page.height))
    }

    static func percent(zoom: CGFloat, view: CGSize, page: CGSize) -> Int {
        Int((fitScale(view: view, page: page) * zoom / actualScale * 100).rounded())
    }

    private var fitScale: CGFloat { Self.fitScale(view: viewSize, page: pageSize) }
    private var scale: CGFloat { fitScale * zoom }
    private var center: CGPoint { CGPoint(x: viewSize.width / 2, y: viewSize.height / 2) }
    private func clamp(_ z: CGFloat) -> CGFloat { min(max(z, Self.minZoom), Self.maxZoom) }

    /// Il foglio non può uscire del tutto dalla vista.
    private func clamp(offset o: CGSize, scale s: CGFloat) -> CGSize {
        let mx = pageSize.width * s / 2 + viewSize.width / 2 - 80
        let my = pageSize.height * s / 2 + viewSize.height / 2 - 80
        return CGSize(width: min(max(o.width, -mx), mx), height: min(max(o.height, -my), my))
    }

    private func apply(zoom z: CGFloat, offset o: CGSize, animated: Bool) {
        let o2 = clamp(offset: o, scale: fitScale * z)
        if animated {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { zoom = z; offset = o2 }
        } else {
            zoom = z; offset = o2
        }
    }

    /// Zoom che tiene fermo il punto `anchor` (coordinate della vista, origine in alto a sinistra).
    func zoom(by factor: CGFloat, at anchor: CGPoint? = nil, animated: Bool = false) {
        let s1 = scale
        let z2 = clamp(zoom * factor)
        let s2 = fitScale * z2
        let a = anchor ?? center
        let px = (a.x - center.x - offset.width) / s1     // punto del foglio sotto l'ancora
        let py = (a.y - center.y - offset.height) / s1
        apply(zoom: z2, offset: CGSize(width: a.x - center.x - px * s2, height: a.y - center.y - py * s2),
              animated: animated)
    }

    func zoomToward(rect: CGRect) {
        guard rect.width > 4, rect.height > 4, viewSize.width > 0 else { return }
        let s1 = scale
        let z2 = clamp(zoom * min(viewSize.width / rect.width, viewSize.height / rect.height) * 0.92)
        let s2 = fitScale * z2
        let px = (rect.midX - center.x - offset.width) / s1
        let py = (rect.midY - center.y - offset.height) / s1
        apply(zoom: z2, offset: CGSize(width: -px * s2, height: -py * s2), animated: true)
    }

    func pan(by d: CGSize) {
        offset = clamp(offset: CGSize(width: offset.width + d.width, height: offset.height + d.height), scale: scale)
    }

    func fit() { apply(zoom: 1, offset: .zero, animated: true) }

    func setPercent(_ p: CGFloat) {
        guard fitScale > 0 else { return }
        apply(zoom: clamp(Self.actualScale * p / 100 / fitScale), offset: .zero, animated: true)
    }

    func zoomIn() { zoom(by: 1.25, animated: true) }
    func zoomOut() { zoom(by: 0.8, animated: true) }
}

// MARK: - Livello di interazione (rotella, pinch, trascinamento, tasti)

struct InteractionLayer: NSViewRepresentable {
    @ObservedObject var viewport: ViewportState
    let page: CGSize

    func makeNSView(context: Context) -> InteractionView {
        let v = InteractionView()
        v.viewport = viewport
        return v
    }

    func updateNSView(_ v: InteractionView, context: Context) {
        viewport.pageSize = page
        v.viewport = viewport
        v.window?.invalidateCursorRects(for: v)
    }
}

final class InteractionView: NSView {
    weak var viewport: ViewportState?
    private var monitor: Any?
    private var inside = false
    private var lastPoint = CGPoint.zero
    private var marqueeStart: CGPoint?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }   // il trascinamento sposta il foglio, non la finestra
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        viewport?.viewSize = newSize
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        viewport?.viewSize = bounds.size
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] e in
            self?.handleKey(e) ?? e
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    override func mouseEntered(with event: NSEvent) { inside = true }
    override func mouseExited(with event: NSEvent) { inside = false }

    // MARK: cursore

    override func resetCursorRects() {
        guard let vp = viewport else { return }
        let cursor: NSCursor
        if vp.panning { cursor = .closedHand }
        else if vp.tool == .hand || vp.spaceDown { cursor = .openHand }
        else { cursor = Self.lensCursor(minus: vp.optionDown) }
        addCursorRect(bounds, cursor: cursor)
    }

    private static func lensCursor(minus: Bool) -> NSCursor {
        let cfg = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        guard let base = NSImage(systemSymbolName: minus ? "minus.magnifyingglass" : "plus.magnifyingglass",
                                 accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return .crosshair }
        let img = NSImage(size: base.size, flipped: false) { r in
            base.draw(in: r)
            NSColor(red: 0.74, green: 0.04, blue: 0.36, alpha: 1).set()
            r.fill(using: .sourceAtop)
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: img.size.width * 0.42, y: img.size.height * 0.42))
    }

    // MARK: rotella e pinch

    override func scrollWheel(with e: NSEvent) {
        guard let vp = viewport else { return }
        let p = convert(e.locationInWindow, from: nil)
        let zoomModifier = e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control)
        if zoomModifier || !e.hasPreciseScrollingDeltas {
            if !zoomModifier && e.modifierFlags.contains(.shift) {   // maiusc + rotella: sposta
                vp.pan(by: CGSize(width: e.scrollingDeltaX * 12, height: e.scrollingDeltaY * 12))
                return
            }
            let dy = max(-10, min(10, e.scrollingDeltaY))
            let factor = e.hasPreciseScrollingDeltas ? exp(dy * 0.012) : pow(1.12, dy)
            if e.hasPreciseScrollingDeltas {
                vp.zoom(by: factor, at: p)
            } else {
                withAnimation(.easeOut(duration: 0.12)) { vp.zoom(by: factor, at: p) }
            }
        } else {
            vp.pan(by: CGSize(width: e.scrollingDeltaX, height: e.scrollingDeltaY))
        }
    }

    override func magnify(with e: NSEvent) {
        viewport?.zoom(by: 1 + e.magnification, at: convert(e.locationInWindow, from: nil))
    }

    // MARK: mouse

    override func mouseDown(with e: NSEvent) {
        guard let vp = viewport else { return }
        window?.makeFirstResponder(self)
        let p = convert(e.locationInWindow, from: nil)
        lastPoint = p
        if vp.tool == .hand || vp.spaceDown {
            if e.clickCount == 2 { vp.fit() } else { vp.panning = true; window?.invalidateCursorRects(for: self) }
        } else {
            marqueeStart = p
        }
    }

    override func mouseDragged(with e: NSEvent) {
        guard let vp = viewport else { return }
        let p = convert(e.locationInWindow, from: nil)
        if vp.panning {
            vp.pan(by: CGSize(width: p.x - lastPoint.x, height: p.y - lastPoint.y))
            lastPoint = p
        } else if let s = marqueeStart, hypot(p.x - s.x, p.y - s.y) > 4 {
            vp.marquee = CGRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))
        }
    }

    override func mouseUp(with e: NSEvent) {
        guard let vp = viewport else { return }
        if vp.panning { vp.panning = false; window?.invalidateCursorRects(for: self) }
        if let s = marqueeStart {
            if let r = vp.marquee {
                vp.zoomToward(rect: r)
            } else {   // semplice clic: ingrandisce, con ⌥ rimpicciolisce
                vp.zoom(by: e.modifierFlags.contains(.option) ? 1 / 1.6 : 1.6, at: s, animated: true)
            }
            vp.marquee = nil
            marqueeStart = nil
        }
    }

    // Tasto centrale: sposta, come in Figma.
    override func otherMouseDown(with e: NSEvent) {
        lastPoint = convert(e.locationInWindow, from: nil)
        viewport?.panning = true
        window?.invalidateCursorRects(for: self)
    }
    override func otherMouseDragged(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        viewport?.pan(by: CGSize(width: p.x - lastPoint.x, height: p.y - lastPoint.y))
        lastPoint = p
    }
    override func otherMouseUp(with e: NSEvent) {
        viewport?.panning = false
        window?.invalidateCursorRects(for: self)
    }

    // MARK: tastiera (solo con il mouse sull'anteprima e senza un campo di testo attivo)

    private func handleKey(_ e: NSEvent) -> NSEvent? {
        guard let vp = viewport else { return e }
        if e.type == .flagsChanged {
            let opt = e.modifierFlags.contains(.option)
            if vp.optionDown != opt { vp.optionDown = opt; window?.invalidateCursorRects(for: self) }
            return e
        }
        let key = e.charactersIgnoringModifiers ?? ""
        if e.type == .keyUp {
            if key == " " && vp.spaceDown { vp.spaceDown = false; window?.invalidateCursorRects(for: self); return nil }
            return e
        }
        guard inside, window?.isKeyWindow == true, !(window?.firstResponder is NSText) else { return e }
        if !e.modifierFlags.intersection([.command, .control, .option]).isEmpty { return e }
        switch key.lowercased() {
        case " ":
            if !vp.spaceDown { vp.spaceDown = true; window?.invalidateCursorRects(for: self) }
            return nil
        case "h": vp.tool = .hand; window?.invalidateCursorRects(for: self); return nil
        case "z": vp.tool = .zoom; window?.invalidateCursorRects(for: self); return nil
        case "+", "=": vp.zoomIn(); return nil
        case "-": vp.zoomOut(); return nil
        default: return e
        }
    }
}

// MARK: - Barra degli strumenti

struct ZoomBar: View {
    @ObservedObject var viewport: ViewportState
    let viewSize: CGSize
    let page: CGSize

    var body: some View {
        HStack(spacing: 4) {
            toolButton(.hand, "hand.raised.fill", help: "Mano (H) — trascina per spostarti; spazio per usarla al volo")
            toolButton(.zoom, "magnifyingglass", help: "Lente (Z) — clic ingrandisce, ⌥ clic rimpicciolisce, trascina per zoomare su un'area")
            divider
            iconButton("minus", help: "Riduci (−)") { viewport.zoomOut() }
            Menu {
                Button("Adatta al foglio") { viewport.fit() }
                Divider()
                ForEach([25, 50, 100, 200, 400, 800], id: \.self) { p in
                    Button("\(p)%") { viewport.setPercent(CGFloat(p)) }
                }
            } label: {
                Text("\(ViewportState.percent(zoom: viewport.zoom, view: viewSize, page: page))%")
                    .font(Theme.font(.callout, .bold))
                    .monospacedDigit()
                    .frame(minWidth: 52)
                    .contentTransition(.numericText())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            iconButton("plus", help: "Ingrandisci (+)") { viewport.zoomIn() }
            divider
            iconButton("arrow.up.left.and.arrow.down.right", help: "Adatta al foglio (⌘0)") { viewport.fit() }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.magenta.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 18).padding(.horizontal, 3)
    }

    private func toolButton(_ tool: ViewTool, _ symbol: String, help: String) -> some View {
        let active = viewport.tool == tool
        return Button {
            withAnimation(Theme.spring) { viewport.tool = tool }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? Color.white : Theme.magenta)
                .frame(width: 32, height: 28)
                .background(Capsule().fill(active ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.clear)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.magenta)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Rettangolo di selezione della lente.
struct MarqueeView: View {
    let rect: CGRect
    var body: some View {
        Rectangle()
            .fill(Theme.magenta.opacity(0.10))
            .overlay(Rectangle().strokeBorder(Theme.magenta, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }
}
