import SwiftUI
import Combine
import Accessibility
import UIKit
import FiloCore

/// Stato dell'app: incapsula GameEngine (FiloCore, logica pura) e aggiunge
/// persistenza UserDefaults (schema equivalente a README §11.2), sequenze
/// animate degli esiti, cambio giorno e testi normativi NEURO_SPEC.
@MainActor
final class GameViewModel: ObservableObject {

    // MARK: Tipi

    enum Scheda: String, Identifiable {
        case comeSiGioca, onboardingProgressivo, risultato, statistiche, profilo
        var id: String { rawValue }
    }

    struct EsitoVisuale: Equatable {
        let percorso: [Int]
        let esito: EsitoFilo
    }

    /// Schema `filo.today` (equivalente a §11.2 web).
    struct TodayRecord: Codable {
        var data: String
        var numero: Int
        var stato: StatoPartita
        var fili: [FiloConcluso]
        var stelle: Int
        var sartoBattuto: Bool
        var percorsoVincente: [Int]?
    }

    // MARK: Stato pubblicato

    @Published private(set) var puzzle: Puzzle
    @Published private(set) var numero: Int
    @Published private(set) var dataOggi: String
    @Published private(set) var engine: GameEngine
    @Published private(set) var stats: Statistiche
    @Published private(set) var stelleOggi = 0
    @Published private(set) var sartoBattutoOggi = false

    @Published var scheda: Scheda?
    @Published var showStrappoDialog = false
    @Published private(set) var lockInput = false
    @Published private(set) var revealSarto = false
    @Published private(set) var esitoVisuale: EsitoVisuale?
    @Published private(set) var toast: String?
    @Published private(set) var showNuovoGiornoBanner = false
    @Published private(set) var shakes: [Int: Int] = [:]
    @Published private(set) var shakeTick = 0          // trigger sensoryFeedback
    @Published private(set) var casellaNonValida: Int? // flash bordo (reduce motion)

    private var bannerDismissedFor: String?
    private var risultatoMostrato = false
    private var toastTask: Task<Void, Never>?
    /// True solo al PRIMO avvio (onboarding classico non ancora fatto): abilita
    /// la catena tutorial → onboarding progressivo → daily.
    private var primoAvvio = false
    private let progressiveKey = "filo.onboardingProgressivoFatto"

    private let defaults = UserDefaults.standard

    // MARK: Init / bootstrap

    init() {
        let o = Self.oggiParts()
        let daily = Generator.daily(y: o.y, m: o.m, d: o.d)
        puzzle = daily.puzzle
        numero = daily.numero
        dataOggi = FiloDate.dateString(y: o.y, m: o.m, d: o.d)
        engine = GameEngine(puzzle: daily.puzzle)
        stats = Self.loadStats(from: UserDefaults.standard)
        ripristinaGiornata()
        if !defaults.bool(forKey: "filo.onboarded") {
            primoAvvio = true
            scheda = .comeSiGioca
        } else {
            // Retro-compat: chi ha già l'onboarding classico NON deve vedere
            // l'onboarding progressivo (lo consideriamo già fatto).
            if !defaults.bool(forKey: progressiveKey) {
                defaults.set(true, forKey: progressiveKey)
            }
            if engine.gameOver {
                revealSarto = true
                risultatoMostrato = true
                scheda = .risultato        // RF9: giorno concluso → risultato
            }
        }
    }

    /// Carica (o ricarica) il puzzle del giorno corrente.
    func bootGiorno() {
        let o = Self.oggiParts()
        let daily = Generator.daily(y: o.y, m: o.m, d: o.d)
        puzzle = daily.puzzle
        numero = daily.numero
        dataOggi = FiloDate.dateString(y: o.y, m: o.m, d: o.d)
        engine = GameEngine(puzzle: daily.puzzle)
        stelleOggi = 0
        sartoBattutoOggi = false
        revealSarto = false
        esitoVisuale = nil
        lockInput = false
        risultatoMostrato = false
        showNuovoGiornoBanner = false
        scheda = nil
        ripristinaGiornata()
        if engine.gameOver {
            revealSarto = true
            risultatoMostrato = true
            scheda = .risultato
        }
    }

