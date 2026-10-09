import SwiftUI
import FiloCore

// MARK: - Metriche e layer condivisi delle board (REDESIGN_SPEC §5, ROUND2 #7)

/// Geometria della griglia 5×5 (identica in Partita, Salita, Archivio,
/// Riscaldamento): griglia quadrata uniforme, gap 8 pt, lato massimo 392 pt
/// (tessere 72 × 72 su un display da 440 pt con margini 24), margini
/// orizzontali 24 pt (16 se la larghezza < 390). Hit area: cella ridotta del
/// 12 % per lato (meno falsi positivi negli angoli, come il web).
///
/// Uso statico (storico): `BoardMetrics.side(forWidth:)`, `origin`, `center`,
/// `cell(at:side:)`. Per dimensionare la griglia in base allo spazio
/// disponibile in LARGHEZZA e in ALTEZZA:
/// `let m = BoardMetrics(width: geo.size.width, height: spazioPerLaGriglia)`
/// → `m.boardSide` (lato della griglia), `m.tileSide`, `m.margin`; oppure
/// passare `maxSide:` a `BoardView` / `PracticeBoardView`.
struct BoardMetrics {
    static let gap: CGFloat = 8
    /// Lato massimo della griglia (392 → tessere da 72).
    static let maxWidth: CGFloat = 392
    /// Alias di `maxWidth` (la griglia è quadrata).
    static var maxSide: CGFloat { maxWidth }
    /// Lato minimo sensato della griglia (tessere da ~44 pt).
    static let minSide: CGFloat = 252

    /// Margine orizzontale attorno alla griglia: 24 pt (16 se < 390).
    static func margin(forWidth width: CGFloat) -> CGFloat {
        FiloMetrics.margin(forWidth: width)
    }

    /// Lato della griglia per una schermata/contenitore largo `width`
    /// (margini INCLUSI: vengono sottratti qui) con al massimo `height` pt
    /// disponibili in verticale per la griglia stessa. Limitato a 392.
    static func boardSide(width: CGFloat, height: CGFloat? = nil) -> CGFloat {
        var lato = min(maxWidth, width - 2 * margin(forWidth: width))
        if let height { lato = min(lato, height) }
        return max(0, lato)
    }

    /// Lato di una tessera per una griglia larga `width` (= lato griglia).
    static func side(forWidth width: CGFloat) -> CGFloat {
        max(0, (width - gap * 4) / 5)
    }

    static func origin(_ idx: Int, side: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(idx % 5) * (side + gap), y: CGFloat(idx / 5) * (side + gap))
    }

    static func center(_ idx: Int, side: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(idx % 5) * (side + gap) + side / 2,
                y: CGFloat(idx / 5) * (side + gap) + side / 2)
    }

    /// Storico (maschera dei numeri, rimossa nel round 2). Resta per
    /// compatibilità: ≈ 0,56 × lato.
    static func maskDiameter(_ side: CGFloat) -> CGFloat { side * 0.56 }

    /// Indice della cella sotto il punto (area utile ridotta del 12 %).
    static func cell(at p: CGPoint, side: CGFloat) -> Int? {
        let step = side + gap
        let c = Int(floor(p.x / step)), r = Int(floor(p.y / step))
        guard (0..<5).contains(c), (0..<5).contains(r) else { return nil }
        let x0 = CGFloat(c) * step, y0 = CGFloat(r) * step
        let m = side * 0.12
        guard p.x >= x0 + m, p.x <= x0 + side - m,
              p.y >= y0 + m, p.y <= y0 + side - m else { return nil }
        return r * 5 + c
    }

    // Istanza: misure per uno spazio disponibile.

    /// Larghezza di riferimento (schermata o contenitore, margini inclusi).
    let width: CGFloat
    /// Altezza massima disponibile per la griglia (nil = illimitata).
    let height: CGFloat?
    /// Margine orizzontale (24 / 16).
    let margin: CGFloat
    /// Lato della griglia quadrata (≤ 392).
    let boardSide: CGFloat
    /// Lato di una tessera.
    let tileSide: CGFloat

    init(width: CGFloat, height: CGFloat? = nil) {
        self.width = width
        self.height = height
        self.margin = Self.margin(forWidth: width)
        self.boardSide = Self.boardSide(width: width, height: height)
        self.tileSide = Self.side(forWidth: boardSide)
    }
}

