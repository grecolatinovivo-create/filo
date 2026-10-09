import SwiftUI

/// "Come si gioca" — primo accesso e richiamabile con ? (REDESIGN_SPEC §6.8).
/// Tre passi, demo 3×3, nota finale e CTA fissata in basso.
/// Flusso invariato: la CTA segna l'onboarding come visto e chiude la
/// scheda; la catena del primo avvio (→ Riscaldamento) parte dall'onDismiss
/// del presentatore (`vm.onboardingChiuso()`).
struct OnboardingView: View {
    @EnvironmentObject private var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ComeSiGiocaContenuto(onChiudi: { dismiss() }, cta: {
            Button("Gioca il FILO #\(vm.numero)") {
                FiloHaptics.light()
                vm.segnaOnboarded()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: true))
        })
    }
}

/// Contenuto della guida, riusabile senza `GameViewModel` (es. il "?" della
/// Salita). `cta` (opzionale) resta fissata in basso con `safeAreaInset`.
struct ComeSiGiocaContenuto<CTA: View>: View {
    var nota: LocalizedStringKey?
    let onChiudi: () -> Void
    private let cta: CTA?

    init(nota: LocalizedStringKey? = nil,
         onChiudi: @escaping () -> Void,
         @ViewBuilder cta: () -> CTA) {
        self.nota = nota
        self.onChiudi = onChiudi
        self.cta = cta()
    }

    var body: some View {
        GeometryReader { geo in
            let margine = FiloMetrics.margin(forWidth: geo.size.width)
            ScrollView {
                VStack(alignment: .leading, spacing: FiloMetrics.sectionGap) {
                    header

                    // ROUND2 §13: 24 pt tra i passi numerati.
                    VStack(alignment: .leading, spacing: FiloMetrics.sectionGap) {
                        PassoGuida(numero: 1,
                                   titolo: "Collega le caselle",
                                   paragrafi: [LocalizedStringKey("Traccia un filo in orizzontale o in verticale. Mai in diagonale.")])
                        PassoGuida(numero: 2,
                                   titolo: "Raggiungi la somma esatta",
                                   paragrafi: [LocalizedStringKey("Ogni casella aggiunge il suo numero. Devi raggiungere esattamente l'obiettivo.")]) {
                            esempio
                        }
                        // Passo 3 in tre paragrafi: caselle già usate / tre fili
                        // e fallimenti / stelle e Sarto.
                        PassoGuida(numero: 3,
                                   titolo: "Ogni casella conta",
                                   paragrafi: [
                                       LocalizedStringKey("Non puoi ripassare su una casella già usata."),
                                       LocalizedStringKey("Hai tre fili: se superi la somma il filo si spezza, se resti senza uscite si annoda."),
                                       LocalizedStringKey("Più caselle usi, più stelle ottieni: supera il Sarto per la medaglia.")
                                   ])
                    }

                    DemoView()
                        .frame(maxWidth: .infinity)

                    if let nota {
                        Text(nota)
                            .filoFont(.body)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Un nuovo FILO ogni giorno, uguale per tutti.")
                        .filoFont(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, margine)
                .padding(.top, FiloMetrics.relatedGap)
                .padding(.bottom, FiloMetrics.sectionGap)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let cta {
                    cta
                        .padding(.horizontal, margine)
                        .padding(.top, 12)
                        .padding(.bottom, FiloMetrics.relatedGap)
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity)
                        .background {
                            Theme.bg.opacity(0.96)
                                .ignoresSafeArea(edges: .bottom)
                                .accessibilityHidden(true)
                        }
                }
            }
        }
        .background { FiloBackground() }
        .presentationCornerRadius(FiloMetrics.sheetCorner)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: FiloMetrics.relatedGap) {
            Text("Come si gioca")
                .filoFont(.screenTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            FiloIconButton(systemName: "xmark", label: "Chiudi") { onChiudi() }
                .padding(.trailing, -10)   // allinea il glifo al margine
        }
        .frame(minHeight: FiloMetrics.headerHeight)
        .padding(.top, FiloMetrics.relatedGap)
    }

    /// "2 + 3 + 5 + 4 = 14": lo stesso percorso della demo.
    private var esempio: some View {
        Text(verbatim: "2 + 3 + 5 + 4 = 14")
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.gold)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(Capsule().fill(Theme.surfaceRaised))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            .padding(.top, 4)
    }
}

extension ComeSiGiocaContenuto where CTA == EmptyView {
    /// Guida senza CTA (solo chiusura).
    init(nota: LocalizedStringKey? = nil, onChiudi: @escaping () -> Void) {
        self.nota = nota
        self.onChiudi = onChiudi
        self.cta = nil
    }
}

/// Un passo della guida: pallino col numero, titolo 18 semibold, uno o più
/// paragrafi SF Pro 15 secondari (interlinea ≈ 21 pt, 12 pt tra paragrafi),
/// contenuto extra opzionale. Un solo elemento VoiceOver.
private struct PassoGuida<Extra: View>: View {
    let numero: Int
    let titolo: LocalizedStringKey
    let paragrafi: [LocalizedStringKey]
    private let extra: Extra

