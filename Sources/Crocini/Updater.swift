import SwiftUI
import AppKit

/// Controlla le GitHub Releases del repo e, se c'è una versione più nuova,
/// scarica lo zip, sostituisce l'app in uso e la riavvia.
@MainActor
final class Updater: ObservableObject {
    nonisolated static let repo = "friconelli/crocini"
    nonisolated static let assetName = "Crocini.zip"

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, notes: String, downloadURL: URL, pageURL: URL)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// Avanzamento del download (0...1) e fase corrente durante l'installazione.
    @Published private(set) var progress: Double = 0
    @Published private(set) var phase: Phase = .downloading

    enum Phase { case downloading, extracting, verifying, restarting }
    /// Mostra la finestra dell'aggiornamento (aperta da menu o all'avvio se c'è una novità).
    @Published var showSheet = false

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var isUpdateAvailable: Bool {
        if case .available = state { return true }
        return false
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let body: String?
        let html_url: URL
        let assets: [Asset]
    }

    // MARK: - Check

    func check() async {
        switch state {
        case .checking, .installing: return
        default: break
        }
        state = .checking
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UpdateError.network }
            if http.statusCode == 404 { state = .upToDate; return }  // nessuna release ancora
            guard http.statusCode == 200 else { throw UpdateError.http(http.statusCode) }

            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            guard Self.isNewer(latest, than: currentVersion) else { state = .upToDate; return }
            guard let asset = release.assets.first(where: { $0.name == Self.assetName }) else {
                throw UpdateError.missingAsset
            }
            state = .available(
                version: latest,
                notes: release.body ?? "",
                downloadURL: asset.browser_download_url,
                pageURL: release.html_url
            )
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Install

    func install() async {
        guard case let .available(_, _, downloadURL, _) = state else { return }
        state = .installing
        progress = 0
        phase = .downloading
        do {
            let fm = FileManager.default
            let target = Bundle.main.bundleURL
            guard target.pathExtension == "app" else { throw UpdateError.notAnApp }
            guard fm.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
                throw UpdateError.notWritable
            }

            let workDir = fm.temporaryDirectory.appendingPathComponent("CrociniUpdate-\(UUID().uuidString)")
            try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

            let zip = workDir.appendingPathComponent(Self.assetName)
            try await Self.download(downloadURL, to: zip) { [weak self] fraction in
                Task { @MainActor in self?.progress = fraction }
            }
            progress = 1

            phase = .extracting
            let extracted = workDir.appendingPathComponent("extracted")
            try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
            try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path])

            let newApp = extracted.appendingPathComponent("Crocini.app")
            guard fm.fileExists(atPath: newApp.path) else { throw UpdateError.badArchive }
            // Verifica che il bundle sia integro prima di sostituire quello in uso.
            phase = .verifying
            try Self.run("/usr/bin/codesign", ["--verify", "--deep", newApp.path])

            phase = .restarting
            // Script distaccato: attende la chiusura dell'app, sostituisce il bundle e riapre.
            let script = """
            PID=\(ProcessInfo.processInfo.processIdentifier)
            i=0
            while kill -0 $PID 2>/dev/null; do
              i=$((i+1))
              [ $i -gt 25 ] && kill -9 $PID 2>/dev/null   # se l'app non si chiude entro ~5 secondi, la chiudo io
              sleep 0.2
            done
            rm -rf "$TARGET"
            ditto "$NEW" "$TARGET"
            xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
            open "$TARGET"
            rm -rf "$WORK"
            """
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", script]
            task.environment = ["TARGET": target.path, "NEW": newApp.path, "WORK": workDir.path]
            task.standardOutput = nil
            task.standardError = nil
            try task.run()

            NSApp.terminate(nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    /// Scarica un file notificando l'avanzamento (0...1).
    private static func download(_ url: URL, to dest: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let delegate = DownloadDelegate(dest: dest, progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            delegate.continuation = c
            session.downloadTask(with: url).resume()
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func run(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = nil
        p.standardError = nil
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError.badArchive }
    }

    enum UpdateError: LocalizedError {
        case network, http(Int), missingAsset, notAnApp, notWritable, badArchive

        var errorDescription: String? {
            switch self {
            case .network: return L("Errore di rete.")
            case .http(let code): return L("GitHub ha risposto con errore %d.", code)
            case .missingAsset: return L("La release non contiene %@.", Updater.assetName)
            case .notAnApp: return L("L'app non è in esecuzione da un bundle .app.")
            case .notWritable: return L("Impossibile scrivere nella cartella dell'app. Scarica la nuova versione manualmente.")
            case .badArchive: return L("L'archivio scaricato non è valido.")
            }
        }
    }
}

/// Finestra di dialogo con stato dell'aggiornamento.
struct UpdateSheet: View {
    @ObservedObject var updater: Updater
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                LogoMark()
                Text("Aggiornamenti")
                    .font(Theme.font(.title3, .heavy))
            }
            switch updater.state {
            case .idle, .checking:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Controllo aggiornamenti…") }
            case .upToDate:
                Label("Crocini è aggiornato (v\(updater.currentVersion)).", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.magenta)
            case let .available(version, notes, _, pageURL):
                Text("Nuova versione disponibile: v\(version)")
                    .font(Theme.font(.headline, .bold))
                Text("Hai la v\(updater.currentVersion).").foregroundStyle(.secondary)
                if !notes.isEmpty {
                    ScrollView { Text(notes).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 140)
                }
                HStack {
                    Link("Note di rilascio", destination: pageURL)
                    Spacer()
                    Button("Più tardi") { dismiss() }
                    Button("Aggiorna e riavvia") { Task { await updater.install() } }
                        .keyboardShortcut(.defaultAction)
                }
            case .installing:
                VStack(alignment: .leading, spacing: 8) {
                    if updater.phase == .downloading {
                        ProgressView(value: updater.progress)
                        Text("Download in corso… \(Int(updater.progress * 100))%")
                    } else {
                        ProgressView()
                        switch updater.phase {
                        case .extracting: Text("Estrazione…")
                        case .verifying: Text("Verifica dell'app…")
                        default: Text("Riavvio di Crocini…")
                        }
                    }
                }
                .foregroundStyle(.secondary)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Button("Riprova") { Task { await updater.check() } }
            }
            if !updater.isUpdateAvailable, updater.state != .installing {
                HStack { Spacer(); Button("Chiudi") { dismiss() } }
            }
        }
        .padding(22)
        .frame(width: 440)
        .tint(Theme.magenta)
    }
}


private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let dest: URL
    let progress: @Sendable (Double) -> Void
    var continuation: CheckedContinuation<Void, Error>?
    private var moveError: Error?

    init(dest: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.dest = dest
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if (downloadTask.response as? HTTPURLResponse)?.statusCode != 200 {
            moveError = Updater.UpdateError.network
            return
        }
        do { try FileManager.default.moveItem(at: location, to: dest) } catch { moveError = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error ?? moveError { continuation?.resume(throwing: error) } else { continuation?.resume() }
        continuation = nil
    }
}
