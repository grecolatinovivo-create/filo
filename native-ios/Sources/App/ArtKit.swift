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

    /// Spessore del filo in funzione della tessera (ROUND3 #1):
    /// lato × 0,075, limitato a 4,5…6 pt (≈ 5,4 sulla tessera da 72).
    static func spessoreFilo(_ lato: CGFloat) -> CGFloat { min(6, max(4.5, lato * 0.075)) }
    /// Larghezza dell'alone delle cifre (ROUND3 #2): lato × 0,045,
    /// limitata a 2,5…3,5 pt (≈ 3,2 sulla tessera da 72).
    static func aloneCifra(_ lato: CGFloat) -> CGFloat { min(3.5, max(2.5, lato * 0.045)) }

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
/// THREAD_V3 §3: quando il filo PRENDE la tessera (`accesa` false → true) la
/// tessera reagisce alla tensione: scala 1 → 0,985 → 1 (60–240 ms,
/// spring 0,24/0,84), rotazione 0°. Niente con Riduci Movimento. Tutte le
/// board (giornaliera, Salita, riscaldamento, archivio, demo) lo ereditano.
struct TesseraArte: View {
    let accesa: Bool
    let lato: CGFloat
    var accesaParziale: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tensione: CGFloat = 1

    init(accesa: Bool, lato: CGFloat, accesaParziale: Bool = false) {
        self.accesa = accesa
        self.lato = lato
        self.accesaParziale = accesaParziale
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Arte.raggio(lato), style: .continuous)
        ZStack {
            shape.fill(accesa ? Theme.cellSelected : Theme.cell)
            shape.strokeBorder(bordo, lineWidth: 1)
        }
        .frame(width: lato, height: lato)
        .scaleEffect(tensione)
        .modifier(TensioneDellaPresa(accesa: accesa, tensione: $tensione, reduceMotion: reduceMotion))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var bordo: Color {
        if accesa { return Theme.cellSelectedStroke }
        if accesaParziale { return Theme.sarto.opacity(0.55) }
        return Theme.border
    }
}

/// STORICO (prima del filo V3): le board ora usano `FiloSeta`. Resta per
/// compatibilità con eventuali call-site esterni.
/// Il filo (spec §5, ROUND2 #1, ROUND3 #1): UN solo tracciato continuo
/// centro-centro, oro, riflesso interno 1 pt goldHighlight @ 0,55, cap/join
/// arrotondati, ombra nera 15 % r2 y1. Sta SOPRA le tessere e SOTTO i numeri
/// (che hanno un alone del colore della tessera: il filo passa SOTTO le cifre).
/// Spessore: se è dato `lato` (lato tessera) = `Arte.spessoreFilo(lato)`
/// (lato × 0,075, 4,5…6 pt), altrimenti `spessore` (default 4,5).
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
    var lato: CGFloat? = nil

    init(punti: [CGPoint], trim: CGFloat = 1, spessore: CGFloat = 4.5,
         colore: Color = Arte.oro, progresso: CGFloat? = nil, lato: CGFloat? = nil) {
        self.punti = punti
        self.trim = trim
        self.spessore = spessore
        self.colore = colore
        self.progresso = progresso
        self.lato = lato
    }

    private var larghezza: CGFloat { lato.map(Arte.spessoreFilo) ?? spessore }

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
                .stroke(colore, style: stile(larghezza))
                .shadow(color: Arte.oroOmbra.opacity(0.15), radius: 2, y: 1)
            forma
                .stroke(Arte.oroAnima.opacity(0.55), style: stile(1))
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

/// STORICO (prima del filo V3): sostituito da `FiloSeta`.
/// Filo che si cuce da sé: quando arriva un punto nuovo anima SOLO il
/// segmento nuovo (`FiloMotion.segment`, 0,12 s easeOut); se i punti
/// diminuiscono (filo concluso/azzerato) si aggiorna senza animazione.
/// Con Riduci Movimento il segmento compare subito.
struct CordaProgressiva: View {
    let punti: [CGPoint]
    var spessore: CGFloat = 4.5
    var colore: Color = Arte.oro
    var animazione: Animation = FiloMotion.segment
    /// Lato tessera: se dato, spessore = `Arte.spessoreFilo(lato)`.
    var lato: CGFloat? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progresso: CGFloat = 0

