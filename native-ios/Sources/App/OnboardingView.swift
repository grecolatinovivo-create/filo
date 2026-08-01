import SwiftUI

/// "Come si gioca" — primo accesso e richiamabile con ? (README §13.2).
struct OnboardingView: View {
    @EnvironmentObject private var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Come si gioca")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.text)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.textMuted)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Chiudi")
                    }

                    Text("Collega le caselle con un filo continuo (niente diagonali) fino a fare ESATTAMENTE la Somma del Giorno.")
                        .font(.body)
                        .foregroundStyle(Theme.text)

                    DemoView()
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("🧵 Hai 3 fili.")
                        Text("⛔ Il filo non si riavvolge: ogni casella è per sempre.")
                        Text("💥 Superi la somma? Spezzato.")
                        Text("🪢 Resti senza uscite? Nodo.")
                        Text("⭐ Più caselle usi, più stelle: batti il Sarto!")
                    }
                    .font(.body)
                    .foregroundStyle(Theme.text)

                    Text("Un nuovo FILO ogni giorno, uguale per tutto il mondo.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textMuted)

                    Button("Gioca il FILO #\(vm.numero)") {
                        vm.segnaOnboarded()
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Demo animata 3×3 (dati fissi UX_SPEC §8 — MAI dal generatore).
private struct DemoView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var passo = -1   // -1 vuoto, 0..3 caselle, 4 = "14 ✓"

    private let valori = [2, 4, 1, 3, 5, 2, 1, 3, 4]
    private let percorso = [0, 3, 4, 1]
    private let somme = [2, 5, 10, 14]
    private let lato: CGFloat = 40
    private let gap: CGFloat = 4

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("Somma").captionStyle()
                Text("14")
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
            ZStack(alignment: .topLeading) {
                ForEach(0..<9, id: \.self) { i in
                    let acceso = passo >= 0 && percorso.prefix(min(passo, 3) + 1).contains(i)
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(acceso ? Theme.filo : Theme.surface2)
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(acceso ? Theme.filoScuro : Theme.border, lineWidth: 1)
                        Text("\(valori[i])")
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(acceso ? Theme.bg : Theme.text)
                    }
                    .frame(width: lato, height: lato)
                    .offset(x: CGFloat(i % 3) * (lato + gap),
                            y: CGFloat(i / 3) * (lato + gap))
                    .animation(.easeInOut(duration: 0.16), value: acceso)
                }
                if passo >= 0 {
                    let punti = percorso.prefix(min(passo, 3) + 1).map { centro($0) }
                    Circle().fill(Theme.filo).frame(width: 8, height: 8)
                        .position(punti[0])
                    if punti.count >= 2 {
                        PolylineShape(points: punti)
                            .stroke(Theme.filo,
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .frame(width: lato * 3 + gap * 2, height: lato * 3 + gap * 2)
            Text(contatore)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(passo >= 4 ? Theme.ok : Theme.text)
        }
        .task {
            if reduceMotion {
                passo = 4
                return
            }
            // loop ~5.2s (UX §8), cancellato alla chiusura della scheda
            while !Task.isCancelled {
                passo = -1
                try? await Task.sleep(nanoseconds: 600_000_000)
                for k in 0...3 {
                    if Task.isCancelled { return }
                    passo = k
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }
                passo = 4
                try? await Task.sleep(nanoseconds: 1_600_000_000)
            }
        }
    }

    private var contatore: String {
        if passo >= 4 { return "14 ✓" }
        if passo >= 0 { return "\(somme[passo])" }
        return "0"
    }

    private func centro(_ i: Int) -> CGPoint {
        CGPoint(x: CGFloat(i % 3) * (lato + gap) + lato / 2,
                y: CGFloat(i / 3) * (lato + gap) + lato / 2)
    }
}
