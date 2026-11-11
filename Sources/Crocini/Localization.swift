import Foundation

/// Traduce un testo: le chiavi sono i testi in italiano, le traduzioni stanno in Resources/<lingua>.lproj.
/// Serve per le stringhe costruite a codice; i testi letterali di SwiftUI (Text("…"), Button("…")) si traducono da soli.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: args)
}
