import SwiftUI

/// TRANSIZIONE DI SCHERMATA (REDESIGN_SPEC §6.2): crossfade pulito sullo
/// sfondo dell'app. Il fondale entra in dissolvenza (0,24 s easeOut; 0,15 s
/// con Riduci Movimento), copre lo schermo, e mentre è coperto il controller
/// esegue l'azione di cambio schermata (fullScreenCover con animazioni
/// disabilitate); poi il fondale esce in dissolvenza rivelando la nuova
/// schermata. Totale ≈ 0,52 s (≈ 0,34 s con Riduci Movimento).
///
/// API invariata (i nomi storici "Tile…" restano): un unico
/// `TileTransitionController` condiviso; un `TileRevealOverlay` attaccato SIA
/// alla schermata di partenza SIA al contenuto del cover: alla presentazione
/// il cover nasce già coperto (fase `.entrata`) e l'uscita avviene sopra la
/// schermata nuova. Per lo spostamento di 12 pt del contenuto usare
/// `.filoScreenShift(controller)` (DesignSystem.swift).
@MainActor
final class TileTransitionController: ObservableObject {

    enum Fase { case nascosta, entrata, uscita }

    @Published private(set) var fase: Fase = .nascosta
    /// Storico (origine dell'onda di tessere): conservato per compatibilità.
    @Published private(set) var origine: UnitPoint = .topLeading

    private var task: Task<Void, Never>?

    var attiva: Bool { fase != .nascosta }

    /// Durata di ciascuna dissolvenza (entrata e uscita).
    static func durataDissolvenza(reduceMotion: Bool) -> Double {
        reduceMotion ? FiloMotion.reducedDuration : FiloMotion.screenDuration
    }

    /// Coreografia completa: entrata → (schermo coperto) `alCoperto()` → uscita.
    /// Robusta e cancellabile: una nuova chiamata annulla la precedente.
    func esegui(da origine: UnitPoint = .topLeading,
                reduceMotion: Bool,
                alCoperto: @escaping @MainActor () -> Void) {
        task?.cancel()
        self.origine = origine
        let dissolvenza = UInt64(Self.durataDissolvenza(reduceMotion: reduceMotion) * 1_000_000_000)
        let pausa: UInt64 = 40_000_000
        fase = .entrata
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: dissolvenza)
            guard let self, !Task.isCancelled else { return }
            alCoperto()
            try? await Task.sleep(nanoseconds: pausa)
            guard !Task.isCancelled else { return }
            self.fase = .uscita
            try? await Task.sleep(nanoseconds: dissolvenza)
            guard !Task.isCancelled else { return }
            self.fase = .nascosta
        }
    }
}

/// Overlay a schermo intero: il fondale dell'app (`FiloBackground`) che
/// entra ed esce in dissolvenza. Resta sempre nella gerarchia (opacità 0,
/// inerte) così l'entrata può animare da 0; durante la transizione
/// intercetta i tocchi (niente doppio tap). Nascosto all'accessibilità.
struct TileRevealOverlay: View {
    @ObservedObject var controller: TileTransitionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let durata = TileTransitionController.durataDissolvenza(reduceMotion: reduceMotion)
        FiloBackground()
            .opacity(controller.fase == .entrata ? 1 : 0)
            .animation(.easeOut(duration: durata), value: controller.fase)
            .contentShape(Rectangle())
            .allowsHitTesting(controller.attiva)
            .accessibilityHidden(true)
    }
}
