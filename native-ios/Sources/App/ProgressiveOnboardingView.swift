import SwiftUI
import FiloCore

/// ONBOARDING PROGRESSIVO "Riscaldamento" (primo avvio, dopo "Come si gioca").
/// Tre mini-sfide a somma piccola e crescente (6, 10, 15 con percorsi di 2, 3
/// e 4 caselle) generate con `SalitaGenerator.make(target:length:seed:minShortest:)`:
/// nessuna soluzione più corta del percorso previsto, quindi niente
/// soluzioni banali fatte di una sola cifra ripetuta. Crea confidenza col
/// gesto del filo PRIMA del FILO del giorno.
/// Saltabile e mostrato UNA sola volta (flag `filo.onboardingProgressivoFatto`).
/// Stesso linguaggio visivo dell'HUD/board della Partita (REDESIGN_SPEC §6.9).
struct ProgressiveOnboardingView: View {
    @EnvironmentObject private var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var indice = 0
    private let targets = [6, 10, 15]
    /// Lunghezza del percorso d'autore di ogni sfida (SALITA_TIMER_SPEC §2).
    private let lunghezze = [2, 3, 4]

    var body: some View {
        GeometryReader { geo in
            let margine = FiloMetrics.margin(forWidth: geo.size.width)
            VStack(spacing: 0) {
                header
                SfidaPratica(
                    target: targets[indice],
                    lunghezza: lunghezze[indice],
                    indice: indice,
                    totale: targets.count,
                    ultima: indice == targets.count - 1,
                    onVittoria: avanza
                )
                .id(indice)   // ricrea la sotto-vista (e il suo @StateObject) a ogni sfida
            }
            .padding(.horizontal, margine)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background { FiloBackground() }
        .presentationCornerRadius(FiloMetrics.sheetCorner)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: FiloMetrics.relatedGap) {
            Text("Riscaldamento")
                .filoFont(.screenTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button("Salta") { completa() }
                .buttonStyle(TertiaryButtonStyle())
                .padding(.trailing, -8)   // allinea il testo al margine
        }
        .frame(minHeight: FiloMetrics.headerHeight)
        .padding(.top, FiloMetrics.relatedGap)
    }

    private func avanza() {
        if indice < targets.count - 1 {
            indice += 1
        } else {
            completa()
        }
    }

    private func completa() {
        vm.segnaOnboardingProgressivoFatto()
        dismiss()
    }
}

/// Una singola mini-sfida di riscaldamento.
private struct SfidaPratica: View {
    let target: Int
    let indice: Int
    let totale: Int
    let ultima: Bool
    var onVittoria: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var session: PracticeSession
    @State private var vinta = false
    @State private var feedback: String?

    init(target: Int, lunghezza: Int, indice: Int, totale: Int, ultima: Bool,
         onVittoria: @escaping () -> Void) {
        self.target = target
        self.indice = indice
        self.totale = totale
        self.ultima = ultima
        self.onVittoria = onVittoria
        // Seme fisso (riscaldamento identico per tutti); `minShortest` =
        // lunghezza: nessuna soluzione più corta del percorso previsto.
        let puzzle = SalitaGenerator.make(target: target, length: lunghezza,
                                          seed: UInt64(0xF11040 + indice),
                                          minShortest: lunghezza)
        _session = StateObject(wrappedValue: PracticeSession(puzzle: puzzle))
    }

    /// Altezza misurata di consegna + HUD (dimensionamento della griglia).
    @State private var altezzaTesta: CGFloat = 200

    /// Messaggio (22) + spazi (2 × 16) + CTA (56): sotto la griglia.
    private var altezzaControlli: CGFloat { 22 + 16 + 16 + FiloMetrics.primaryHeight }

    var body: some View {
        // Stessa composizione della Partita (ROUND2 §6): consegna + HUD in
        // alto, griglia + feedback + CTA centrati nello spazio che resta.
        GeometryReader { area in
            let larghezza = GameScreenMetrics.larghezzaGriglia(contenitore: area.size.width, margine: 0)
            let lato = GameScreenMetrics.latoGriglia(larghezza: larghezza,
                                                     altezzaDisponibile: area.size.height,
                                                     altezzaHUD: altezzaTesta,
                                                     altezzaControlli: altezzaControlli)
            ScrollView {
                GameScreenLayout(altezzaMinima: area.size.height) {
                    VStack(spacing: FiloMetrics.relatedGapLarge) {
                        VStack(spacing: FiloMetrics.relatedGap) {
                            Text("Sfida \(indice + 1) di \(totale)")
                                .eyebrowStyle()
                            Text("Traccia un filo che faccia esattamente \(target).")
                                .filoFont(.body)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, FiloMetrics.relatedGap)

                        hud
                    }
                    .frame(maxWidth: larghezza)
                    .misuraAltezza($altezzaTesta)

                    VStack(spacing: FiloMetrics.relatedGapLarge) {
                        PracticeBoardView(session: session, onMove: gestisci)
                            .frame(width: lato, height: lato)

                        Text(feedback ?? " ")
                            .filoFont(.body)
                            .foregroundStyle(vinta ? Theme.success : Theme.textSecondary)
                            .frame(minHeight: 22)
                            .animation(FiloMotion.adaptive(FiloMotion.screen, reduceMotion: reduceMotion), value: feedback)

                        // Spazio riservato alla CTA: la board non salta quando compare.
                        ZStack {
                            if vinta {
                                Button(ultima ? String(localized: "Inizia a giocare")
                                              : String(localized: "Prossima sfida")) {
                                    FiloHaptics.light()
                                    onVittoria()
                                }
                                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                                .transition(.opacity)
                            }
                        }
                        .frame(maxWidth: lato, minHeight: FiloMetrics.primaryHeight)
                        .animation(FiloMotion.adaptive(FiloMotion.screen, reduceMotion: reduceMotion), value: vinta)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var hud: some View {
        VStack(spacing: 4) {
            Text("Obiettivo").eyebrowStyle()
            Text(verbatim: "\(target)")
                .filoFont(.target)
                .monospacedDigit()
                .foregroundStyle(vinta ? Theme.success : Theme.gold)
                .animation(.easeOut(duration: 0.25), value: vinta)
                .accessibilityLabel(Text("Obiettivo: \(target)"))
            // Stessa metrica "Somma attuale" di Partita e Salita.
            GameHUDMetric(somma: session.somma,
                          totale: target,
                          coloreValore: vinta ? Theme.success : Theme.textPrimary,
                          etichetta: Text("Somma attuale: \(session.somma) di \(target)"))
                .padding(.top, 4)
        }
    }

    private func gestisci(_ mossa: Mossa) {
        switch mossa {
        case .vittoria:
            guard !vinta else { return }
            vinta = true
            session.blocca()
            feedback = String(localized: "Perfetto.")
        case .spezzato, .annodato:
            feedback = String(localized: "Quasi. Riprova.")
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !vinta { session.ripulisci() }
            }
        default:
            break
        }
    }
}
