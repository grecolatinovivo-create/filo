import SwiftUI
import FiloCore

/// ONBOARDING PROGRESSIVO (primo avvio, dopo il tutorial "Come si gioca").
/// Tre mini-sfide a somma piccola e crescente generate con `PracticeGenerator`,
/// per creare confidenza col gesto del filo PRIMA del FILO del giorno.
/// Saltabile e mostrato UNA sola volta (flag `filo.onboardingProgressivoFatto`).
struct ProgressiveOnboardingView: View {
    @EnvironmentObject private var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var indice = 0
    private let targets = [6, 10, 15]

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            SfidaPratica(
                target: targets[indice],
                indice: indice,
                totale: targets.count,
                ultima: indice == targets.count - 1,
                onVittoria: avanza,
                onFine: completa
            )
            .id(indice)   // ricrea la sotto-vista (e il suo @StateObject) a ogni sfida
            .padding(24)
        }
        .preferredColorScheme(.dark)
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
    var onFine: () -> Void

    @StateObject private var session: PracticeSession
    @State private var vinta = false
    @State private var messaggio: String?

    init(target: Int, indice: Int, totale: Int, ultima: Bool,
         onVittoria: @escaping () -> Void, onFine: @escaping () -> Void) {
        self.target = target
        self.indice = indice
        self.totale = totale
        self.ultima = ultima
        self.onVittoria = onVittoria
        self.onFine = onFine
        let puzzle = PracticeGenerator.make(target: target, seed: UInt64(0xF11040 + indice))
        _session = StateObject(wrappedValue: PracticeSession(puzzle: puzzle))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Riscaldamento")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Salta") { onFine() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
            }

            Text("Sfida \(indice + 1) di \(totale)")
                .captionStyle()

            Text("Collega le caselle fino a fare esattamente \(target).")
                .font(.body)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)

            VStack(spacing: 2) {
                Text("Obiettivo").captionStyle()
                Text("\(target)")
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Theme.filoGradient)
                HStack(spacing: 4) {
                    Text("Somma").captionStyle()
                    Text("\(session.somma)")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(vinta ? Theme.ok : Theme.text)
                }
            }

            PracticeBoardView(session: session, onMove: gestisci)
                .frame(maxWidth: 360)

            Text(messaggio ?? " ")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(vinta ? Theme.ok : Theme.textMuted)
                .frame(minHeight: 22)

            if vinta {
                Button(ultima ? String(localized: "Inizia a giocare")
                              : String(localized: "Prossima sfida")) {
                    onVittoria()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func gestisci(_ mossa: Mossa) {
        switch mossa {
        case .vittoria:
            guard !vinta else { return }
            vinta = true
            session.blocca()
            messaggio = String(localized: "Perfetto!")
        case .spezzato, .annodato:
            messaggio = String(localized: "Ci sei quasi, riprova.")
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !vinta { session.ripulisci() }
            }
        default:
            break
        }
    }
}
