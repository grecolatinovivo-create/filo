import SwiftUI
import Combine
import FiloCore

/// MENU DI GIOCO — la home dopo l'intro: scelta fra "FILO del giorno" e
/// "Salita". La card del daily si accende a mezzanotte (nuovo puzzle) e si
/// spegne quando la partita di oggi è conclusa; la Salita è sempre attiva.
/// Le schermate si aprono con la transizione a blocchi numerici
/// (TileRevealTransition), presentate in fullScreenCover senza animazione di
/// sistema: il cambio avviene "sotto" le tessere.
struct MenuView: View {
    @EnvironmentObject private var vm: GameViewModel
    @EnvironmentObject private var theme: ThemeManager   // ridisegna al cambio tema
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var account: Account
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var tessere = TileTransitionController()
    @State private var showDaily = false
    @State private var showSalita = false
    /// "Adesso" aggiornato dal timer/scenePhase: fa ricalcolare lo stato della
    /// card daily allo scoccare della mezzanotte anche senza tocchi.
    @State private var adesso = Date()
    @State private var glowPulse = false

    private let timerGiorno = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // MARK: Stato derivato

    /// True se la mezzanotte è passata rispetto al puzzle caricato: il nuovo
    /// FILO esiste anche se il vecchio engine è gameOver.
    private var giornoNuovoDisponibile: Bool {
        let o = GameViewModel.oggiParts(adesso)
        return FiloDate.dateString(y: o.y, m: o.m, d: o.d) != vm.dataOggi
    }

    private var dailyDisponibile: Bool {
        !vm.engine.gameOver || giornoNuovoDisponibile
    }

