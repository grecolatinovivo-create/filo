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

    var body: some View {
        GeometryReader { geo in
            let margin = FiloMetrics.margin(forWidth: geo.size.width)
            ZStack(alignment: .top) {
                FiloBackground()

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, max(4, margin - 12))
                    ScrollView {
                        VStack(spacing: FiloMetrics.sectionGap) {
                            HUDView()
                                .frame(maxWidth: BoardMetrics.maxWidth)
                            BoardView()
                            tagliaButton
                            AdSlot(isPro: store.isPro)
                        }
                        .padding(.horizontal, margin)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                        .frame(maxWidth: 480)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)   // niente rimbalzo se il contenuto sta a schermo
                }

                // Contenitore dedicato: l'animazione riguarda solo il banner.
                VStack(spacing: 0) {
                    if vm.showNuovoGiornoBanner {
                        bannerNuovoGiorno
                            .padding(.horizontal, margin)
                            .padding(.top, FiloMetrics.headerHeight + 4)
                            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(reduceMotion ? FiloMotion.reduced : FiloMotion.screen, value: vm.showNuovoGiornoBanner)
                .zIndex(1)
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
            .buttonStyle(DestructiveButtonStyle(enabled: vm.strappaDisponibile))
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
                .accessibilityLabel(Text("Somma del giorno: \(vm.puzzle.T)"))
            Text("Sarto: \(vm.puzzle.lSarto) caselle")
                .filoFont(.caption)
                .foregroundStyle(Theme.textMuted)
                .accessibilityLabel(Text("Il Sarto ha usato \(vm.puzzle.lSarto) caselle. Minimo teorico: \(vm.engine.caselleMinime)"))

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Somma attuale")
                        .filoFont(.caption)
                        .foregroundStyle(Theme.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(verbatim: "\(vm.engine.somma)")
                            .filoFont(.currentSum)
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : FiloMotion.numeric, value: vm.engine.somma)
                        Text(verbatim: " / \(vm.puzzle.T)")
                            .filoFont(.body)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Somma attuale: \(vm.engine.somma) su \(vm.puzzle.T)"))

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
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
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
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
