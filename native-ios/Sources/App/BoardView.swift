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

/// Nodi del filo (ROUND2 #2), disegnati nel layer del filo (SOTTO i numeri,
/// al centro della cella: le cifre a contorno restano leggibili).
/// Partenza: cerchio vuoto 12 pt, contorno oro 2 pt (interno del colore
/// della tessera selezionata, così il filo non lo attraversa).
/// Estremo corrente: punto oro pieno 10 pt (`contrazione` lo riduce,
/// vicolo cieco: 3). Le misure scalano solo su tessere < 60 pt.
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

    private var scala: CGFloat { min(1, max(0.7, side / 60)) }

    var body: some View {
        switch tipo {
        case .partenza:
            let d = 12 * scala
            ZStack {
                Circle().fill(Theme.cellSelected)
                Circle().strokeBorder(colore, lineWidth: 2)
            }
            .frame(width: d, height: d)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        case .estremo:
            let d = max(4, 10 * scala - contrazione)
            Circle()
                .fill(colore)
                .frame(width: d, height: d)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Layer FILO della board (sopra le tessere, sotto i numeri): percorso del
/// Sarto tratteggiato 2 pt (sotto), filo d'esito in dissolvenza, filo
/// corrente come UN solo tracciato continuo centro-centro che si cuce da sé
/// (solo il segmento nuovo si anima, 0,12 s easeOut), nodo di partenza e
/// nodo estremo (spring 0,24/0,78). Inerte e nascosto all'accessibilità.
/// `trim` è mantenuto per compatibilità ma ignorato: l'animazione del
/// segmento è interna (`CordaProgressiva`), così nessun chiamante può
/// rianimare i segmenti già tracciati.
struct BoardThreadLayer: View {
    let side: CGFloat
    let filo: [Int]
    var trim: CGFloat = 1
    /// Percorso del Sarto (vuoto = nessun reveal).
    var sarto: [Int] = []
    var sartoTrim: CGFloat = 1
    /// Scala del nodo finale (somma esatta: 1 → 1,08 → 1).
    var endScale: CGFloat = 1
    /// Filo appena perso (spezzato/annodato/strappato) da mostrare in uscita.
    var esitoPercorso: [Int]? = nil
    var esito: EsitoFilo? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                PolylineShape(points: sarto.map(c))
                    .trim(from: 0, to: sartoTrim)
                    .stroke(Theme.sarto,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [5, 5]))
            }
            if let esitoPercorso, let esito, !esitoPercorso.isEmpty {
                EsitoFiloOverlay(punti: esitoPercorso.map(c), esito: esito, side: side)
            }
            // filo corrente: un solo Path, sempre presente (anche vuoto) così
            // lo stato dell'animazione del segmento resta stabile
            CordaProgressiva(punti: filo.map(c))
            if let primo = filo.first {
                FiloNodo(tipo: .partenza, side: side)
                    .position(c(primo))
            }
            ZStack(alignment: .topLeading) {
                if filo.count >= 2, let ultimo = filo.last {
                    FiloNodo(tipo: .estremo, side: side)
                        .scaleEffect(endScale)
                        .position(c(ultimo))
                        .transition(reduceMotion ? AnyTransition.opacity
                                    : AnyTransition.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? FiloMotion.reduced : FiloMotion.node,
                       value: filo.count >= 2 ? (filo.last ?? -1) : -1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Layer NUMERI (sopra il filo): cifre a contorno (`NumeroCella`, nessuna
/// maschera). Inerte e nascosto all'accessibilità.
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
                NumeroCella(valore: idx < valori.count ? valori[idx] : 0, accesa: acceso)
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

/// Filo appena perso (spec §5): spezzato = l'ultimo segmento perde tensione
/// e svanisce (0,24 s easeIn), annodato = il nodo finale si contrae di 3 pt
/// (spring 0,28/0,85), strappato = dissolvenza 0,30 s easeIn. Con Riduci
/// Movimento: solo dissolvenza. Deve finire entro la durata dell'esito.
struct EsitoFiloOverlay: View {
    let punti: [CGPoint]
    let esito: EsitoFilo
    let side: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacita = 1.0
    @State private var codaOpacita = 1.0
    @State private var allentamento: CGFloat = 0
    @State private var contrazione: CGFloat = 0

    private var corpo: [CGPoint] {
        if esito == .spezzato && punti.count >= 2 { return Array(punti.dropLast()) }
        return punti
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if corpo.count >= 2 {
                CordaOro(punti: corpo)
            }
            if esito == .spezzato, punti.count >= 2 {
                SegmentoAllentato(da: punti[punti.count - 2], a: punti[punti.count - 1],
                                  freccia: side * 0.3, allentamento: allentamento)
                    .stroke(Theme.spezzato,
                            style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                    .opacity(codaOpacita)
            }
            if let primo = corpo.first {
                FiloNodo(tipo: .partenza, side: side).position(primo)
            }
            if corpo.count >= 2, let ultimo = corpo.last {
                FiloNodo(tipo: .estremo, side: side,
                         colore: esito == .annodato ? Theme.annodato : Theme.filo,
                         contrazione: contrazione)
                    .position(ultimo)
            }
        }
        .opacity(opacita)
        .onAppear(perform: avvia)
    }

    private func avvia() {
        if reduceMotion {
            withAnimation(FiloMotion.reduced) { opacita = 0 }
            return
        }
        switch esito {
        case .spezzato:
            withAnimation(FiloMotion.slack) {
                allentamento = 1
                codaOpacita = 0
            }
            withAnimation(.easeIn(duration: 0.34).delay(0.24)) { opacita = 0 }
        case .annodato:
            withAnimation(FiloMotion.contract) { contrazione = 3 }
            withAnimation(.easeIn(duration: 0.3).delay(0.22)) { opacita = 0 }
        default:
            withAnimation(FiloMotion.cut) { opacita = 0 }
        }
    }
}

/// Segmento che "perde tensione": curva quadratica con freccia animabile,
/// verso il basso (o verso destra se il segmento è verticale).
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

/// Griglia 5×5 del FILO di oggi: tessere → filo (+ nodi) → numeri a contorno.
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
    @State private var popIdx: Int?
    @State private var popScale: CGFloat = 1
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
                        .scaleEffect(popIdx == idx ? popScale : 1)
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
                BoardNumberLayer(side: side, valori: vm.puzzle.valori, filo: vm.engine.filo,
                                 popIdx: popIdx, popScale: popScale)
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

    /// Nuova casella: selezione (throttled), prima casella con scale
    /// 0,97 → 1. Il segmento nuovo lo cuce `BoardThreadLayer` (0,12 s).
    private func casellaAggiunta(vecchio: Int, nuovo: Int) {
        guard nuovo > vecchio else { return }
        if vm.engine.stato == .inCorso { FiloHaptics.selection() }
        if nuovo == 1, let primo = vm.engine.filo.first, !reduceMotion {
            popIdx = primo
            popScale = 0.97
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 16_000_000)
                withAnimation(FiloMotion.tile) { popScale = 1 }
            }
        }
    }

    /// Somma esatta: il nodo finale si assesta 1 → 1,08 → 1.
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
