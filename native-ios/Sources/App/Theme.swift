import SwiftUI

/// Design system "sartoria notturna" — palette esatta UX_SPEC §2 (normativa).
enum Theme {
    static let bg        = Color(hexRGB: 0x101418)
    static let surface   = Color(hexRGB: 0x1B222B)
    static let surface2  = Color(hexRGB: 0x232C37)
    static let border    = Color(hexRGB: 0x2C3642)
    static let text      = Color(hexRGB: 0xECEFF3)
    static let textMuted = Color(hexRGB: 0x97A3B2)
    static let filo      = Color(hexRGB: 0xE8B84B)
    static let filoHover = Color(hexRGB: 0xF0C563)
    static let filoScuro = Color(hexRGB: 0x8A6A1F)   // SOLO bordi decorativi
    static let sarto     = Color(hexRGB: 0xF5E6BC)
    static let ok        = Color(hexRGB: 0x43A06B)
    static let spezzato  = Color(hexRGB: 0xE56060)
    static let annodato  = Color(hexRGB: 0x6C93E4)
    static let overlay   = Color(hexRGB: 0x080A0D).opacity(0.72)
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

/// Bottone primario pill dorato (UX_SPEC §5.2).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.bold))
            .foregroundStyle(Theme.bg)
            .padding(.vertical, 14)
            .padding(.horizontal, 28)
            .frame(minHeight: 48)
            .background(configuration.isPressed ? Theme.filoHover : Theme.filo)
            .clipShape(Capsule())
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
