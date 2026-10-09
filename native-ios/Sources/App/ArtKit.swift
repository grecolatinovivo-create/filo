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

/// Tessera piatta (spec §5, ROUND2 #2/#7). Riposo: fill `cell`, bordo 1 pt
/// stroke #35445C. Sul filo (`accesa`): fill `cellSelected` #2F4056, bordo
/// 1 pt #73674F (l'oro è riservato al filo e ai nodi). Raggio lato × 0,18
/// (8…12; 12 sulla tessera da 72 pt). Nessuna ombra né bagliore.
/// `accesaParziale` (anteprima del Sarto, solo se non accesa): bordo sarto
/// attenuato. Occupa esattamente `lato × lato`; il chiamante anima `accesa`.
struct TesseraArte: View {
    let accesa: Bool
    let lato: CGFloat
    var accesaParziale: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Arte.raggio(lato), style: .continuous)
        ZStack {
            shape.fill(accesa ? Theme.cellSelected : Theme.cell)
            shape.strokeBorder(bordo, lineWidth: 1)
        }
        .frame(width: lato, height: lato)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var bordo: Color {
        if accesa { return Theme.cellSelectedStroke }
        if accesaParziale { return Theme.sarto.opacity(0.55) }
        return Theme.border
    }
}

/// Il filo (spec §5, ROUND2 #1): UN solo tracciato continuo centro-centro,
/// oro 4,5 pt, riflesso interno 1 pt goldHighlight @ 0,55, cap/join
/// arrotondati, ombra nera 15 % r2 y1. Sta SOPRA le tessere e SOTTO i numeri.
/// Due modi di disegno:
/// - `trim` (storico): taglio del tracciato intero (0…1);
/// - `progresso` (consigliato): numero di segmenti disegnati (es. `2.4` =
///   due segmenti pieni + 40 % del terzo). Animando `progresso` da n−2 a n−1
///   si disegna SOLO il segmento nuovo: quelli già tracciati non si
///   rianimano mai. Se impostato, `trim` è ignorato.
/// `colore` permette di tingere il filo di un esito (default oro).
struct CordaOro: View {
    var punti: [CGPoint]
    var trim: CGFloat = 1
    var spessore: CGFloat = 4.5
    var colore: Color = Arte.oro
    var progresso: CGFloat? = nil

    init(punti: [CGPoint], trim: CGFloat = 1, spessore: CGFloat = 4.5,
         colore: Color = Arte.oro, progresso: CGFloat? = nil) {
        self.punti = punti
        self.trim = trim
        self.spessore = spessore
        self.colore = colore
        self.progresso = progresso
    }