    init(punti: [CGPoint], spessore: CGFloat = 4.5, colore: Color = Arte.oro,
         animazione: Animation = FiloMotion.segment, lato: CGFloat? = nil) {
        self.punti = punti
        self.lato = lato
        self.spessore = spessore
        self.colore = colore
        self.animazione = animazione
        // primo render già completo (niente "ricucitura" all'apparire)
        _progresso = State(initialValue: CGFloat(max(0, punti.count - 1)))
    }

    var body: some View {
        CordaOro(punti: punti, spessore: spessore, colore: colore, progresso: progresso, lato: lato)
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

/// Numero di una casella (layer SOPRA il filo, ROUND2 #1, ROUND3 #2).
/// SF Rounded medium (lato × 0,42, 20…30 pt; 28 sulla tessera da 72),
/// #F5F3ED, con un ALONE attorno ai soli glifi del colore della tessera
/// sottostante (`cellSelected` #2F4056 se accesa, `cell` #1D2B42 a riposo),
/// largo lato × 0,045 (2,5…3,5 pt): il filo passa visibilmente SOTTO ogni
/// cifra, con un varco che segue la forma del glifo (nessun disco).
/// Tecnica: 16 copie spostate sul cerchio di raggio = alone + 8 a metà
/// raggio (alone pieno e rotondo), appiattite con `drawingGroup`.
/// Riempie il frame proposto (il chiamante lo dimensiona `lato × lato`).
/// `font` e `maschera` sono mantenuti per compatibilità ma ignorati.
/// `contorno`: colore esplicito dell'alone (nil = colore della tessera);
/// `spessoreContorno`: larghezza esplicita (nil = automatica);
/// `alone`: THREAD_V3 — default `false`: le asole del filo lasciano libere le
/// cifre (verificato da geometry_check: ≥ 1,3 pt fra il bordo del filo e il
/// riquadro del glifo), quindi niente alone. Passare `true` solo per un filo
/// che passi davvero sotto le cifre.
/// Come `TesseraArte`, reagisce alla presa (scala 0,985, solo se `accesa`
/// passa a true) così cifra e tessera si comprimono insieme.
struct NumeroCella: View {
    let valore: Int
    let accesa: Bool
    var font: Font? = nil
    /// Colore del numero su tessera a riposo (default textPrimary).
    var coloreSpento: Color? = nil
    var maschera: Bool = true
    var contorno: Color? = nil
    var spessoreContorno: CGFloat? = nil
    var alone: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tensione: CGFloat = 1

    init(valore: Int, accesa: Bool, font: Font? = nil, coloreSpento: Color? = nil,
         maschera: Bool = true, contorno: Color? = nil,
         spessoreContorno: CGFloat? = nil, alone: Bool = false) {
        self.valore = valore
        self.accesa = accesa
        self.font = font
        self.coloreSpento = coloreSpento
        self.maschera = maschera
        self.contorno = contorno
        self.spessoreContorno = spessoreContorno
        self.alone = alone
    }

    /// Offset unitari dell'alone: 16 sul cerchio + 8 a metà raggio.
    private static let direzioni: [CGSize] = {
        var v: [CGSize] = []
        for i in 0..<16 {
            let a = Double(i) * .pi / 8
            v.append(CGSize(width: cos(a), height: sin(a)))
        }
        for i in 0..<8 {
            let a = Double(i) * .pi / 4 + .pi / 8
            v.append(CGSize(width: cos(a) * 0.5, height: sin(a) * 0.5))
        }
        return v
    }()

    var body: some View {
        GeometryReader { geo in
            let lato = min(geo.size.width, geo.size.height)
            let w = spessoreContorno ?? Arte.aloneCifra(lato)
            let coloreAlone = contorno ?? (accesa ? Theme.cellSelected : Theme.cell)
            ZStack {
                if alone {
                    ZStack {
                        ForEach(0..<Self.direzioni.count, id: \.self) { i in
                            cifra(lato: lato)
                                .offset(x: Self.direzioni[i].width * w,
                                        y: Self.direzioni[i].height * w)
                        }
                    }
                    .foregroundStyle(coloreAlone)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .drawingGroup()
                }
                cifra(lato: lato)
                    .foregroundStyle(accesa ? Theme.text : (coloreSpento ?? Theme.text))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .scaleEffect(tensione)
        .modifier(TensioneDellaPresa(accesa: accesa, tensione: $tensione, reduceMotion: reduceMotion))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func cifra(lato: CGFloat) -> some View {
        Text(verbatim: "\(valore)")
            .font(FiloFont.tile(side: lato))
            .monospacedDigit()
            // il numero resta al centro geometrico della tessera (le asole
            // sono calcolate attorno al centro)
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

// MARK: - Filo V3: seta a due capi + asole (THREAD_V3_SPEC)

/// Reazione della tessera (e della sua cifra) quando il filo la prende:
/// dopo 60 ms scala a 0,985 e torna a 1 (spring 0,24/0,84). Scatta solo sul
/// passaggio `accesa` false → true (mai al primo render, mai al reset).
struct TensioneDellaPresa: ViewModifier {
    let accesa: Bool
    @Binding var tensione: CGFloat
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content.onChange(of: accesa) { _, nuova in
            guard nuova, !reduceMotion else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(FiloMotion.tensionDelay * 1_000_000_000))
                withAnimation(FiloMotion.tension) { tensione = FiloMotion.tensionScale }
                try? await Task.sleep(nanoseconds: 90_000_000)
                withAnimation(FiloMotion.tension) { tensione = 1 }
            }
        }
    }
}

/// Disegno del filo di seta in un `GraphicsContext` (Canvas). Ordine (spec §1):
/// ombra di contatto → corpo 5,2 pt (cap/join tondi) → capo in ombra → capo
/// illuminato → sovrapposizione alternata del capo in ombra (torsione da
/// vicino) → riflesso satinato → microfibre. Tutte le misure × k = lato / 72.
/// La geometria (asole, campionamento ogni 2 pt, normali, fase della
/// torsione continua su TUTTO il filo) viene da `FiloThreadBuilder`.
enum FiloSetaDisegno {
    typealias M = FiloThreadMetrics
    typealias B = FiloThreadBuilder

    static func cg(_ v: FiloVec2) -> CGPoint { CGPoint(x: v.x, y: v.y) }
    static func vec(_ p: CGPoint) -> FiloVec2 { FiloVec2(Double(p.x), Double(p.y)) }

    /// Polilinea levigata: quadratiche fra i punti medi.
    static func levigata(_ pts: [CGPoint]) -> Path {
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: first)
        guard pts.count > 2 else {
            if pts.count == 2 { p.addLine(to: pts[1]) }
            return p
        }
        for i in 1..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            p.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
        }
        p.addLine(to: pts[pts.count - 1])
        return p
    }

    /// Il filo dei `campioni` (già tagliati). `sfilacciatura` 0…1 = filo
    /// spezzato (gli ultimi 8 pt si aprono nei due capi ±12°, fibre esposte
    /// 5 pt). `tinta` = stato d'esito con Riduci Movimento (solo colore).
    static func filo(_ ctx: inout GraphicsContext, campioni: [FiloThreadSample], k: Double,
                     sfilacciatura: Double = 0, tinta: Color? = nil) {
        guard campioni.count >= 2, let ultimo = campioni.last else { return }
        let totale = ultimo.s
        let fineCorpo = totale - M.frayLength * k * sfilacciatura
        let corpo = sfilacciatura > 0 ? B.cut(campioni, at: fineCorpo) : campioni
        let corpoPath = levigata(corpo.map { cg($0.p) })
        let tondo = StrokeStyle(lineWidth: CGFloat(M.width * k), lineCap: .round, lineJoin: .round)

        // 1. ombra di contatto
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: CGFloat(M.shadowBlur * k)))
            l.translateBy(x: 0, y: CGFloat(M.shadowOffsetY * k))
            l.stroke(corpoPath, with: .color(Theme.silkContactShadow.opacity(M.shadowOpacity)), style: tondo)
        }
        // 2. corpo
        ctx.stroke(corpoPath, with: .color(Theme.silkBody), style: tondo)

