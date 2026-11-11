import SwiftUI

enum Theme {
    // Quadricromia: i colori di processo della stampa (C, M, Y) più il nero (K) per testi e bordi.
    static let cyan = Color(red: 0.0, green: 0.68, blue: 0.94)          // #00AEEF
    static let magenta = Color(red: 0.925, green: 0.0, blue: 0.549)     // #EC008C
    static let yellow = Color(red: 1.0, green: 0.95, blue: 0.0)         // #FFF200
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.08)          // K
    static let magentaLight = Color(red: 1.0, green: 0.24, blue: 0.66)
    static let magentaDeep = Color(red: 0.78, green: 0.0, blue: 0.46)
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

/// Una "lastra" della quadricromia: colore pieno e colore leggibile da metterci sopra.
struct Plate {
    let color: Color
    let onColor: Color
    static let cyan = Plate(color: Theme.cyan, onColor: Theme.ink)
    static let magenta = Plate(color: Theme.magenta, onColor: .white)
    static let yellow = Plate(color: Theme.yellow, onColor: Theme.ink)
    static let black = Plate(color: Theme.ink, onColor: .white)
}

/// Barra colore C M Y K, come ai bordi di un foglio di prova.
struct CMYKBar: View {
    var body: some View {
        HStack(spacing: 0) {
            Theme.cyan; Theme.magenta; Theme.yellow; Theme.ink
        }
    }
}

/// Sfondo a retino: tre griglie di punti C M Y leggermente sfalsate, che sfumano verso l'angolo in alto a destra.
struct HalftoneBackdrop: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 20
            func layer(_ color: Color, dx: CGFloat, dy: CGFloat, r: CGFloat) {
                var p = Path()
                var y = dy
                while y < size.height + step {
                    var x = dx
                    while x < size.width + step {
                        p.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                        x += step
                    }
                    y += step
                }
                ctx.fill(p, with: .color(color))
            }
            layer(Theme.cyan.opacity(0.34), dx: 0, dy: 0, r: 1.5)
            layer(Theme.magenta.opacity(0.28), dx: 7, dy: 7, r: 1.5)
            layer(Theme.yellow.opacity(0.75), dx: 14, dy: 3, r: 1.7)
        }
        .mask(RadialGradient(colors: [.black, .clear], center: .topTrailing, startRadius: 0, endRadius: 780))
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
                .stroke(Color(red: 1, green: 0.95, blue: 0), style: StrokeStyle(lineWidth: 3, lineCap: .square, lineJoin: .miter))
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
    let title: LocalizedStringKey
    let symbol: String
    var plate: Plate = .magenta
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
                        .foregroundStyle(plate.onColor)
                        .frame(width: 26, height: 26)
                        .background(plate.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.ink, lineWidth: 1.4))
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
                .strokeBorder(hovering ? plate.color.opacity(0.7) : Color.primary.opacity(0.10), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .onAppear { open = startsOpen }
    }
}

/// Etichetta a sinistra, controllo a destra.
struct FieldRow<Control: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder let control: Control

    init(_ label: LocalizedStringKey, @ViewBuilder control: () -> Control) {
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
    let title: LocalizedStringKey
    @Binding var value: Double
    var digits = 1
    @FocusState private var focused: Bool

    init(_ title: LocalizedStringKey, value: Binding<Double>, digits: Int = 1) {
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
                        .strokeBorder(Theme.cyan.opacity(focused ? 1 : 0), lineWidth: 2))
                    .animation(.easeOut(duration: 0.15), value: focused)
                Text("mm").font(Theme.font(.caption)).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Pulsante principale: magenta pieno, bordo nero e ombra piena, come una stampa a lastre; si "schiaccia" al clic.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return configuration.label
            .font(Theme.font(.body, .bold))
            .foregroundStyle(enabled ? .white : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(shape.fill(enabled ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.gray.opacity(0.25))))
            .overlay(shape.strokeBorder(enabled ? Theme.ink : Color.gray.opacity(0.4), lineWidth: 2))
            .background(shape.fill(enabled ? Theme.ink : .clear).offset(x: down ? 0 : (hovering ? 4 : 3), y: down ? 0 : (hovering ? 4 : 3)))
            .offset(x: down ? 3 : (hovering && enabled ? -1 : 0), y: down ? 3 : (hovering && enabled ? -1 : 0))
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: down)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Pulsante secondario a pillola, nel colore di una lastra (magenta, ciano o giallo).
struct ChipButtonStyle: ButtonStyle {
    var plate: Plate = .magenta
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let magenta = plate.color == Theme.magenta
        return configuration.label
            .font(Theme.font(.callout, .semibold))
            .foregroundStyle(magenta ? Theme.magentaDeep : Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(plate.color.opacity(hovering ? (magenta ? 0.22 : 0.55) : (magenta ? 0.12 : 0.32))))
            .overlay(Capsule().strokeBorder(plate.color.opacity(hovering ? 0.9 : 0), lineWidth: 1.5))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

struct ChipLabel: View {
    let text: LocalizedStringKey
    let symbol: String
    var body: some View {
        Label(text, systemImage: symbol)
            .font(Theme.font(.callout, .semibold))
            .foregroundStyle(Theme.magenta)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Theme.magenta.opacity(0.11)))
    }
}
