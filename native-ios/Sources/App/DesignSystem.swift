import SwiftUI
import UIKit
import FiloCore

// DESIGN SYSTEM 2.0 ("quiet luxury") — REDESIGN_SPEC §2, §3, §4, §8.
// Componenti condivisi da tutte le schermate. Colori: `Theme.*` (Theme.swift).
// Documentazione per le schermate: /home/claude/redesign/notes/COMPONENTS.md.

// MARK: - Metriche (spec §3)

/// Griglia a 8 pt e misure ricorrenti.
enum FiloMetrics {
    /// Margine orizzontale di schermata: 24 pt (16 se la larghezza < 390).
    static func margin(forWidth width: CGFloat) -> CGFloat { width < 390 ? 16 : 24 }
    static let sectionGap: CGFloat = 24
    static let sectionGapLarge: CGFloat = 32
    static let relatedGap: CGFloat = 8
    static let relatedGapLarge: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let cardPaddingLarge: CGFloat = 24
    static let cardRadius: CGFloat = 20
    static let buttonRadius: CGFloat = 16
    static let primaryHeight: CGFloat = 56
    static let secondaryHeight: CGFloat = 48
    static let minTouch: CGFloat = 44
    static let headerHeight: CGFloat = 48
    /// Da usare con `.presentationCornerRadius(FiloMetrics.sheetCorner)`.
    static let sheetCorner: CGFloat = 28
    /// Raggio della tessera: lato × 0,18, limitato a 8…12 pt.
    static func tileRadius(_ side: CGFloat) -> CGFloat { min(12, max(8, side * 0.18)) }
}

// MARK: - Tipografia (spec §2)

/// Ruoli tipografici. Solo font di sistema; niente `.monospaced`.
enum FiloTextRole {
    case hero, screenTitle, headerTitle, target, currentSum, tile, stat
    case cardTitle, body, button, caption, eyebrow

    var size: CGFloat {
        switch self {
        case .hero: return 32
        case .screenTitle: return 26
        case .headerTitle: return 17
        case .target: return 64
        case .currentSum: return 30
        case .tile: return 28
        case .stat: return 32
        case .cardTitle: return 18
        case .body: return 15
        case .button: return 16
        case .caption: return 13
        case .eyebrow: return 11
        }
    }

    var weight: Font.Weight {
        switch self {
        case .hero, .screenTitle, .headerTitle, .currentSum, .stat, .cardTitle, .button, .eyebrow:
            return .semibold
        case .target: return .bold
        case .tile, .caption: return .medium
        case .body: return .regular
        }
    }

    var design: Font.Design {
        switch self {
        case .hero: return .serif
        case .target, .currentSum, .tile, .stat: return .rounded
        default: return .default
        }
    }

    var tracking: CGFloat {
        switch self {
        case .hero, .screenTitle, .currentSum, .stat: return -0.5
        case .target: return -1.5
        case .cardTitle, .button: return -0.2
        case .eyebrow: return 1.2
        default: return 0
        }
    }

    /// Stile di riferimento per Dynamic Type.
    var textStyle: Font.TextStyle {
        switch self {
        case .hero, .screenTitle, .target, .stat: return .largeTitle
        case .headerTitle, .cardTitle, .button: return .headline
        case .currentSum: return .title
        case .tile, .body: return .body
        case .caption: return .footnote
        case .eyebrow: return .caption2
        }
    }

    /// Crescita massima con Dynamic Type (i numeri grandi restano contenuti).
    var maxScale: CGFloat {
        switch self {
        case .target, .stat, .hero, .currentSum, .tile: return 1.15
        case .screenTitle: return 1.3
        default: return 2.0
        }
    }

    /// Font a dimensione fissa (base della spec).
    var font: Font { .system(size: size, weight: weight, design: design) }
}