        // 3. due capi ritorti: P ± N·0,95·sin(2π s / 12), fase sull'intero filo
        var capo1: [CGPoint] = [], capo2: [CGPoint] = []
        capo1.reserveCapacity(campioni.count)
        capo2.reserveCapacity(campioni.count)
        for c in campioni {
            let d1 = B.plyOffset(s: c.s, sign: 1, k: k, fray: sfilacciatura, total: totale)
            let d2 = B.plyOffset(s: c.s, sign: -1, k: k, fray: sfilacciatura, total: totale)
            capo1.append(cg(c.p + c.normal * d1))
            capo2.append(cg(c.p + c.normal * d2))
        }
        let stileCapo = StrokeStyle(lineWidth: CGFloat(M.plyWidth * k), lineCap: .round, lineJoin: .round)
        ctx.stroke(levigata(capo2), with: .color(Theme.silkShadow), style: stileCapo)
        ctx.stroke(levigata(capo1), with: .color(Theme.silkLit), style: stileCapo)
        // sopra/sotto: dove cos(fase) < 0 il capo in ombra passa davanti
        var davanti = Path()
        var tratto: [CGPoint] = []
        for (i, c) in campioni.enumerated() {
            if B.shadowPlyInFront(s: c.s, k: k) {
                tratto.append(capo2[i])
            } else {
                if tratto.count > 1 { davanti.addPath(levigata(tratto)) }
                tratto.removeAll(keepingCapacity: true)
            }
        }
        if tratto.count > 1 { davanti.addPath(levigata(tratto)) }
        ctx.stroke(davanti, with: .color(Theme.silkShadow.opacity(M.overUnderOpacity)), style: stileCapo)

