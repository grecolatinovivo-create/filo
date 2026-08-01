import SwiftUI

/// Un tema è una palette di colori. Restano gli stessi token del design system
/// originale (UX_SPEC §2), ma ora sono selezionabili: il tema di default è
/// gratuito, gli altri sono un "extra" sbloccabile con l'acquisto in-app.
struct Palette: Equatable {
    let bg: Color
    let bg2: Color          // secondo stop del gradiente di sfondo
    let surface: Color
    let surface2: Color
    let border: Color
    let text: Color
    let textMuted: Color
    let filo: Color
    let filoHover: Color
    let filoScuro: Color     // SOLO bordi decorativi
    let sarto: Color
    let ok: Color
    let spezzato: Color
    let annodato: Color
    let overlay: Color

    /// Gradiente di sfondo (angolare morbido) — cuore del look "colorato".
    var bgGradient: LinearGradient {
        LinearGradient(colors: [bg, bg2], startPoint: .top, endPoint: .bottom)
    }
    /// Gradiente del filo del giocatore (caldo, con brillantezza).
    var filoGradient: LinearGradient {
        LinearGradient(colors: [filoHover, filo], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// Riempimento di una casella accesa.
    var cellaAccesa: LinearGradient {
        LinearGradient(colors: [filoHover, filo], startPoint: .top, endPoint: .bottom)
    }
}

/// Catalogo dei temi. `notte` è gratuito; gli altri richiedono l'acquisto extra.
enum ThemeID: String, CaseIterable, Identifiable, Codable {
    case notte, aurora, tramonto, foresta, ciclamino

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .notte:     return String(localized: "Notte")
        case .aurora:    return String(localized: "Aurora")
        case .tramonto:  return String(localized: "Tramonto")
        case .foresta:   return String(localized: "Foresta")
        case .ciclamino: return String(localized: "Ciclamino")
        }
    }

    /// True se il tema fa parte del pacchetto extra a pagamento.
    var premium: Bool { self != .notte }

    var palette: Palette {
        switch self {
        case .notte:
            // Default gratuito: dark ricco blu-notte con filo oro caldo.
            return Palette(
                bg: Color(hexRGB: 0x11151F), bg2: Color(hexRGB: 0x1A1030),
                surface: Color(hexRGB: 0x1B2233), surface2: Color(hexRGB: 0x263149),
                border: Color(hexRGB: 0x33405C), text: Color(hexRGB: 0xF2F5FB),
                textMuted: Color(hexRGB: 0x9FB0CC), filo: Color(hexRGB: 0xF5B531),
                filoHover: Color(hexRGB: 0xFFD15C), filoScuro: Color(hexRGB: 0x8A6A1F),
                sarto: Color(hexRGB: 0xF7E7B4), ok: Color(hexRGB: 0x38D39F),
                spezzato: Color(hexRGB: 0xFF6B6B), annodato: Color(hexRGB: 0x6EA8FE),
                overlay: Color(hexRGB: 0x05070D).opacity(0.74))
        case .aurora:
            // Viola-teal con filo verde-acqua brillante.
            return Palette(
                bg: Color(hexRGB: 0x0E1428), bg2: Color(hexRGB: 0x241546),
                surface: Color(hexRGB: 0x1A2340), surface2: Color(hexRGB: 0x263156),
                border: Color(hexRGB: 0x3A2E6B), text: Color(hexRGB: 0xF3F1FF),
                textMuted: Color(hexRGB: 0xAEA6D6), filo: Color(hexRGB: 0x2EE6C9),
                filoHover: Color(hexRGB: 0x67F3DC), filoScuro: Color(hexRGB: 0x1B7E6E),
                sarto: Color(hexRGB: 0xC9F7EF), ok: Color(hexRGB: 0x2EE6C9),
                spezzato: Color(hexRGB: 0xFF6E9C), annodato: Color(hexRGB: 0x8B8CFF),
                overlay: Color(hexRGB: 0x070512).opacity(0.76))
        case .tramonto:
            // Rosso-magenta caldo con filo ambra.
            return Palette(
                bg: Color(hexRGB: 0x1C0F1A), bg2: Color(hexRGB: 0x3A1424),
                surface: Color(hexRGB: 0x2A1622), surface2: Color(hexRGB: 0x3E2130),
                border: Color(hexRGB: 0x5A2C3F), text: Color(hexRGB: 0xFFF2EE),
                textMuted: Color(hexRGB: 0xD7A9AE), filo: Color(hexRGB: 0xFF9F45),
                filoHover: Color(hexRGB: 0xFFBE6E), filoScuro: Color(hexRGB: 0x9A5A22),
                sarto: Color(hexRGB: 0xFFE0BE), ok: Color(hexRGB: 0x4FD08A),
                spezzato: Color(hexRGB: 0xFF5C7A), annodato: Color(hexRGB: 0xC58BFF),
                overlay: Color(hexRGB: 0x0F0509).opacity(0.76))
        case .foresta:
            // Verde profondo con filo lime.
            return Palette(
                bg: Color(hexRGB: 0x0D1A15), bg2: Color(hexRGB: 0x102A1E),
                surface: Color(hexRGB: 0x142720), surface2: Color(hexRGB: 0x1E3A2E),
                border: Color(hexRGB: 0x2C5140), text: Color(hexRGB: 0xEFF7F1),
                textMuted: Color(hexRGB: 0x9FC4AE), filo: Color(hexRGB: 0xB6E44B),
                filoHover: Color(hexRGB: 0xCEF56E), filoScuro: Color(hexRGB: 0x5E7E22),
                sarto: Color(hexRGB: 0xE6F7C4), ok: Color(hexRGB: 0x53D98A),
                spezzato: Color(hexRGB: 0xFF7A6B), annodato: Color(hexRGB: 0x5FC7E4),
                overlay: Color(hexRGB: 0x040A07).opacity(0.76))
        case .ciclamino:
            // Rosa-indaco vivace con filo fucsia.
            return Palette(
                bg: Color(hexRGB: 0x140F26), bg2: Color(hexRGB: 0x2A123F),
                surface: Color(hexRGB: 0x201640), surface2: Color(hexRGB: 0x2F2056),
                border: Color(hexRGB: 0x453070), text: Color(hexRGB: 0xF6F0FF),
                textMuted: Color(hexRGB: 0xBBA6DE), filo: Color(hexRGB: 0xFF5FBD),
                filoHover: Color(hexRGB: 0xFF87D0), filoScuro: Color(hexRGB: 0x9A2E77),
                sarto: Color(hexRGB: 0xFFD1EE), ok: Color(hexRGB: 0x46D9B0),
                spezzato: Color(hexRGB: 0xFF6B6B), annodato: Color(hexRGB: 0x7C8CFF),
                overlay: Color(hexRGB: 0x08040F).opacity(0.78))
        }
    }
}

