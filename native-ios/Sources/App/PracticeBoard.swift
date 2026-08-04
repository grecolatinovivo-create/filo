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
/// Stessa gestualità tap+drag della `BoardView` del giornaliero, ma disaccoppiata
/// da `GameViewModel`: ogni esito di mossa viene inoltrato al genitore via `onMove`.
struct PracticeBoardView: View {
    @ObservedObject var session: PracticeSession
    var onMove: (Mossa) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var trimFilo: CGFloat = 1
    @State private var solTrim: CGFloat = 0
    @State private var dragAttivo = false
    @State private var downSuUltima = false
    @State private var caselleAlDown = 0

    private let gap: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let side = (geo.size.width - gap * 4) / 5
            ZStack(alignment: .topLeading) {
                ForEach(0..<25, id: \.self) { idx in
                    PracticeCellView(session: session, idx: idx, side: side)
                        .frame(width: side, height: side)
                        .offset(x: CGFloat(idx % 5) * (side + gap),
                                y: CGFloat(idx / 5) * (side + gap))
                }
                overlay(side: side)
            }
            .frame(width: geo.size.width, height: geo.size.width, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(dragGesture(side: side))
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.error, trigger: session.shakeTick)
        .onChange(of: session.engine.filo.count) { vecchio, nuovo in
            guard nuovo > vecchio, nuovo >= 2, !reduceMotion else { trimFilo = 1; return }
            trimFilo = CGFloat(nuovo - 2) / CGFloat(nuovo - 1)
            withAnimation(.easeOut(duration: 0.12)) { trimFilo = 1 }
        }
        .onChange(of: session.revealSolution) { _, attivo in
            aggiornaSoluzione(attivo: attivo, animato: true)
        }
        .onAppear { aggiornaSoluzione(attivo: session.revealSolution, animato: false) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Griglia di gioco, 5 righe per 5 colonne")
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

    private func centro(_ idx: Int, side: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(idx % 5) * (side + gap) + side / 2,
                y: CGFloat(idx / 5) * (side + gap) + side / 2)
    }

    @ViewBuilder
    private func overlay(side: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if session.revealSolution {
                PolylineShape(points: session.puzzle.percorsoSarto.map { centro($0, side: side) })
                    .trim(from: 0, to: solTrim)
                    .stroke(Theme.sarto,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let primo = session.engine.filo.first {
                Circle().stroke(Theme.sarto, lineWidth: 2)
                    .frame(width: 18, height: 18).position(centro(primo, side: side))
                Circle().fill(Theme.filoGradient)
                    .frame(width: 11, height: 11).position(centro(primo, side: side))
                if session.engine.filo.count >= 2 {
                    PolylineShape(points: session.engine.filo.map { centro($0, side: side) })
                        .trim(from: 0, to: trimFilo)
                        .stroke(Theme.filoGradient,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                        .shadow(color: Theme.filo.opacity(0.6), radius: 4, y: 0)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func cella(at p: CGPoint, side: CGFloat) -> Int? {
        let step = side + gap
        let c = Int(floor(p.x / step)), r = Int(floor(p.y / step))
        guard (0..<5).contains(c), (0..<5).contains(r) else { return nil }
        let x0 = CGFloat(c) * step, y0 = CGFloat(r) * step
        let m = side * 0.12
        guard p.x >= x0 + m, p.x <= x0 + side - m,
              p.y >= y0 + m, p.y <= y0 + side - m else { return nil }
        return r * 5 + c
    }

    private func dragGesture(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { g in
                guard !session.lockInput, !session.engine.gameOver else { return }
                guard let idx = cella(at: g.location, side: side) else { return }
                if !dragAttivo {
                    dragAttivo = true
                    caselleAlDown = session.engine.filo.count
                    downSuUltima = (session.engine.filo.last == idx)
                    if !downSuUltima { onMove(session.gioca(idx, viaTap: true)) }
                } else {
                    onMove(session.gioca(idx, viaTap: false))
                }
            }
            .onEnded { g in
                if dragAttivo, downSuUltima,
                   session.engine.filo.count == caselleAlDown,
                   !session.engine.gameOver, !session.lockInput,
                   let idx = cella(at: g.location, side: side),
                   idx == session.engine.filo.last {
                    session.tapSuUltima(idx)
                }
                dragAttivo = false
                downSuUltima = false
            }
    }
}

/// Singola casella della board di pratica (stati default / in-filo / ultima / soluzione).
private struct PracticeCellView: View {
    @ObservedObject var session: PracticeSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let idx: Int
    let side: CGFloat

    var body: some View {
        let pos = session.engine.filo.firstIndex(of: idx)
        let inFilo = pos != nil
        let sulSarto = session.revealSolution && session.puzzle.percorsoSarto.contains(idx)
        let flashNonValida = reduceMotion && session.casellaNonValida == idx

        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(inFilo ? AnyShapeStyle(Theme.cellaAccesa) : AnyShapeStyle(Theme.surface2))
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(flashNonValida ? Theme.spezzato
                              : (inFilo ? Theme.filoScuro : Theme.border), lineWidth: 1)
            if sulSarto {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Theme.sarto, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .padding(2)
            }
            Text("\(session.puzzle.valori[idx])")
                .font(.system(size: max(17, side * 0.4), weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(inFilo ? Theme.bg : Theme.text)
                .minimumScaleFactor(0.6)
        }
        .overlay(alignment: .topTrailing) {
            if let p = pos {
                Text("\(p + 1)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.filo)
                    .frame(width: 16, height: 16)
                    .background(Theme.bg.opacity(0.85), in: Circle())
                    .overlay(Circle().strokeBorder(Theme.filo.opacity(0.5), lineWidth: 1))
                    .padding(3)
            }
        }
        .modifier(ShakeEffect(travel: reduceMotion ? 0 : 4,
                              shakes: CGFloat(session.shakes[idx] ?? 0)))
        .animation(reduceMotion ? nil : .linear(duration: 0.24), value: session.shakes[idx])
        .animation(.easeInOut(duration: 0.16), value: inFilo)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Casella riga \(idx / 5 + 1) colonna \(idx % 5 + 1), valore \(session.puzzle.valori[idx])"))
        .accessibilityAddTraits(.isButton)
    }
}