/// Helper `Font` a dimensione fissa (spec §2). Per il tracking e il Dynamic
/// Type preferire il modificatore `.filoFont(_:)`.
enum FiloFont {
    /// New York 32 semibold (titolo editoriale).
    static func hero() -> Font { FiloTextRole.hero.font }
    /// SF Pro 26 semibold (titolo di schermata).
    static func screenTitle() -> Font { FiloTextRole.screenTitle.font }
    /// SF Pro 17 semibold (titolo centrato nell'header 48 pt).
    static func headerTitle() -> Font { FiloTextRole.headerTitle.font }
    /// SF Rounded bold, 64 pt di default (numero obiettivo).
    static func target(_ size: CGFloat = 64) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    /// SF Rounded 30 semibold (somma attuale).
    static func currentSum() -> Font { FiloTextRole.currentSum.font }
    /// SF Rounded medium per il numero di una tessera (THREAD_V3 §2):
    /// lato × 0,39, 20…28 pt (28 sulla tessera da 72).
    static func tile(side: CGFloat) -> Font {
        .system(size: min(28, max(20, side * 0.39)), weight: .medium, design: .rounded)
    }
    /// SF Rounded 32 semibold (numeri delle statistiche).
    static func stat() -> Font { FiloTextRole.stat.font }
    /// SF Pro 18 semibold.
    static func cardTitle() -> Font { FiloTextRole.cardTitle.font }
    /// SF Pro 15 regular.
    static func body() -> Font { FiloTextRole.body.font }
    /// SF Pro 16 semibold.
    static func button() -> Font { FiloTextRole.button.font }
    /// SF Pro 13 medium.
    static func caption() -> Font { FiloTextRole.caption.font }
    /// SF Pro 11 semibold (usare con `.eyebrowStyle()` per maiuscolo+tracking).
    static func eyebrow() -> Font { FiloTextRole.eyebrow.font }
}

/// Applica font + tracking del ruolo, scalando con Dynamic Type (limitato
/// da `maxScale`).
struct FiloFontModifier: ViewModifier {
    let role: FiloTextRole
    @ScaledMetric private var scaled: CGFloat

    init(role: FiloTextRole) {
        self.role = role
        _scaled = ScaledMetric(wrappedValue: role.size, relativeTo: role.textStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: min(scaled, role.size * role.maxScale),
                          weight: role.weight, design: role.design))
            .tracking(role.tracking)
    }
}

extension View {
    /// Font + tracking di un ruolo tipografico della spec, con Dynamic Type.
    func filoFont(_ role: FiloTextRole) -> some View { modifier(FiloFontModifier(role: role)) }
}

// MARK: - Motion (spec §4, §8)

/// Curve d'animazione condivise. Con Riduci Movimento usare `reduced`
/// (o `adaptive(_:reduceMotion:)`): niente spring, scale né traslazioni.
enum FiloMotion {
    /// Tessera toccata per prima: scale 0,97 → 1.
    static let tile = Animation.spring(response: 0.24, dampingFraction: 0.78)
    /// Stelle del risultato (scale 0,65 → 1).
    static let star = Animation.spring(response: 0.34, dampingFraction: 0.68)
    /// Medaglia (fade + scale 0,9 → 1).
    static let medal = Animation.spring(response: 0.38, dampingFraction: 0.78)
    /// Cambio schermata / apertura partita (crossfade + 12 pt).
    static let screen = Animation.easeOut(duration: 0.24)
    /// Cambio livello Salita (crossfade + 12 pt).
    static let level = Animation.easeInOut(duration: 0.30)
    /// Nuovo segmento del filo.
    static let segment = Animation.easeOut(duration: 0.12)
    /// Aggiornamento numerico (con `.contentTransition(.numericText())`).
    static let numeric = Animation.easeOut(duration: 0.16)
    /// Pressione dei bottoni.
    static let press = Animation.easeOut(duration: 0.12)
    /// Somma esatta: nodo finale 1 → 1,08 → 1.
    static let settle = Animation.spring(response: 0.30, dampingFraction: 0.70)
    /// Vicolo cieco: il nodo finale si contrae di 3 pt.
    static let contract = Animation.spring(response: 0.28, dampingFraction: 0.85)
    /// Filo spezzato: l'ultimo segmento perde tensione e svanisce.
    static let slack = Animation.easeIn(duration: 0.24)
    /// Filo tagliato dall'utente: dissolvenza.
    static let cut = Animation.easeIn(duration: 0.30)
    /// Vita persa (nodo che si svuota).
    static let lifeLost = Animation.easeOut(duration: 0.18)
    /// Nodo estremo del filo (spostamento/comparsa).
    static let node = Animation.spring(response: 0.24, dampingFraction: 0.78)
    /// Indicatori fili/vite: consumo in dissolvenza 0,18 s easeOut.
    static let indicator = Animation.easeOut(duration: 0.18)
    /// Intervallo (s) fra le stelle del risultato.
    static let starInterval: Double = 0.18
    /// Fade unico con Riduci Movimento.
    static let reduced = Animation.easeInOut(duration: 0.15)