        // 4. riflesso satinato (da lontano: una linea d'oro satinata)
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: CGFloat(0.5 * k)))
            l.stroke(corpoPath, with: .color(Theme.silkLit.opacity(M.sheenOpacity)),
                     style: StrokeStyle(lineWidth: CGFloat(M.sheenWidth * k), lineCap: .round, lineJoin: .round))
        }

        // 5. microfibre (deterministiche, ogni 6 pt; nessun rumore per frame)
        var chiare = Path(), scure = Path()
        for f in B.fibres(campioni, k: k, limit: fineCorpo) {
            if f.dark {
                scure.move(to: cg(f.a)); scure.addLine(to: cg(f.b))
            } else {
                chiare.move(to: cg(f.a)); chiare.addLine(to: cg(f.b))
            }
        }
        let stileFibra = StrokeStyle(lineWidth: CGFloat(M.fibreWidth * k), lineCap: .round)
        ctx.stroke(chiare, with: .color(Theme.silkFibreLight.opacity(M.fibreOpacity)), style: stileFibra)
        ctx.stroke(scure, with: .color(Theme.silkFibreDark.opacity(M.fibreOpacity)), style: stileFibra)

        // filo spezzato: fibre esposte dove il corpo si apre
        if sfilacciatura > 0, let p = B.sample(campioni, at: fineCorpo) {
            var esposte = Path()
            for (i, gradi) in [-7.0, 0, 7].enumerated() {
                let a = gradi * .pi / 180
                let t = FiloVec2(p.tangent.x * cos(a) - p.tangent.y * sin(a),
                                 p.tangent.x * sin(a) + p.tangent.y * cos(a))
                let l = M.frayFibre * k * sfilacciatura * (i == 1 ? 1 : 0.8)
                esposte.move(to: cg(p.p)); esposte.addLine(to: cg(p.p + t * l))
            }
            ctx.stroke(esposte, with: .color(Theme.silkLit.opacity(0.55 * sfilacciatura)), style: stileFibra)
        }
        // esito con Riduci Movimento: solo cambio di colore
        if let tinta {
            ctx.stroke(corpoPath, with: .color(tinta.opacity(0.6)), style: tondo)
        }
    }

    /// Punto terminale (partenza 7 pt, estremo 10 pt): pieno, leggermente
    /// rilevato (ombra morbida + piccolo riflesso).
    static func punto(_ ctx: inout GraphicsContext, in centro: CGPoint, diametro: CGFloat,
                      colore: Color = Theme.silkDot, k: Double) {
        guard diametro > 0 else { return }
        let r = diametro / 2
        let disco = CGRect(x: centro.x - r, y: centro.y - r, width: diametro, height: diametro)
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: CGFloat(1.2 * k)))
            l.fill(Path(ellipseIn: disco.offsetBy(dx: 0, dy: CGFloat(k))),
                   with: .color(Theme.silkContactShadow.opacity(0.35)))
        }
        ctx.fill(Path(ellipseIn: disco), with: .color(colore))
        let hr = r * 0.38
        ctx.fill(Path(ellipseIn: CGRect(x: centro.x - r * 0.28 - hr, y: centro.y - r * 0.3 - hr,
                                        width: hr * 2, height: hr * 2)),
                 with: .color(Theme.silkDotHighlight.opacity(0.55)))
    }

    /// Disegna `campioni` con un'opacità d'insieme (layer: corpo e capi non
    /// si sommano in trasparenza).
    static func filo(_ ctx: inout GraphicsContext, campioni: [FiloThreadSample], k: Double,
                     opacita: Double, sfilacciatura: Double = 0, tinta: Color? = nil) {
        guard opacita > 0.001 else { return }
        if opacita >= 0.999 {
            filo(&ctx, campioni: campioni, k: k, sfilacciatura: sfilacciatura, tinta: tinta)
            return
        }
        var c = ctx
        c.opacity = opacita
        c.drawLayer { l in
            filo(&l, campioni: campioni, k: k, sfilacciatura: sfilacciatura, tinta: tinta)
        }
    }

    static func easeOut(_ t: Double) -> Double { let x = max(0, min(1, t)); return 1 - pow(1 - x, 3) }
    static func easeIn(_ t: Double) -> Double { let x = max(0, min(1, t)); return x * x * x }
    static func easeInOut(_ t: Double) -> Double {
        let x = max(0, min(1, t))
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }
}

