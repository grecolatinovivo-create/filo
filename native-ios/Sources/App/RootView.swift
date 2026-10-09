import SwiftUI
import Combine
import FiloCore

/// PARTITA (REDESIGN_SPEC §6.3): header (indietro "Menu", "FILO #N", "?"),
/// HUD, griglia, "Taglia il filo"; banner nuovo giorno, toast e dialog di
/// conferma. Presentata dal MenuView in fullScreenCover; `onBack` torna al
/// menu con il crossfade (fallback: dismiss standard).
struct RootView: View {
    @EnvironmentObject private var vm: GameViewModel
    @EnvironmentObject private var theme: ThemeManager   // ridisegna al cambio tema
    @EnvironmentObject private var store: Store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Ritorno al menu orchestrato dal presentatore (crossfade + dismiss).
    var onBack: (() -> Void)? = nil

    private let timerGiorno = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// Altezza misurata dell'HUD: serve a dimensionare la griglia anche in
    /// altezza (schermi piccoli). Stima iniziale per il primo frame.
    @State private var altezzaHUD: CGFloat = GameScreenMetrics.stimaHUD

    var body: some View {
        GeometryReader { esterno in
            let margin = FiloMetrics.margin(forWidth: esterno.size.width)
            ZStack(alignment: .top) {
                FiloBackground()

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, max(4, margin - 12))

                    // Banner nel flusso (non sopra l'HUD): il blocco
                    // griglia + bottone si ricentra nello spazio che resta.
                    if vm.showNuovoGiornoBanner {
                        bannerNuovoGiorno
                            .padding(.horizontal, margin)
                            .padding(.top, 4)
                            .padding(.bottom, FiloMetrics.relatedGap)
                            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }

                    // Composizione (ROUND2 §6): HUD in alto, blocco griglia +
                    // "Taglia il filo" centrato nello spazio sotto l'HUD.
                    // Schermi piccoli / Dynamic Type grande: ScrollView.
                    GeometryReader { area in
                        let larghezza = GameScreenMetrics.larghezzaGriglia(contenitore: area.size.width,
                                                                           margine: margin)
                        let lato = GameScreenMetrics.latoGriglia(larghezza: larghezza,
                                                                 altezzaDisponibile: area.size.height,
                                                                 altezzaHUD: altezzaHUD)
                        ScrollView {
                            GameScreenLayout(altezzaMinima: area.size.height,
                                             compensazioneBasso: esterno.safeAreaInsets.bottom) {
                                HUDView()
                                    .frame(maxWidth: larghezza)
                                    .padding(.top, FiloMetrics.relatedGap)
                                    .misuraAltezza($altezzaHUD)
                                VStack(spacing: GameScreenMetrics.spazioGrigliaBottone) {
                                    BoardView()
                                        .frame(width: lato, height: lato)
                                    tagliaButton
                                        .frame(maxWidth: lato)
                                    AdSlot(isPro: store.isPro)
                                }
                            }
                            .padding(.horizontal, margin)
                            .frame(maxWidth: .infinity)
                        }
                        .scrollBounceBehavior(.basedOnSize)   // niente rimbalzo se il contenuto sta a schermo
                    }
                }
                .animation(reduceMotion ? FiloMotion.reduced : FiloMotion.screen, value: vm.showNuovoGiornoBanner)
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                if let toast = vm.toast { ToastView(testo: toast) }
            }
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? FiloMotion.reduced : FiloMotion.screen, value: vm.toast)
            .allowsHitTesting(false)   // il toast non blocca i tocchi sulla griglia
        }
        .sheet(item: $vm.scheda, onDismiss: { vm.onboardingChiuso() }) { scheda in
            switch scheda {
            case .comeSiGioca: OnboardingView()
            case .onboardingProgressivo: ProgressiveOnboardingView()
            case .risultato: ResultView()
            case .statistiche: StatsView()
            case .profilo: ProfileView()
            case .archivio: ArchiveView()
            }
        }
        .confirmationDialog("Tagliare questo filo?",
                            isPresented: $vm.showStrappoDialog,
                            titleVisibility: .visible) {
            Button("Taglia il filo", role: .destructive) { vm.confermaStrappo() }
            Button("Continua a giocare", role: .cancel) {}
        } message: {
            Text(vm.testoDialogStrappo)
        }
        .onChange(of: scenePhase) { _, fase in
            if fase == .active { vm.checkNuovoGiorno() }
        }
        .onReceive(timerGiorno) { _ in vm.checkNuovoGiorno() }
        .onAppear { vm.onDailyAperto() }
        .preferredColorScheme(.dark)
    }

    // MARK: Header (48 pt)

    private var header: some View {
        ZStack {
            Text("FILO #\(vm.numero)")
                .filoFont(.headerTitle)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 56)

            HStack(spacing: 0) {
                FiloIconButton(systemName: "chevron.left", label: "Menu") {
                    if let onBack { onBack() } else { dismiss() }
                }
                Spacer(minLength: 0)
                FiloIconButton(systemName: "questionmark.circle", label: "Come si gioca") {
                    vm.scheda = .comeSiGioca
                }
            }
        }
        .frame(height: FiloMetrics.headerHeight)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    // MARK: Azioni

    private var tagliaButton: some View {
        Button("Taglia il filo") { vm.richiediStrappo() }
            .buttonStyle(DestructiveButtonStyle(enabled: vm.strappaDisponibile, fullWidth: true))
            .disabled(!vm.strappaDisponibile)
    }

    // MARK: Banner nuovo giorno (RF10)

    private var bannerNuovoGiorno: some View {
        HStack(spacing: 8) {
            Text("C'è un nuovo FILO.")
                .filoFont(.body)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                FiloHaptics.light()
                vm.giocaNuovoGiorno()
            } label: {
                Text("Gioca")
                    .filoFont(.button)
                    .foregroundStyle(Theme.onGold)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(Theme.gold))
                    .frame(minHeight: FiloMetrics.minTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            FiloIconButton(systemName: "xmark", label: "Nascondi avviso") {
                vm.nascondiBanner()
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: 480, minHeight: FiloMetrics.headerHeight)
        .background(FiloCardBackground(radius: 16, floating: true, fill: Theme.surfaceRaised))
    }
}

