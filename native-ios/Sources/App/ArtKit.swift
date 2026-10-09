import SwiftUI

/// KIT GRAFICO "velluto blu-notte + filo d'oro" (tema `notte`, `Theme.usaArte`).
///
/// Gli asset raster stanno in Resources/Assets.xcassets e sono prodotti da
/// `native-ios/tools/prepare_art.py` (script riproducibile): BgVelluto,
/// TileIdle/TileLit, LogoFilo, CardDaily/CardSalita, IconStar/IconMedal/IconHeart.
/// Tutte le immagini qui sono DECORATIVE (`Image(decorative:)`): non entrano
/// nell'albero di accessibilità, così le etichette esistenti (usate anche dai
/// UI test) restano identiche.
enum Arte {
    /// Corpo della tessera / lato della tela PNG (prepare_art.py: margine 8%
    /// per lato → 1 − 2·0,08). Disegnando la tela a `lato / corpoSuTela` il
    /// CORPO coincide con la cella; bagliore e ombra escono nel gap.
    static let corpoSuTela: CGFloat = 0.84
    /// Raggio d'angolo del corpo della tessera, in frazione del lato (misurato
    /// sugli asset: ~23 px su 202).
    static let raggioRelativo: CGFloat = 0.12

    static func raggio(_ lato: CGFloat) -> CGFloat { lato * raggioRelativo }

    // Oro della "corda" e dei pulsanti.
    static let oroChiaro = Color(hexRGB: 0xFFD766)
    static let oro = Color(hexRGB: 0xF5B531)
    static let oroScuro = Color(hexRGB: 0xC88A12)
    static let oroAnima = Color(hexRGB: 0xFFF6DA)      // core chiaro della corda
    static let oroOmbra = Color(hexRGB: 0x4A3004)      // contorno sottile della corda
    static let velluto = Color(hexRGB: 0x0B1230)       // pannelli semi-trasparenti

    /// Testo su tessera spenta (velluto) e accesa (oro): contrasto AA.
    static let testoSuVelluto = Color(hexRGB: 0xF2F5FB)
    static let testoSuOro = Color(hexRGB: 0x1A1408)

