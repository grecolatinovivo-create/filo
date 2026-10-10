import SwiftUI
import Combine
import UIKit
import FiloCore

// MARK: - Impostazione "Tempo nella Salita" (SALITA_TIMER_SPEC §1)

/// Modalità del tempo nella Salita: "normale" (C(n) secondi), "esteso"
/// (2 × C(n)), "libero" (nessun timer). Chiave `filo.salitaTempo`. Se
/// l'utente non ha mai scelto e VoiceOver è attivo, il default è "libero".
/// Record separati: modalità a tempo → `filo.salitaBest`, libero →
/// `filo.salitaBestLibero`.
enum SalitaTempo: String, CaseIterable, Identifiable {
    case normale, esteso, libero

    static let defaultsKey = "filo.salitaTempo"
    static let recordATempoKey = "filo.salitaBest"
    static let recordLiberoKey = "filo.salitaBestLibero"

    var id: String { rawValue }

    /// Default quando l'utente non ha mai scelto.
    static var predefinito: SalitaTempo {
        UIAccessibility.isVoiceOverRunning ? .libero : .normale
    }

    /// Modalità in vigore (scelta salvata o default).
    static var corrente: SalitaTempo {
        leggi(UserDefaults.standard.string(forKey: defaultsKey))
    }

    static func leggi(_ salvato: String?) -> SalitaTempo {
        if let salvato, let m = SalitaTempo(rawValue: salvato) { return m }
        return predefinito
    }

    /// Moltiplicatore dei secondi; nil = senza timer.
    var moltiplicatore: Int? {
        switch self {
        case .normale: return 1
        case .esteso: return 2
        case .libero: return nil
        }
    }

    var aTempo: Bool { moltiplicatore != nil }

    var chiaveRecord: String { aTempo ? Self.recordATempoKey : Self.recordLiberoKey }

    /// Record (livello raggiunto) della modalità.
    var record: Int { UserDefaults.standard.integer(forKey: chiaveRecord) }

    var titolo: LocalizedStringKey {
        switch self {
        case .normale: return "Normale"
        case .esteso: return "Esteso"
        case .libero: return "Libero"
        }
    }
}

/// MODALITÀ SALITA v2 — livelli progressivi, separata dal daily.
/// Ogni livello è un puzzle di `SalitaGenerator` (target T(n), percorso
/// d'autore L(n)), con un conto alla rovescia C(n) (× 2 in "Esteso", nessuno
/// in "Libero") e 3 vite.
/// - Somma esatta → livello superato, il tempo si ferma.
/// - Filo spezzato/annodato → il filo si ritira, NESSUNA vita persa, il tempo
///   continua (in "Libero", senza timer, costa invece una vita come nella v1).
/// - Tempo scaduto → filo tagliato, una vita in meno, stessa griglia con il
///   tempo azzerato. Senza vite → fine.
/// - App in background → pausa automatica con "Riprendi" (griglia nascosta);
///   pausa manuale dall'header.
/// Il puzzle del livello successivo è precalcolato fuori dal main thread.
/// Haptics d'esito emessi QUI: la board va creata con `outcomeHaptics: false`.
@MainActor
final class SalitaViewModel: ObservableObject {

    enum Fase: Equatable {
        /// Livello appena mostrato ("Livello N" + obiettivo): orologio fermo.
        case rivelazione
        case inGioco
        /// Somma esatta: celebrazione prima del cambio livello.
        case superato
        /// Tempo scaduto: taglio del filo, poi stessa griglia.
        case tempoScaduto
        case fine
    }

    /// Taglio del filo allo scadere del tempo (resa in uscita sulla board).
    struct Taglio: Equatable {
        let id: Int
        let percorso: [Int]
    }