    /// Flusso E: fili conclusi ripristinati, filo a metà perso senza penalità.
    private func ripristinaGiornata() {
        guard let today = loadToday(), today.data == dataOggi else { return }
        engine.ripristina(fili: today.fili, stato: today.stato,
                          percorsoVincente: today.percorsoVincente)
        stelleOggi = today.stelle
        sartoBattutoOggi = today.sartoBattuto
        if today.stato == .inCorso && engine.stato == .persa {
            // reload avvenuto dopo il terzo filo ma prima della valutazione finale
            let o = Self.oggiParts()
            stats.registra(vinta: false, filiUsati: 3, caselle: 0, gold: false, oggi: o)
            salvaStats()
            salvaOggi()
        }
    }

    // MARK: Data locale

    static func oggiParts(_ date: Date = Date()) -> (y: Int, m: Int, d: Int) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    // MARK: Persistenza (UserDefaults, schema §11.2)

    private static func loadStats(from defaults: UserDefaults) -> Statistiche {
        guard let data = defaults.data(forKey: "filo.stats"),
              let s = try? JSONDecoder().decode(Statistiche.self, from: data)
        else { return Statistiche() }
        return s
    }

    private func salvaStats() {
        if let data = try? JSONEncoder().encode(stats) {
            defaults.set(data, forKey: "filo.stats")
        }
    }

    private func loadToday() -> TodayRecord? {
        guard let data = defaults.data(forKey: "filo.today") else { return nil }
        return try? JSONDecoder().decode(TodayRecord.self, from: data)
    }

