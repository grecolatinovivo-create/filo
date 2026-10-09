import SwiftUI
import Combine
import FiloCore

/// HOME (REDESIGN_SPEC §6.2): header con icone (Statistiche, Archivio, Come
/// si gioca, Impostazioni), logo + claim, card "FILO di oggi" (gioca /
/// continua / completato con conto alla rovescia) e card "Salita".
/// Daily e Salita si aprono in fullScreenCover con il crossfade del
/// `TileTransitionController` (+ spostamento di 12 pt), senza animazione di
/// sistema: il cambio avviene "sotto" il fondale.
struct MenuView: View {
    @EnvironmentObject private var vm: GameViewModel
    @EnvironmentObject private var theme: ThemeManager   // ridisegna al cambio tema
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var account: Account
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True quando la Home è visibile (intro dissolta): avvia l'entrata.
    var entrata: Bool = true

    @StateObject private var tessere = TileTransitionController()
    @State private var showDaily = false
    @State private var showSalita = false
    /// "Adesso" aggiornato dal timer/scenePhase: fa ricalcolare lo stato della
    /// card daily allo scoccare della mezzanotte anche senza tocchi.
    @State private var adesso = Date()
    /// Entrata della Home (logo → card di oggi → Salita).
    @State private var entrato = false

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

    /// Partita di oggi iniziata (almeno un filo concluso o in corso).
    private var dailyInCorso: Bool {
        !giornoNuovoDisponibile && !vm.engine.gameOver
            && (!vm.engine.fili.isEmpty || !vm.engine.filo.isEmpty)
    }

    /// `vm.scheda` vista dal menu: nil (nessuna presentazione, nessun
    /// onDismiss) finché il daily o la Salita coprono il menu.
    private var schedaMenu: Binding<GameViewModel.Scheda?> {
        Binding(
            get: { (showDaily || showSalita) ? nil : vm.scheda },
            set: { nuova in
                guard !showDaily, !showSalita else { return }
                vm.scheda = nuova
            }
        )
    }