    @Published private(set) var livello = 1
    @Published private(set) var vite = 3
    @Published private(set) var session: PracticeSession
    @Published private(set) var fase: Fase = .rivelazione
    @Published private(set) var best: Int
    @Published private(set) var nuovoRecord = false
    @Published private(set) var toast: String?
    /// Livello appena completato (l'obiettivo vira al colore success prima
    /// del cambio livello). `nil` fuori dalla celebrazione.
    @Published private(set) var livelloCompletato: Int?
    /// Pausa con overlay "Riprendi" (manuale o automatica): griglia nascosta.
    @Published private(set) var inPausa = false
    @Published private(set) var taglio: Taglio?
    /// Orologio del tentativo corrente (budget fisso per livello).
    @Published private(set) var cronometro = FiloCronometro()
    /// Secondi rimasti arrotondati per eccesso (testo, a11y, passi di 1 s).
    @Published private(set) var secondiRimasti = 0
    @Published private(set) var modo: SalitaTempo

    private let defaults = UserDefaults.standard
    private var semeBase: UInt64
    private var bestIniziale: Int
    private var toastTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    /// Invalida i task differiti (rivelazione, cambio livello, ritentativo).
    private var generazione = 0
    private var regoleAperte = false
    private var appAttiva = true
    private var attivo = false
    /// Soglie già segnalate nel tentativo corrente (10/5 haptic, 15/5 VoiceOver).
    private var soglieSegnalate: Set<Int> = []
    /// Puzzle del livello successivo, calcolato fuori dal main thread.
    private var prossimo: (livello: Int, task: Task<PuzzlePronto, Never>)?
    // La `session` è un ObservableObject annidato: inoltriamo i suoi cambi (somma,
    // filo…) così anche l'HUD che legge `vm.session` si ridisegna a ogni mossa.
    private var sessionCancellable: AnyCancellable?

    /// Durata della rivelazione "Livello N" + obiettivo prima dell'orologio.
    private static let durataRivelazione: Double = 0.6

    init() {
        let m = SalitaTempo.corrente
        modo = m
        let b = UserDefaults.standard.integer(forKey: m.chiaveRecord)
        best = b
        bestIniziale = b
        let seme = UInt64.random(in: 1...UInt64(UInt32.max))
        semeBase = seme
        // Livello 1 (L = 3): generazione immediata; dal 2 in poi precalcolo.
        session = PracticeSession(puzzle: SalitaGenerator.make(level: 1, seed: seme &+ 1))
        osserva(session)
        preparaCronometro()
        precalcola(livello: 2)
    }

