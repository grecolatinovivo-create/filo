import SwiftUI

/// TRANSIZIONE "BLOCCHI NUMERICI" — riusabile per aprire/chiudere le schermate
/// dal menu: una griglia di tessere in stile CellView entra in cascata (onda
/// diagonale dall'angolo di partenza), copre lo schermo, e mentre è coperta il
/// controller esegue l'azione di cambio schermata (fullScreenCover con
/// animazioni disabilitate); poi le tessere escono nella stessa onda rivelando
/// la nuova schermata. Con Riduci Movimento la coreografia degrada a un fade
/// pieno e veloce.
///
/// Uso: un unico `TileTransitionController` condiviso; un `TileRevealOverlay`
/// attaccato SIA alla schermata di partenza SIA al contenuto del cover: alla
/// presentazione il cover mostra le stesse tessere già "piene" (griglia e
/// numeri deterministici → nessun salto visivo) e l'uscita avviene sopra la
/// schermata nuova.
@MainActor
final class TileTransitionController: ObservableObject {

    enum Fase { case nascosta, entrata, uscita }

    @Published private(set) var fase: Fase = .nascosta
    @Published private(set) var origine: UnitPoint = .topLeading

    private var task: Task<Void, Never>?

    var attiva: Bool { fase != .nascosta }

    /// Coreografia completa: entrata → (schermo coperto) `alCoperto()` → uscita.
    /// Robusta e cancellabile: una nuova chiamata annulla la precedente.
    func esegui(da origine: UnitPoint = .topLeading,
                reduceMotion: Bool,
                alCoperto: @escaping @MainActor () -> Void) {
        task?.cancel()
        self.origine = origine
        // Tempi (vedi TileRevealOverlay): stagger max ~0.16s + spring ~0.28s.
        let copertura: UInt64 = reduceMotion ? 180_000_000 : 440_000_000
        let pausa: UInt64     = reduceMotion ?  40_000_000 :  70_000_000
        let uscita: UInt64    = reduceMotion ? 220_000_000 : 500_000_000
        fase = .entrata
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: copertura)
            guard let self, !Task.isCancelled else { return }
            alCoperto()
            try? await Task.sleep(nanoseconds: pausa)
            guard !Task.isCancelled else { return }
            self.fase = .uscita
            try? await Task.sleep(nanoseconds: uscita)
            guard !Task.isCancelled else { return }
            self.fase = .nascosta
        }
    }
}

/// Overlay a schermo intero con le tessere numerate. Inerte (rimosso dalla
/// gerarchia) quando la fase è `.nascosta`; durante la transizione intercetta
/// i tocchi così non si tappa due volte.
struct TileRevealOverlay: View {
    @ObservedObject var controller: TileTransitionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Colonne fisse: le righe seguono l'altezza reale dello schermo.
    private static let colonne = 6

    /// Numero stabile per tessera: hash intero seedato dall'indice
    /// (deterministico fra render e fra istanze dell'overlay, mai random).
    static func numero(per indice: Int) -> Int {
        Int((UInt64(indice) &* 2_654_435_761) % 9) + 1
    }

    var body: some View {
        if controller.fase != .nascosta {
            GeometryReader { geo in
                if reduceMotion {
                    // Degradazione: fade pieno, niente cascata.
                    Theme.bg
                        .opacity(controller.fase == .entrata ? 1 : 0)
                        .animation(.easeInOut(duration: 0.16), value: controller.fase)
                } else {
                    griglia(in: geo.size)
                }
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .accessibilityHidden(true)
            .transition(.identity)
        }
    }

    private func griglia(in size: CGSize) -> some View {
        let cols = Self.colonne
        let lato = size.width / CGFloat(cols)
        let rows = max(1, Int(ceil(size.height / lato)))
        let visibile = controller.fase == .entrata
        let o = controller.origine
        // Onda diagonale normalizzata: distanza Manhattan dall'angolo d'origine.
        let ondaMax = max(1.0, Double(cols - 1) + Double(rows - 1))
        return ZStack(alignment: .topLeading) {
            // Fondale opaco: copre le fughe fra le tessere quando lo schermo
            // cambia "sotto" la griglia.
            Theme.bg
                .opacity(visibile ? 1 : 0)
                .animation(.easeInOut(duration: 0.22).delay(visibile ? 0.18 : 0.05),
                           value: controller.fase)
            ForEach(0..<(rows * cols), id: \.self) { i in
                let r = i / cols
                let c = i % cols
                let dx = abs(Double(c) - Double(o.x) * Double(cols - 1))
                let dy = abs(Double(r) - Double(o.y) * Double(rows - 1))
                let ritardo = (dx + dy) / ondaMax * 0.16
                TileCell(numero: Self.numero(per: i), lato: lato)
                    .frame(width: lato, height: lato)
                    .scaleEffect(visibile ? 1 : 0.6)
                    .opacity(visibile ? 1 : 0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.82)
                        .delay(ritardo), value: controller.fase)
                    .offset(x: CGFloat(c) * lato, y: CGFloat(r) * lato)
            }
        }
    }
}

/// Singola tessera, stile CellView (RoundedRectangle surface2 + bordo +
/// numero monospaced).
private struct TileCell: View {
    let numero: Int
    let lato: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface2)
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.border, lineWidth: 1)
            Text(verbatim: "\(numero)")
                .font(.system(size: lato * 0.38, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Theme.textMuted)
        }
        .padding(2)
    }
}