    private var salitaBest: Int {
        UserDefaults.standard.integer(forKey: "filo.salitaBest")
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let margin = FiloMetrics.margin(forWidth: geo.size.width)
            let corto = geo.size.height < 700
            ZStack {
                FiloBackground()

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, max(4, margin - 12))
                        .opacity(entrato ? 1 : 0)
                        .animation(entrataAnimazione(ritardo: 0), value: entrato)

                    ScrollView {
                        VStack(spacing: 0) {
                            logo
                                .opacity(entrato ? 1 : 0)
                                .offset(y: entrato || reduceMotion ? 0 : 6)
                                .animation(entrataAnimazione(ritardo: 0, durata: 0.45), value: entrato)

                            dailyCard
                                .padding(.top, corto ? 24 : 40)
                                .opacity(entrato ? 1 : 0)
                                .offset(y: entrato || reduceMotion ? 0 : 8)
                                .animation(entrataAnimazione(ritardo: 0.12), value: entrato)

                            salitaCard
                                .padding(.top, 16)
                                .opacity(entrato ? 1 : 0)
                                .offset(y: entrato || reduceMotion ? 0 : 8)
                                .animation(entrataAnimazione(ritardo: 0.20), value: entrato)
                        }
                        .frame(maxWidth: 480)
                        .padding(.horizontal, margin)
                        .padding(.vertical, corto ? 8 : 16)
                        .frame(maxWidth: .infinity,
                               minHeight: max(0, geo.size.height - FiloMetrics.headerHeight - 48))   // centro ottico un po' più in alto
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .filoScreenShift(tessere)   // solo il contenuto: lo sfondo resta fermo
            }
        }
        .overlay(TileRevealOverlay(controller: tessere))
        // UNA sola sheet attiva per contesto: mentre il daily (o la Salita) è
        // presentato in fullScreenCover, le schede le presenta RootView. Se
        // anche questa sheet reagisse a `vm.scheda`, iOS impilerebbe DUE fogli
        // identici (Menu + Root) e alla chiusura uno resterebbe orfano: a
        // binding già nil, "Salta"/dismiss() non avrebbe più effetto.
        .sheet(item: schedaMenu, onDismiss: { vm.onboardingChiuso() }) { scheda in
            switch scheda {
            case .comeSiGioca: OnboardingView()
            case .onboardingProgressivo: ProgressiveOnboardingView()
            case .risultato: ResultView()
            case .statistiche: StatsView()
            case .profilo: ProfileView()
            case .archivio: ArchiveView()
            }
        }
        .fullScreenCover(isPresented: $showDaily) {
            // Fondale fisso sotto la schermata: lo spostamento di 12 pt non
            // scopre mai il fondo del cover.
            ZStack {
                FiloBackground()
                RootView(onBack: { chiudiSchermata { showDaily = false } })
                    .filoScreenShift(tessere)
            }
            .environmentObject(vm)
            .environmentObject(theme)
            .environmentObject(store)
            .environmentObject(account)
            .overlay(TileRevealOverlay(controller: tessere))
        }
        .fullScreenCover(isPresented: $showSalita) {
            ZStack {
                FiloBackground()
                SalitaView(onClose: { chiudiSchermata { showSalita = false } })
                    .filoScreenShift(tessere)
            }
            .environmentObject(theme)
            .overlay(TileRevealOverlay(controller: tessere))
        }
        .onChange(of: scenePhase) { _, fase in
            if fase == .active { aggiornaGiorno() }
        }
        .onReceive(timerGiorno) { _ in aggiornaGiorno() }
        .onChange(of: entrata) { _, visibile in
            if visibile { entrato = true }
        }
        .onAppear {
            if entrata { entrato = true }
        }
        .preferredColorScheme(.dark)
    }

    /// Animazione d'entrata (spec §6.2/§8). Riduci Movimento: dissolvenza 0,15 s.
    private func entrataAnimazione(ritardo: Double, durata: Double = 0.32) -> Animation {
        reduceMotion ? FiloMotion.reduced : .easeOut(duration: durata).delay(ritardo)
    }

    // MARK: Header (48 pt, icone 44×44 allineate a destra)

    private var header: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            FiloIconButton(systemName: "chart.bar", label: "Statistiche") {
                vm.scheda = .statistiche
            }
            FiloIconButton(systemName: "square.grid.2x2", label: "Archivio") {
                vm.scheda = .archivio
            }
            FiloIconButton(systemName: "questionmark.circle", label: "Come si gioca") {
                vm.scheda = .comeSiGioca
            }
            FiloIconButton(systemName: "gearshape", label: "Impostazioni") {
                vm.scheda = .profilo
            }
        }
        .frame(height: FiloMetrics.headerHeight)
    }

    // MARK: Logo + claim

    private var logo: some View {
        VStack(spacing: 8) {
            // Per VoiceOver (e per chi cerca il testo) resta l'intestazione "FILO".
            Image("LogoFilo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 176)
                .accessibilityLabel(Text("FILO"))
                .accessibilityRemoveTraits(.isImage)
                .accessibilityAddTraits(.isHeader)
            Text("Un filo al giorno.")
                .filoFont(.body)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Card FILO di oggi

    /// Card unica con tre stati (gioca / continua / completato). L'intera
    /// card è un solo pulsante e un solo elemento d'accessibilità, con le
    /// etichette usate dai test UI.
    private var dailyCard: some View {
        let completato = !dailyDisponibile
        return Button {
            FiloHaptics.light()
            if completato { vm.mostraRisultato() } else { apriDaily() }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("FILO di oggi")
                        .eyebrowStyle()
                    Spacer(minLength: 8)
                    if !giornoNuovoDisponibile {
                        Text(verbatim: "#\(vm.numero)")
                            .filoFont(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                if giornoNuovoDisponibile {
                    Text("C'è un nuovo FILO.")
                        .filoFont(.cardTitle)
                        .foregroundStyle(Theme.text)
                        .padding(.top, 16)
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        Text("Somma \(numeroObiettivo)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: 0)
                        if completato {
                            if vm.engine.stato == .vinta {
                                Chip("Completato", systemImage: "checkmark", tint: Theme.success, filled: true)
                            } else {
                                Chip("Completato")
                            }
                        }
                    }
                    .padding(.top, 4)

                    Text("Il Sarto ha usato \(vm.puzzle.lSarto) caselle.")
                        .filoFont(.body)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // "Bottone" primario visivo: l'azione è quella dell'intera card.
                Text(titoloAzioneDaily(completato: completato))
                    .filoFont(.button)
                    .foregroundStyle(Theme.onGold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: FiloMetrics.primaryHeight)
                    .background(
                        RoundedRectangle(cornerRadius: FiloMetrics.buttonRadius, style: .continuous)
                            .fill(Theme.gold)
                    )
                    .padding(.top, 20)

                if completato {
                    TimelineView(.periodic(from: .now, by: 15)) { ctx in
                        let r = Self.tempoAllaMezzanotte(da: ctx.date)
                        Text("Prossimo FILO tra \(r.ore) h \(r.minuti) min")
                            .filoFont(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                }
            }
            .padding(FiloMetrics.cardPaddingLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FiloCardBackground(radius: FiloMetrics.cardRadius))
            .contentShape(RoundedRectangle(cornerRadius: FiloMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(MenuCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(completato
            ? String(localized: "FILO del giorno, già completato, si rinnova a mezzanotte")
            : String(localized: "FILO del giorno, disponibile"))
    }

    /// Numero obiettivo in SF Rounded 64 bold oro, interpolato nella chiave
    /// "Somma %@" (l'ordine delle parole resta localizzabile).
    private var numeroObiettivo: Text {
        Text(verbatim: "\(vm.puzzle.T)")
            .font(FiloFont.target())
            .kerning(-1.5)
            .foregroundStyle(Theme.gold)
    }

    private func titoloAzioneDaily(completato: Bool) -> LocalizedStringKey {
        if completato { return "Rivedi il risultato" }
        if dailyInCorso { return "Continua la partita" }
        return "Gioca il FILO di oggi"
    }

    /// Ore e minuti alla prossima mezzanotte locale (minuti arrotondati per
    /// eccesso: "0 h 1 min" fino allo scoccare).
    nonisolated static func tempoAllaMezzanotte(da now: Date) -> (ore: Int, minuti: Int) {
        let cal = Calendar.current
        let inizio = cal.startOfDay(for: now)
        let domani = cal.date(byAdding: .day, value: 1, to: inizio) ?? now.addingTimeInterval(86_400)
        let secondi = max(0, Int(domani.timeIntervalSince(now).rounded(.up)))
        let minutiTotali = (secondi + 59) / 60
        return (minutiTotali / 60, minutiTotali % 60)
    }

    // MARK: Card Salita

    private var salitaCard: some View {
        Button {
            FiloHaptics.light()
            apriSalita()
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Salita")
                        .filoFont(.cardTitle)
                        .foregroundStyle(Theme.text)
                    Group {
                        if salitaBest > 0 {
                            Text("Livello \(salitaBest) · \(3) vite")
                        } else {
                            Text("Somme sempre più alte, tre vite")
                        }
                    }
                    .filoFont(.body)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(FiloMetrics.cardPadding)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(FiloCardBackground(radius: FiloMetrics.cardRadius))
            .contentShape(RoundedRectangle(cornerRadius: FiloMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(MenuCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Salita, sempre disponibile"))
    }

    // MARK: Cambio giorno

    /// Timer/scenePhase: se è scoccata la mezzanotte e la Home è libera
    /// (nessuna schermata o scheda aperta), carica subito il FILO nuovo così
    /// la card mostra sempre il puzzle di oggi.
    private func aggiornaGiorno() {
        vm.checkNuovoGiorno()
        adesso = Date()
        if giornoNuovoDisponibile, !showDaily, !showSalita, vm.scheda == nil, !tessere.attiva {
            vm.giocaNuovoGiorno()
        }
    }

    // MARK: Apertura/chiusura (crossfade + 12 pt)

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

    /// Dissolvenza in entrata → a schermo coperto presenta il cover SENZA
    /// animazione di sistema → dissolvenza in uscita.
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

/// Stile delle card del menu: leggera pressione (scale), niente styling
/// proprio — il look vive nella label.
struct MenuCardStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(FiloMotion.press, value: configuration.isPressed)
    }
}