/// Cache della geometria (si ricostruisce SOLO quando cambiano percorso o
/// lato; durante i 0,24 s della presa il Canvas calcola le pose intermedie).
final class FiloSetaCache {
    private var chiave: [CGPoint] = []
    private var latoChiave: CGFloat = -1
    private var geometria = FiloThreadGeometry.empty

    func geometria(_ centri: [CGPoint], lato: CGFloat) -> FiloThreadGeometry {
        if centri != chiave || lato != latoChiave {
            chiave = centri
            latoChiave = lato
            geometria = FiloThreadBuilder.geometry(centri.map(FiloSetaDisegno.vec), k: Double(lato) / 72)
        }
        return geometria
    }
}

/// IL FILO (THREAD_V3_SPEC): un solo Canvas per tutto il filo — seta a due
/// capi 5,2 pt che passa da ogni tessera presa e ne avvolge il numero con
/// un'asola (raggio 22, ≥ 14 pt dai bordi), punto di partenza 7 pt, estremo
/// 10 pt sul fianco dell'ultima asola. Tutto scala con `lato / 72`.
/// Funziona su qualunque griglia: `centri` = centri delle tessere in ordine
/// di percorso (board 5×5, demo 3×3…), adiacenze ortogonali.
///
/// Presa di una tessera (un solo centro in più, stesso prefisso):
/// 0–60 ms il filo raggiunge l'ingresso (easeOut), 60–200 ms l'asola si
/// forma (easeOut); l'estremo precedente si riconfigura in 0,10 s (morph
/// dell'asola sul cerchio; se cambia verso attorno al numero, dissolvenza
/// incrociata — mai attraverso la cifra). Drag veloce: una presa nuova
/// chiude subito quella in corso (ritardo massimo una tessera). Altri cambi
/// (reset, filo perso, ripristino) = nessuna animazione.
/// Riduci Movimento: asola subito nella forma finale.
/// `scalaEstremo` (animabile) scala il punto estremo (somma esatta 1 → 1,08 → 1).
/// Inerte e nascosto all'accessibilità; disegna anche 8 pt oltre il proprio
/// frame (ombre, ricciolo del nodo).
struct FiloSeta: View, Animatable {
    let centri: [CGPoint]
    let lato: CGFloat
    var scalaEstremo: CGFloat = 1
    var marcatori: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cache = FiloSetaCache()
    @State private var inizioPresa = Date.distantPast
    @State private var inPresa = false
    @State private var inversione = false

