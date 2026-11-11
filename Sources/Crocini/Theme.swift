import SwiftUI

enum Theme {
    static let magenta = Color(red: 0.93, green: 0.13, blue: 0.47)
    static let magentaLight = Color(red: 1.0, green: 0.36, blue: 0.62)
    static let magentaDeep = Color(red: 0.74, green: 0.04, blue: 0.36)
    static let cyan = Color(red: 0.0, green: 0.68, blue: 0.93)
    static let bleedColor = magenta
    /// Sfondo dell'anteprima: carta calda in chiaro, grafite in scuro.
    static let canvasBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.13, green: 0.12, blue: 0.13, alpha: 1)
            : NSColor(red: 0.97, green: 0.95, blue: 0.96, alpha: 1)
    })

    static let brandGradient = LinearGradient(colors: [magentaLight, magenta, magentaDeep],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)

    // MARK: Tipografia — Bricolage Grotesque (OFL), inclusa nell'app in Resources/Fonts.
    static let fontFamily = "Bricolage Grotesque"

    static func font(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        let size: CGFloat
        switch style {
        case .largeTitle: size = 28
        case .title: size = 24
        case .title2: size = 21
        case .title3: size = 18
        case .headline: size = 15
        case .body: size = 15
        case .callout: size = 14
        case .subheadline: size = 13
        case .footnote: size = 12
        default: size = 12 // caption, caption2
        }
        return .custom(fontFamily, size: size, relativeTo: style).weight(weight)
    }

    static func font(size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(fontFamily, size: size).weight(weight)
    }

    /// Registra i font inclusi nell'app (serve anche fuori dal bundle, per le prove).
    static func registerFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for f in files where f.pathExtension.lowercased() == "ttf" || f.pathExtension.lowercased() == "otf" {
            CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
        }
    }
}

/// I quattro crocini disposti a cornice: il marchio dell'app.
struct CropGlyph: Shape {
    var inset: CGFloat = 0      // 0 = angoli al bordo, valori maggiori li allontanano
    var arm: CGFloat = 0.28

    var animatableData: CGFloat {
        get { inset }
        set { inset = newValue }
    }

    func path(in r: CGRect) -> Path {
        let a = min(r.width, r.height) * arm
        let o = inset
        var p = Path()
        let l = r.minX - o, t = r.minY - o, rr = r.maxX + o, b = r.maxY + o
        p.move(to: CGPoint(x: l, y: t + a)); p.addLine(to: CGPoint(x: l, y: t)); p.addLine(to: CGPoint(x: l + a, y: t))
        p.move(to: CGPoint(x: rr - a, y: t)); p.addLine(to: CGPoint(x: rr, y: t)); p.addLine(to: CGPoint(x: rr, y: t + a))
        p.move(to: CGPoint(x: l, y: b - a)); p.addLine(to: CGPoint(x: l, y: b)); p.addLine(to: CGPoint(x: l + a, y: b))
        p.move(to: CGPoint(x: rr - a, y: b)); p.addLine(to: CGPoint(x: rr, y: b)); p.addLine(to: CGPoint(x: rr, y: b - a))
        return p
    }
}

/// Logo animato: i crocini si chiudono attorno al biglietto all'apertura.
struct LogoMark: View {
    @State private var closed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.brandGradient)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(.white)
                .frame(width: 22, height: 14)
                .scaleEffect(closed ? 1 : 0.4)
            CropGlyph(inset: closed ? 0 : 9)
                .stroke(.black, style: StrokeStyle(lineWidth: 3, lineCap: .square, lineJoin: .miter))
                .frame(width: 30, height: 26)
        }
        .frame(width: 44, height: 44)
        .shadow(color: Theme.magenta.opacity(0.45), radius: 8, y: 3)
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.2)) { closed = true } }
    }
}

// MARK: - Componenti

/// Sezione a scheda richiudibile, con icona colorata e animazione.
struct SectionCard<Content: View>: View {
    let title: String
    let symbol: String
    var startsOpen = true
    @ViewBuilder let content: Content
    @State private var open = true
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Theme.spring) { open.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(Theme.font(size: 12, .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(title)
                        .font(Theme.font(.subheadline, .bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Theme.font(size: 11, .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(alignment: .leading, spacing: 10) { content }
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.magenta.opacity(hovering ? 0.45 : 0.10), lineWidth: 1)
        )
        .shadow(color: Theme.magenta.opacity(hovering ? 0.16 : 0.0), radius: 10, y: 3)
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hovering = h } }
        .onAppear { open = startsOpen }
    }
}

/// Etichetta a sinistra, controllo a destra.
struct FieldRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(label).font(Theme.font(.callout)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            control
        }
    }
}

/// Campo numerico in mm con bordo magenta quando è attivo.
struct MMField: View {
    let title: String
    @Binding var value: Double
    var digits = 1
    @FocusState private var focused: Bool

    init(_ title: String, value: Binding<Double>, digits: Int = 1) {
        self.title = title
        self._value = value
        self.digits = digits
    }

    var body: some View {
        FieldRow(title) {
            HStack(spacing: 5) {
                TextField("", value: $value, format: .number.precision(.fractionLength(0...digits)))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(Theme.font(.callout, .semibold))
                    .frame(width: 58)
                    .focused($focused)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(focused ? 0.04 : 0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.magenta.opacity(focused ? 0.9 : 0), lineWidth: 1.5))
                    .animation(.easeOut(duration: 0.15), value: focused)
                Text("mm").font(Theme.font(.caption)).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Pulsante principale: gradiente magenta, bagliore, rimbalzo alla pressione.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(.body, .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(enabled ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.gray.opacity(0.35)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(hovering && enabled ? 0.12 : 0))
            )
            .shadow(color: Theme.magenta.opacity(enabled ? (hovering ? 0.55 : 0.35) : 0), radius: hovering ? 14 : 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.96 : (hovering && enabled ? 1.02 : 1))
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.18), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Pulsante secondario a pillola, tinta magenta.
struct ChipButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(.callout, .semibold))
            .foregroundStyle(Theme.magenta)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Theme.magenta.opacity(hovering ? 0.20 : 0.11)))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

struct ChipLabel: View {
    let text: String
    let symbol: String
    var body: some View {
        Label(text, systemImage: symbol)
            .font(Theme.font(.callout, .semibold))
            .foregroundStyle(Theme.magenta)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Theme.magenta.opacity(0.11)))
    }
}
