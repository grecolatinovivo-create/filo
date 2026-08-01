import SwiftUI
import FiloCore

/// Archivio dei FILO passati (extra a pagamento). I puzzle sono deterministici
/// dalla data (Generator.daily), quindi l'archivio non richiede alcun backend:
/// ogni giorno dall'EPOCH a ieri è rigiocabile in locale. Le partite d'archivio
/// NON toccano statistiche né streak del gioco quotidiano.
struct ArchiveView: View {
    @EnvironmentObject private var vm: GameViewModel
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var selezione: GiornoArchivio?

    private var giorni: [GiornoArchivio] { Self.giorniPassati(oggi: GameViewModel.oggiParts()) }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            if !store.featuresUnlocked {
                paywall
            } else if giorni.isEmpty {
                vuoto
            } else {
                lista
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $selezione) { g in
            ArchivePlayerView(giorno: g)
        }
    }

    private var header: some View {
        HStack {
            Text("Archivio FILO")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Chiudi")
        }
    }

    private var lista: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Text("Rigioca ogni FILO uscito finora. Non intacca la tua serie.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)
                LazyVStack(spacing: 8) {
                    ForEach(giorni) { g in
                        Button { selezione = g } label: { riga(g) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private func riga(_ g: GiornoArchivio) -> some View {
        HStack(spacing: 14) {
            Text("#\(g.numero)")
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(Theme.filo)
                .frame(minWidth: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(g.etichettaData)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.text)
                Text("Somma \(g.somma) · Sarto \(g.lSarto) caselle")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.filo)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("FILO numero \(g.numero), \(g.etichettaData), somma \(g.somma)")
    }

    private var vuoto: some View {
        VStack(spacing: 14) {
            header
            Spacer()
            Text("🧵")
                .font(.system(size: 48))
            Text("Il primo FILO è quello di oggi.\nDa domani ritrovi qui gli scorsi.")
                .font(.body)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }

    private var paywall: some View {
        VStack(spacing: 16) {
            header
            Spacer()
            Text("🗂️")
                .font(.system(size: 52))
            Text("Archivio dei FILO passati")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.text)
            Text("Rigioca ogni puzzle uscito finora e sblocca i temi colorati con l'acquisto extra, una volta sola.")
                .font(.body)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
            Button(store.prezzoExtra.map { "Sblocca extra · \($0)" } ?? "Sblocca extra") {
                Task { await store.acquistaExtra() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.inCorso)
            Button("Ripristina acquisti") { Task { await store.ripristina() } }
                .font(.subheadline)
                .foregroundStyle(Theme.filo)
                .frame(minHeight: 44)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 480)
    }

    // MARK: Dati archivio

    struct GiornoArchivio: Identifiable, Equatable {
        let y: Int, m: Int, d: Int
        let numero: Int
        let somma: Int
        let lSarto: Int
        var id: Int { numero }
        var etichettaData: String {
            let mesi = ["", "gennaio","febbraio","marzo","aprile","maggio","giugno",
                        "luglio","agosto","settembre","ottobre","novembre","dicembre"]
            return "\(d) \(mesi[m]) \(y)"
        }
    }

    /// Tutti i giorni dall'EPOCH fino a ieri, dal più recente. Limite prudente
    /// per non generare all'infinito (l'archivio cresce di un giorno al giorno).
    static func giorniPassati(oggi: (y: Int, m: Int, d: Int)) -> [GiornoArchivio] {
        let oggiN = FiloDate.puzzleNumber(y: oggi.y, m: oggi.m, d: oggi.d)
        guard oggiN > 1 else { return [] }
        var out: [GiornoArchivio] = []
        var cur = FiloDate.previousDay(y: oggi.y, m: oggi.m, d: oggi.d)
        var n = oggiN - 1
        let massimo = 400
        while n >= 1 && out.count < massimo {
            let daily = Generator.daily(y: cur.y, m: cur.m, d: cur.d)
            out.append(GiornoArchivio(y: cur.y, m: cur.m, d: cur.d, numero: daily.numero,
                                      somma: daily.puzzle.T, lSarto: daily.puzzle.lSarto))
            cur = FiloDate.previousDay(y: cur.y, m: cur.m, d: cur.d)
            n -= 1
        }
        return out
    }
}

/// Sessione di gioco d'archivio: un GameEngine isolato, senza persistenza né
/// statistiche. Riusa la logica pura di FiloCore (nessuna deviazione di regole).
@MainActor
final class ArchiveSession: ObservableObject {
    let puzzle: Puzzle
    let numero: Int
    @Published private(set) var engine: GameEngine
    @Published private(set) var revealSarto = false

    init(giorno g: ArchiveView.GiornoArchivio) {
        let daily = Generator.daily(y: g.y, m: g.m, d: g.d)
        puzzle = daily.puzzle
        numero = daily.numero
        engine = GameEngine(puzzle: daily.puzzle)
    }

    func gioca(_ idx: Int) {
        guard !engine.gameOver else { return }
        let mossa = engine.gioca(idx)
        if mossa == .vittoria || engine.stato == .persa { revealSarto = true }
    }

    func strappa() {
        guard !engine.filo.isEmpty, !engine.gameOver else { return }
        _ = engine.strappa()
        if engine.stato == .persa { revealSarto = true }
    }

    func ricomincia() {
        engine = GameEngine(puzzle: puzzle)
        revealSarto = false
    }

    var esitoTesto: String {
        switch engine.stato {
        case .vinta:
            let c = engine.percorsoVincente?.count ?? 0
            return Punteggio.stelle(caselle: c, lSarto: puzzle.lSarto).label
        case .persa: return "Il Sarto la spunta — riprova"
        case .inCorso: return ""
        }
    }
}

/// Player d'archivio: board compatta autonoma, stessa estetica del gioco.
struct ArchivePlayerView: View {
    @StateObject private var s: ArchiveSession
    @Environment(\.dismiss) private var dismiss

    init(giorno: ArchiveView.GiornoArchivio) {
        _s = StateObject(wrappedValue: ArchiveSession(giorno: giorno))
    }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            VStack(spacing: 14) {
                HStack {
                    Text("FILO #\(s.numero)")
                        .font(.headline).foregroundStyle(Theme.text)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textMuted)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Chiudi")
                }

                VStack(spacing: 2) {
                    Text("Somma del Giorno").captionStyle()
                    Text("\(s.puzzle.T)")
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                    Text("Filo \(s.engine.somma) · \(s.engine.filo.count) caselle · Sarto \(s.puzzle.lSarto)")
                        .captionStyle()
                }

                ArchiveBoard(session: s)
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 8)

                if s.engine.gameOver {
                    Text(s.esitoTesto)
                        .font(.headline)
                        .foregroundStyle(s.engine.stato == .vinta ? Theme.filo : Theme.text)
                        .multilineTextAlignment(.center)
                    Button("Rigioca") { s.ricomincia() }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("Strappa il filo") { s.strappa() }
                        .buttonStyle(SecondaryButtonStyle(enabled: !s.engine.filo.isEmpty))
                        .disabled(s.engine.filo.isEmpty)
                }
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .preferredColorScheme(.dark)
    }
}

/// Board compatta per il player d'archivio (input tap + drag, stessa semantica
/// di BoardView ma disaccoppiata dal GameViewModel quotidiano).
private struct ArchiveBoard: View {
    @ObservedObject var session: ArchiveSession
    private let gap: CGFloat = 6
    @State private var dragAttivo = false

    var body: some View {
        GeometryReader { geo in
            let side = (geo.size.width - gap * 4) / 5
            ZStack(alignment: .topLeading) {
                ForEach(0..<25, id: \.self) { idx in
                    cella(idx: idx, side: side)
                        .frame(width: side, height: side)
                        .offset(x: CGFloat(idx % 5) * (side + gap),
                                y: CGFloat(idx / 5) * (side + gap))
                }
                overlay(side: side)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { g in
                        guard !session.engine.gameOver,
                              let idx = indice(g.location, side: side) else { return }
                        if !dragAttivo {
                            dragAttivo = true
                            if session.engine.filo.last != idx { session.gioca(idx) }
                        } else {
                            session.gioca(idx)
                        }
                    }
                    .onEnded { _ in dragAttivo = false }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func indice(_ p: CGPoint, side: CGFloat) -> Int? {
        let step = side + gap
        let c = Int(floor(p.x / step)), r = Int(floor(p.y / step))
        guard (0..<5).contains(c), (0..<5).contains(r) else { return nil }
        let x0 = CGFloat(c) * step, y0 = CGFloat(r) * step, m = side * 0.12
        guard p.x >= x0 + m, p.x <= x0 + side - m,
              p.y >= y0 + m, p.y <= y0 + side - m else { return nil }
        return r * 5 + c
    }

    private func centro(_ idx: Int, side: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(idx % 5) * (side + gap) + side / 2,
                y: CGFloat(idx / 5) * (side + gap) + side / 2)
    }

    private func cella(idx: Int, side: CGFloat) -> some View {
        let pos = session.engine.filo.firstIndex(of: idx)
        let inFilo = pos != nil
        let sulSarto = session.revealSarto && session.puzzle.percorsoSarto.contains(idx)
        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(inFilo ? AnyShapeStyle(Theme.cellaAccesa) : AnyShapeStyle(Theme.surface2))
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(inFilo ? Theme.filoScuro : Theme.border, lineWidth: 1)
            if sulSarto {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.sarto, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .padding(2)
            }
            Text("\(session.puzzle.valori[idx])")
                .font(.system(size: max(17, side * 0.4), weight: .semibold, design: .monospaced))
                .foregroundStyle(inFilo ? Theme.bg : Theme.text)
        }
        .animation(.easeInOut(duration: 0.16), value: inFilo)
    }

    @ViewBuilder
    private func overlay(side: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if session.revealSarto {
                PolylineShape(points: session.puzzle.percorsoSarto.map { centro($0, side: side) })
                    .stroke(Theme.sarto, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let primo = session.engine.filo.first {
                Circle().fill(Theme.filo).frame(width: 10, height: 10)
                    .position(centro(primo, side: side))
                if session.engine.filo.count >= 2 {
                    PolylineShape(points: session.engine.filo.map { centro($0, side: side) })
                        .stroke(Theme.filoGradient,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
