import SwiftUI
import AppKit

/// Barra di scorrimento a quattro colori (ciano, magenta, giallo, nero) e rotella del mouse "morbida" per i ScrollView SwiftUI.
/// Si applica con `.background(ScrollStyler())` dentro il contenuto di uno ScrollView.
struct ScrollStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> StylerView { StylerView() }
    func updateNSView(_ nsView: StylerView, context: Context) {}
}

final class StylerView: NSView {
    private weak var scrollView: NSScrollView?
    private var monitor: Any?
    private var timer: Timer?
    private var current = 0.0, target = 0.0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.attach() }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        timer?.invalidate()
    }

    private func attach() {
        guard window != nil, scrollView == nil, let sv = enclosingScrollView else { return }
        scrollView = sv
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
        // solo per le prove: --show-scrollbar tiene la barra sempre visibile
        sv.scrollerStyle = CommandLine.arguments.contains("--show-scrollbar") ? .legacy : .overlay
        sv.verticalScroller = ColorScroller()
        sv.scrollerInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 2)
        sv.flashScrollers()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in self?.handle(e) ?? e }
    }

    /// Rotella del mouse: invece di scatti, il contenuto scivola verso la posizione di arrivo.
    private func handle(_ e: NSEvent) -> NSEvent? {
        guard let sv = scrollView, e.window === sv.window, let doc = sv.documentView else { return e }
        let p = sv.convert(e.locationInWindow, from: nil)
        guard sv.bounds.contains(p) else { return e }
        if e.hasPreciseScrollingDeltas { stopTimer(); return e }   // trackpad: già fluido di suo
        let maxY = max(0, doc.frame.height - sv.contentView.bounds.height)
        if timer == nil { current = sv.contentView.bounds.origin.y; target = current }
        let delta = e.scrollingDeltaY * 28 * (doc.isFlipped ? -1 : 1)
        target = min(max(target + delta, 0), maxY)
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.tick() }
        }
        return nil
    }

    private func tick() {
        guard let sv = scrollView else { stopTimer(); return }
        let diff = target - current
        if abs(diff) < 0.3 { current = target; apply(sv); stopTimer(); return }
        current += diff * 0.16
        apply(sv)
    }

    private func apply(_ sv: NSScrollView) {
        sv.contentView.scroll(to: NSPoint(x: sv.contentView.bounds.origin.x, y: current))
        sv.reflectScrolledClipView(sv.contentView)
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }
}

/// Indicatore sottile a pillola con le quattro fasce di stampa, come la barra in alto sul sito.
final class ColorScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // nessuna guida: solo la pillola
    }

    override func drawKnob() {
        let k = rect(for: .knob)
        guard k.height > 0 else { return }
        let w: CGFloat = 6
        let r = NSRect(x: k.midX - w / 2, y: k.minY + 1, width: w, height: max(w, k.height - 2))
        let path = NSBezierPath(roundedRect: r, xRadius: w / 2, yRadius: w / 2)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let c = [NSColor(Theme.cyan), NSColor(Theme.magenta), NSColor(Theme.yellow), NSColor(Theme.ink)]
        var colors: [NSColor] = [], locs: [CGFloat] = []
        for (i, col) in c.enumerated() {
            colors += [col, col]; locs += [CGFloat(i) / 4, CGFloat(i + 1) / 4]
        }
        NSGradient(colors: colors, atLocations: locs, colorSpace: .sRGB)?.draw(in: r, angle: isFlipped ? 90 : -90)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
