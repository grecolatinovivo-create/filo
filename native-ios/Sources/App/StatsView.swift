import SwiftUI
import FiloCore

/// Modal STATISTICHE (README §13.4).
struct StatsView: View {
    @EnvironmentObject private var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss

    private var pct: Int {
        vm.stats.giocate > 0
            ? Int((Double(vm.stats.vinte) / Double(vm.stats.giocate) * 100).rounded())
            : 0
    }

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Statistiche")
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

                    HStack(alignment: .top) {
                        statBox("\(vm.stats.giocate)", "giocate")
                        statBox("\(pct)%", "vittorie")
                        statBox("🔥 \(vm.streakEffettiva)", "serie")
                        statBox("\(vm.stats.maxStreak)", "max")
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Vittorie per filo usato").captionStyle()
                        ForEach(0..<3, id: \.self) { i in
                            barRow(filo: i + 1, valore: vm.stats.distFili[i])
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Record caselle: ").foregroundStyle(Theme.text)
                            + Text("\(vm.stats.recordCaselle)/25").bold().foregroundStyle(Theme.text)
                        Text("Sarto battuto: ").foregroundStyle(Theme.text)
                            + Text("\(vm.stats.sartoBattuto) volte").bold().foregroundStyle(Theme.text)
                            + Text(" 🥇")
                    }
                    .font(.subheadline)

                    if vm.engine.gameOver {
                        ShareLink(item: vm.shareText) {
                            Text("Condividi il risultato 🧵")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func statBox(_ valore: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(valore)
                .font(.system(.title2, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .minimumScaleFactor(0.7)
            Text(label).captionStyle()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func barRow(filo: Int, valore: Int) -> some View {
        let massimo = max(1, vm.stats.distFili.max() ?? 1)
        return HStack(spacing: 8) {
            Text("\(filo)° filo")
                .font(.subheadline)
                .foregroundStyle(Theme.textMuted)
                .frame(width: 56, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface2)
                    if valore > 0 {
                        Capsule()
                            .fill(Theme.filo)
                            .frame(width: max(4, geo.size.width * CGFloat(valore) / CGFloat(massimo)))
                    }
                }
            }
            .frame(height: 12)
            Text("\(valore)")
                .font(.system(.subheadline, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(filo)° filo: \(valore) vittorie")
    }
}