    // Filo V3 — "il filo prende la casella" (THREAD_V3_SPEC §3). Le fasi del
    // filo sono disegnate dal Canvas di `FiloSeta` (TimelineView), queste
    // sono le durate normative.
    /// 0–60 ms: il filo raggiunge l'ingresso della casella (easeOut).
    static let threadReachDuration: Double = 0.06
    /// 60–200 ms: l'asola si forma attorno al numero (easeOut).
    static let loopFormDuration: Double = 0.14
    /// L'estremo precedente diventa intermedio: l'asola si riconfigura.
    static let loopMorphDuration: Double = 0.10
    /// Durata totale della presa (0,06 + 0,14, + margine della tensione).
    static let takeDuration: Double = 0.24
    /// 60–240 ms: la tessera reagisce alla tensione (scala 1 → 0,985 → 1).
    static let tension = Animation.spring(response: 0.24, dampingFraction: 0.84)
    static let tensionScale: CGFloat = 0.985
    static let tensionDelay: Double = 0.06
    /// Filo spezzato: i capi si separano (easeOut 0,16 s), poi dissolvenza.
    static let frayDuration: Double = 0.16
    /// Filo annodato: ricciolo terminale 270° in 0,20 s, resta 0,35 s.
    static let knotDuration: Double = 0.20
    static let knotHold: Double = 0.35
    /// Riduci Movimento: solo cambio di colore + dissolvenza ≤ 0,12 s.
    static let reducedFadeDuration: Double = 0.12
    /// Durate (s) utili per le sequenze temporizzate.
    static let screenDuration: Double = 0.24
    static let reducedDuration: Double = 0.15

    /// `animation` normalmente, `reduced` con Riduci Movimento.
    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }
}

// MARK: - Haptics (spec §4, §8, ROUND2 #14)

/// Servizio haptics unico. Rispetta l'interruttore `filo.haptics` (default
/// acceso). Generatori creati una volta e preparati in anticipo.
/// Anti-doppioni:
/// - selezione limitata a una ogni 90 ms;
/// - un solo haptic d'ESITO (success/warning/error/medium) per finestra di
///   0,30 s: se due chiamanti segnalano lo stesso evento (es. filo perso +
///   vita persa) vibra solo il primo;
/// - nessuna selezione nei 120 ms successivi a un esito (la casella che
///   chiude il filo non vibra due volte).
@MainActor
enum FiloHaptics {
    /// Chiave UserDefaults dell'interruttore "Vibrazione" (default true).
    static let defaultsKey = "filo.haptics"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Intervallo minimo fra due selezioni (s).
    static let selectionInterval: TimeInterval = 0.09
    /// Finestra in cui un secondo haptic d'esito viene ignorato (s).
    static let outcomeWindow: TimeInterval = 0.30
    /// Pausa della selezione dopo un esito (s).
    static let selectionQuietAfterOutcome: TimeInterval = 0.12

    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static var lastSelection: TimeInterval = -1_000
    private static var lastOutcome: TimeInterval = -1_000

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Prepara i generatori (chiamare all'apparire di una board/schermata).
    static func prepare() {
        guard isEnabled else { return }
        selectionGenerator.prepare()
        lightGenerator.prepare()
        mediumGenerator.prepare()
        notificationGenerator.prepare()
    }

    /// Nuova casella nel filo (throttled ≥ 90 ms, silenziosa subito dopo un esito).
    static func selection() {
        guard isEnabled else { return }
        let t = now
        guard t - lastSelection >= selectionInterval,
              t - lastOutcome >= selectionQuietAfterOutcome else { return }
        lastSelection = t
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    /// Tap su un'azione primaria, stelle 1-2, medaglia.
    static func light() {
        guard isEnabled else { return }
        lightGenerator.impactOccurred()
        lightGenerator.prepare()
    }

    /// Filo tagliato, terza stella (conta come esito: niente doppioni).
    static func medium() {
        guard isEnabled, reclamaEsito() else { return }
        mediumGenerator.impactOccurred()
        mediumGenerator.prepare()
    }

    /// Somma esatta, livello superato.
    static func success() { notify(.success) }
    /// Vicolo cieco (annodato), vita persa.
    static func warning() { notify(.warning) }
    /// Somma superata (spezzato).
    static func error() { notify(.error) }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled, reclamaEsito() else { return }
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
    }

    /// True se nessun altro esito ha vibrato negli ultimi `outcomeWindow` s.
    private static func reclamaEsito() -> Bool {
        let t = now
        guard t - lastOutcome >= outcomeWindow else { return false }
        lastOutcome = t
        return true
    }
}

// MARK: - Sfondo (spec §1)

/// Sfondo di schermata: gradiente verticale pulito #0E1628 → #090F1E con una
/// luce radiale molto morbida in alto al centro. Niente bitmap né particelle.
struct FiloBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bg2, Theme.bg], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hexRGB: 0x1A2742).opacity(0.35), Color(hexRGB: 0x1A2742).opacity(0)],
                           center: .top, startRadius: 0, endRadius: 440)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Bottoni (spec §4)

