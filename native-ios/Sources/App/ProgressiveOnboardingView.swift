import SwiftUI
import FiloCore

/// ONBOARDING PROGRESSIVO "Riscaldamento" (primo avvio, dopo "Come si gioca").
/// Tre mini-sfide a somma piccola e crescente generate con `PracticeGenerator`,
/// per creare confidenza col gesto del filo PRIMA del FILO del giorno.
/// Saltabile e mostrato UNA sola volta (flag `filo.onboardingProgressivoFatto`).
/// Stesso linguaggio visivo dell'HUD/board della Partita (REDESIGN_SPEC §6.9).
struct ProgressiveOnboardingView: View {
    @EnvironmentObject private var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var indice = 0
    private let targets = [6, 10, 15]

    var body: some View {
        GeometryReader { geo in
            let margine = FiloMetrics.margin(forWidth: geo.size.width)
            VStack(spacing: 0) {
                header
                SfidaPratica(
                    target: targets[indice],
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
    @State private var messaggio: String?

    init(target: Int, indice: Int, totale: Int, ultima: Bool,
         onVittoria: @escaping () -> Void) {
        self.target = target
        self.indice = indice
        self.totale = totale
        self.ultima = ultima
        self.onVittoria = onVittoria
        let puzzle = PracticeGenerator.make(target: target, seed: UInt64(0xF11040 + indice))
        _session = StateObject(wrappedValue: PracticeSession(puzzle: puzzle))
    }

    var body: some View {
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

            // La board si adatta all'altezza disponibile (aspectRatio .fit).
            PracticeBoardView(session: session, onMove: gestisci)
                .frame(maxWidth: BoardMetrics.maxWidth)
                .layoutPriority(1)

            Text(messaggio ?? " ")
                .filoFont(.body)
                .foregroundStyle(vinta ? Theme.success : Theme.textSecondary)
                .frame(minHeight: 22)
                .animation(FiloMotion.adaptive(FiloMotion.screen, reduceMotion: reduceMotion), value: messaggio)

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
            .frame(minHeight: FiloMetrics.primaryHeight)
            .animation(FiloMotion.adaptive(FiloMotion.screen, reduceMotion: reduceMotion), value: vinta)
            .padding(.bottom, FiloMetrics.relatedGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            HStack(alignment: .firstTextBaseline, spacing: FiloMetrics.relatedGap) {
                Text("Somma attuale")
                    .filoFont(.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\(session.somma)")
                        .filoFont(.currentSum)
                        .monospacedDigit()
                        .foregroundStyle(vinta ? Theme.success : Theme.textPrimary)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : FiloMotion.numeric, value: session.somma)
                    Text(verbatim: "/ \(target)")
                        .filoFont(.body)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Somma attuale: \(session.somma) di \(target)"))
        }
    }

    private func gestisci(_ mossa: Mossa) {
        switch mossa {
        case .vittoria:
            guard !vinta else { return }
            vinta = true
            session.blocca()
            messaggio = String(localized: "Perfetto.")
        case .spezzato, .annodato:
            messaggio = String(localized: "Quasi. Riprova.")
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !vinta { session.ripulisci() }
            }
        default:
            break
        }
    }
}