    init(centri: [CGPoint], lato: CGFloat, scalaEstremo: CGFloat = 1, marcatori: Bool = true) {
        self.centri = centri
        self.lato = lato
        self.scalaEstremo = scalaEstremo
        self.marcatori = marcatori
    }

    var animatableData: CGFloat {
        get { scalaEstremo }
        set { scalaEstremo = newValue }
    }

    private static let margine: CGFloat = 8

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !inPresa)) { tl in
            let tau = inPresa ? tl.date.timeIntervalSince(inizioPresa) : FiloMotion.takeDuration
            Canvas(rendersAsynchronously: false) { ctx, _ in
                ctx.translateBy(x: Self.margine, y: Self.margine)
                disegna(&ctx, tau: tau)
            }
        }
        .padding(-Self.margine)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: centri) { vecchi, nuovi in
            presa(da: vecchi, a: nuovi)
        }
    }

    private func presa(da vecchi: [CGPoint], a nuovi: [CGPoint]) {
        let unaInPiu = nuovi.count == vecchi.count + 1 && Array(nuovi.prefix(vecchi.count)) == vecchi
        guard unaInPiu, !reduceMotion else {
            inPresa = false
            return
        }
        let k = Double(lato) / 72
        inversione = FiloThreadBuilder.isFlip(nuovi.map(FiloSetaDisegno.vec), k: k)
        let inizio = Date()
        inizioPresa = inizio
        inPresa = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((FiloMotion.takeDuration + 0.04) * 1_000_000_000))
            if inizioPresa == inizio { inPresa = false }
        }
    }

    private func disegna(_ ctx: inout GraphicsContext, tau: Double) {
        let n = centri.count
        guard n > 0 else { return }
        typealias D = FiloSetaDisegno
        let k = Double(lato) / 72
        let finale = cache.geometria(centri, lato: lato)
        let animando = tau < FiloMotion.takeDuration
        let morph = animando ? D.easeInOut(tau / FiloMotion.loopMorphDuration) : 1
        let raggiungi = animando ? D.easeOut(tau / FiloMotion.threadReachDuration) : 1
        let forma = animando
            ? D.easeOut((tau - FiloMotion.threadReachDuration) / FiloMotion.loopFormDuration) : 1
        let flip = animando && n >= 2 && inversione && morph < 1

        let g: FiloThreadGeometry = (animando && n >= 2 && morph < 1 && !flip)
            ? FiloThreadBuilder.geometry(centri.map(D.vec), k: k, morph: morph)
            : finale
        var taglio = g.length
        if animando {
            if n >= 2 {
                let da = g.marks.apex[n - 2], ingresso = g.marks.entry[n - 1], apice = g.marks.apex[n - 1]
                taglio = da + (ingresso - da) * raggiungi + (apice - ingresso) * forma
            } else {
                taglio = g.length * forma
            }
        }
        let campioni = FiloThreadBuilder.cut(g.samples, at: taglio)

        if flip {
            // l'estremo precedente cambia verso attorno al numero: dissolvenza
            // incrociata della sua asola (0,10 s), mai attraverso la cifra
            let vecchi = Array(centri.prefix(n - 1)).map(D.vec)
            let gv = FiloThreadBuilder.geometry(vecchi, k: k)
            let sE = g.marks.entry[n - 2], sX = g.marks.exit[n - 2]
            D.filo(&ctx, campioni: FiloThreadBuilder.range(gv.samples, from: gv.marks.entry[n - 2], to: gv.length),
                   k: k, opacita: 1 - morph)
            D.filo(&ctx, campioni: FiloThreadBuilder.range(campioni, from: 0, to: sE), k: k, opacita: 1)
            D.filo(&ctx, campioni: FiloThreadBuilder.range(campioni, from: sE, to: sX), k: k, opacita: morph)
            D.filo(&ctx, campioni: FiloThreadBuilder.range(campioni, from: sX, to: taglio), k: k, opacita: 1)
            if marcatori, let fine = gv.samples.last {
                var c = ctx
                c.opacity = 1 - morph
                D.punto(&c, in: D.cg(fine.p), diametro: CGFloat(FiloThreadMetrics.endDot * k) * scalaEstremo, k: k)
            }
        } else {
            D.filo(&ctx, campioni: campioni, k: k)
        }

        guard marcatori else { return }
        if n >= 2, let primo = campioni.first {
            var c = ctx
            c.opacity = n == 2 ? morph : 1
            D.punto(&c, in: D.cg(primo.p), diametro: CGFloat(FiloThreadMetrics.startDot * k), k: k)
        }
        if let ultimo = campioni.last {
            var c = ctx
            c.opacity = flip ? morph : 1
            D.punto(&c, in: D.cg(ultimo.p), diametro: CGFloat(FiloThreadMetrics.endDot * k) * scalaEstremo, k: k)
        }
    }
}