/// Sorgente del tema attivo. `Theme.*` legge da qui, così le viste che
/// osservano questo oggetto si ridisegnano al cambio tema senza toccare i
/// call-site esistenti.
@MainActor
final class ThemeManager: ObservableObject {
    @Published var id: ThemeID {
        didSet {
            Theme.current = id.palette
            UserDefaults.standard.set(id.rawValue, forKey: Self.key)
        }
    }

    private static let key = "filo.theme"

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        let start = saved.flatMap(ThemeID.init(rawValue:)) ?? .notte
        id = start
        Theme.current = start.palette
    }

    /// Sceglie un tema solo se sbloccato (i premium richiedono l'acquisto).
    func seleziona(_ nuovo: ThemeID, sbloccato: Bool) {
        guard !nuovo.premium || sbloccato else { return }
        id = nuovo
    }
}

/// Facciata statica: mantiene i vecchi call-site `Theme.bg`, `Theme.filo`, ecc.,
/// ma ora restituisce i colori del tema attivo (aggiornato da ThemeManager).
enum Theme {
    static var current: Palette = ThemeID.notte.palette

    static var bg: Color        { current.bg }
    static var bg2: Color       { current.bg2 }
    static var surface: Color   { current.surface }
    static var surface2: Color  { current.surface2 }
    static var border: Color    { current.border }
    static var text: Color      { current.text }
    static var textMuted: Color { current.textMuted }
    static var filo: Color      { current.filo }
    static var filoHover: Color { current.filoHover }
    static var filoScuro: Color { current.filoScuro }
    static var sarto: Color     { current.sarto }
    static var ok: Color        { current.ok }
    static var spezzato: Color  { current.spezzato }
    static var annodato: Color  { current.annodato }
    static var overlay: Color   { current.overlay }

    static var bgGradient: LinearGradient { current.bgGradient }
    static var filoGradient: LinearGradient { current.filoGradient }
    static var cellaAccesa: LinearGradient { current.cellaAccesa }
}

extension Color {
    init(hexRGB: UInt32) {
        self.init(red: Double((hexRGB >> 16) & 0xFF) / 255.0,
                  green: Double((hexRGB >> 8) & 0xFF) / 255.0,
                  blue: Double(hexRGB & 0xFF) / 255.0)
    }
}

/// Caption uppercase in stile HUD (UX_SPEC §3).
struct CaptionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.footnote.weight(.medium))
            .textCase(.uppercase)
            .kerning(1.0)
            .foregroundStyle(Theme.textMuted)
    }
}

/// Bottone primario pill (ora con gradiente del tema, UX_SPEC §5.2).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.bold))
            .foregroundStyle(Theme.bg)
            .padding(.vertical, 14)
            .padding(.horizontal, 28)
            .frame(minHeight: 48)
            .background(Theme.filoGradient)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.filoHover.opacity(0.5), lineWidth: 1))
            .shadow(color: Theme.filo.opacity(configuration.isPressed ? 0.15 : 0.35),
                    radius: configuration.isPressed ? 4 : 12, y: 3)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Bottone secondario rosso ("Strappa il filo", UX_SPEC §5.3).
struct SecondaryButtonStyle: ButtonStyle {
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.bold))
            .foregroundStyle(enabled ? Theme.spezzato : Theme.textMuted)
            .padding(.vertical, 14)
            .padding(.horizontal, 28)
            .frame(minHeight: 48)
            .background(
                Capsule().strokeBorder(enabled ? Theme.spezzato : Theme.border, lineWidth: 2)
            )
            .background(
                Capsule().fill(configuration.isPressed && enabled
                               ? Theme.spezzato.opacity(0.2) : Color.clear)
            )
            .opacity(enabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed && enabled ? 0.97 : 1)
    }
}

extension View {
    func captionStyle() -> some View { modifier(CaptionStyle()) }
}

/// Shake orizzontale ±4pt (mossa non valida, UX_SPEC §6).
struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 4
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: travel * sin(shakes * .pi * 2 * 3), y: 0))
    }
}

/// Polilinea fra i centri delle caselle (filo del giocatore / del Sarto).
struct PolylineShape: Shape {
    var points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for pt in points.dropFirst() { p.addLine(to: pt) }
        return p
    }
}