/// HUD (spec §6.3), centrato. Ordine d'accessibilità INVARIATO per i test:
/// obiettivo ("Somma del giorno: T") → Sarto ("Il Sarto ha usato…") →
/// somma attuale / caselle → "Fili rimasti: n di 3" (sempre l'ultimo).
/// Riga inferiore = `GameHUDMetricRow` (stessa struttura della Salita):
/// "Somma attuale" a sinistra; a destra "10 caselle" e, 8 pt sotto,
/// l'indicatore dei fili rimasti allineato a destra.
struct HUDView: View {
    @EnvironmentObject private var vm: GameViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Text("Obiettivo")
                .eyebrowStyle()
            Text(verbatim: "\(vm.puzzle.T)")
                .filoFont(.target)
                .monospacedDigit()
                .foregroundStyle(Theme.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel(Text("Somma del giorno: \(vm.puzzle.T)"))
            Text("Sarto: \(vm.puzzle.lSarto) caselle")
                .filoFont(.caption)
                .foregroundStyle(Theme.textMuted)
                .accessibilityLabel(Text("Il Sarto ha usato \(vm.puzzle.lSarto) caselle. Minimo teorico: \(vm.engine.caselleMinime)"))

            GameHUDMetricRow {
                GameHUDMetric(somma: vm.engine.somma,
                              totale: vm.puzzle.T,
                              etichetta: Text("Somma attuale: \(vm.engine.somma) su \(vm.puzzle.T)"))
            } trailing: {
                VStack(alignment: .trailing, spacing: FiloMetrics.relatedGap) {
                    Text("\(vm.engine.filo.count) caselle")
                        .filoFont(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textMuted)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : FiloMotion.numeric, value: vm.engine.filo.count)
                    ThreadsLeftIndicator(outcomes: vm.engine.fili.map(\.esito),
                                         remaining: vm.engine.filiRimasti)
                }
            }
            .padding(.top, FiloMetrics.relatedGapLarge)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Componenti condivisi Partita / Salita (ROUND2 §6, §9)

/// Metrica "Somma attuale" dell'HUD, identica in Partita e Salita:
/// etichetta SF Pro 13 (textSecondary), valore SF Rounded 30 semibold
/// (textPrimary, transizione numerica), totale "/25" 15 (textTertiary).
/// Un solo elemento d'accessibilità con l'etichetta passata dal chiamante.
struct GameHUDMetric: View {
    let somma: Int
    let totale: Int
    var coloreValore: Color = Theme.textPrimary
    let etichetta: Text
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(somma: Int, totale: Int, coloreValore: Color = Theme.textPrimary, etichetta: Text) {
        self.somma = somma
        self.totale = totale
        self.coloreValore = coloreValore
        self.etichetta = etichetta
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Somma attuale")
                .fontWeight(.regular)
                .filoFont(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: "\(somma)")
                    .filoFont(.currentSum)
                    .monospacedDigit()
                    .foregroundStyle(coloreValore)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : FiloMotion.numeric, value: somma)
                Text(verbatim: "/\(totale)")
                    .filoFont(.body)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etichetta)
    }
}

