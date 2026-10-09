import SwiftUI
import FiloCore

/// Scheda STATISTICHE (REDESIGN_SPEC §6.5): titolo + chiudi, 4 StatCard 2×2,
/// percentuale di vittorie, vittorie per filo, record. Stato vuoto se non
/// si è ancora giocato. Nessuna condivisione qui (sta nel Risultato).
struct StatsView: View {
    @EnvironmentObject private var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss

    private var stats: Statistiche { vm.stats }

    /// "100%" localizzato, "—" se non si è ancora giocato.
    private var percentualeTesto: String {
        guard stats.giocate > 0 else { return "—" }
        let frazione = Double(stats.vinte) / Double(stats.giocate)
        return frazione.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        ZStack {
            FiloBackground()
            GeometryReader { geo in
                let margine = FiloMetrics.margin(forWidth: geo.size.width)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        if stats.giocate == 0 {
                            statoVuoto
                                .padding(.top, FiloMetrics.sectionGap)
                        } else {
                            riepilogo
                                .padding(.top, FiloMetrics.relatedGapLarge)
                            vittoriePerFilo
                                .padding(.top, FiloMetrics.sectionGapLarge)
                            Rectangle()
                                .fill(Theme.stroke)
                                .frame(height: 1)
                                .padding(.top, FiloMetrics.sectionGap)
                                .accessibilityHidden(true)
                            record
                                .padding(.top, FiloMetrics.sectionGap)
                        }
                    }
                    .padding(.horizontal, margine)
                    .padding(.top, 8)
                    .padding(.bottom, FiloMetrics.sectionGapLarge)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .presentationCornerRadius(FiloMetrics.sheetCorner)
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Statistiche")
                .filoFont(.screenTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            FiloIconButton(systemName: "xmark", label: "Chiudi") {
                dismiss()
            }
        }
        .frame(minHeight: FiloMetrics.headerHeight)
        .padding(.trailing, -10)   // l'icona 44×44 ha già il suo respiro interno
    }

    // MARK: Stato vuoto

    private var statoVuoto: some View {
        FiloCard(padding: FiloMetrics.cardPaddingLarge) {
            VStack(alignment: .leading, spacing: FiloMetrics.relatedGapLarge) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
                Text("Il tuo percorso inizia con il primo FILO.")
                    .filoFont(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    FiloHaptics.light()
                    dismiss()
                } label: {
                    Text("Gioca il FILO di oggi")
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .padding(.top, FiloMetrics.relatedGap)
            }
        }
    }

    // MARK: 2×2 StatCard + percentuale

    private var riepilogo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatCard(value: "\(stats.giocate)", label: "Sfide giocate")
                    StatCard(value: "\(stats.vinte)", label: "Vittorie")
                }
                GridRow {
                    StatCard(value: "\(vm.streakEffettiva)", label: "Serie attuale")
                    StatCard(value: "\(stats.maxStreak)", label: "Serie migliore")
                }
            }
            Text("Percentuale di vittorie: \(percentualeTesto)")
                .filoFont(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Vittorie per filo

    private var vittoriePerFilo: some View {
        let dist = stats.distFili
        let massimo = dist.max() ?? 0
        return VStack(alignment: .leading, spacing: FiloMetrics.relatedGap) {
            Text("Vittorie per filo")
                .filoFont(.cardTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    let valore = i < dist.count ? dist[i] : 0
                    barra(etichetta: nomeFilo(i), valore: valore, massimo: massimo)
                }
            }
        }
    }

    private func nomeFilo(_ i: Int) -> LocalizedStringKey {
        switch i {
        case 0: return "Primo filo"
        case 1: return "Secondo filo"
        default: return "Terzo filo"
        }
    }

    private func barra(etichetta: LocalizedStringKey, valore: Int, massimo: Int) -> some View {
        let principale = massimo > 0 && valore == massimo
        let frazione = massimo > 0 ? CGFloat(valore) / CGFloat(massimo) : 0
        return HStack(spacing: 12) {
            Text(etichetta)
                .filoFont(.body)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 112, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface)
                    if valore > 0 {
                        Capsule()
                            .fill(principale ? Theme.gold.opacity(0.85) : Theme.stroke)
                            .frame(width: max(6, geo.size.width * frazione))
                    }
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            Text(valore, format: .number)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .frame(minWidth: 28, alignment: .trailing)
        }
        .frame(height: 32)
        .accessibilityElement(children: .combine)
    }

    // MARK: Record

    private var record: some View {
        VStack(alignment: .leading, spacing: FiloMetrics.relatedGap) {
            Text("I tuoi record")
                .filoFont(.cardTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            rigaRecord("Più caselle in un FILO", valore: stats.recordCaselle)
            rigaRecord("Volte sopra il Sarto", valore: stats.sartoBattuto)
        }
    }

    private func rigaRecord(_ etichetta: LocalizedStringKey, valore: Int) -> some View {
        HStack(spacing: 12) {
            Text(etichetta)
                .filoFont(.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(valore, format: .number)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }
}
