import AppKit

/// Solo per le prove: `Crocini --snapshot file.png` salva la finestra in PNG e chiude l'app.
enum Snapshot {
    /// Solo per le prove e le immagini del sito: `--stage 1240 860` porta la finestra a quella misura
    /// (in punti), la centra e toglie il focus dai campi di testo.
    static func prepareIfRequested() {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--stage"), i + 2 < a.count, let w = Double(a[i + 1]), let h = Double(a[i + 2]) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard let win = NSApp.windows.first(where: { $0.isVisible }) else { return }
            win.setContentSize(NSSize(width: w, height: h))
            win.center()
            win.makeFirstResponder(nil)
            NSApp.activate(ignoringOtherApps: true)   // finestra attiva: i tre pallini sono colorati
            win.makeKeyAndOrderFront(nil)
        }
    }

    static func scheduleIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let path = args[i + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard let view = NSApp.windows.first(where: { $0.isVisible })?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(2) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }
}
