import SwiftUI

/// Un tema è una palette di colori. I nomi delle proprietà restano quelli del
/// design system originale (call-site invariati); i valori del tema `notte`
/// seguono REDESIGN_SPEC §1 ("quiet luxury": blu notte + oro misurato).
/// Alias spec → proprietà: background=bg, bg2, surface, surfaceRaised=surface2,
/// stroke=border, gold=filo, goldHighlight=filoHover, textPrimary=text,
/// textSecondary=textMuted, error=spezzato, success=ok.
struct Palette: Equatable {
    let bg: Color
    let bg2: Color          // secondo stop del gradiente di sfondo (in alto)
    let surface: Color
    let surface2: Color     // surfaceRaised: overlay, bottoni secondari, pannelli
    let border: Color       // stroke: separatori, bordi 1 pt
    let text: Color
    let textMuted: Color    // textSecondary
    let filo: Color         // gold: filo, primario, ricompense, numero obiettivo
    let filoHover: Color    // goldHighlight
    let filoScuro: Color    // oro attenuato (punti, disabilitato)
    let sarto: Color
    let ok: Color
    let spezzato: Color
    let annodato: Color
    let overlay: Color
    /// Storico: true = ramo "kit grafico" nelle schermate. Resta true per
    /// `notte` così i rami esistenti usano i componenti ridisegnati
    /// (TesseraArte, CordaOro, PannelloVelluto, IconaArte…).
    var usaArte: Bool = false
    /// Metadati, testo terziario.
    var textTertiary: Color = Color(hexRGB: 0x9AA9BA)
    /// Tessera a riposo.
    var cell: Color = Color(hexRGB: 0x1D2B42)
    /// Tessera sul filo.
    var cellSelected: Color = Color(hexRGB: 0x2F4056)
    /// Testo su oro (mai bianco).
    var onGold: Color = Color(hexRGB: 0x182235)
    /// Bordo 1 pt della tessera sul filo (l'oro resta al filo e ai nodi).
    var cellSelectedStroke: Color = Color(hexRGB: 0x73674F)
    /// Contorno 1,5 pt delle cifre delle tessere (niente disco dietro).
    var tileNumberOutline: Color = Color(hexRGB: 0x2F4056)

    /// Gradiente verticale pulito dello sfondo: bg2 (in alto) → bg (in basso).
    var bgGradient: LinearGradient {
        LinearGradient(colors: [bg2, bg], startPoint: .top, endPoint: .bottom)
    }
    /// "Gradiente" del filo: oro pieno (niente effetto slot machine).
    var filoGradient: LinearGradient {
        LinearGradient(colors: [filo, filo], startPoint: .top, endPoint: .bottom)
    }
    /// Riempimento di una casella accesa (piatto, cellSelected).
    var cellaAccesa: LinearGradient {
        LinearGradient(colors: [cellSelected, cellSelected], startPoint: .top, endPoint: .bottom)
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
            // Unico look dalla 2.0 (REDESIGN_SPEC §1): blu notte + oro caldo.
            return Palette(
                bg: Color(hexRGB: 0x090F1E), bg2: Color(hexRGB: 0x0E1628),
                surface: Color(hexRGB: 0x121C30), surface2: Color(hexRGB: 0x19253B),
                border: Color(hexRGB: 0x35445C), text: Color(hexRGB: 0xF5F3ED),
                textMuted: Color(hexRGB: 0xBEC9D7), filo: Color(hexRGB: 0xE8C27C),
                filoHover: Color(hexRGB: 0xF3D79E), filoScuro: Color(hexRGB: 0x8A6E3E),
                sarto: Color(hexRGB: 0xD9C9A3), ok: Color(hexRGB: 0x82DBB2),
                spezzato: Color(hexRGB: 0xFF959C), annodato: Color(hexRGB: 0x9DB8FF),
                overlay: Color(hexRGB: 0x050914).opacity(0.72),
                usaArte: true,
                textTertiary: Color(hexRGB: 0x9AA9BA),
                cell: Color(hexRGB: 0x1D2B42), cellSelected: Color(hexRGB: 0x2F4056),
                onGold: Color(hexRGB: 0x182235))
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
        // Dalla 1.1.0 l'identita' visiva e' UNA sola: il kit grafico "velluto
        // blu-notte + filo d'oro" (tema `notte`). I vecchi temi colore restano
        // nel codice ma non sono piu' selezionabili: chi ne aveva scelto uno
        // viene riportato a `notte` (migrazione una tantum, idempotente).
        id = .notte
        Theme.current = ThemeID.notte.palette
        UserDefaults.standard.set(ThemeID.notte.rawValue, forKey: Self.key)
    }

    /// Selezione temi disattivata: un solo look. Mantenuta per compatibilita'.
    func seleziona(_ nuovo: ThemeID, sbloccato: Bool) {
        id = .notte
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
    /// Ramo "kit" attivo nelle schermate (sempre true: tema `notte`).
    static var usaArte: Bool    { current.usaArte }

    // Token della spec 2.0 (REDESIGN_SPEC §1), con alias leggibili.
    static var textTertiary: Color  { current.textTertiary }
    static var cell: Color          { current.cell }
    static var cellSelected: Color  { current.cellSelected }
    static var onGold: Color        { current.onGold }
    /// #73674F — bordo 1 pt della tessera selezionata.
    static var cellSelectedStroke: Color { current.cellSelectedStroke }
    /// #2F4056 — contorno 1,5 pt delle cifre delle tessere.
    static var tileNumberOutline: Color  { current.tileNumberOutline }
    static var surfaceRaised: Color { current.surface2 }
    static var stroke: Color        { current.border }
    static var gold: Color          { current.filo }
    static var goldHighlight: Color { current.filoHover }
    static var textPrimary: Color   { current.text }
    static var textSecondary: Color { current.textMuted }
    static var error: Color         { current.spezzato }
    static var success: Color       { current.ok }

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

/// EYEBROW (REDESIGN_SPEC §2): SF Pro 11 semibold, MAIUSCOLO, tracking +1.2,
/// colore textTertiary. `.captionStyle()` è il nome storico; `.eyebrowStyle()`
/// è l'alias nuovo. Scala con Dynamic Type (relativo a .caption2).
struct CaptionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .filoFont(.eyebrow)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textTertiary)
    }
}

extension View {
    /// Eyebrow (nome storico).
    func captionStyle() -> some View { modifier(CaptionStyle()) }
    /// Eyebrow: 11 semibold, maiuscolo, tracking 1.2, textTertiary.
    func eyebrowStyle() -> some View { modifier(CaptionStyle()) }
}

// PrimaryButtonStyle, SecondaryButtonStyle, DestructiveButtonStyle e
// TertiaryButtonStyle vivono in DesignSystem.swift.

/// Shake orizzontale ±4pt. Non più usato dalle board (spec 2.0: mossa non
/// valida = nessun movimento); resta per compatibilità.
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