/// Filo appena perso, con l'effetto terminale (THREAD_V3_SPEC §3):
/// - spezzato: gli ultimi 8 pt si aprono nei due capi (±12°, fibre esposte
///   5 pt, 0,16 s easeOut), la punta arretra di 6 pt, poi dissolvenza
///   (0,34 s easeIn dopo 0,24 s);
/// - annodato: la punta disegna un ricciolo Ø 12 pt (270° in 0,20 s), resta
///   0,35 s, poi dissolvenza 0,10 s; punto finale annodato #9DB8FF;
/// - strappato / altro: dissolvenza 0,30 s easeIn.
/// Riduci Movimento: niente sfilacciatura né nodo; solo cambio di colore
/// (spezzato → error, annodato → annodato) e dissolvenza 0,12 s.
/// Deve stare entro la durata d'esito dei chiamanti (0,7 / 0,6 / 0,35 s;
/// 0,24 s con Riduci Movimento).
struct FiloSetaEsito: View {
    let centri: [CGPoint]
    let lato: CGFloat
    let esito: EsitoFiloVisivo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inizio = Date()
    @State private var attivo = true

    init(centri: [CGPoint], lato: CGFloat, esito: EsitoFiloVisivo) {
        self.centri = centri
        self.lato = lato
        self.esito = esito
    }

    /// Esito da rappresentare (indipendente da FiloCore).
    enum EsitoFiloVisivo { case spezzato, annodato, dissolvenza }