    private func osserva(_ s: PracticeSession) {
        sessionCancellable = s.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: Derivati

    var target: Int { session.target }

    var gameOver: Bool { fase == .fine }

    /// L'obiettivo mostrato è in fase di celebrazione (colore success).
    var celebra: Bool { livelloCompletato == livello }

    var aTempo: Bool { modo.aTempo }

    /// Budget del livello corrente in secondi (0 = senza timer).
    var budget: Int {
        guard let k = modo.moltiplicatore else { return 0 }
        return SalitaGenerator.parameters(level: livello).seconds * k
    }

    /// Secondi rimasti (frazionari) all'istante dato.
    func rimanente(_ adesso: ContinuousClock.Instant = ContinuousClock.now) -> Double {
        max(0, Double(budget) - cronometro.trascorso(adesso))
    }

    /// Quota rimasta 0…1 (barra continua).
    func frazione(_ adesso: ContinuousClock.Instant = ContinuousClock.now) -> Double {
        guard budget > 0 else { return 0 }
        return rimanente(adesso) / Double(budget)
    }

    /// Quota rimasta a passi di 1 s (Riduci Movimento).
    var frazioneAPassi: Double {
        guard budget > 0 else { return 0 }
        return Double(secondiRimasti) / Double(budget)
    }

    var pausaDisponibile: Bool {
        aTempo && !inPausa && (fase == .rivelazione || fase == .inGioco)
    }

    // MARK: Ciclo di vita della schermata

    /// Schermata visibile: avvia il tick e la rivelazione del livello.
    /// `ritardo`: tempo extra per la transizione di presentazione.
    func avvia(ritardo: Double = 0.3) {
        guard !attivo else { return }
        attivo = true
        avviaTick()
        if fase == .rivelazione { rivela(ritardoExtra: ritardo) }
        aggiornaOrologio()
    }

    /// Schermata chiusa: ferma tutto.
    func termina() {
        attivo = false
        tickTask?.cancel()
        tickTask = nil
        cronometro.ferma()
    }

    /// scenePhase: fuori da `.active` la Salita a tempo va in pausa subito e
    /// al ritorno mostra "Riprendi".
    func cambioScena(attiva: Bool) {
        appAttiva = attiva
        if !attiva, aTempo, fase != .fine {
            inPausa = true
        }
        aggiornaOrologio()
    }

    /// Foglio delle regole aperto: orologio fermo (la griglia è coperta).
    func regole(aperte: Bool) {
        regoleAperte = aperte
        aggiornaOrologio()
    }

    func pausa() {
        guard pausaDisponibile else { return }
        inPausa = true
        aggiornaOrologio()
    }

    func riprendi() {
        guard inPausa else { return }
        inPausa = false
        aggiornaOrologio()
    }

    // MARK: Mosse

    func gestisci(_ mossa: Mossa) {
        guard fase != .fine else { return }
        switch mossa {
        case .iniziato, .esteso:
            // Primo tocco durante la rivelazione: l'orologio parte subito.
            if fase == .rivelazione { iniziaGioco() }
        case .vittoria:
            superaLivello()
        case .spezzato, .annodato:
            if fase == .rivelazione { iniziaGioco() }
            filoRitirato(mossa == .spezzato ? .spezzato : .annodato)
        default:
            break
        }
    }

    /// "Ricomincia il filo": azzera il filo corrente, nessuna vita persa.
    func ripulisci() {
        guard fase != .fine else { return }
        session.ripulisci()
    }

    /// "Ricomincia la Salita": dal livello 1 con 3 vite (rilegge la modalità).
    func riprova() {
        generazione += 1
        modo = SalitaTempo.corrente
        best = defaults.integer(forKey: modo.chiaveRecord)
        livello = 1
        vite = 3
        nuovoRecord = false
        livelloCompletato = nil
        inPausa = false
        taglio = nil
        bestIniziale = best
        semeBase = UInt64.random(in: 1...UInt64(UInt32.max))
        prossimo?.task.cancel()
        prossimo = nil
        imposta(SalitaGenerator.make(level: 1, seed: semeBase &+ 1))
        precalcola(livello: 2)
        rivela(ritardoExtra: 0)
    }

    // MARK: Orologio

    /// L'orologio corre solo in gioco, a tempo, app attiva, senza pausa né
    /// fogli sopra la griglia.
    private var orologioDeveCorrere: Bool {
        attivo && aTempo && fase == .inGioco && !inPausa && !regoleAperte && appAttiva
    }

    private func aggiornaOrologio() {
        let deve = orologioDeveCorrere
        if deve && !cronometro.inCorsa {
            cronometro.avvia()
        } else if !deve && cronometro.inCorsa {
            cronometro.ferma()
        }
        aggiornaSecondi()
    }

    /// Orologio nuovo (budget pieno) per il tentativo corrente.
    private func preparaCronometro() {
        cronometro = FiloCronometro()
        soglieSegnalate = []
        secondiRimasti = budget
    }

    private func aggiornaSecondi() {
        guard aTempo else { secondiRimasti = 0; return }
        let s = Int(rimanente().rounded(.up))
        if s != secondiRimasti { secondiRimasti = s }
    }

    private func avviaTick() {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard cronometro.inCorsa else { return }
        aggiornaSecondi()
        let resto = rimanente()
        segnala(resto)
        if resto <= 0 { tempoScaduto() }
    }

    /// Feedback alle soglie: haptic leggero a 10 s e 5 s; annuncio VoiceOver
    /// SOLO a 15 s e 5 s. Niente ticchettio, niente lampeggi.
    private func segnala(_ resto: Double) {
        for soglia in [15, 10, 5] where resto <= Double(soglia) && resto > 0
            && budget > soglia && !soglieSegnalate.contains(soglia) {
            soglieSegnalate.insert(soglia)
            if soglia == 10 || soglia == 5 { FiloHaptics.light() }
            if soglia == 15 || soglia == 5 {
                AccessibilityNotification.Announcement(
                    String(localized: "Tempo rimasto: \(soglia) secondi")).post()
            }
        }
    }

    // MARK: Interno

    /// Mostra il livello ("Livello N" + obiettivo) e poi avvia l'orologio.
    private func rivela(ritardoExtra: Double) {
        generazione += 1
        let g = generazione
        fase = .rivelazione
        preparaCronometro()
        aggiornaOrologio()
        let attesa = SalitaViewModel.durataRivelazione + max(0, ritardoExtra)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(attesa * 1_000_000_000))
            guard let self, self.generazione == g, self.fase == .rivelazione else { return }
            self.iniziaGioco()
        }
    }

    private func iniziaGioco() {
        guard fase == .rivelazione else { return }
        fase = .inGioco
        aggiornaOrologio()
    }

    private func superaLivello() {
        generazione += 1
        let g = generazione
        fase = .superato
        aggiornaOrologio()          // tempo fermo
        session.blocca()
        livelloCompletato = livello
        FiloHaptics.success()
        mostraToast(String(localized: "Livello completato"))
        let successivo = livello + 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, self.generazione == g else { return }
            let puzzle = await self.puzzle(livello: successivo)
            guard self.generazione == g, self.fase != .fine else { return }
            self.livello = successivo
            if self.livello > self.best {
                self.best = self.livello
                self.defaults.set(self.best, forKey: self.modo.chiaveRecord)
            }
            self.imposta(puzzle)
            self.precalcola(livello: successivo + 1)
            self.rivela(ritardoExtra: 0)
        }
    }

    /// Somma superata o vicolo cieco (la board mostra l'esito).
    /// - Modalità a tempo: il filo si ritira, nessuna vita persa, l'orologio
    ///   continua.
    /// - "Libero" (senza timer): come la Salita v1, il filo costa una vita.
    private func filoRitirato(_ esito: EsitoFilo) {
        // Il motore ha già chiuso il filo: azzeriamo anche il conteggio dei
        // fili (i tentativi della Salita non dipendono dai 3 fili del daily).
        session.ripulisci()
        guard aTempo else {
            FiloHaptics.warning()
            vite = max(0, vite - 1)
            if vite == 0 {
                AccessibilityNotification.Announcement(
                    String(localized: "Hai perso una vita.")).post()
                finePartita()
            } else {
                mostraToast(String(localized: "Hai perso una vita."))
            }
            return
        }
        if esito == .spezzato { FiloHaptics.error() } else { FiloHaptics.warning() }
        mostraToast(String(localized: "Filo ritirato. Riprova."))
    }

    /// Tempo scaduto: filo tagliato, una vita in meno, stessa griglia e
    /// stesso obiettivo con il tempo azzerato.
    private func tempoScaduto() {
        guard fase == .inGioco else { return }
        generazione += 1
        let g = generazione
        fase = .tempoScaduto
        aggiornaOrologio()
        secondiRimasti = 0
        let percorso = session.engine.filo
        if !percorso.isEmpty {
            taglio = Taglio(id: (taglio?.id ?? 0) + 1, percorso: percorso)
        }
        session.blocca()
        session.ripulisci()
        FiloHaptics.medium()
        vite = max(0, vite - 1)
        let avviso = String(localized: "Tempo scaduto. Hai perso una vita.")
        if vite == 0 {
            AccessibilityNotification.Announcement(avviso).post()
            finePartita()
            return
        }
        mostraToast(avviso)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self, self.generazione == g, self.fase == .tempoScaduto else { return }
            self.taglio = nil
            self.session.sblocca()
            self.rivela(ritardoExtra: 0)
        }
    }

    private func finePartita() {
        generazione += 1
        fase = .fine
        inPausa = false
        aggiornaOrologio()
        nuovoRecord = livello > bestIniziale
        toastTask?.cancel()
        toast = nil
        session.blocca()
        session.mostraSoluzione()
    }

    private func imposta(_ puzzle: Puzzle) {
        session = PracticeSession(puzzle: puzzle)
        osserva(session)
        livelloCompletato = nil
    }

    // MARK: Precalcolo (fuori dal main thread)

    private func seme(livello n: Int) -> UInt64 {
        semeBase &+ UInt64(max(1, n))
    }

    private func precalcola(livello n: Int) {
        if let p = prossimo, p.livello == n { return }
        prossimo?.task.cancel()
        let s = seme(livello: n)
        let task = Task.detached(priority: .userInitiated) {
            PuzzlePronto(puzzle: SalitaGenerator.make(level: n, seed: s))
        }
        prossimo = (n, task)
    }

    /// Puzzle del livello `n`: dal precalcolo se pronto (o in corso), altrimenti
    /// calcolato ora, comunque fuori dal main thread.
    private func puzzle(livello n: Int) async -> Puzzle {
        if let p = prossimo, p.livello == n {
            prossimo = nil
            return await p.task.value.puzzle
        }
        let s = seme(livello: n)
        return await Task.detached(priority: .userInitiated) {
            PuzzlePronto(puzzle: SalitaGenerator.make(level: n, seed: s))
        }.value.puzzle
    }

    private func mostraToast(_ t: String) {
        toastTask?.cancel()
        toast = t
        AccessibilityNotification.Announcement(t).post()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }
}