/// Primario: oro pieno, testo onGold 16 semibold, altezza 56, raggio 16,
/// nessun bagliore. Premuto: scale 0,975 (0,12 s). L'haptic leggero lo
/// esegue il chiamante (`FiloHaptics.light()`). `fullWidth` = larghezza piena.
struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        FiloButtonBody(configuration: configuration, kind: .primary, fullWidth: fullWidth, enabled: true)
    }
}

/// Secondario: fondo surfaceRaised, bordo 1 pt stroke, testo primario,
/// altezza 48, raggio 16. `enabled: false` = aspetto disabilitato (usare
/// anche `.disabled(...)` sul Button).
struct SecondaryButtonStyle: ButtonStyle {
    var enabled = true
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        FiloButtonBody(configuration: configuration, kind: .secondary, fullWidth: fullWidth, enabled: enabled)
    }
}

/// Distruttivo ("Taglia il filo"): testo error su surfaceRaised, bordo 1 pt
/// stroke, altezza 48. Niente oro.
struct DestructiveButtonStyle: ButtonStyle {
    var enabled = true
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        FiloButtonBody(configuration: configuration, kind: .destructive, fullWidth: fullWidth, enabled: enabled)
    }
}

/// Terziario: solo testo/icona, area di tocco minima 44×44.
struct TertiaryButtonStyle: ButtonStyle {
    var color: Color = Theme.textMuted

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .filoFont(.button)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(minWidth: FiloMetrics.minTouch, minHeight: FiloMetrics.minTouch)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(FiloMotion.press, value: configuration.isPressed)
    }
}

private struct FiloButtonBody: View {
    enum Kind { case primary, secondary, destructive }

    let configuration: ButtonStyleConfiguration
    let kind: Kind
    let fullWidth: Bool
    let enabled: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var attivo: Bool { enabled && isEnabled }

    private var foreground: Color {
        switch kind {
        case .primary: return Theme.onGold
        case .secondary: return attivo ? Theme.text : Theme.textTertiary
        case .destructive: return attivo ? Theme.spezzato : Theme.textTertiary
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FiloMetrics.buttonRadius, style: .continuous)
        let pressed = configuration.isPressed && attivo
        configuration.label
            .filoFont(.button)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .frame(maxWidth: fullWidth ? .infinity : nil,
                   minHeight: kind == .primary ? FiloMetrics.primaryHeight : FiloMetrics.secondaryHeight)
            .background {
                ZStack {
                    if kind == .primary {
                        shape.fill(pressed ? Theme.filoHover : Theme.filo)
                    } else {
                        shape.fill(Theme.surface2)
                        shape.strokeBorder(Theme.border, lineWidth: 1)
                    }
                }
            }
            .contentShape(shape)
            .opacity(attivo ? 1 : (kind == .primary ? 0.45 : 0.6))
            .scaleEffect(pressed && !reduceMotion ? 0.975 : 1)
            .animation(FiloMotion.press, value: configuration.isPressed)
    }
}

/// Bottone-icona dell'header: SF Symbol 19 pt medium in un'area 44×44.
/// `label` è l'etichetta d'accessibilità (chiave del catalogo).
struct FiloIconButton: View {
    let systemName: String
    let label: LocalizedStringKey
    var tint: Color = Theme.textMuted
    let action: () -> Void