    /// Scrittura DOPO ogni filo concluso e a fine partita (mai a metà filo, §6.6).
    private func salvaOggi() {
        let record = TodayRecord(data: dataOggi, numero: numero, stato: engine.stato,
                                 fili: engine.fili, stelle: stelleOggi,
                                 sartoBattuto: sartoBattutoOggi,
                                 percorsoVincente: engine.percorsoVincente)
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: "filo.today")
        }
    }

    func segnaOnboarded() {
        defaults.set(true, forKey: "filo.onboarded")
    }

    func segnaOnboardingProgressivoFatto() {
        defaults.set(true, forKey: progressiveKey)
    }

    // MARK: Derivati

    var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    var durataReveal: Double {
        min(1.8, 0.09 * Double(max(1, puzzle.percorsoSarto.count - 1)))
    }

    var streakEffettiva: Int {
        stats.streakEffettiva(oggi: Self.oggiParts())
    }

    /// Testo di condivisione — unica fonte: ShareText di FiloCore (§9.1).
    /// Include la riga URL finale, come CONFIG.SHARE_URL sul web: anteprima
    /// e testo condiviso coincidono carattere per carattere su ogni piattaforma.
    var shareText: String {
        ShareText.build(numero: numero, vinta: engine.stato == .vinta,
                        fili: engine.fili, T: puzzle.T, stelle: stelleOggi,
                        sartoBattuto: sartoBattutoOggi, streak: streakEffettiva,
                        url: ShareText.shareURL)
    }

    var strappaDisponibile: Bool {
        !engine.filo.isEmpty && !engine.gameOver && !lockInput
    }

    /// Corpo del dialog strappo (NEURO_SPEC §2.3, plurale normativo).
    var testoDialogStrappo: String {
        let n = engine.filiRimasti - 1
        if n == 0 { return String(localized: "È l'ultimo filo: strapparlo chiude la partita di oggi.") }
        if n == 1 { return String(localized: "Un filo strappato non si ricuce: te ne resterà 1.") }
        return String(localized: "Un filo strappato non si ricuce: te ne resteranno \(n).")
    }

    /// aria-label equivalente per VoiceOver (UX_SPEC §9.4).
    func etichettaCasella(_ idx: Int) -> String {
        let r = idx / 5 + 1, c = idx % 5 + 1
        var lbl = String(localized: "Casella riga \(r) colonna \(c), valore \(puzzle.valori[idx])")
        if let pos = engine.filo.firstIndex(of: idx) {
            if pos == engine.filo.count - 1 { lbl += String(localized: ", ultima del filo") }
            else { lbl += String(localized: ", nel filo, posizione \(pos + 1)") }
        }
        if engine.gameOver && puzzle.percorsoSarto.contains(idx) {
            lbl += String(localized: ", percorso del Sarto")
        }
        return lbl
    }

    // MARK: Input di gioco

    /// viaTap = tap/VoiceOver (feedback su mossa non valida); drag = silenzioso (§6.6).
    func gioca(_ idx: Int, viaTap: Bool) {
        guard !lockInput, !engine.gameOver else { return }
        let filoPrima = engine.filo
        let mossa = engine.gioca(idx)
        switch mossa {
        case .iniziato:
            annuncia(String(localized: "Filo iniziato. Somma \(engine.somma) su \(puzzle.T)."))
        case .esteso:
            annuncia(String(localized: "Più \(puzzle.valori[idx]). Somma \(engine.somma) su \(puzzle.T), \(engine.filo.count) caselle."))
        case .vittoria:
            gestisciVittoria()
        case .spezzato:
            gestisciFiloPerso(.spezzato, percorso: filoPrima + [idx])
        case .annodato:
            gestisciFiloPerso(.annodato, percorso: filoPrima + [idx])
        case .giaUsata:
            if viaTap {
                shake(idx)
                annuncia(String(localized: "Mossa non valida: casella già usata in questo filo."))
            }
        case .nonAdiacente:
            if viaTap {
                shake(idx)
                annuncia(String(localized: "Mossa non valida: la casella non è adiacente all'ultima."))
            }
        case .ignorata:
            break
        }
    }

    /// Tap secco sull'ultima casella del filo (senza estensione): shake (§6.6).
    func tapSuUltima(_ idx: Int) {
        guard !lockInput, !engine.gameOver else { return }
        shake(idx)
        annuncia(String(localized: "Mossa non valida: casella già usata in questo filo."))
    }

    func richiediStrappo() {
        guard strappaDisponibile else { return }
        showStrappoDialog = true
    }

    func confermaStrappo() {
        guard strappaDisponibile else { return }
        let percorso = engine.filo
        if engine.strappa() {
            gestisciFiloPerso(.strappato, percorso: percorso)
        }
    }

    private func shake(_ idx: Int) {
        shakes[idx, default: 0] += 1
        shakeTick += 1
        casellaNonValida = idx
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if casellaNonValida == idx { casellaNonValida = nil }
        }
    }

    // MARK: Esiti (sequenze animate + haptics UINotificationFeedbackGenerator)

    private func gestisciVittoria() {
        lockInput = true
        let C = engine.percorsoVincente?.count ?? 0
        let res = Punteggio.stelle(caselle: C, lSarto: puzzle.lSarto)
        stelleOggi = res.stelle
        sartoBattutoOggi = res.gold
        let o = Self.oggiParts()
        stats.registra(vinta: true, filiUsati: engine.fili.count, caselle: C,
                       gold: res.gold, oggi: o)
        salvaStats()
        salvaOggi()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let parole = res.gold ? String(localized: "Tre stelle, hai battuto il Sarto!")
            : (res.stelle == 3 ? String(localized: "Tre stelle")
               : res.stelle == 2 ? String(localized: "Due stelle") : String(localized: "Una stella"))
        annuncia(String(localized: "Vittoria! Somma esatta \(puzzle.T) con \(C) caselle. \(parole)."))
        revealPoiRisultato()
    }

    private func gestisciFiloPerso(_ esito: EsitoFilo, percorso: [Int]) {
        lockInput = true
        guard let concluso = engine.fili.last else { return }
        esitoVisuale = EsitoVisuale(percorso: percorso, esito: esito)
        if esito == .strappato {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        salvaOggi()
        let n = engine.filiRimasti
        switch esito {
        case .spezzato:
            annuncia(String(localized: "Filo spezzato: somma \(concluso.somma), superiore a \(puzzle.T). Fili rimasti: \(n)."))
        case .annodato:
            annuncia(String(localized: "Filo annodato: nessuna casella libera adiacente. Fili rimasti: \(n)."))
        default:
            annuncia(String(localized: "Filo strappato. Fili rimasti: \(n)."))
        }
        let durata: Double = reduceMotion ? 0.24
            : (esito == .spezzato ? 0.7 : esito == .annodato ? 0.6 : 0.35)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(durata * 1_000_000_000))
            esitoVisuale = nil
            if engine.stato == .persa {
                gestisciSconfitta()
            } else {
                lockInput = false
                mostraToast(testoToastEsito(esito, somma: concluso.somma, n: n))
            }
        }
    }

    private func gestisciSconfitta() {
        let o = Self.oggiParts()
        stats.registra(vinta: false, filiUsati: 3, caselle: 0, gold: false, oggi: o)
        salvaStats()
        salvaOggi()
        annuncia(String(localized: "Fili finiti. Il percorso del Sarto viene rivelato."))
        revealPoiRisultato()
    }

    /// Reveal del Sarto poi modal risultato (UX_SPEC §7.5: delay 350ms, poi +400ms).
    private func revealPoiRisultato() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            revealSarto = true
            let attesa = (reduceMotion ? 0.0 : durataReveal) + 0.4
            try? await Task.sleep(nanoseconds: UInt64(attesa * 1_000_000_000))
            lockInput = false
            risultatoMostrato = true
            scheda = .risultato
        }
    }

    /// Testi toast esito (NEURO_SPEC §2.3, plurale normativo).
    func testoToastEsito(_ esito: EsitoFilo, somma: Int, n: Int) -> String {
        let resto = (n == 1) ? String(localized: "Te ne resta 1.") : String(localized: "Te ne restano \(n).")
        switch esito {
        case .spezzato: return String(localized: "💥 Crack! \(somma) su \(puzzle.T): il filo non ha retto. \(resto)")
        case .annodato: return String(localized: "🪢 Vicolo cieco a \(somma) su \(puzzle.T). \(resto)")
        default: return String(localized: "✂️ Strappo netto. \(resto)")
        }
    }

    // MARK: Toast e annunci

    func mostraToast(_ testo: String) {
        toastTask?.cancel()
        toast = testo
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }

    /// Annuncio VoiceOver (AccessibilityNotification, iOS 17).
    private func annuncia(_ testo: String) {
        AccessibilityNotification.Announcement(testo).post()
    }

    // MARK: Cambio giorno (RF10: scenePhase active + timer 30s)

    func checkNuovoGiorno() {
        let o = Self.oggiParts()
        let oggiStr = FiloDate.dateString(y: o.y, m: o.m, d: o.d)
        if oggiStr != dataOggi && bannerDismissedFor != oggiStr {
            showNuovoGiornoBanner = true
        }
    }

    func giocaNuovoGiorno() {
        showNuovoGiornoBanner = false
        bootGiorno()
    }

    func nascondiBanner() {
        let o = Self.oggiParts()
        bannerDismissedFor = FiloDate.dateString(y: o.y, m: o.m, d: o.d)
        showNuovoGiornoBanner = false
    }

    // MARK: Strumenti TESTER/ADMIN (fuori dalle regole normali)

    /// Azzera la partita di OGGI: rimette i 3 fili, il filo corrente e lo stato
    /// come a inizio giornata, cancellando il salvataggio del giorno. Non tocca
    /// le statistiche storiche. Solo per test.
    func testerAzzera() {
        engine = GameEngine(puzzle: puzzle)
        stelleOggi = 0
        sartoBattutoOggi = false
        revealSarto = false
        esitoVisuale = nil
        lockInput = false
        risultatoMostrato = false
        shakes = [:]
        casellaNonValida = nil
        toast = nil
        scheda = nil
        defaults.removeObject(forKey: "filo.today")
    }

    /// Carica una griglia CASUALE (numeri diversi) per provare, senza intaccare
    /// il puzzle del giorno né le statistiche. Solo per test.
    func testerNuoviNumeri() {
        let semeCasuale = Int.random(in: 10_000_000...99_999_999)
        puzzle = Generator.generate(seed: semeCasuale)
        engine = GameEngine(puzzle: puzzle)
        stelleOggi = 0
        sartoBattutoOggi = false
        revealSarto = false
        esitoVisuale = nil
        lockInput = false
        risultatoMostrato = false
        shakes = [:]
        casellaNonValida = nil
        toast = nil
        scheda = nil
    }

    // MARK: Chiusura schede

    /// Chiamata alla chiusura del tutorial: vale come visto anche con swipe (RF7).
    func onboardingChiuso() {
        segnaOnboarded()
        // Catena primo avvio: dopo il tutorial classico, una volta sola, mostra
        // l'onboarding progressivo PRIMA del daily.
        if primoAvvio && !defaults.bool(forKey: progressiveKey) {
            primoAvvio = false
            Task { @MainActor in self.scheda = .onboardingProgressivo }
            return
        }
        if engine.gameOver && !risultatoMostrato {
            revealSarto = true
            risultatoMostrato = true
            scheda = .risultato
        }
    }
}