    init(numero: Int, titolo: LocalizedStringKey, paragrafi: [LocalizedStringKey],
         @ViewBuilder extra: () -> Extra) {
        self.numero = numero
        self.titolo = titolo
        self.paragrafi = paragrafi
        self.extra = extra()
    }

    var body: some View {
        HStack(alignment: .top, spacing: FiloMetrics.relatedGapLarge) {
            Text(verbatim: "\(numero)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.gold)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.surfaceRaised))
                .overlay(Circle().strokeBorder(Theme.gold.opacity(0.45), lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(titolo)
                    .filoFont(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(paragrafi.indices, id: \.self) { i in
                        Text(paragrafi[i])
                            .filoFont(.body)
                            .lineSpacing(3)   // 15 pt → interlinea ≈ 21 pt
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                extra
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

extension PassoGuida where Extra == EmptyView {
    init(numero: Int, titolo: LocalizedStringKey, paragrafi: [LocalizedStringKey]) {
        self.numero = numero
        self.titolo = titolo
        self.paragrafi = paragrafi
        self.extra = EmptyView()
    }
}

/// Demo 3×3 (≈ 192 pt, dati fissi — MAI dal generatore) con il look delle
/// board: tessere piatte, filo di seta V3 (`FiloSeta`: asole attorno ai
/// numeri, punti terminali) e numeri senza alone.
/// Il filo prende una casella alla volta (presa 0,24 s, una ogni 0,42 s),
/// poi "14 = 14" in success. Si gioca UNA volta; "Rivedi esempio" la ripete.
/// Riduci Movimento: stato finale, senza animazione.
private struct DemoView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Caselle accese (0…4).
    @State private var passo = 0
    @State private var completato = false
    @State private var giro = 0

    private let valori = [2, 4, 1, 3, 5, 2, 1, 3, 4]
    private let percorso = [0, 3, 4, 1]
    private let somme = [2, 5, 10, 14]
    private let larghezza: CGFloat = 192
    private let gap: CGFloat = 8
    private var lato: CGFloat { (larghezza - gap * 2) / 3 }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: FiloMetrics.relatedGap) {
                Text("Obiettivo").eyebrowStyle()
                Text(verbatim: "14")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.gold)
            }
            .accessibilityHidden(true)

            griglia
                .frame(width: larghezza, height: larghezza, alignment: .topLeading)
                .accessibilityHidden(true)

            Text(verbatim: contatore)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(completato ? Theme.success : Theme.textPrimary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : FiloMotion.numeric, value: contatore)
                .accessibilityHidden(true)

            if !reduceMotion {
                Button {
                    giro += 1
                } label: {
                    Label("Rivedi esempio", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(TertiaryButtonStyle())
                .opacity(completato ? 1 : 0)
                .allowsHitTesting(completato)
                .accessibilityHidden(!completato)
                .animation(FiloMotion.screen, value: completato)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, FiloMetrics.cardPadding)
        .frame(maxWidth: .infinity)
        .background(FiloCardBackground())
        .task(id: giro) { await anima() }
    }

    private var griglia: some View {
        ZStack(alignment: .topLeading) {
            // 1. tessere
            ForEach(0..<9, id: \.self) { i in
                let o = origine(i)
                TesseraArte(accesa: acceso(i), lato: lato)
                    .frame(width: lato, height: lato)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: acceso(i))
                    .offset(x: o.x, y: o.y)
            }
            // 2. filo di seta (asole + punti terminali), anima da sé ogni presa
            FiloSeta(centri: percorso.prefix(passo).map(centro), lato: lato)
            // 3. numeri SOPRA il filo
            ForEach(0..<9, id: \.self) { i in
                let o = origine(i)
                NumeroCella(valore: valori[i], accesa: acceso(i))
                    .frame(width: lato, height: lato)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: acceso(i))
                    .offset(x: o.x, y: o.y)
            }
        }
    }

    private var contatore: String {
        if completato { return "14 = 14" }
        if passo >= 1 { return "\(somme[min(passo, somme.count) - 1])" }
        return "0"
    }

    private func acceso(_ i: Int) -> Bool {
        percorso.prefix(passo).contains(i)
    }

    private func origine(_ i: Int) -> CGPoint {
        CGPoint(x: CGFloat(i % 3) * (lato + gap), y: CGFloat(i / 3) * (lato + gap))
    }

    private func centro(_ i: Int) -> CGPoint {
        CGPoint(x: CGFloat(i % 3) * (lato + gap) + lato / 2,
                y: CGFloat(i / 3) * (lato + gap) + lato / 2)
    }

    @MainActor
    private func mostraFinale() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            passo = percorso.count
            completato = true
        }
    }

    /// Una sola esecuzione (annullata alla chiusura della scheda o da un
    /// nuovo "Rivedi esempio").
    @MainActor
    private func anima() async {
        if reduceMotion {
            mostraFinale()
            return
        }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            passo = 0
            completato = false
        }
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard !Task.isCancelled else { return }
        passo = 1
        try? await Task.sleep(nanoseconds: 350_000_000)
        for k in 2...percorso.count {
            guard !Task.isCancelled else { return }
            passo = k
            try? await Task.sleep(nanoseconds: 420_000_000)
        }
        guard !Task.isCancelled else { return }
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard !Task.isCancelled else { return }
        completato = true
    }
}