/// Riga inferiore dell'HUD: metrica a sinistra, contenuto a destra
/// (caselle + fili nella Partita, vite nella Salita) allineato all'ultima
/// linea di base della metrica. L'ordine d'accessibilità resta
/// sinistra → destra.
struct GameHUDMetricRow<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: FiloMetrics.relatedGapLarge) {
            leading
            Spacer(minLength: 0)
            trailing
        }
        .frame(maxWidth: .infinity)
    }
}

/// Misure condivise delle schermate di gioco (Partita, Salita).
enum GameScreenMetrics {
    /// Larghezza massima della griglia (440 pt → margini 24, tessere 72).
    static let grigliaMassima: CGFloat = 392
    /// Lato minimo della griglia: sotto questo valore si scorre.
    static let grigliaMinima: CGFloat = 264
    /// Griglia ↔ bottone.
    static let spazioGrigliaBottone: CGFloat = 24
    /// HUD ↔ blocco griglia (minimo).
    static let spazioHUD: CGFloat = 24
    /// Margine minimo sotto il bottone.
    static let spazioBasso: CGFloat = 16
    /// Altezza del bottone sotto la griglia (secondario/distruttivo).
    static let altezzaBottone: CGFloat = FiloMetrics.secondaryHeight
    /// Stima dell'HUD prima della prima misura.
    static let stimaHUD: CGFloat = 190

    static func larghezzaGriglia(contenitore: CGFloat, margine: CGFloat) -> CGFloat {
        max(0, min(grigliaMassima, contenitore - 2 * margine))
    }

    /// Lato della griglia limitato dalla larghezza E dall'altezza disponibile
    /// (HUD + spazi + bottone), mai sotto `grigliaMinima` (allora scorre).
    static func latoGriglia(larghezza: CGFloat, altezzaDisponibile: CGFloat,
                            altezzaHUD: CGFloat, altezzaControlli: CGFloat = GameScreenMetrics.altezzaBottone) -> CGFloat {
        let perAltezza = altezzaDisponibile - altezzaHUD - spazioHUD
            - spazioGrigliaBottone - altezzaControlli - spazioBasso
        let lato = max(min(larghezza, grigliaMinima), min(larghezza, perAltezza))
        return max(0, lato.rounded(.down))
    }
}