    private var salitaBest: Int {
        UserDefaults.standard.integer(forKey: "filo.salitaBest")
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)
                wordmark
                Spacer(minLength: 28)
                VStack(spacing: 18) {
                    dailyCard
                    salitaCard
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 480)
                Spacer(minLength: 28)
                iconRow
                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity)
        }
        .overlay(TileRevealOverlay(controller: tessere))
        .sheet(item: $vm.scheda, onDismiss: { vm.onboardingChiuso() }) { scheda in
            switch scheda {
            case .comeSiGioca: OnboardingView()
            case .onboardingProgressivo: ProgressiveOnboardingView()
            case .risultato: ResultView()
            case .statistiche: StatsView()
            case .profilo: ProfileView()
            }
        }
        .fullScreenCover(isPresented: $showDaily) {
            RootView(onBack: { chiudiSchermata { showDaily = false } })
                .environmentObject(vm)
                .environmentObject(theme)
                .environmentObject(store)
                .environmentObject(account)
                .overlay(TileRevealOverlay(controller: tessere))
        }
        .fullScreenCover(isPresented: $showSalita) {
            SalitaView(onClose: { chiudiSchermata { showSalita = false } })
                .environmentObject(theme)
                .overlay(TileRevealOverlay(controller: tessere))
        }
        .onChange(of: scenePhase) { _, fase in
            if fase == .active {
                vm.checkNuovoGiorno()
                adesso = Date()
            }
        }
        .onReceive(timerGiorno) { _ in
            vm.checkNuovoGiorno()
            adesso = Date()
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Wordmark

    private var wordmark: some View {
        VStack(spacing: 6) {
            Text("FILO")
                .font(.system(size: 40, weight: .heavy))
                .kerning(12)
                .padding(.leading, 12)   // compensa il kerning finale
                .foregroundStyle(Theme.filoGradient)
                .accessibilityAddTraits(.isHeader)
            Text("FILO #\(vm.numero)")
                .captionStyle()
        }
    }

    // MARK: Card FILO del giorno

    @ViewBuilder
    private var dailyCard: some View {
        if dailyDisponibile {
            dailyCardAccesa
        } else {
            dailyCardSpenta
        }
    }

    /// Stato ACCESO: oggi non ancora concluso, oppure è scoccata la mezzanotte
    /// (nuovo puzzle pronto anche se il vecchio engine è gameOver).
    private var dailyCardAccesa: some View {
        Button { apriDaily() } label: {
            HStack(spacing: 16) {
                cardIcon(emoji: "🧵", tinta: Theme.filo)
                VStack(alignment: .leading, spacing: 4) {
                    Text("FILO del giorno")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.text)
                    if giornoNuovoDisponibile {
                        Text("🧵 C'è un nuovo FILO!")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.filo)
                    } else {
                        Text("Somma del Giorno: \(vm.puzzle.T)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.filo)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Theme.filo.opacity(0.85), lineWidth: 2))
            .shadow(color: Theme.filo.opacity(glowPulse ? 0.5 : 0.22),
                    radius: glowPulse ? 18 : 10, y: 2)
        }
        .buttonStyle(MenuCardStyle())
        .onAppear {
            guard !reduceMotion else { return }
            glowPulse = false
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "FILO del giorno, disponibile"))
    }

    /// Stato SPENTO: partita di oggi conclusa e mezzanotte non ancora passata.
    /// Resta tappabile per rivedere risultato e percorso del Sarto.
    private var dailyCardSpenta: some View {
        Button { apriDaily() } label: {
            HStack(spacing: 16) {
                cardIcon(emoji: "🧵", tinta: Theme.textMuted)
                    .saturation(0)
                    .opacity(0.6)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("FILO del giorno")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.textMuted)
                        Text("Fatto ✓")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.bg)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 8)
                            .background(Theme.textMuted, in: Capsule())
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Il prossimo FILO si cuce tra")
                            .font(.footnote)
                            .foregroundStyle(Theme.textMuted)
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(verbatim: ResultView.countdown(da: ctx.date))
                                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textMuted.opacity(0.6))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface2.opacity(0.55), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(MenuCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "FILO del giorno, già completato, si rinnova a mezzanotte"))
    }

    // MARK: Card Salita

    private var salitaCard: some View {
        Button { apriSalita() } label: {
            HStack(spacing: 16) {
                cardIcon(systemName: "figure.climbing", tinta: Theme.sarto)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Salita")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.text)
                    Text("Livelli a somma crescente")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textMuted)
                    if salitaBest > 0 {
                        Text("Record: livello \(salitaBest)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.sarto)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.sarto)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Theme.sarto.opacity(0.5), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 2)
        }
        .buttonStyle(MenuCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Salita, sempre disponibile"))
    }

    // MARK: Icone secondarie (44×44)

    private var iconRow: some View {
        HStack(spacing: 12) {
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

            Button {
                vm.scheda = .comeSiGioca
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Come si gioca")
        }
    }

    private func cardIcon(emoji: String? = nil, systemName: String? = nil, tinta: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(tinta.opacity(0.14))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(tinta.opacity(0.35), lineWidth: 1)
            if let emoji {
                Text(verbatim: emoji).font(.title2)
            } else if let systemName {
                Image(systemName: systemName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tinta)
            }
        }
        .frame(width: 52, height: 52)
    }

    // MARK: Apertura/chiusura con le tessere

    private func apriDaily() {
        guard !tessere.attiva else { return }
        // Se la mezzanotte è passata, carica PRIMA il puzzle nuovo: il daily
        // si presenta già sul FILO di oggi.
        if giornoNuovoDisponibile { vm.giocaNuovoGiorno() }
        apriSchermata(da: .topLeading) { showDaily = true }
    }

    private func apriSalita() {
        guard !tessere.attiva else { return }
        apriSchermata(da: .bottomTrailing) { showSalita = true }
    }

    /// Entrata tessere → a schermo coperto presenta il cover SENZA animazione
    /// di sistema (il cambio avviene sotto la griglia) → uscita tessere.
    private func apriSchermata(da origine: UnitPoint,
                               _ presenta: @escaping @MainActor () -> Void) {
        tessere.esegui(da: origine, reduceMotion: reduceMotion) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { presenta() }
        }
    }

    /// Ritorno al menu con la stessa coreografia (l'overlay nel cover copre,
    /// il cover si dismette senza animazione, l'overlay del menu rivela).
    private func chiudiSchermata(_ nascondi: @escaping @MainActor () -> Void) {
        guard !tessere.attiva else { return }
        tessere.esegui(da: .topLeading, reduceMotion: reduceMotion) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { nascondi() }
        }
    }
}

/// Stile delle card del menu: leggera pressione (scale + opacity), niente
/// styling proprio — il look vive nella label.
struct MenuCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
