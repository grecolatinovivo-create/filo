import SwiftUI
import FiloCore

/// Sessione di gioco per le modalità di PRATICA (onboarding progressivo, Salita).
/// Incapsula un `GameEngine` su un `Puzzle` di `PracticeGenerator` senza toccare
/// il flusso del gioco giornaliero (`GameViewModel`). La macchina a stati resta
/// quella pura di FiloCore; qui aggiungiamo solo lo shake della mossa non valida.
@MainActor
final class PracticeSession: ObservableObject {
    let puzzle: Puzzle
    @Published private(set) var engine: GameEngine
    @Published private(set) var lockInput = false
    @Published private(set) var revealSolution = false
    @Published private(set) var shakes: [Int: Int] = [:]
    @Published private(set) var shakeTick = 0
    @Published private(set) var casellaNonValida: Int?

    init(puzzle: Puzzle) {
        self.puzzle = puzzle
        self.engine = GameEngine(puzzle: puzzle)
    }

    var somma: Int { engine.somma }
    var target: Int { puzzle.T }
    var caselle: Int { engine.filo.count }
    var gameOver: Bool { engine.gameOver }

    @discardableResult
    func gioca(_ idx: Int, viaTap: Bool) -> Mossa {
        guard !lockInput, !engine.gameOver else { return .ignorata }
        let m = engine.gioca(idx)
        if m == .iniziato || m == .esteso || m == .vittoria {
            SoundManager.shared.plin(passo: engine.filo.count)
        }
        if viaTap && (m == .giaUsata || m == .nonAdiacente) { shake(idx) }
        return m
    }

    func tapSuUltima(_ idx: Int) {
        guard !lockInput, !engine.gameOver else { return }
        shake(idx)
    }

    /// Ricomincia il tentativo sullo stesso puzzle (filo azzerato, nessuna penalità).
    func ripulisci() {
        engine = GameEngine(puzzle: puzzle)
    }

    func blocca() { lockInput = true }
    func sblocca() { lockInput = false }
    func mostraSoluzione() { revealSolution = true }

    private func shake(_ idx: Int) {
        shakes[idx, default: 0] += 1
        shakeTick += 1
        casellaNonValida = idx
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if casellaNonValida == idx { casellaNonValida = nil }
        }
    }
}

/// Griglia 5×5 interattiva riutilizzabile, guidata da una `PracticeSession`.
/// Stessa gestualità tap+drag, stessa resa (filo di seta V3 con asole,
/// `BoardThreadLayer`) e STESSE misure (REDESIGN_SPEC §5, ROUND2 #1/#2/#7)
/// della `BoardView` del giornaliero, ma disaccoppiata da
/// `GameViewModel`: ogni esito di mossa viene inoltrato al genitore via
/// `onMove`. Haptics: selezione (throttled 90 ms) a ogni casella nuova; con
/// `outcomeHaptics` (default true) anche success (somma esatta), error
/// (spezzato), warning (annodato). Passare `outcomeHaptics: false` se la
/// schermata emette i propri haptics d'esito (niente doppioni).
/// `maxSide`: lato massimo della griglia (nil = 392); la griglia è quadrata
/// e il contenitore etichettato coincide con essa.
struct PracticeBoardView: View {
    @ObservedObject var session: PracticeSession
    var onMove: (Mossa) -> Void = { _ in }
    var outcomeHaptics: Bool = true
    var maxSide: CGFloat? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var solTrim: CGFloat = 0
    @State private var dragAttivo = false
    @State private var downSuUltima = false
    @State private var caselleAlDown = 0
    @State private var endScale: CGFloat = 1
    @State private var esitoLocale: EsitoLocale?

    init(session: PracticeSession,
         onMove: @escaping (Mossa) -> Void = { _ in },
         outcomeHaptics: Bool = true,
         maxSide: CGFloat? = nil) {
        _session = ObservedObject(wrappedValue: session)
        self.onMove = onMove
        self.outcomeHaptics = outcomeHaptics
        self.maxSide = maxSide
    }

    /// Filo appena perso (la sessione lo azzera subito): resa d'uscita.
    private struct EsitoLocale: Equatable {
        let id: Int
        let percorso: [Int]
        let esito: EsitoFilo
    }

    private var limite: CGFloat { min(BoardMetrics.maxWidth, maxSide ?? .infinity) }

