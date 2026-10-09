import SwiftUI

/// KIT GRAFICO 2.0 — resa interamente vettoriale (REDESIGN_SPEC §1, §4, §5).
///
/// I nomi storici (`Arte`, `SfondoTema`, `TesseraArte`, `CordaOro`,
/// `PannelloVelluto`, `IconaArte`, `NumeroCella`, `BadgeOrdine`) restano per
/// compatibilità con i call-site, ma disegnano il nuovo look: tessere piatte,
/// filo d'oro sottile, card "FiloCard", icone SF Symbols. Gli asset raster
/// (BgVelluto, TileIdle/TileLit, Card*, Icon*) restano nel catalogo ma non
/// sono più usati qui. Tutto è DECORATIVO (accessibilityHidden): le etichette
/// d'accessibilità restano sulle celle/contenitori dei chiamanti.
enum Arte {
    /// Storico (tela PNG più grande della cella). Ora la tessera coincide con
    /// la cella: 1.
    static let corpoSuTela: CGFloat = 1
    /// Raggio d'angolo della tessera in frazione del lato (spec: lato × 0,18).
    static let raggioRelativo: CGFloat = 0.18

    /// Raggio della tessera: lato × 0,18, limitato a 8…12 pt (spec §3).
    static func raggio(_ lato: CGFloat) -> CGFloat { FiloMetrics.tileRadius(lato) }

    // Oro (spec §1): un solo oro pieno + un riflesso controllato.
    static let oroChiaro = Color(hexRGB: 0xF3D79E)     // goldHighlight
    static let oro = Color(hexRGB: 0xE8C27C)           // gold
    static let oroScuro = Color(hexRGB: 0x8A6E3E)      // oro attenuato
    static let oroAnima = Color(hexRGB: 0xF3D79E)      // riflesso interno del filo
    static let oroOmbra = Color.black                  // ombra del filo (al 15 %)
    /// Storico "velluto": ora è il colore surface.
    static let velluto = Color(hexRGB: 0x121C30)

    /// Testo su tessera / superficie e su oro (contrasto AA).
    static let testoSuVelluto = Color(hexRGB: 0xF5F3ED)
    static let testoSuOro = Color(hexRGB: 0x182235)

    /// Oro pieno (niente gradiente "slot machine").
    static var oroGradient: LinearGradient {
        LinearGradient(colors: [oro, oro], startPoint: .top, endPoint: .bottom)
    }
}

/// Sfondo di schermata: gradiente verticale pulito + luce radiale morbida
/// (vedi `FiloBackground`). Niente bitmap velluto, niente particelle.
struct SfondoTema: View {
    var body: some View {
        FiloBackground()
    }
}

/// Tessera piatta (spec §5). Riposo: fill `cell`, bordo 1 pt stroke.
/// Sul filo (`accesa`): fill `cellSelected`, bordo oro 1,5 pt. Raggio
/// lato × 0,18 (8…12). Nessuna ombra né bagliore. `accesaParziale`
/// (anteprima del Sarto, solo se non accesa): bordo sarto attenuato.
/// Occupa esattamente `lato × lato`; il chiamante anima `accesa`.
struct TesseraArte: View {
    let accesa: Bool
    let lato: CGFloat
    var accesaParziale: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Arte.raggio(lato), style: .continuous)
        ZStack {
            shape.fill(accesa ? Theme.cellSelected : Theme.cell)
            shape.strokeBorder(bordo, lineWidth: accesa ? 1.5 : 1)
        }
        .frame(width: lato, height: lato)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var bordo: Color {
        if accesa { return Theme.filo }
        if accesaParziale { return Theme.sarto.opacity(0.55) }
        return Theme.border
    }
}

/// Il filo (spec §5): tratto principale oro 4,5 pt, riflesso interno 1 pt
/// goldHighlight @ 0,55, cap/join arrotondati, ombra nera 15 % r2 y1.
/// `trim` anima il segmento nuovo (0,12 s easeOut, lo gestisce il chiamante).
/// `colore` permette di tingere il filo di un esito (default oro).
struct CordaOro: View {
    var punti: [CGPoint]
    var trim: CGFloat = 1
    var spessore: CGFloat = 4.5
    var colore: Color = Arte.oro

    var body: some View {
        let forma = PolylineShape(points: punti).trim(from: 0, to: trim)
        ZStack {
            forma
                .stroke(colore, style: stile(spessore))
                .shadow(color: Arte.oroOmbra.opacity(0.15), radius: 2, y: 1)
            forma
                .stroke(Arte.oroAnima.opacity(0.55), style: stile(max(1, spessore * 0.22)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func stile(_ w: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
    }
}

/// Storico pannello "velluto": ora disegna lo sfondo di una FiloCard
/// (surface, bordo 1 pt stroke @ 0,6, nessun bagliore). `bordoOpacita` 0 =
/// senza bordo; `bordoSpessore` è ignorato (sempre 1 pt). Per contenuti nuovi
/// usare `FiloCard` / `.filoCard()`.
struct PannelloVelluto: View {
    var raggio: CGFloat = FiloMetrics.cardRadius
    var bordoOpacita: Double = 0.9
    var bordoSpessore: CGFloat = 1

    var body: some View {
        FiloCardBackground(radius: raggio, bordered: bordoOpacita > 0)
    }
}

/// Icona decorativa (spec §4): stella `star.fill`/`star`, medaglia
/// `medal.fill`, "cuore" = nodo d'oro (vite della Salita). `spenta`: stella
/// a contorno textTertiary / nodo vuoto.
struct IconaArte: View {
    enum Tipo: String { case stella = "IconStar", medaglia = "IconMedal", cuore = "IconHeart" }
    let tipo: Tipo
    var spenta = false
    var lato: CGFloat = 28

    var body: some View {
        Group {
            switch tipo {
            case .stella:
                StarIcon(earned: !spenta, size: lato)
            case .medaglia:
                MedalIcon(size: lato)
                    .opacity(spenta ? 0.35 : 1)
            case .cuore:
                KnotDot(filled: !spenta, size: max(8, lato * 0.7))
                    .frame(width: lato, height: lato)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Numero di una casella (layer SOPRA il filo). SF Rounded medium
/// (lato × 0,42, 20…30 pt) su una piccola maschera circolare (≈ 0,56 × lato)
/// del colore della tessera, così il filo non attraversa mai una cifra.
/// Riempie il frame proposto (il chiamante lo dimensiona `lato × lato`).
/// `font` è mantenuto per compatibilità ma ignorato (la misura deriva dal
/// lato). `maschera: false` = nessun cerchio.
struct NumeroCella: View {
    let valore: Int
    let accesa: Bool
    var font: Font? = nil
    /// Colore del numero su tessera a riposo (default textPrimary).
    var coloreSpento: Color? = nil
    var maschera: Bool = true

    var body: some View {
        GeometryReader { geo in
            let lato = min(geo.size.width, geo.size.height)
            ZStack {
                if maschera {
                    Circle()
                        .fill(accesa ? Theme.cellSelected : Theme.cell)
                        .frame(width: lato * 0.56, height: lato * 0.56)
                }
                Text(verbatim: "\(valore)")
                    .font(FiloFont.tile(side: lato))
                    .monospacedDigit()
                    .foregroundStyle(accesa ? Theme.text : (coloreSpento ?? Theme.text))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Storico chip "passo n": la spec 2.0 rimuove i badge d'ordine dalle
/// tessere. Non disegna nulla.
struct BadgeOrdine: View {
    let passo: Int

    var body: some View {
        EmptyView()
    }
}