/// Composizione delle schermate di gioco: il primo figlio (HUD) in alto, il
/// secondo (griglia + bottone) centrato verticalmente nello spazio sotto
/// l'HUD. `compensazioneBasso` (= safe area inferiore) centra il blocco
/// rispetto al bordo fisico dello schermo, come nel riferimento 440×956
/// (griglia ≈ y 390, bottone ≈ y 855). Mai meno di `spazioHUD` sopra e
/// `spazioBasso` sotto: se non c'è spazio la vista cresce (e la ScrollView
/// che la contiene scorre). Nessuno spazio fisso sotto il bottone.
struct GameScreenLayout: Layout {
    var altezzaMinima: CGFloat
    var compensazioneBasso: CGFloat = 0
    var spazioMinimo: CGFloat = GameScreenMetrics.spazioHUD
    var spazioBasso: CGFloat = GameScreenMetrics.spazioBasso

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let larghezza = proposal.width
            ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let proposta = ProposedViewSize(width: larghezza, height: nil)
        let altezze = subviews.map { $0.sizeThatFits(proposta).height }
        let necessaria: CGFloat
        if altezze.count >= 2 {
            necessaria = altezze.reduce(0, +) + spazioMinimo + spazioBasso
        } else {
            necessaria = altezze.reduce(0, +)
        }
        return CGSize(width: larghezza, height: max(altezzaMinima, necessaria))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let proposta = ProposedViewSize(width: bounds.width, height: nil)
        guard subviews.count >= 2 else {
            var y = bounds.minY
            for s in subviews {
                s.place(at: CGPoint(x: bounds.midX, y: y), anchor: .top, proposal: proposta)
                y += s.sizeThatFits(proposta).height
            }
            return
        }
        let hud = subviews[0]
        let blocco = subviews[1]
        let altezzaHUD = hud.sizeThatFits(proposta).height
        let altezzaBlocco = blocco.sizeThatFits(proposta).height
        hud.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: proposta)

        let minimo = bounds.minY + altezzaHUD + spazioMinimo
        let massimo = bounds.maxY - spazioBasso - altezzaBlocco
        let centrato = bounds.minY + (altezzaHUD + bounds.height + compensazioneBasso - altezzaBlocco) / 2
        let y = max(minimo, min(centrato, massimo))
        blocco.place(at: CGPoint(x: bounds.midX, y: y.rounded()), anchor: .top, proposal: proposta)

        // Eventuali figli in più (non previsti) in coda, senza sovrapporsi.
        var coda = y + altezzaBlocco
        for s in subviews.dropFirst(2) {
            s.place(at: CGPoint(x: bounds.midX, y: coda), anchor: .top, proposal: proposta)
            coda += s.sizeThatFits(proposta).height
        }
    }
}

/// Altezza di una vista misurata via preferenza (API iOS 17).
private struct AltezzaMisurataKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Scrive in `altezza` l'altezza della vista (aggiornata a ogni cambio).
    func misuraAltezza(_ altezza: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { g in
                Color.clear.preference(key: AltezzaMisurataKey.self, value: g.size.height)
            }
        )
        .onPreferenceChange(AltezzaMisurataKey.self) { nuova in
            if nuova > 0, abs(nuova - altezza.wrappedValue) > 0.5 {
                altezza.wrappedValue = nuova
            }
        }
    }
}

/// Toast (spec §6.3/§7: niente emoji né punti esclamativi), auto-dismiss
/// gestito dal ViewModel. Fluttuante: surfaceRaised, bordo 1 pt, ombra 18 %.
struct ToastView: View {
    let testo: String

    var body: some View {
        Text(testo)
            .filoFont(.body)
            .foregroundStyle(Theme.text)
            .multilineTextAlignment(.center)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                Capsule().fill(Theme.surfaceRaised)
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
            )
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            .padding(.bottom, 24)
            .padding(.horizontal, 24)
            .transition(.opacity)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
