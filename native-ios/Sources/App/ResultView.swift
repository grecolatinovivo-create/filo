import SwiftUI
import FiloCore

/// Scheda RISULTATO (REDESIGN_SPEC §6.4): header "FILO #N" + chiudi, titolo
/// per esito, stelle in stagger con haptics, caselle/Sarto/tentativo,
/// mini-griglia, CTA condividi + statistiche, countdown al prossimo FILO.
struct ResultView: View {
    @EnvironmentObject private var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Fasi della sequenza d'ingresso (§6.4 / §8).
    @State private var titoloVisibile = false
    @State private var stelleVisibili = 0
    @State private var medagliaVisibile = false
    @State private var ctaVisibili = false

    private var vinta: Bool { vm.engine.stato == .vinta }
    private var L: Int { vm.puzzle.lSarto }

    private var filoVincente: (filo: FiloConcluso, indice: Int)? {
        for (i, f) in vm.engine.fili.enumerated() where f.esito == .vinto {
            return (f, i + 1)
        }
        return nil
    }

    /// Caselle del filo vincente (0 se persa).
    private var caselle: Int {
        filoVincente?.filo.caselle ?? (vm.engine.percorsoVincente?.count ?? 0)
    }

    private var sartoBattuto: Bool {
        vinta && (vm.sartoBattutoOggi || caselle > L)
    }

    private var stelle: Int {
        guard vinta else { return 0 }
        return vm.stelleOggi > 0 ? vm.stelleOggi
            : Punteggio.stelle(caselle: caselle, lSarto: L).stelle
    }

    /// ROUND2 §8: ≈ 720 pt sui dispositivi da 956 pt (limitata allo spazio
    /// disponibile); con Dynamic Type molto grande la scheda è `.large` e il
    /// contenuto scorre.
    private var detents: Set<PresentationDetent> {
        dynamicTypeSize >= .xxLarge ? [.large] : [.custom(AltezzaSchedaRisultato.self)]
    }