    var body: some View {
        GeometryReader { geo in
            let lato = min(geo.size.width, geo.size.height)
            let side = BoardMetrics.side(forWidth: lato)
            ZStack(alignment: .topLeading) {
                ForEach(0..<25, id: \.self) { idx in
                    let o = BoardMetrics.origin(idx, side: side)
                    PracticeCellView(session: session, idx: idx, side: side)
                        .frame(width: side, height: side)
                        .offset(x: o.x, y: o.y)
                }
                BoardThreadLayer(side: side,
                                 filo: session.engine.filo,
                                 sarto: session.revealSolution ? session.puzzle.percorsoSarto : [],
                                 sartoTrim: solTrim,
                                 endScale: endScale,
                                 esitoPercorso: esitoLocale?.percorso,
                                 esito: esitoLocale?.esito)
                    .id(esitoLocale?.id ?? 0)
                // numeri SOPRA il filo (layer inerte)
                BoardNumberLayer(side: side, valori: session.puzzle.valori,
                                 filo: session.engine.filo)
            }
            .frame(width: lato, height: lato, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(dragGesture(side: side))
        }
        // prima il limite, poi il quadrato: frame finale = griglia
        .frame(maxWidth: limite, maxHeight: limite)
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: session.engine.filo.count) { vecchio, nuovo in
            casellaAggiunta(vecchio: vecchio, nuovo: nuovo)
        }
        .onChange(of: session.engine.stato) { _, stato in
            if stato == .vinta { assesta() }
        }
        .onChange(of: session.revealSolution) { _, attivo in
            aggiornaSoluzione(attivo: attivo, animato: true)
        }
        .onChange(of: ObjectIdentifier(session)) { _, _ in
            esitoLocale = nil
            endScale = 1
            aggiornaSoluzione(attivo: session.revealSolution, animato: false)
        }
        .onAppear {
            aggiornaSoluzione(attivo: session.revealSolution, animato: false)
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
        if session.engine.stato == .inCorso { FiloHaptics.selection() }
    }

    private func assesta() {
        guard !reduceMotion else { return }
        withAnimation(FiloMotion.settle) { endScale = 1.08 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            withAnimation(FiloMotion.settle) { endScale = 1 }
        }
    }

    private func aggiornaSoluzione(attivo: Bool, animato: Bool) {
        guard attivo else { solTrim = 0; return }
        if reduceMotion || !animato {
            solTrim = 1
        } else {
            solTrim = 0
            withAnimation(.easeInOut(duration: 1.2)) { solTrim = 1 }
        }
    }

    /// Gioca la mossa sulla sessione, applica la resa d'esito (visuale +
    /// haptics) e la inoltra al genitore.
    private func muovi(_ idx: Int, viaTap: Bool) {
        let prima = session.engine.filo
        let m = session.gioca(idx, viaTap: viaTap)
        reagisci(m, percorso: prima + [idx])
        onMove(m)
    }

    private func reagisci(_ m: Mossa, percorso: [Int]) {
        switch m {
        case .vittoria:
            if outcomeHaptics { FiloHaptics.success() }
        case .spezzato, .annodato:
            let esito: EsitoFilo = (m == .spezzato) ? .spezzato : .annodato
            if outcomeHaptics {
                if esito == .spezzato { FiloHaptics.error() } else { FiloHaptics.warning() }
            }
            let nuovo = EsitoLocale(id: (esitoLocale?.id ?? 0) + 1, percorso: percorso, esito: esito)
            esitoLocale = nuovo
            let durata: Double = reduceMotion ? 0.24 : (esito == .spezzato ? 0.7 : 0.6)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(durata * 1_000_000_000))
                if esitoLocale == nuovo { esitoLocale = nil }
            }
        default:
            break
        }
    }

    private func dragGesture(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { g in
                guard !session.lockInput, !session.engine.gameOver else { return }
                guard let idx = BoardMetrics.cell(at: g.location, side: side) else { return }
                if !dragAttivo {
                    dragAttivo = true
                    caselleAlDown = session.engine.filo.count
                    downSuUltima = (session.engine.filo.last == idx)
                    if !downSuUltima { muovi(idx, viaTap: true) }
                } else {
                    muovi(idx, viaTap: false)
                }
            }
            .onEnded { g in
                if dragAttivo, downSuUltima,
                   session.engine.filo.count == caselleAlDown,
                   !session.engine.gameOver, !session.lockInput,
                   let idx = BoardMetrics.cell(at: g.location, side: side),
                   idx == session.engine.filo.last {
                    session.tapSuUltima(idx)
                }
                dragAttivo = false
                downSuUltima = false
            }
    }
}

/// Singola casella della board di pratica (layer di fondo): tessera piatta,
/// breve bordo error sulla mossa non valida, accessibilità.
private struct PracticeCellView: View {
    @ObservedObject var session: PracticeSession
    let idx: Int
    let side: CGFloat

    var body: some View {
        let inFilo = session.engine.filo.contains(idx)
        let nonValida = session.casellaNonValida == idx

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
        .accessibilityLabel(Text("Casella riga \(idx / 5 + 1) colonna \(idx % 5 + 1), valore \(session.puzzle.valori[idx])"))
        .accessibilityAddTraits(.isButton)
    }
}