    init(systemName: String, label: LocalizedStringKey, tint: Color = Theme.textMuted,
         action: @escaping () -> Void) {
        self.systemName = systemName
        self.label = label
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: FiloMetrics.minTouch, height: FiloMetrics.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Card (spec §4)

/// Sfondo di una FiloCard: surface, raggio 20, bordo 1 pt stroke @ 0,6,
/// niente bagliore. `floating`: ombra nera 18 %, raggio 16, y 6 (solo card
/// fluttuanti / sheet).
struct FiloCardBackground: View {
    var radius: CGFloat = FiloMetrics.cardRadius
    var floating: Bool = false
    var bordered: Bool = true
    var fill: Color = Theme.surface

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(fill)
            .overlay {
                if bordered {
                    shape.strokeBorder(Theme.border.opacity(0.6), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(floating ? 0.18 : 0), radius: floating ? 16 : 0, y: floating ? 6 : 0)
    }
}

/// Card contenitore: padding (16 default, 24 per la card di oggi), larghezza
/// piena, sfondo `FiloCardBackground`.
struct FiloCard<Content: View>: View {
    var padding: CGFloat
    var radius: CGFloat
    var floating: Bool
    var alignment: Alignment
    let content: Content

    init(padding: CGFloat = FiloMetrics.cardPadding,
         radius: CGFloat = FiloMetrics.cardRadius,
         floating: Bool = false,
         alignment: Alignment = .leading,
         @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.radius = radius
        self.floating = floating
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: alignment)
            .background(FiloCardBackground(radius: radius, floating: floating))
    }
}

extension View {
    /// Applica il look FiloCard a una vista esistente.
    func filoCard(padding: CGFloat = FiloMetrics.cardPadding,
                  radius: CGFloat = FiloMetrics.cardRadius,
                  floating: Bool = false) -> some View {
        self
            .padding(padding)
            .background(FiloCardBackground(radius: radius, floating: floating))
    }
}

/// Card dato (Statistiche): numero SF Rounded 32 semibold + etichetta 13,
/// surface, padding 16, raggio 16, altezza minima 104. Elemento
/// d'accessibilità unico (etichetta + valore).
struct StatCard: View {
    let value: String
    let label: LocalizedStringKey
    var valueColor: Color = Theme.text

    init(value: String, label: LocalizedStringKey, valueColor: Color = Theme.text) {
        self.value = value
        self.label = label
        self.valueColor = valueColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: value)
                .filoFont(.stat)
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .filoFont(.caption)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .bottomLeading)
        .background(FiloCardBackground(radius: 16))
        .accessibilityElement(children: .combine)
    }
}

/// Chip: altezza 32, raggio 16, testo 13 medium, SF Symbol opzionale.
/// `filled`: tinta al 14 % (es. "Completato" con `tint: Theme.ok`).
struct Chip: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var tint: Color = Theme.textMuted
    var filled: Bool = false

    init(_ title: LocalizedStringKey, systemImage: String? = nil,
         tint: Color = Theme.textMuted, filled: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.filled = filled
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(title)
                .filoFont(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(Capsule().fill(filled ? tint.opacity(0.14) : Theme.surface2))
        .overlay(Capsule().strokeBorder(filled ? tint.opacity(0.35) : Theme.border, lineWidth: 1))
    }
}

// MARK: - Ricompense (spec §4)

