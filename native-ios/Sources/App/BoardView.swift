import SwiftUI
import FiloCore

/// Griglia 5×5 con overlay del filo (Path/Shape animati) e input tap + drag
/// via DragGesture(minimumDistance: 0) — semantica README §6.2/§6.6.
struct BoardView: View {
    @EnvironmentObject private var vm: GameViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var trimFilo: CGFloat = 1
    @State private var sartoTrim: CGFloat = 0
    @State private var dragAttivo = false
    @State private var downSuUltima = false
    @State private var caselleAlDown = 0
    @State private var casellaDown: Int?

    private let gap: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let side = (geo.size.width - gap * 4) / 5
            ZStack(alignment: .topLeading) {
                ForEach(0..<25, id: \.self) { idx in
                    CellView(idx: idx, side: side)
                        .frame(width: side, height: side)
                        .offset(x: CGFloat(idx % 5) * (side + gap),
                                y: CGFloat(idx / 5) * (side + gap))
                }
                overlayFili(side: side)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(side: side))
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.error, trigger: vm.shakeTick)
        .onChange(of: vm.engine.filo.count) { vecchio, nuovo in
            // il segmento nuovo "viene cucito" (trim dell'ultimo tratto, UX §7.2)
            guard nuovo > vecchio, nuovo >= 2, !reduceMotion else {
                trimFilo = 1
                return
            }
            trimFilo = CGFloat(nuovo - 2) / CGFloat(nuovo - 1)
            withAnimation(.easeOut(duration: 0.12)) { trimFilo = 1 }
        }
        .onChange(of: vm.revealSarto) { _, attivo in
            aggiornaSarto(attivo: attivo, animato: true)
        }
        .onAppear {
            aggiornaSarto(attivo: vm.revealSarto, animato: false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Griglia di gioco, 5 righe per 5 colonne")
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

    // MARK: Overlay del filo

    private func centro(_ idx: Int, side: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(idx % 5) * (side + gap) + side / 2,
                y: CGFloat(idx / 5) * (side + gap) + side / 2)
    }

    @ViewBuilder
    private func overlayFili(side: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // reveal del percorso del Sarto (filo d'oro chiaro che "si cuce")
            if vm.revealSarto {
                PolylineShape(points: vm.puzzle.percorsoSarto.map { centro($0, side: side) })
                    .trim(from: 0, to: sartoTrim)
                    .stroke(Theme.sarto,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            // filo dell'esito appena concluso, in dissolvenza colorata
            if let ev = vm.esitoVisuale {
                EsitoFiloOverlay(punti: ev.percorso.map { centro($0, side: side) },
                                 esito: ev.esito)
            }
            // filo corrente
            if let primo = vm.engine.filo.first {
                Circle()
                    .fill(Theme.filo)
                    .frame(width: 10, height: 10)
                    .position(centro(primo, side: side))
                if vm.engine.filo.count >= 2 {
                    PolylineShape(points: vm.engine.filo.map { centro($0, side: side) })
                        .trim(from: 0, to: trimFilo)
                        .stroke(Theme.filo,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Input tap + drag

    private func cella(at p: CGPoint, side: CGFloat) -> Int? {
        let step = side + gap
        let c = Int(floor(p.x / step)), r = Int(floor(p.y / step))
        guard (0..<5).contains(c), (0..<5).contains(r) else { return nil }
        // area utile ridotta del 12%: meno falsi positivi negli angoli (come il web)
        let x0 = CGFloat(c) * step, y0 = CGFloat(r) * step
        let m = side * 0.12
        guard p.x >= x0 + m, p.x <= x0 + side - m,
              p.y >= y0 + m, p.y <= y0 + side - m else { return nil }
        return r * 5 + c
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

/// Filo appena perso: resta visibile nel colore dell'esito e si dissolve.
private struct EsitoFiloOverlay: View {
    let punti: [CGPoint]
    let esito: EsitoFilo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacita = 1.0
    @State private var caduta = 0.0

    private var colore: Color {
        switch esito {
        case .spezzato: return Theme.spezzato
        case .annodato: return Theme.annodato
        default: return Theme.filo
        }
    }

    var body: some View {
        ZStack {
            if let primo = punti.first {
                Circle().fill(colore).frame(width: 10, height: 10).position(primo)
            }
            PolylineShape(points: punti)
                .stroke(colore,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round,
                                           dash: esito == .spezzato && !reduceMotion ? [4, 8] : []))
        }
        .opacity(opacita)
        .offset(y: caduta)
        .onAppear {
            let durata = reduceMotion ? 0.2 : 0.4
            let ritardo = reduceMotion ? 0.0 : 0.15
            withAnimation(.easeIn(duration: durata).delay(ritardo)) {
                opacita = 0
                if esito != .spezzato && !reduceMotion { caduta = 4 }
            }
        }
    }
}

/// Singola casella: stati default / in-filo / ultima / sarto / shake (UX §5.1).
struct CellView: View {
    @EnvironmentObject private var vm: GameViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let idx: Int
    let side: CGFloat
    @State private var pulse = false

    var body: some View {
        let pos = vm.engine.filo.firstIndex(of: idx)
        let inFilo = pos != nil
        let ultima = inFilo && pos == vm.engine.filo.count - 1 && !vm.engine.gameOver
        let sulSarto = vm.revealSarto && vm.puzzle.percorsoSarto.contains(idx)
        let flashNonValida = reduceMotion && vm.casellaNonValida == idx

        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(inFilo ? Theme.filo : Theme.surface2)
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(flashNonValida ? Theme.spezzato
                              : (inFilo ? Theme.filoScuro : Theme.border), lineWidth: 1)
            if sulSarto {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.sarto,
                                  style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .padding(2)
            }
            Text("\(vm.puzzle.valori[idx])")
                .font(.system(size: max(17, side * 0.4), weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(inFilo ? Theme.bg : Theme.text)
                .minimumScaleFactor(0.6)
        }
        .overlay(alignment: .topTrailing) {
            if let p = pos {
                Text("\(p + 1)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.bg)
                    .padding(.top, 3)
                    .padding(.trailing, 5)
            }
        }
        .overlay {
            if ultima {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.filo.opacity(reduceMotion ? 0.4 : (pulse ? 0.15 : 0.4)),
                                  lineWidth: 3)
                    .padding(-3)
                    .onAppear {
                        guard !reduceMotion else { return }
                        pulse = false
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
            }
        }
        .modifier(ShakeEffect(travel: reduceMotion ? 0 : 4,
                              shakes: CGFloat(vm.shakes[idx] ?? 0)))
        .animation(reduceMotion ? nil : .linear(duration: 0.24), value: vm.shakes[idx])
        .animation(.easeInOut(duration: 0.16), value: inFilo)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(vm.etichettaCasella(idx))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            vm.gioca(idx, viaTap: true)
        }
    }
}