    private var durata: Double {
        if reduceMotion { return 2 * FiloMotion.reducedFadeDuration }
        switch esito {
        case .spezzato: return 0.58
        case .annodato: return FiloMotion.knotDuration + FiloMotion.knotHold + 0.10
        case .dissolvenza: return 0.30
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !attivo)) { tl in
            let t = tl.date.timeIntervalSince(inizio)
            Canvas(rendersAsynchronously: false) { ctx, _ in
                ctx.translateBy(x: 8, y: 8)
                disegna(&ctx, t: t)
            }
        }
        .padding(-8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            inizio = Date()
            attivo = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64((durata + 0.05) * 1_000_000_000))
                attivo = false
            }
        }
    }

    private func disegna(_ ctx: inout GraphicsContext, t: Double) {
        typealias D = FiloSetaDisegno
        typealias TM = FiloThreadMetrics
        guard !centri.isEmpty else { return }
        let k = Double(lato) / 72
        let punti = centri.map(D.vec)
        if reduceMotion {
            let g = FiloThreadBuilder.geometry(punti, k: k)
            let tinta: Color? = esito == .spezzato ? Theme.error : (esito == .annodato ? Theme.annodato : nil)
            let fr = FiloMotion.reducedFadeDuration
            let opacita = t < fr ? 1 : 1 - min(1, (t - fr) / fr)
            D.filo(&ctx, campioni: g.samples, k: k, opacita: opacita, tinta: tinta)
            disegnaPunti(&ctx, g.samples, k: k, opacita: opacita, finale: tinta ?? Theme.silkDot)
            return
        }
        switch esito {
        case .spezzato:
            let f = D.easeOut(t / FiloMotion.frayDuration)
            let opacita = t < 0.24 ? 1 : 1 - D.easeIn((t - 0.24) / 0.34)
            let g = FiloThreadBuilder.geometry(punti, k: k)
            let campioni = FiloThreadBuilder.cut(g.samples, at: g.length - TM.recoil * k * f)
            D.filo(&ctx, campioni: campioni, k: k, opacita: opacita, sfilacciatura: f)
            if punti.count >= 2, let primo = campioni.first {
                var c = ctx
                c.opacity = opacita
                D.punto(&c, in: D.cg(primo.p), diametro: CGFloat(TM.startDot * k), k: k)
            }
        case .annodato:
            let sweep = D.easeOut(t / FiloMotion.knotDuration) * TM.knotSweepDegrees * .pi / 180
            let fine = FiloMotion.knotDuration + FiloMotion.knotHold
            let opacita = t < fine ? 1 : 1 - min(1, (t - fine) / 0.10)
            let g = FiloThreadBuilder.geometry(punti, k: k, knotSweep: sweep)
            D.filo(&ctx, campioni: g.samples, k: k, opacita: opacita)
            disegnaPunti(&ctx, g.samples, k: k, opacita: opacita, finale: Theme.annodato, diametroFinale: TM.startDot)
        case .dissolvenza:
            let opacita = 1 - D.easeIn(t / 0.30)
            let g = FiloThreadBuilder.geometry(punti, k: k)
            D.filo(&ctx, campioni: g.samples, k: k, opacita: opacita)
            disegnaPunti(&ctx, g.samples, k: k, opacita: opacita, finale: Theme.silkDot)
        }
    }

    private func disegnaPunti(_ ctx: inout GraphicsContext, _ campioni: [FiloThreadSample], k: Double,
                              opacita: Double, finale: Color,
                              diametroFinale: Double = FiloThreadMetrics.endDot) {
        typealias D = FiloSetaDisegno
        var c = ctx
        c.opacity = opacita
        if centri.count >= 2, let primo = campioni.first {
            D.punto(&c, in: D.cg(primo.p), diametro: CGFloat(FiloThreadMetrics.startDot * k), k: k)
        }
        if let ultimo = campioni.last {
            D.punto(&c, in: D.cg(ultimo.p), diametro: CGFloat(diametroFinale * k), colore: finale, k: k)
        }
    }
}

/// Il tracciato delle asole come `Shape` (cubiche esatte, nessun
/// campionamento): per il percorso del Sarto (tratteggio 2 pt, `.trim`),
/// così anche la soluzione gira attorno ai numeri invece di attraversarli.
struct FiloAsole: Shape {
    var centri: [CGPoint]
    var lato: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let loops = FiloThreadBuilder.loops(centri.map(FiloSetaDisegno.vec), k: Double(lato) / 72)
        guard let primo = loops.first else { return p }
        typealias D = FiloSetaDisegno
        p.move(to: D.cg(primo.a0))
        for l in loops {
            p.addLine(to: D.cg(l.a0))
            if !(l.a0 == l.a1 && l.a1 == l.a2 && l.a2 == l.m) {
                p.addCurve(to: D.cg(l.m), control1: D.cg(l.a1), control2: D.cg(l.a2))
            }
            if !(l.m == l.b1 && l.b1 == l.b2 && l.b2 == l.b3) {
                p.addCurve(to: D.cg(l.b3), control1: D.cg(l.b1), control2: D.cg(l.b2))
            }
        }
        return p
    }
}