/// Stella vettoriale: `star.fill` oro se guadagnata, `star` contorno
/// textTertiary se no. Decorativa.
struct StarIcon: View {
    let earned: Bool
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: earned ? "star.fill" : "star")
            .font(.system(size: size * 0.9, weight: .medium))
            .foregroundStyle(earned ? Theme.filo : Theme.textTertiary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Fila di stelle (3 × 32 pt, gap 12). `visible` (opzionale) = quante stelle
/// mostrare: le altre restano a scale 0,65 / opacità 0 e compaiono con
/// `FiloMotion.star` quando il chiamante incrementa `visible` (gli haptics
/// light/light/medium li esegue il chiamante). Con Riduci Movimento: solo
/// fade. Decorativa: l'etichetta d'accessibilità la mette il chiamante.
struct StarRow: View {
    let earned: Int
    var total: Int = 3
    var visible: Int? = nil
    var size: CGFloat = 32
    var spacing: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(earned: Int, total: Int = 3, visible: Int? = nil, size: CGFloat = 32, spacing: CGFloat = 12) {
        self.earned = earned
        self.total = total
        self.visible = visible
        self.size = size
        self.spacing = spacing
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<max(0, total), id: \.self) { i in
                let mostrata = visible.map { i < $0 } ?? true
                StarIcon(earned: i < earned, size: size)
                    .scaleEffect(mostrata || reduceMotion ? 1 : 0.65)
                    .opacity(mostrata ? 1 : 0)
                    .animation(reduceMotion ? FiloMotion.reduced : FiloMotion.star, value: mostrata)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Medaglia del Sarto: SF Symbol `medal.fill` oro, 24 pt. Decorativa.
struct MedalIcon: View {
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: "medal.fill")
            .font(.system(size: size * 0.9, weight: .medium))
            .foregroundStyle(Theme.filo)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Indicatori di gioco (spec §4)

/// Nodo (vita) della Salita: puntino 14 pt, pieno oro = disponibile,
/// contorno stroke = perso. Decorativo.
struct KnotDot: View {
    let filled: Bool
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().fill(filled ? Theme.filo : Color.clear)
            Circle().strokeBorder(filled ? Theme.filo : Theme.border, lineWidth: 1.5)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Pallino degli indicatori fili/vite (ROUND2 #3/#9): 10 pt pieno,
/// oro #E8C27C = disponibile, #35445C (stroke) = consumato. Decorativo.
struct IndicatorDot: View {
    let available: Bool
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(available ? Theme.filo : Theme.border)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Vite della Salita (ROUND2 #9): `total` pallini 10 pt, gap 6 (oro = vita
/// rimasta, stroke = persa; dissolvenza 0,18 s easeOut). Con
/// `showsText: true` aggiunge a destra (gap 8) "%lld vite" (13 medium,
/// textSecondary) oppure "Ultima vita" in colore error con 1 vita.
/// Etichetta d'accessibilità invariata (elemento unico): "Vite rimaste: n di 3".
struct LivesIndicator: View {
    let lives: Int
    var total: Int = 3
    var size: CGFloat = 10
    var showsText: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(lives: Int, total: Int = 3, size: CGFloat = 10, showsText: Bool = false) {
        self.lives = lives
        self.total = total
        self.size = size
        self.showsText = showsText
    }

    var body: some View {
        HStack(spacing: FiloMetrics.relatedGap) {
            HStack(spacing: 6) {
                ForEach(0..<max(0, total), id: \.self) { i in
                    IndicatorDot(available: i < lives, size: size)
                }
            }
            if showsText {
                Group {
                    if lives == 1 {
                        Text("Ultima vita")
                            .foregroundStyle(Theme.error)
                    } else {
                        Text("\(lives) vite")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .filoFont(.caption)
                .monospacedDigit()
                .lineLimit(1)
            }
        }
        .animation(reduceMotion ? FiloMotion.reduced : FiloMotion.indicator, value: lives)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Vite rimaste: \(lives) di 3"))
    }
}

/// Fili rimasti (ROUND2 #3): 3 pallini 10 pt, gap 6 (oro #E8C27C =
/// disponibile, #35445C = usato; consumo in dissolvenza 0,18 s easeOut) +
/// testo "%lld fili rimasti" (it: 1 → "1 filo rimasto"; SF Pro 13 medium,
/// textSecondary), gap 8. `showsText: false` = solo pallini.
/// Etichetta d'accessibilità invariata (elemento unico, da tenere ULTIMO
/// nell'HUD): "Fili rimasti: n di 3". `outcomes` è mantenuto per
/// compatibilità (la resa dipende solo da `remaining`).
/// Uso: `ThreadsLeftIndicator(outcomes: vm.engine.fili.map(\.esito), remaining: vm.engine.filiRimasti)`.
struct ThreadsLeftIndicator: View {
    let outcomes: [EsitoFilo]
    let remaining: Int
    var total: Int = 3
    var showsText: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(outcomes: [EsitoFilo] = [], remaining: Int, total: Int = 3, showsText: Bool = true) {
        self.outcomes = outcomes
        self.remaining = remaining
        self.total = total
        self.showsText = showsText
    }

    var body: some View {
        HStack(spacing: FiloMetrics.relatedGap) {
            HStack(spacing: 6) {
                ForEach(0..<max(0, total), id: \.self) { i in
                    IndicatorDot(available: i < remaining, size: 10)
                }
            }
            if showsText {
                Text("\(remaining) fili rimasti")
                    .filoFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .animation(reduceMotion ? FiloMotion.reduced : FiloMotion.indicator, value: remaining)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Fili rimasti: \(remaining) di 3"))
    }
}

// MARK: - Transizione schermata

extension View {
    /// Spostamento di 12 pt sincronizzato con `TileTransitionController`: la
    /// schermata appare con crossfade + 12 pt (spec §6.2). Niente
    /// traslazione con Riduci Movimento.
    func filoScreenShift(_ controller: TileTransitionController) -> some View {
        modifier(FiloScreenShift(controller: controller))
    }
}

private struct FiloScreenShift: ViewModifier {
    @ObservedObject var controller: TileTransitionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(y: controller.fase == .entrata && !reduceMotion ? 12 : 0)
            .animation(reduceMotion ? nil : FiloMotion.screen, value: controller.fase)
    }
}

// MARK: - Tempo (SALITA_TIMER_SPEC §0/§1)

/// Cronometro MONOTONO (ContinuousClock: mai `Date`, immune ai cambi
/// d'orologio). Accumula i secondi dei tratti in corsa; `ferma()` chiude il
/// tratto corrente. Usato dal conto alla rovescia della Salita e dal tempo
/// attivo del FILO del giorno.
struct FiloCronometro: Equatable {
    private(set) var accumulato: Double
    private(set) var inizio: ContinuousClock.Instant?

    init(accumulato: Double = 0) {
        self.accumulato = max(0, accumulato)
        self.inizio = nil
    }

    var inCorsa: Bool { inizio != nil }

    /// Secondi trascorsi (tratti chiusi + tratto in corso).
    func trascorso(_ adesso: ContinuousClock.Instant = ContinuousClock.now) -> Double {
        guard let inizio else { return accumulato }
        return accumulato + Self.secondi(inizio.duration(to: adesso))
    }

    mutating func avvia(_ adesso: ContinuousClock.Instant = ContinuousClock.now) {
        guard inizio == nil else { return }
        inizio = adesso
    }

    mutating func ferma(_ adesso: ContinuousClock.Instant = ContinuousClock.now) {
        guard let i = inizio else { return }
        accumulato += Self.secondi(i.duration(to: adesso))
        inizio = nil
    }

    mutating func azzera() {
        accumulato = 0
        inizio = nil
    }

    static func secondi(_ d: Duration) -> Double {
        let c = d.components
        return max(0, Double(c.seconds) + Double(c.attoseconds) / 1e18)
    }
}

/// Formattazione dei tempi "m:ss" (es. 0:48, 3:07, 75:02).
enum FiloDurata {
    static func testo(secondi: Int) -> String {
        let s = max(0, secondi)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Barra del conto alla rovescia (Salita): 3 pt, raggio 1,5, si svuota da
/// sinistra a destra (la parte piena resta ancorata a destra). Colore per
/// quota rimasta: > 30 % oro #D8B56A, 30–15 % ambra #C58A48, < 15 % corallo
/// #B45A52 (il testo accanto resta avorio: il colore non è mai l'unico
/// indizio). Decorativa: l'etichetta d'accessibilità va sul contenitore.
/// Uso: `CountdownBar(frazione: 0.62)`.
struct CountdownBar: View {
    let frazione: Double
    var altezza: CGFloat = 3

    init(frazione: Double, altezza: CGFloat = 3) {
        self.frazione = frazione
        self.altezza = altezza
    }

    static let oro = Color(hexRGB: 0xD8B56A)
    static let ambra = Color(hexRGB: 0xC58A48)
    static let corallo = Color(hexRGB: 0xB45A52)

    /// Colore per quota rimasta (0…1).
    static func colore(frazione f: Double) -> Color {
        if f > 0.30 { return oro }
        if f >= 0.15 { return ambra }
        return corallo
    }

    var body: some View {
        let f = min(1, max(0, frazione))
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                Capsule().fill(Theme.stroke.opacity(0.7))
                Capsule()
                    .fill(Self.colore(frazione: f))
                    .frame(width: geo.size.width * f)
            }
        }
        .frame(height: altezza)
        .clipShape(RoundedRectangle(cornerRadius: altezza / 2, style: .continuous))
        .accessibilityHidden(true)
    }
}