/// Contenitore per riportare sul main actor un `Puzzle` calcolato in un task
/// separato (`Puzzle` è un valore immutabile di soli Int: nessuno stato
/// condiviso; FiloCore non lo dichiara `Sendable`).
struct PuzzlePronto: @unchecked Sendable {
    let puzzle: Puzzle
}

struct SalitaView: View {
    @StateObject private var vm = SalitaViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mostraRegole = false

    /// Ritorno al menu orchestrato dal presentatore (transizione a tessere).
    /// Se assente, chiusura standard con dismiss.
    var onClose: (() -> Void)? = nil

    private func chiudi() {
        if let onClose { onClose() } else { dismiss() }
    }

    /// Altezza misurata dell'HUD (dimensionamento della griglia in altezza).
    @State private var altezzaHUD: CGFloat = GameScreenMetrics.stimaHUD

    var body: some View {
        GeometryReader { esterno in
            let margine = FiloMetrics.margin(forWidth: esterno.size.width)
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, max(0, margine - 12))
                ZStack {
                    // Stessa composizione della Partita (ROUND2 §6/§9): HUD in
                    // alto, griglia + "Ricomincia il filo" centrati sotto.
                    GeometryReader { area in
                        let larghezza = GameScreenMetrics.larghezzaGriglia(contenitore: area.size.width,
                                                                           margine: margine)
                        let lato = GameScreenMetrics.latoGriglia(larghezza: larghezza,
                                                                 altezzaDisponibile: area.size.height,
                                                                 altezzaHUD: altezzaHUD)
                        ScrollView {
                            GameScreenLayout(altezzaMinima: area.size.height,
                                             compensazioneBasso: esterno.safeAreaInsets.bottom) {
                                hud
                                    .frame(maxWidth: larghezza)
                                    .padding(.top, FiloMetrics.relatedGap)
                                    .misuraAltezza($altezzaHUD)
                                VStack(spacing: GameScreenMetrics.spazioGrigliaBottone) {
                                    board(lato: lato)
                                        .frame(width: lato, height: lato)
                                    Button("Ricomincia il filo") {
                                        FiloHaptics.light()
                                        vm.ripulisci()
                                    }
                                    .buttonStyle(SecondaryButtonStyle(enabled: !vm.gameOver, fullWidth: true))
                                    .disabled(vm.gameOver)
                                    .frame(maxWidth: lato)
                                }
                                // In pausa la griglia non si vede (niente
                                // tempo "gratis" per pensare).
                                .opacity(vm.inPausa ? 0 : 1)
                                .allowsHitTesting(!vm.inPausa)
                                .accessibilityHidden(vm.inPausa)
                            }
                            .padding(.horizontal, margine)
                            .frame(maxWidth: .infinity)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }

                    if vm.inPausa && !vm.gameOver {
                        pausaOverlay
                            .transition(.opacity)
                    }

                    if vm.gameOver {
                        gameOverOverlay
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: reduceMotion ? FiloMotion.reducedDuration : 0.25),
                           value: vm.gameOver)
                .animation(.easeInOut(duration: reduceMotion ? FiloMotion.reducedDuration : 0.2),
                           value: vm.inPausa)
            }
        }
        .background { FiloBackground() }
        .overlay(alignment: .bottom) {
            ZStack {
                if let toast = vm.toast, !vm.gameOver, !vm.inPausa {
                    ToastView(testo: toast)
                }
            }
            .animation(FiloMotion.adaptive(FiloMotion.screen, reduceMotion: reduceMotion), value: vm.toast)
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $mostraRegole) {
            RegoleSalitaView()
        }
        .onChange(of: mostraRegole) { _, aperte in vm.regole(aperte: aperte) }
        .onChange(of: scenePhase) { _, fase in vm.cambioScena(attiva: fase == .active) }
        .onAppear {
            FiloHaptics.prepare()
            vm.cambioScena(attiva: scenePhase == .active)
            vm.avvia()
        }
        .onDisappear { vm.termina() }
        .preferredColorScheme(.dark)
    }

    // MARK: Header (48 pt): chiudi · "Salita" · pausa · regole

    private var header: some View {
        ZStack {
            Text("Salita")
                .filoFont(.headerTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                FiloIconButton(systemName: "xmark", label: "Chiudi") { chiudi() }
                Spacer()
                if vm.aTempo && !vm.gameOver {
                    FiloIconButton(systemName: "pause", label: "Pausa") {
                        FiloHaptics.light()
                        vm.pausa()
                    }
                    .disabled(!vm.pausaDisponibile)
                    .opacity(vm.pausaDisponibile ? 1 : 0.45)
                }
                FiloIconButton(systemName: "questionmark.circle", label: "Come si gioca") {
                    mostraRegole = true
                }
            }
        }
        .frame(height: FiloMetrics.headerHeight)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    // MARK: HUD

    private var transizioneLivello: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .offset(y: 12).combined(with: .opacity),
            removal: .offset(y: -12).combined(with: .opacity))
    }

    /// Stessa struttura e metriche dell'HUD della Partita: eyebrow, obiettivo
    /// 64, barra del tempo (solo a tempo), poi `GameHUDMetricRow` con "Somma
    /// attuale" a sinistra e le vite a destra. Ordine d'accessibilità:
    /// "Livello N" → "Obiettivo: N" → tempo → somma → vite.
    private var hud: some View {
        VStack(spacing: 0) {
            Text("Livello \(vm.livello)")
                .eyebrowStyle()
                .contentTransition(.numericText())
                .animation(FiloMotion.adaptive(FiloMotion.level, reduceMotion: reduceMotion),
                           value: vm.livello)

            // Obiettivo: vira a success (0,25 s) quando il livello è
            // completato, poi il vecchio numero sale di 12 pt e svanisce
            // mentre il nuovo entra da +12 pt (0,30 s easeInOut).
            ZStack {
                Text(verbatim: "\(vm.target)")
                    .filoFont(.target)
                    .monospacedDigit()
                    .foregroundStyle(vm.celebra ? Theme.success : Theme.gold)
                    .animation(.easeOut(duration: 0.25), value: vm.celebra)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel(Text("Obiettivo: \(vm.target)"))
                    .id(vm.livello)
                    .transition(transizioneLivello)
            }
            .animation(FiloMotion.adaptive(FiloMotion.level, reduceMotion: reduceMotion), value: vm.livello)

            if vm.aTempo {
                timer
                    .padding(.top, FiloMetrics.relatedGap)
            }

            GameHUDMetricRow {
                GameHUDMetric(somma: vm.session.somma,
                              totale: vm.target,
                              etichetta: Text("Somma attuale: \(vm.session.somma) di \(vm.target)"))
            } trailing: {
                LivesIndicator(lives: vm.vite, size: 10, showsText: true)
            }
            .padding(.top, FiloMetrics.relatedGapLarge)
        }
        .frame(maxWidth: .infinity)
    }

    /// Conto alla rovescia: barra 3 pt a tutta larghezza (continua; a passi
    /// di 1 s con Riduci Movimento) + "TEMPO" e "0:48" (SF Rounded 15
    /// semibold, cifre tabellari, avorio). Un solo elemento d'accessibilità.
    private var timer: some View {
        VStack(spacing: 6) {
            Group {
                if reduceMotion {
                    CountdownBar(frazione: vm.frazioneAPassi)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                            paused: !vm.cronometro.inCorsa)) { _ in
                        CountdownBar(frazione: vm.frazione())
                    }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Tempo")
                    .eyebrowStyle()
                Spacer(minLength: 8)
                Text(verbatim: FiloDurata.testo(secondi: vm.secondiRimasti))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Tempo rimasto: \(vm.secondiRimasti) secondi"))
    }

    // MARK: Board (crossfade 0,22 s al cambio livello)

    private func board(lato: CGFloat) -> some View {
        let side = BoardMetrics.side(forWidth: min(lato, BoardMetrics.maxWidth))
        return ZStack(alignment: .topLeading) {
            PracticeBoardView(session: vm.session, onMove: vm.gestisci, outcomeHaptics: false)
                .id(vm.livello)
                .transition(.opacity)
            // Tempo scaduto: il filo tagliato svanisce (resa del taglio).
            if let taglio = vm.taglio {
                EsitoFiloOverlay(punti: taglio.percorso.map { BoardMetrics.center($0, side: side) },
                                 esito: .strappato, side: side)
                    .frame(width: lato, height: lato, alignment: .topLeading)
                    .id(taglio.id)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .animation(.easeInOut(duration: reduceMotion ? FiloMotion.reducedDuration : 0.22), value: vm.livello)
    }

    // MARK: Pausa

    private var pausaOverlay: some View {
        ZStack {
            Theme.overlay
                .ignoresSafeArea(edges: .bottom)
                .accessibilityHidden(true)
            FiloCard(padding: FiloMetrics.cardPaddingLarge, floating: true, alignment: .center) {
                VStack(spacing: FiloMetrics.relatedGapLarge) {
                    Text("In pausa")
                        .filoFont(.screenTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: FiloDurata.testo(secondi: vm.secondiRimasti))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityLabel(Text("Tempo rimasto: \(vm.secondiRimasti) secondi"))
                    Button("Riprendi") {
                        FiloHaptics.light()
                        vm.riprendi()
                    }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .padding(.top, FiloMetrics.relatedGap)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, FiloMetrics.sectionGap)
        }
    }

    // MARK: Fine partita

    private var gameOverOverlay: some View {
        ZStack {
            Theme.overlay
                .ignoresSafeArea(edges: .bottom)
                .accessibilityHidden(true)
            FiloCard(padding: FiloMetrics.cardPaddingLarge, floating: true, alignment: .center) {
                VStack(spacing: FiloMetrics.relatedGapLarge) {
                    VStack(spacing: FiloMetrics.relatedGap) {
                        Text("La salita finisce qui.")
                            .filoFont(.screenTitle)
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text("Hai raggiunto il livello \(vm.livello).")
                            .filoFont(.body)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    if vm.nuovoRecord {
                        Chip("Nuovo record", systemImage: "arrow.up", tint: Theme.success, filled: true)
                    } else {
                        Text("Record: livello \(vm.best)")
                            .filoFont(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    VStack(spacing: FiloMetrics.relatedGap) {
                        Button("Ricomincia la Salita") {
                            FiloHaptics.light()
                            vm.riprova()
                        }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                        Button("Torna alla Home") { chiudi() }
                            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                    }
                    .padding(.top, FiloMetrics.relatedGap)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, FiloMetrics.sectionGap)
        }
    }
}

/// Regole aperte dal "?" della Salita: stessa guida di "Come si gioca", con
/// una nota su tempo e vite e senza la CTA del daily (non richiede
/// GameViewModel, che la Salita non riceve nell'environment).
struct RegoleSalitaView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ComeSiGiocaContenuto(
            nota: "Nella Salita ogni livello alza la somma. Se il filo si spezza o si annoda, si ritira e riprovi. Hai tre vite: ne perdi una quando scade il tempo. In modalità Libero non c'è timer: ogni filo spezzato o annodato costa una vita.",
            onChiudi: { dismiss() }
        )
    }
}