/// STORICO (ROUND3 #3): anelli attorno alla cifra. Il filo V3 li ha
/// sostituiti con i punti terminali disegnati da `FiloSeta` (partenza 7 pt,
/// estremo 10 pt sul fianco dell'asola): nessuna board li usa più. Resta per
/// compatibilità di API.
struct FiloNodo: View {
    enum Tipo { case partenza, estremo }
    let tipo: Tipo
    let side: CGFloat
    var colore: Color = Theme.filo
    /// Contrazione in pt (vicolo cieco: 3).
    var contrazione: CGFloat = 0

    init(tipo: Tipo, side: CGFloat, colore: Color = Theme.filo, contrazione: CGFloat = 0) {
        self.tipo = tipo
        self.side = side
        self.colore = colore
        self.contrazione = contrazione
    }

    /// Diametro degli anelli: lato × 0,62.
    static func diametro(_ side: CGFloat) -> CGFloat { side * 0.62 }

    var body: some View {
        let d = max(8, Self.diametro(side) - contrazione * 2)
        Group {
            switch tipo {
            case .partenza:
                Circle()
                    .strokeBorder(colore, lineWidth: 1.5)
            case .estremo:
                ZStack {
                    Circle().fill(colore.opacity(0.14))
                    Circle().strokeBorder(colore, lineWidth: 2.5)
                }
            }
        }
        .frame(width: d, height: d)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Layer FILO della board (sopra le tessere, sotto i numeri) — THREAD_V3:
/// percorso del Sarto tratteggiato 2 pt lungo le stesse asole (sotto), filo
/// d'esito con il suo effetto terminale (`FiloSetaEsito`), e il filo
/// corrente: seta a due capi in UN solo Canvas (`FiloSeta`) che avvolge ogni
/// numero preso con un'asola, punto di partenza 7 pt e punto estremo 10 pt.
/// La presa di una tessera anima solo l'ultima asola (0,06 s + 0,14 s) e
/// riconfigura quella precedente (0,10 s). Inerte e nascosto
/// all'accessibilità. `trim` è mantenuto per compatibilità ma ignorato.
/// `endScale` scala il punto estremo (somma esatta 1 → 1,08 → 1).
struct BoardThreadLayer: View {
    let side: CGFloat
    let filo: [Int]
    var trim: CGFloat = 1
    /// Percorso del Sarto (vuoto = nessun reveal).
    var sarto: [Int] = []
    var sartoTrim: CGFloat = 1
    /// Scala del punto estremo (somma esatta: 1 → 1,08 → 1).
    var endScale: CGFloat = 1
    /// Filo appena perso (spezzato/annodato/strappato) da mostrare in uscita.
    var esitoPercorso: [Int]? = nil
    var esito: EsitoFilo? = nil

    init(side: CGFloat, filo: [Int], trim: CGFloat = 1, sarto: [Int] = [],
         sartoTrim: CGFloat = 1, endScale: CGFloat = 1,
         esitoPercorso: [Int]? = nil, esito: EsitoFilo? = nil) {
        self.side = side
        self.filo = filo
        self.trim = trim
        self.sarto = sarto
        self.sartoTrim = sartoTrim
        self.endScale = endScale
        self.esitoPercorso = esitoPercorso
        self.esito = esito
    }

    private func c(_ idx: Int) -> CGPoint { BoardMetrics.center(idx, side: side) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if sarto.count >= 2 {
                FiloAsole(centri: sarto.map(c), lato: side)
                    .trim(from: 0, to: sartoTrim)
                    .stroke(Theme.sarto,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [5, 5]))
            }
            if let esitoPercorso, let esito, !esitoPercorso.isEmpty {
                EsitoFiloOverlay(punti: esitoPercorso.map(c), esito: esito, side: side)
            }
            // filo corrente: un solo Canvas, sempre presente (anche vuoto) così
            // lo stato della presa resta stabile
            FiloSeta(centri: filo.map(c), lato: side, scalaEstremo: endScale)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Layer NUMERI (sopra il filo): cifre bianche SENZA alone né disco — le
/// asole del filo V3 le lasciano libere. Inerte e nascosto all'accessibilità.
/// `popIdx`/`popScale`: scala opzionale di una cifra (compatibilità); la
/// compressione della presa è già in `NumeroCella`.
struct BoardNumberLayer: View {
    let side: CGFloat
    let valori: [Int]
    let filo: [Int]
    var popIdx: Int? = nil
    var popScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<25, id: \.self) { idx in
                let acceso = filo.contains(idx)
                let o = BoardMetrics.origin(idx, side: side)
                NumeroCella(valore: idx < valori.count ? valori[idx] : 0, accesa: acceso, alone: false)
                    .frame(width: side, height: side)
                    .scaleEffect(popIdx == idx ? popScale : 1)
                    .animation(.easeInOut(duration: 0.16), value: acceso)
                    .offset(x: o.x, y: o.y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Filo appena perso (THREAD_V3 §3), stessa seta del filo corrente:
/// spezzato = i due capi si aprono e la punta arretra, poi dissolvenza;
/// annodato = ricciolo terminale Ø 12 pt (270°), poi dissolvenza;
/// strappato = dissolvenza 0,30 s. Riduci Movimento: solo colore +
/// dissolvenza 0,12 s. Finisce entro la durata dell'esito (0,7/0,6/0,35 s).
/// API invariata (`punti` = centri delle tessere del filo perso).
struct EsitoFiloOverlay: View {
    let punti: [CGPoint]
    let esito: EsitoFilo
    let side: CGFloat

    var body: some View {
        FiloSetaEsito(centri: punti, lato: side, esito: visivo)
    }

    private var visivo: FiloSetaEsito.EsitoFiloVisivo {
        switch esito {
        case .spezzato: return .spezzato
        case .annodato: return .annodato
        default: return .dissolvenza
        }
    }
}

/// STORICO: segmento che "perde tensione" (esito spezzato prima del filo
/// V3). Non più usato dalle board; resta per compatibilità.
struct SegmentoAllentato: Shape {
    var da: CGPoint
    var a: CGPoint
    var freccia: CGFloat
    var allentamento: CGFloat

    var animatableData: CGFloat {
        get { allentamento }
        set { allentamento = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let dx = a.x - da.x, dy = a.y - da.y
        let len = max(0.001, sqrt(dx * dx + dy * dy))
        var nx = -dy / len, ny = dx / len
        if ny < 0 || (abs(ny) < 0.001 && nx < 0) { nx = -nx; ny = -ny }
        let k = freccia * allentamento
        let ctrl = CGPoint(x: (da.x + a.x) / 2 + nx * k, y: (da.y + a.y) / 2 + ny * k)
        var p = Path()
        p.move(to: da)
        p.addQuadCurve(to: a, control: ctrl)
        return p
    }
}

// MARK: - Board del giornaliero

/// Griglia 5×5 del FILO di oggi: tessere → filo di seta (asole + punti
/// terminali) → numeri bianchi senza alone.
/// Input tap + drag via DragGesture(minimumDistance: 0) — semantica
/// README §6.2/§6.6 invariata. Haptics: selezione (throttled 90 ms) a ogni
/// casella nuova; gli esiti (success/error/warning/medium) li emette
/// GameViewModel via FiloHaptics. Mossa non valida: nessun movimento, nessun
/// haptic (resta l'annuncio VoiceOver e un breve bordo error).
///
/// Dimensione: quadrata, lato = min(larghezza proposta, altezza proposta,
/// `maxSide` ?? 392). Il contenitore etichettato "Griglia di gioco…"
/// coincide ESATTAMENTE con la griglia (i test UI toccano coordinate
/// calcolate dal suo frame). Il genitore aggiunge i margini 24/16.
struct BoardView: View {
    /// Lato massimo della griglia (nil = `BoardMetrics.maxWidth`, 392).
    var maxSide: CGFloat?

    @EnvironmentObject private var vm: GameViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sartoTrim: CGFloat = 0
    @State private var dragAttivo = false
    @State private var downSuUltima = false
    @State private var caselleAlDown = 0
    @State private var casellaDown: Int?
    @State private var endScale: CGFloat = 1

    init(maxSide: CGFloat? = nil) {
        self.maxSide = maxSide
    }

    private var limite: CGFloat { min(BoardMetrics.maxWidth, maxSide ?? .infinity) }

    var body: some View {
        GeometryReader { geo in
            let lato = min(geo.size.width, geo.size.height)
            let side = BoardMetrics.side(forWidth: lato)
            ZStack(alignment: .topLeading) {
                ForEach(0..<25, id: \.self) { idx in
                    let o = BoardMetrics.origin(idx, side: side)
                    CellView(idx: idx, side: side)
                        .frame(width: side, height: side)
                        .offset(x: o.x, y: o.y)
                }
                BoardThreadLayer(side: side,
                                 filo: vm.engine.filo,
                                 sarto: vm.revealSarto ? vm.puzzle.percorsoSarto : [],
                                 sartoTrim: sartoTrim,
                                 endScale: endScale,
                                 esitoPercorso: vm.esitoVisuale?.percorso,
                                 esito: vm.esitoVisuale?.esito)
                // numeri SOPRA il filo (layer inerte: tocchi e
                // accessibilità restano sulle CellView sotto)
                BoardNumberLayer(side: side, valori: vm.puzzle.valori, filo: vm.engine.filo)
            }
            // Le caselle sono posizionate con .offset (spostamento SOLO visivo):
            // senza un frame esplicito la ZStack resterebbe grande una casella e
            // il gesto partirebbe solo dall'angolo in alto a sinistra. Diamo alla
            // ZStack la dimensione piena della griglia, così il tocco e il drag
            // coprono TUTTE le caselle, ovunque siano.
            .frame(width: lato, height: lato, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(dragGesture(side: side))
        }
        // prima il limite, poi il quadrato: il frame finale è sempre un
        // quadrato pari alla griglia (anche quando decide l'altezza)
        .frame(maxWidth: limite, maxHeight: limite)
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: vm.engine.filo.count) { vecchio, nuovo in
            casellaAggiunta(vecchio: vecchio, nuovo: nuovo)
        }
        .onChange(of: vm.engine.stato) { _, stato in
            if stato == .vinta { assesta() }
        }
        .onChange(of: vm.revealSarto) { _, attivo in
            aggiornaSarto(attivo: attivo, animato: true)
        }
        .onAppear {
            aggiornaSarto(attivo: vm.revealSarto, animato: false)
            FiloHaptics.prepare()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Griglia di gioco, 5 righe per 5 colonne")
    }

    /// Nuova casella: selezione (throttled). La presa (filo → ingresso →
    /// asola, compressione 0,985 della tessera) la disegnano `FiloSeta` e
    /// `TesseraArte`/`NumeroCella`.
    private func casellaAggiunta(vecchio: Int, nuovo: Int) {
        guard nuovo > vecchio else { return }
        if vm.engine.stato == .inCorso { FiloHaptics.selection() }
    }

    /// Somma esatta: il punto estremo si assesta 1 → 1,08 → 1.
    private func assesta() {
        guard !reduceMotion else { return }
        withAnimation(FiloMotion.settle) { endScale = 1.08 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            withAnimation(FiloMotion.settle) { endScale = 1 }
        }
    }

    private func aggiornaSarto(attivo: Bool, animato: Bool) {
        guard attivo else {
            sartoTrim = 0
            return
        }
        if reduceMotion || !animato {
            sartoTrim = 1
        } else {
            sartoTrim = 0
            withAnimation(.easeInOut(duration: vm.durataReveal)) { sartoTrim = 1 }
        }
    }

    // MARK: Input tap + drag

    private func cella(at p: CGPoint, side: CGFloat) -> Int? {
        BoardMetrics.cell(at: p, side: side)
    }

    private func dragGesture(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { g in
                guard !vm.lockInput, !vm.engine.gameOver else { return }
                guard let idx = cella(at: g.location, side: side) else { return }
                if !dragAttivo {
                    dragAttivo = true
                    casellaDown = idx
                    caselleAlDown = vm.engine.filo.count
                    // pointerdown sull'ultima casella = possibile ripresa del drag:
                    // il feedback "già usata" arriva solo al rilascio senza estensione
                    downSuUltima = (vm.engine.filo.last == idx)
                    if !downSuUltima { vm.gioca(idx, viaTap: true) }
                } else {
                    // fuori griglia o mossa non valida: silenzioso, il filo resta (§6.6)
                    vm.gioca(idx, viaTap: false)
                }
            }
            .onEnded { g in
                if dragAttivo, downSuUltima,
                   vm.engine.filo.count == caselleAlDown,
                   !vm.engine.gameOver, !vm.lockInput,
                   let idx = cella(at: g.location, side: side),
                   idx == vm.engine.filo.last {
                    vm.tapSuUltima(idx)
                }
                dragAttivo = false
                downSuUltima = false
                casellaDown = nil
            }
    }
}

/// Singola casella (layer di FONDO): tessera piatta riposo / sul filo,
/// breve bordo error sulla mossa non valida, tocchi e accessibilità. Il
/// numero sta in `BoardNumberLayer`, sopra il filo.
struct CellView: View {
    @EnvironmentObject private var vm: GameViewModel
    let idx: Int
    let side: CGFloat

    var body: some View {
        let inFilo = vm.engine.filo.contains(idx)
        let nonValida = vm.casellaNonValida == idx

        ZStack {
            TesseraArte(accesa: inFilo, lato: side)
            if nonValida {
                RoundedRectangle(cornerRadius: Arte.raggio(side), style: .continuous)
                    .strokeBorder(Theme.spezzato, lineWidth: 1.5)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: inFilo)
        .animation(.easeOut(duration: 0.12), value: nonValida)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(vm.etichettaCasella(idx))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            vm.gioca(idx, viaTap: true)
        }
    }
}
