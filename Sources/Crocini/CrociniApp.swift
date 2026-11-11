import SwiftUI

@main
struct CrociniApp: App {
    @StateObject private var store = Store()
    @StateObject private var viewport = ViewportState()
    @StateObject private var updater = Updater()

    init() { Theme.registerFonts() }

    var body: some Scene {
        WindowGroup("Crocini") {
            ContentView()
                .environmentObject(store)
                .environmentObject(viewport)
                .environmentObject(updater)
                .frame(minWidth: 900, minHeight: 640)
                .onAppear(perform: Snapshot.scheduleIfRequested)
        }
        .defaultSize(width: 1140, height: 780)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Verifica aggiornamenti…") {
                    updater.showSheet = true
                    Task { await updater.check() }
                }
            }
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Ingrandisci") { viewport.zoomIn() }.keyboardShortcut("=", modifiers: .command)
                Button("Riduci") { viewport.zoomOut() }.keyboardShortcut("-", modifiers: .command)
                Button("Adatta al foglio") { viewport.fit() }.keyboardShortcut("0", modifiers: .command)
                Button("Dimensioni reali (100%)") { viewport.setPercent(100) }.keyboardShortcut("1", modifiers: .command)
            }
        }
    }
}