    var body: some View {
        GeometryReader { geo in
            let margine = FiloMetrics.margin(forWidth: geo.size.width)
            VStack(spacing: 0) {
                header
                    .padding(.leading, margine)
                    .padding(.trailing, max(0, margine - 10))

                GeometryReader { area in
                    ScrollView {
                        contenuto
                            .padding(.horizontal, margine)
                            .padding(.bottom, FiloMetrics.sectionGap)   // countdown a 24 pt dal fondo
                            .frame(maxWidth: 480)
                            .frame(maxWidth: .infinity, minHeight: area.size.height, alignment: .top)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .padding(.top, 8)
        }
        .background { Theme.surface.ignoresSafeArea() }
        .presentationDetents(detents)
        .presentationCornerRadius(FiloMetrics.sheetCorner)
        .presentationBackground(Theme.surface)
        .preferredColorScheme(.dark)
        .task { await sequenzaIngresso() }
    }

    // MARK: Header (48 pt): "FILO #N" a sinistra, chiudi a destra

    private var header: some View {
        HStack(spacing: 8) {
            Text("FILO #\(vm.numero)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            FiloIconButton(systemName: "xmark", label: "Chiudi") {
                dismiss()
            }
        }
        .frame(height: FiloMetrics.headerHeight)
    }

    // MARK: Contenuto

    private var contenuto: some View {
        VStack(spacing: 0) {
            // Titolo per esito + (sconfitta) dettaglio
            VStack(spacing: FiloMetrics.relatedGap) {
                Text(titolo)
                    .filoFont(.screenTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !vinta {
                    Text("I tre fili sono terminati. Domani ti aspetta una nuova sfida.")
                        .filoFont(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, FiloMetrics.relatedGap)
            .opacity(titoloVisibile ? 1 : 0)

            // Stelle (3 × 32, gap 12; non guadagnate = contorno)
            StarRow(earned: stelle, visible: stelleVisibili, size: 32, spacing: 12)
                .padding(.top, FiloMetrics.relatedGapLarge)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(etichettaStelleAccessibile)
                .accessibilityHidden(!vinta)

            // Medaglia solo se il Sarto è battuto
            if sartoBattuto {
                HStack(spacing: FiloMetrics.relatedGap) {
                    MedalIcon(size: 24)
                    Text("Medaglia del Sarto")
                        .filoFont(.caption)
                        .foregroundStyle(Theme.gold)
                }
                .padding(.top, FiloMetrics.relatedGapLarge)
                .opacity(medagliaVisibile ? 1 : 0)
                .scaleEffect(medagliaVisibile || reduceMotion ? 1 : 0.9)
                .accessibilityElement(children: .combine)
            }

            // Caselle · Sarto · tentativo
            VStack(spacing: 4) {
                if vinta {
                    Text("\(caselle) caselle")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .tracking(-0.5)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
                Text("Il Sarto: \(L) caselle")
                    .filoFont(.body)
                    .foregroundStyle(Theme.textSecondary)
                if let fv = filoVincente {
                    Text(rigaTentativo(fv.indice))
                        .filoFont(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                // Tempo attivo (statistica personale, solo a vittoria; non
                // entra nel testo di condivisione).
                if vinta, let secondi = vm.tempoRisolto {
                    let durataTesto = FiloDurata.testo(secondi: secondi)
                    Text("Risolto in \(durataTesto)")
                        .filoFont(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.top, FiloMetrics.relatedGapLarge)
            .opacity(titoloVisibile ? 1 : 0)
            .accessibilityElement(children: .combine)

            // Mosaico 156 pt, solo tessere
            MiniGridView(lato: 156)
                .padding(.top, FiloMetrics.sectionGap)
                .opacity(titoloVisibile ? 1 : 0)
                .accessibilityHidden(true)

            // Spazio flessibile: le CTA restano in fondo alla scheda.
            Spacer(minLength: FiloMetrics.sectionGap)

            // CTA (56) + statistiche (44) + countdown
            VStack(spacing: FiloMetrics.relatedGap) {
                ShareLink(item: vm.shareText) {
                    Text("Condividi il risultato")
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))

                Button {
                    vm.scheda = .statistiche
                } label: {
                    Text("Vedi le statistiche")
                }
                .buttonStyle(TertiaryButtonStyle(color: Theme.textPrimary))
                .frame(minHeight: 44)

                // Countdown al prossimo FILO (mezzanotte locale), aggiornato dal vivo
                TimelineView(.everyMinute) { ctx in
                    Text(Self.testoProssimoFilo(da: ctx.date))
                        .filoFont(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 4)
            }
            .opacity(ctaVisibili ? 1 : 0)
            .offset(y: ctaVisibili || reduceMotion ? 0 : 8)
        }
    }

    // MARK: Sequenza d'ingresso (§6.4, tempi relativi alla comparsa della scheda)
    // Spec (dalla mossa vincente): scheda +0.35, titolo +0.65, stelle
    // +0.80/+0.98/+1.16, medaglia +1.40, CTA +1.60 → qui: 0.30, 0.45/0.63/0.81,
    // 1.05, 1.25 dopo onAppear. Riduci Movimento: un solo fade 0.15 s.

    @MainActor
    private func sequenzaIngresso() async {
        guard !titoloVisibile else { return }
        FiloHaptics.prepare()
        if reduceMotion {
            withAnimation(FiloMotion.reduced) {
                titoloVisibile = true
                stelleVisibili = 3
                medagliaVisibile = true
                ctaVisibili = true
            }
            if vinta { FiloHaptics.light() }
            return
        }
        guard await attendi(0.30) else { return mostraTutto() }
        withAnimation(.easeOut(duration: 0.20)) { titoloVisibile = true }
        if !vinta {
            // Sconfitta: stelle tutte a contorno, nessun haptic.
            stelleVisibili = 3
        } else {
            let tempi: [Double] = [0.15, 0.18, 0.18]
            for i in 0..<3 {
                guard await attendi(tempi[i]) else { return mostraTutto() }
                stelleVisibili = i + 1           // StarRow anima con FiloMotion.star
                if i < stelle {
                    if i == 2 { FiloHaptics.medium() } else { FiloHaptics.light() }
                }
            }
            if sartoBattuto {
                guard await attendi(0.24) else { return mostraTutto() }
                withAnimation(FiloMotion.medal) { medagliaVisibile = true }
                FiloHaptics.light()
            }
        }
        let giaTrascorso: Double = vinta ? (sartoBattuto ? 1.05 : 0.81) : 0.30
        guard await attendi(max(0.05, 1.25 - giaTrascorso)) else { return mostraTutto() }
        withAnimation(FiloMotion.screen) { ctaVisibili = true }
    }

    /// Attende `secondi`; false se il task è stato annullato.
    private func attendi(_ secondi: Double) async -> Bool {
        try? await Task.sleep(nanoseconds: UInt64(secondi * 1_000_000_000))
        return !Task.isCancelled
    }

    @MainActor
    private func mostraTutto() {
        titoloVisibile = true
        stelleVisibili = 3
        medagliaVisibile = true
        ctaVisibili = true
    }

    // MARK: Testi (§6.4 / §7)

    private var titolo: LocalizedStringKey {
        guard vinta else { return "Per oggi il filo finisce qui." }
        if sartoBattuto { return "Hai superato il Sarto" }
        if caselle == L { return "Hai eguagliato il Sarto" }
        return "Filo completato"
    }

    private func rigaTentativo(_ indice: Int) -> LocalizedStringKey {
        switch indice {
        case 1: return "Al primo filo"
        case 2: return "Al secondo filo"
        default: return "Al terzo filo"
        }
    }

    private var etichettaStelleAccessibile: String {
        let base = stelle == 3 ? String(localized: "Tre stelle")
                 : stelle == 2 ? String(localized: "Due stelle")
                 : String(localized: "Una stella")
        return sartoBattuto ? String(localized: "\(base), hai battuto il Sarto") : base
    }

    // MARK: Countdown (mezzanotte locale)

    /// Secondi che mancano alla prossima mezzanotte locale.
    static func secondiAMezzanotte(da now: Date) -> Int {
        let cal = Calendar.current
        let domani = cal.date(byAdding: .day, value: 1, to: now) ?? now
        let mezzanotte = cal.startOfDay(for: domani)
        return max(0, Int(mezzanotte.timeIntervalSince(now)))
    }

    /// Formato storico "HH:MM:SS" (firma invariata: usata da MenuView).
    static func countdown(da now: Date) -> String {
        let s = secondiAMezzanotte(da: now)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// Ore e minuti al prossimo FILO (minuti arrotondati per eccesso, così
    /// "0 h 0 min" non compare mai prima di mezzanotte).
    static func oreMinutiAlProssimoFilo(da now: Date) -> (ore: Int, minuti: Int) {
        let minutiTotali = (secondiAMezzanotte(da: now) + 59) / 60
        return (minutiTotali / 60, minutiTotali % 60)
    }

    /// "Prossimo FILO tra %lld h %lld min" localizzato.
    static func testoProssimoFilo(da now: Date) -> String {
        let t = oreMinutiAlProssimoFilo(da: now)
        return String(localized: "Prossimo FILO tra \(t.ore) h \(t.minuti) min")
    }
}

/// Altezza della scheda Risultato: 720 pt sui dispositivi alti (956 pt),
/// ≈ 82 % dello spazio sui più bassi, mai sotto 620 pt né oltre il massimo.
private struct AltezzaSchedaRisultato: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        let massimo = context.maxDetentValue
        return min(massimo, max(620, min(720, massimo * 0.82)))
    }
}

/// Mini-griglia 5×5 (mosaico, 156 pt di default, gap 3): solo tessere, niente numeri né ordine.
/// Vittoria: tessere del mio filo in oro. Sconfitta: tessere del percorso del
/// Sarto nel colore Sarto (pergamena tenue).
struct MiniGridView: View {
    @EnvironmentObject private var vm: GameViewModel
    var lato: CGFloat = 156

    var body: some View {
        let gap: CGFloat = 3
        let side = (lato - gap * 4) / 5
        let raggio = max(4, min(8, side * 0.2))
        let vinta = vm.engine.stato == .vinta
        let mio = Set(vm.engine.percorsoVincente ?? [])
        let sarto = Set(vm.puzzle.percorsoSarto)
        VStack(spacing: gap) {
            ForEach(0..<5, id: \.self) { r in
                HStack(spacing: gap) {
                    ForEach(0..<5, id: \.self) { c in
                        let idx = r * 5 + c
                        tessera(oro: vinta && mio.contains(idx),
                                sarto: !vinta && sarto.contains(idx),
                                raggio: raggio)
                            .frame(width: side, height: side)
                    }
                }
            }
        }
        .frame(width: lato, height: lato)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tessera(oro: Bool, sarto: Bool, raggio: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: raggio, style: .continuous)
        if oro {
            shape.fill(Theme.gold.opacity(0.85))
        } else if sarto {
            shape.fill(Theme.sarto.opacity(0.28))
                .overlay(shape.strokeBorder(Theme.sarto.opacity(0.55), lineWidth: 1))
        } else {
            shape.fill(Theme.cell)
                .overlay(shape.strokeBorder(Theme.stroke.opacity(0.6), lineWidth: 1))
        }
    }
}