    static var oroGradient: LinearGradient {
        LinearGradient(colors: [oroChiaro, oro, oroScuro],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Sfondo di schermata: velluto (kit grafico) o gradiente del tema.
/// L'immagine è in overlay di un colore pieno: `scaledToFill` non può
/// allargare il layout della schermata, e il ritaglio resta nei bordi.
struct SfondoTema: View {
    var body: some View {
        if Theme.usaArte {
            Theme.bg
                .overlay {
                    Image(decorative: "BgVelluto")
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        } else {
            Theme.bgGradient.ignoresSafeArea()
        }
    }
}

/// Tessera del kit: occupa il frame proposto (lato × lato) e disegna la tela
/// PNG più grande, centrata, così il CORPO combacia con la cella. Idle e lit
/// sono sovrapposte con corpi identici: l'accensione è un cross-fade
/// d'opacità (animabile dal chiamante). `accesaParziale` = anteprima del
/// percorso del Sarto (lit attenuata sopra idle).
struct TesseraArte: View {
    let accesa: Bool
    let lato: CGFloat
    var accesaParziale: Bool = false

    var body: some View {
        let tela = lato / Arte.corpoSuTela
        Color.clear
            .overlay {
                ZStack {
                    Image(decorative: "TileIdle")
                        .resizable()
                        .interpolation(.high)
                    Image(decorative: "TileLit")
                        .resizable()
                        .interpolation(.high)
                        .opacity(accesa ? 1 : (accesaParziale ? 0.3 : 0))
                }
                .frame(width: tela, height: tela)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Il filo come "corda d'oro" (solo codice): alone dorato morbido, contorno
/// scuro sottile che la stacca dalle tessere oro, tratto in gradiente oro a
/// tre toni, riflesso e anima chiara al centro. Cap/join arrotondati.
struct CordaOro: View {
    var punti: [CGPoint]
    var trim: CGFloat = 1
    var spessore: CGFloat = 7.5

    var body: some View {
        let forma = PolylineShape(points: punti).trim(from: 0, to: trim)
        ZStack {
            forma
                .stroke(Arte.oroOmbra.opacity(0.55),
                        style: stile(spessore + 2.5))
            forma
                .stroke(Arte.oroGradient, style: stile(spessore))
                .shadow(color: Arte.oro.opacity(0.7), radius: spessore * 0.9)
                .shadow(color: Arte.oroChiaro.opacity(0.45), radius: 2)
            forma
                .stroke(Arte.oroChiaro.opacity(0.75), style: stile(spessore * 0.45))
            forma
                .stroke(Arte.oroAnima.opacity(0.9), style: stile(max(1, spessore * 0.16)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func stile(_ w: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
    }
}

/// Pannello "velluto" semi-trasparente con bordo oro sottile (card del menu,
/// riquadri). `bordoOpacita` 0 = nessun bordo oro.
struct PannelloVelluto: View {
    var raggio: CGFloat = 22
    var bordoOpacita: Double = 0.9
    var bordoSpessore: CGFloat = 1.2

    var body: some View {
        RoundedRectangle(cornerRadius: raggio)
            .fill(LinearGradient(colors: [Color(hexRGB: 0x18234F).opacity(0.72),
                                          Arte.velluto.opacity(0.82)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: raggio)
                    .strokeBorder(Arte.oroGradient, lineWidth: bordoSpessore)
                    .opacity(bordoOpacita)
            )
    }
}

/// Icona del kit (stella, medaglia, cuore), decorativa. `spenta`: grigia e
/// attenuata (stella non guadagnata, vita persa).
struct IconaArte: View {
    enum Tipo: String { case stella = "IconStar", medaglia = "IconMedal", cuore = "IconHeart" }
    let tipo: Tipo
    var spenta = false
    var lato: CGFloat = 28

    var body: some View {
        Image(decorative: tipo.rawValue)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: lato, height: lato)
            .grayscale(spenta ? 1 : 0)
            .opacity(spenta ? 0.3 : 1)
            .accessibilityHidden(true)
    }
}

/// Numero di una casella, disegnato in un LAYER SOPRA il filo (le board
/// impilano: tessere → filo → numeri). Alone di contrasto sottile: chiaro su
/// tessera accesa, scuro su tessera spenta, così il numero resta leggibile
/// anche dove passa la corda. Decorativo: le etichette d'accessibilità
/// restano sulle celle del layer di fondo.
struct NumeroCella: View {
    let valore: Int
    let accesa: Bool
    var font: Font = .system(.body, design: .monospaced).weight(.semibold)
    /// Colore su tessera spenta nella resa vettoriale (default Theme.text).
    var coloreSpento: Color? = nil

    var body: some View {
        let arte = Theme.usaArte
        Text("\(valore)")
            .font(font)
            .monospacedDigit()
            .foregroundStyle(accesa ? (arte ? Arte.testoSuOro : Theme.bg)
                                    : (arte ? Arte.testoSuVelluto : (coloreSpento ?? Theme.text)))
            .minimumScaleFactor(0.6)
            .shadow(color: accesa ? Color.white.opacity(0.65) : Color.black.opacity(0.75), radius: 1)
            .shadow(color: accesa ? Arte.oroChiaro.opacity(0.6) : Color.black.opacity(0.4), radius: 3)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Chip circolare del contatore d'ordine ("passo n"), sopra il filo.
struct BadgeOrdine: View {
    let passo: Int

    var body: some View {
        Text("\(passo)")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(Theme.filo)
            .frame(width: 16, height: 16)
            .background(Theme.bg.opacity(0.85), in: Circle())
            .overlay(Circle().strokeBorder(Theme.filo.opacity(0.5), lineWidth: 1))
            .padding(3)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
