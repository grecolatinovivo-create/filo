import SwiftUI
import Combine
import FiloCore

/// Schermata principale (GIOCO, wireframe README §13.1) + navigazione a schede.
struct RootView: View {
    @EnvironmentObject private var vm: GameViewModel
    @EnvironmentObject private var theme: ThemeManager   // ridisegna al cambio tema
    @EnvironmentObject private var store: Store
    @Environment(\.scenePhase) private var scenePhase

    private let timerGiorno = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bgGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 16) {
                        HUDView()
                        BoardView()
                            .padding(.horizontal, 16)
                            .frame(maxWidth: 420)
                        strappaButton
                            .padding(.top, 8)
                        AdSlot(isPro: store.isPro)
                    }
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 32)
                }
            }

            if vm.showNuovoGiornoBanner { bannerNuovoGiorno }
        }
        .overlay(alignment: .bottom) {
            if let toast = vm.toast { ToastView(testo: toast) }
        }
        .sheet(item: $vm.scheda, onDismiss: { vm.onboardingChiuso() }) { scheda in
            switch scheda {
            case .comeSiGioca: OnboardingView()
            case .risultato: ResultView()
            case .statistiche: StatsView()
            case .profilo: ProfileView()
            }
        }
        .confirmationDialog("Strappare il filo?",
                            isPresented: $vm.showStrappoDialog,
                            titleVisibility: .visible) {
            Button("Strappa", role: .destructive) { vm.confermaStrappo() }
            Button("Continua", role: .cancel) {}
        } message: {
            Text(vm.testoDialogStrappo)
        }
        .onChange(of: scenePhase) { _, fase in
            if fase == .active { vm.checkNuovoGiorno() }
        }
        .onReceive(timerGiorno) { _ in vm.checkNuovoGiorno() }
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 0) {
            Button {
                vm.scheda = .comeSiGioca
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Come si gioca")

            Spacer()

            Text("FILO")
                .font(.title2.weight(.heavy))
                .kerning(8)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            HStack(spacing: 0) {
                Button {
                    vm.scheda = .statistiche
                } label: {
                    Image(systemName: "chart.bar.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Statistiche")

                Button {
                    vm.scheda = .profilo
                } label: {
                    Image(systemName: store.isPro ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                        .font(.title3)
                        .foregroundStyle(store.isPro ? Theme.filo : Theme.textMuted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Profilo e temi")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .frame(maxWidth: 480)
    }

    // MARK: Azioni

    private var strappaButton: some View {
        Button("Strappa il filo") { vm.richiediStrappo() }
            .buttonStyle(SecondaryButtonStyle(enabled: vm.strappaDisponibile))
            .disabled(!vm.strappaDisponibile)
    }

    // MARK: Banner nuovo giorno (RF10)

    private var bannerNuovoGiorno: some View {
        HStack(spacing: 12) {
            Text("🧵 C'è un nuovo FILO!")
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.text)
            Button("Gioca") { vm.giocaNuovoGiorno() }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.bg)
                .padding(.vertical, 8)
                .padding(.horizontal, 20)
                .background(Theme.filoGradient, in: Capsule())
            Button {
                vm.nascondiBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Nascondi avviso")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Theme.border.frame(height: 1) }
        .transition(.move(edge: .top))
    }
}

/// HUD: Somma del Giorno, riga Sarto/minimo, somma corrente, caselle, fili.
struct HUDView: View {
    @EnvironmentObject private var vm: GameViewModel

    var body: some View {
        VStack(spacing: 4) {
            Text("Somma del Giorno")
                .captionStyle()
            Text("\(vm.puzzle.T)")
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Theme.filoGradient)
                .accessibilityLabel("Somma del giorno: \(vm.puzzle.T)")
            Text("Il Sarto: \(vm.puzzle.lSarto) caselle · minimo \(vm.engine.caselleMinime)")
                .captionStyle()
                .accessibilityLabel("Il Sarto ha usato \(vm.puzzle.lSarto) caselle. Minimo teorico: \(vm.engine.caselleMinime)")

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                HStack(spacing: 4) {
                    Text("Filo").captionStyle()
                    Text("\(vm.engine.somma)")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                }
                HStack(spacing: 4) {
                    Text("Caselle").captionStyle()
                    Text("\(vm.engine.filo.count)")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                }
                filiRimastiView
            }
            .padding(.top, 8)
        }
        .padding(.top, 8)
    }

    private var filiRimastiView: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                if i < vm.engine.fili.count, vm.engine.fili[i].esito != .vinto {
                    HStack(spacing: 0) {
                        Text("🧵").opacity(0.25)
                        Text(emojiEsito(vm.engine.fili[i].esito)).font(.caption)
                    }
                } else {
                    Text("🧵")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fili rimasti: \(vm.engine.filiRimasti) di 3")
    }

    private func emojiEsito(_ esito: EsitoFilo) -> String {
        switch esito {
        case .spezzato: return "💥"
        case .annodato: return "🪢"
        case .strappato: return "✂️"
        case .vinto: return ""
        }
    }
}

/// Toast pill riusato (UX §5.7), auto-dismiss gestito dal ViewModel.
struct ToastView: View {
    let testo: String

    var body: some View {
        Text(testo)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.text)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            .padding(.bottom, 24)
            .padding(.horizontal, 24)
            .transition(.opacity)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