    var body: some View {
        Group {
            if let progresso {
                tratto(FiloTracciato(punti: punti, progresso: progresso))
            } else {
                tratto(PolylineShape(points: punti).trim(from: 0, to: trim))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tratto<S: Shape>(_ forma: S) -> some View {
        ZStack {
            forma
                .stroke(colore, style: stile(spessore))
                .shadow(color: Arte.oroOmbra.opacity(0.15), radius: 2, y: 1)
            forma
                .stroke(Arte.oroAnima.opacity(0.55), style: stile(max(1, spessore * 0.22)))
        }
    }

    private func stile(_ w: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
    }
}

/// Tracciato del filo fino a `progresso` segmenti (animabile). Un unico
/// `Path`: i segmenti interi più la frazione dell'ultimo, così cap e join
/// restano quelli di una sola corda.
struct FiloTracciato: Shape {
    var punti: [CGPoint]
    var progresso: CGFloat

    var animatableData: CGFloat {
        get { progresso }
        set { progresso = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let primo = punti.first else { return p }
        p.move(to: primo)
        let limite = min(max(0, progresso), CGFloat(punti.count - 1))
        guard limite > 0 else { return p }
        let interi = Int(limite.rounded(.down))
        if interi >= 1 {
            for i in 1...interi { p.addLine(to: punti[i]) }
        }
        let frazione = limite - CGFloat(interi)
        if frazione > 0.001, interi + 1 < punti.count {
            let a = punti[interi], b = punti[interi + 1]
            p.addLine(to: CGPoint(x: a.x + (b.x - a.x) * frazione,
                                  y: a.y + (b.y - a.y) * frazione))
        }
        return p
    }
}

/// Filo che si cuce da sé: quando arriva un punto nuovo anima SOLO il
/// segmento nuovo (`FiloMotion.segment`, 0,12 s easeOut); se i punti
/// diminuiscono (filo concluso/azzerato) si aggiorna senza animazione.
/// Con Riduci Movimento il segmento compare subito.
struct CordaProgressiva: View {
    let punti: [CGPoint]
    var spessore: CGFloat = 4.5
    var colore: Color = Arte.oro
    var animazione: Animation = FiloMotion.segment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progresso: CGFloat = 0

    init(punti: [CGPoint], spessore: CGFloat = 4.5, colore: Color = Arte.oro,
         animazione: Animation = FiloMotion.segment) {
        self.punti = punti
        self.spessore = spessore
        self.colore = colore
        self.animazione = animazione
        // primo render già completo (niente "ricucitura" all'apparire)
        _progresso = State(initialValue: CGFloat(max(0, punti.count - 1)))
    }

    var body: some View {
        CordaOro(punti: punti, spessore: spessore, colore: colore, progresso: progresso)
            .onChange(of: punti.count) { vecchio, nuovo in
                let obiettivo = CGFloat(max(0, nuovo - 1))
                if nuovo > vecchio, nuovo >= 2, !reduceMotion {
                    withAnimation(animazione) { progresso = obiettivo }
                } else {
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { progresso = obiettivo }
                }
            }
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

/// Numero di una casella (layer SOPRA il filo, ROUND2 #1). SF Rounded
/// medium (lato × 0,42, 20…30 pt; 28 sulla tessera da 72), #F5F3ED, con un
/// contorno stretto attorno ai soli glifi: 1,5 pt `Theme.tileNumberOutline`
/// (#2F4056), ottenuto con 8 copie spostate. NESSUN disco/maschera dietro:
/// il filo resta continuo e le cifre leggibili sopra di esso.
/// Riempie il frame proposto (il chiamante lo dimensiona `lato × lato`).
/// `font` e `maschera` sono mantenuti per compatibilità ma ignorati.
/// `contorno: nil` = cifre senza contorno.
struct NumeroCella: View {
    let valore: Int
    let accesa: Bool
    var font: Font? = nil
    /// Colore del numero su tessera a riposo (default textPrimary).
    var coloreSpento: Color? = nil
    var maschera: Bool = true
    var contorno: Color? = Theme.tileNumberOutline
    var spessoreContorno: CGFloat = 1.5

    init(valore: Int, accesa: Bool, font: Font? = nil, coloreSpento: Color? = nil,
         maschera: Bool = true, contorno: Color? = Theme.tileNumberOutline,
         spessoreContorno: CGFloat = 1.5) {
        self.valore = valore
        self.accesa = accesa
        self.font = font
        self.coloreSpento = coloreSpento
        self.maschera = maschera
        self.contorno = contorno
        self.spessoreContorno = spessoreContorno
    }

    /// 8 direzioni unitarie (assi + diagonali) per il contorno.
    private static let direzioni: [CGSize] = {
        let d: CGFloat = 0.7071
        return [CGSize(width: 1, height: 0), CGSize(width: -1, height: 0),
                CGSize(width: 0, height: 1), CGSize(width: 0, height: -1),
                CGSize(width: d, height: d), CGSize(width: -d, height: d),
                CGSize(width: d, height: -d), CGSize(width: -d, height: -d)]
    }()

    var body: some View {
        GeometryReader { geo in
            let lato = min(geo.size.width, geo.size.height)
            ZStack {
                if let contorno {
                    ForEach(0..<Self.direzioni.count, id: \.self) { i in
                        cifra(lato: lato)
                            .foregroundStyle(contorno)
                            .offset(x: Self.direzioni[i].width * spessoreContorno,
                                    y: Self.direzioni[i].height * spessoreContorno)
                    }
                }
                cifra(lato: lato)
                    .foregroundStyle(accesa ? Theme.text : (coloreSpento ?? Theme.text))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func cifra(lato: CGFloat) -> some View {
        Text(verbatim: "\(valore)")
            .font(FiloFont.tile(side: lato))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
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
